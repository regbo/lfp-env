#!/usr/bin/env python3
import argparse
import logging
import pathlib
import re
import subprocess
from typing import Sequence

# Deployment helper for commit/tag automation:
# - Resolves owner/repo from git remote origin
# - Normalizes raw.githubusercontent.com README URLs to branch or tag refs
# - Commits and optionally pushes with sensible defaults

_LOG = logging.getLogger("deploy")
_README_PATH = pathlib.Path("README.md")
_URL_PATTERN = re.compile(
    r"https://raw\.githubusercontent\.com/[^/\s]+/[^/\s]+/[^/\s]+/pixi-init\.(sh|ps1)"
)
_REPO_PATTERN = re.compile(r"(?:[:/])(?P<owner>[^/:]+)/(?P<repo>[^/]+?)(?:\.git)?$")
_SEMVER_TAG_PATTERN = re.compile(r"^(?P<prefix>v?)(?P<major>\d+)\.(?P<minor>\d+)\.(?P<patch>\d+)$")


def _run_git(args: Sequence[str]) -> str:
    """Run a git command and return stdout."""
    result = subprocess.run(
        ["git", *args],
        check=True,
        text=True,
        capture_output=True,
    )
    return result.stdout.strip()


def _parse_bool(value: str) -> bool:
    """Parse common truthy/falsey values for argparse."""
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "y", "on"}:
        return True
    if normalized in {"0", "false", "no", "n", "off"}:
        return False
    raise argparse.ArgumentTypeError(
        f"Invalid boolean value '{value}'. Use true/false."
    )


def _detect_repo_slug() -> tuple[str, str]:
    """Detect the repository owner/name from remote.origin.url."""
    remote_url = _run_git(["config", "--get", "remote.origin.url"])
    match = _REPO_PATTERN.search(remote_url)
    if not match:
        raise RuntimeError(f"Unable to parse owner/repo from remote URL: {remote_url}")
    owner = match.group("owner")
    repo = match.group("repo")
    return owner, repo


def _detect_branch_name() -> str:
    """Detect the current branch name; fallback to main for detached HEAD."""
    branch = _run_git(["rev-parse", "--abbrev-ref", "HEAD"])
    if branch == "HEAD":
        _LOG.warning("Detached HEAD detected. Falling back to 'main' for README URLs.")
        return "main"
    return branch


def _list_tags() -> list[str]:
    """Return tags sorted by semantic-like ordering from newest to oldest."""
    output = _run_git(["tag", "--list", "--sort=-v:refname"])
    if not output:
        return []
    return [line for line in output.splitlines() if line.strip()]


def _detect_latest_semver_tag() -> tuple[str, int, int, int] | None:
    """Return latest semantic version tag details if one is present."""
    for tag in _list_tags():
        match = _SEMVER_TAG_PATTERN.match(tag)
        if match:
            return (
                match.group("prefix"),
                int(match.group("major")),
                int(match.group("minor")),
                int(match.group("patch")),
            )
    return None


def _next_tag(major: bool, minor: bool) -> str:
    """Compute the next tag with patch bump by default."""
    latest = _detect_latest_semver_tag()
    if latest is None:
        prefix, major_version, minor_version, patch_version = "v", 0, 0, 0
    else:
        prefix, major_version, minor_version, patch_version = latest
        if not prefix:
            prefix = "v"

    if major:
        major_version += 1
        minor_version = 0
        patch_version = 0
    elif minor:
        minor_version += 1
        patch_version = 0
    else:
        patch_version += 1

    return f"{prefix}{major_version}.{minor_version}.{patch_version}"


def _rewrite_readme_raw_urls(owner: str, repo: str, ref: str) -> bool:
    """Rewrite all init-script raw GitHub URLs in README.md to owner/repo/ref."""
    if not _README_PATH.exists():
        raise FileNotFoundError("README.md not found in repository root.")

    content = _README_PATH.read_text(encoding="utf-8")

    def _replacement(match: re.Match[str]) -> str:
        extension = match.group(1)
        return (
            f"https://raw.githubusercontent.com/{owner}/{repo}/{ref}/"
            f"pixi-init.{extension}"
        )

    updated = _URL_PATTERN.sub(_replacement, content)
    if updated == content:
        _LOG.info("README URLs already point to %s/%s at ref '%s'.", owner, repo, ref)
        return False

    _README_PATH.write_text(updated, encoding="utf-8")
    _LOG.info("Updated README raw URLs to %s/%s at ref '%s'.", owner, repo, ref)
    return True


def _has_staged_or_unstaged_changes() -> bool:
    """Return True when the working tree has pending changes."""
    status = _run_git(["status", "--porcelain"])
    return bool(status)


def _commit_all_changes(message: str) -> bool:
    """Stage all changes and commit when there is anything to commit."""
    _run_git(["add", "-A"])
    if not _has_staged_or_unstaged_changes():
        _LOG.info("No changes to commit.")
        return False
    subprocess.run(["git", "commit", "-m", message], check=True)
    _LOG.info("Created commit: %s", message)
    return True


def _push_commit() -> None:
    """Push current branch to upstream remote."""
    subprocess.run(["git", "push"], check=True)
    _LOG.info("Pushed branch to remote.")


def _create_tag(tag: str) -> None:
    """Create a lightweight git tag."""
    subprocess.run(["git", "tag", tag], check=True)
    _LOG.info("Created tag: %s", tag)


def _push_tag(tag: str) -> None:
    """Push a single git tag to origin."""
    subprocess.run(["git", "push", "origin", tag], check=True)
    _LOG.info("Pushed tag: %s", tag)


def _resolve_message(user_message: str, default_message: str) -> str:
    """Resolve a generated message when message=generate."""
    if user_message == "generate":
        return default_message
    return user_message


def _run_commit_command(message: str, push: bool) -> None:
    owner, repo = _detect_repo_slug()
    branch = _detect_branch_name()
    _rewrite_readme_raw_urls(owner=owner, repo=repo, ref=branch)
    resolved = _resolve_message(
        user_message=message,
        default_message=f"chore: sync README raw URLs to {owner}/{repo}/{branch}",
    )
    committed = _commit_all_changes(resolved)
    if push and committed:
        _push_commit()


def _run_tag_command(
    tag: str | None,
    major: bool,
    minor: bool,
    message: str,
    push: bool,
) -> None:
    owner, repo = _detect_repo_slug()
    resolved_tag = tag if tag else _next_tag(major=major, minor=minor)
    _LOG.info("Using tag: %s", resolved_tag)
    _rewrite_readme_raw_urls(owner=owner, repo=repo, ref=resolved_tag)
    resolved = _resolve_message(
        user_message=message,
        default_message=f"chore: sync README raw URLs to {owner}/{repo}/{resolved_tag}",
    )
    committed = _commit_all_changes(resolved)
    _create_tag(resolved_tag)
    if push:
        if committed:
            _push_commit()
        _push_tag(resolved_tag)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Commit and tag helper that normalizes README raw GitHub URLs "
            "for pixi init scripts."
        )
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    commit_parser = subparsers.add_parser(
        "commit",
        help="Rewrite README URLs to current branch, commit changes, optionally push.",
    )
    commit_parser.add_argument(
        "--message",
        default="generate",
        help="Commit message. Use 'generate' to auto-generate (default).",
    )
    commit_parser.add_argument(
        "--push",
        type=_parse_bool,
        default=True,
        help="Push after commit (true/false). Default: true.",
    )

    tag_parser = subparsers.add_parser(
        "tag",
        help=(
            "Rewrite README URLs to a tag ref, commit, create tag, and optionally push. "
            "Defaults to patch bump when --tag is not supplied."
        ),
    )
    selector_group = tag_parser.add_mutually_exclusive_group()
    selector_group.add_argument(
        "--tag",
        help="Explicit tag to create, for example v0.1.0.",
    )
    selector_group.add_argument(
        "--major",
        action="store_true",
        help="Bump major version from latest semantic version tag.",
    )
    selector_group.add_argument(
        "--minor",
        action="store_true",
        help="Bump minor version from latest semantic version tag.",
    )
    tag_parser.add_argument(
        "--message",
        default="generate",
        help="Commit message. Use 'generate' to auto-generate (default).",
    )
    tag_parser.add_argument(
        "--push",
        type=_parse_bool,
        default=True,
        help="Push branch and tag (true/false). Default: true.",
    )
    return parser


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    parser = _build_parser()
    args = parser.parse_args()

    if args.command == "commit":
        _run_commit_command(message=args.message, push=args.push)
        return
    if args.command == "tag":
        _run_tag_command(
            tag=args.tag,
            major=args.major,
            minor=args.minor,
            message=args.message,
            push=args.push,
        )
        return
    raise RuntimeError(f"Unsupported command: {args.command}")


if __name__ == "__main__":
    main()
