#!/usr/bin/env python3
import argparse
import logging
import pathlib
import re
from typing import Iterable

import git
import semver

# Deployment helper for commit/tag automation:
# - Resolves owner/repo from git remote origin
# - Normalizes raw.githubusercontent.com README URLs to branch or tag refs
# - Commits and optionally pushes with sensible defaults

_LOG = logging.getLogger("deploy")
_README_PATH = pathlib.Path("README.md")
_CARGO_TOML_PATH = pathlib.Path("Cargo.toml")
_URL_PATTERN = re.compile(
    r"https://raw\.githubusercontent\.com/[^/\s]+/[^/\s]+/[^/\s]+/install\.(sh|ps1)"
)
_REPO_PATTERN = re.compile(r"(?:[:/])(?P<owner>[^/:]+)/(?P<repo>[^/]+?)(?:\.git)?$")
_SEMVER_TAG_PATTERN = re.compile(r"^(?P<prefix>v?)(?P<version>\d+\.\d+\.\d+)$")
_CARGO_VERSION_PATTERN = re.compile(r'^(version\s*=\s*")(?P<version>\d+\.\d+\.\d+)(")\s*$')


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
    repo = git.Repo(".")
    remote_url = repo.remotes.origin.url
    match = _REPO_PATTERN.search(remote_url)
    if not match:
        raise RuntimeError(f"Unable to parse owner/repo from remote URL: {remote_url}")
    owner = match.group("owner")
    repo = match.group("repo")
    return owner, repo


def _detect_branch_name() -> str:
    """Detect the current branch name; fallback to main for detached HEAD."""
    repo = git.Repo(".")
    if repo.head.is_detached:
        _LOG.warning("Detached HEAD detected. Falling back to 'main' for README URLs.")
        return "main"
    return repo.active_branch.name


def _parse_semver_tag(tag_name: str) -> tuple[str, semver.Version] | None:
    """Parse tags in the form vX.Y.Z or X.Y.Z."""
    match = _SEMVER_TAG_PATTERN.match(tag_name)
    if not match:
        return None
    prefix = match.group("prefix")
    version = semver.Version.parse(match.group("version"))
    return prefix, version


def _iter_semver_tags(repo: git.Repo) -> Iterable[tuple[str, semver.Version]]:
    """Yield all semantic version tags from the repository."""
    for tag_ref in repo.tags:
        parsed = _parse_semver_tag(tag_ref.name)
        if parsed is not None:
            yield parsed


def _latest_semver_tag_name() -> str | None:
    """Return the latest semantic version tag name, preferring a v-prefix."""
    repo = git.Repo(".")
    semver_tags = list(_iter_semver_tags(repo))
    if not semver_tags:
        return None
    prefix, latest_version = max(semver_tags, key=lambda item: item[1])
    if not prefix:
        prefix = "v"
    return f"{prefix}{latest_version}"


def _next_tag(major: bool, minor: bool) -> str:
    """Compute the next tag with patch bump by default."""
    repo = git.Repo(".")
    semver_tags = list(_iter_semver_tags(repo))
    if semver_tags:
        prefix, latest_version = max(semver_tags, key=lambda item: item[1])
        if not prefix:
            prefix = "v"
    else:
        prefix = "v"
        latest_version = semver.Version.parse("0.0.0")

    if major:
        bumped = latest_version.bump_major()
    elif minor:
        bumped = latest_version.bump_minor()
    else:
        bumped = latest_version.bump_patch()
    return f"{prefix}{bumped}"


def _version_from_tag(tag_name: str) -> str:
    """Extract a plain semver string from a semantic version tag."""
    parsed = _parse_semver_tag(tag_name)
    if parsed is None:
        raise ValueError(f"Tag '{tag_name}' is not a valid semantic version tag.")
    _, version = parsed
    return str(version)


def _resolve_ref_for_commit() -> str:
    """Use latest alias on main, otherwise use current branch."""
    branch = _detect_branch_name()
    if branch != "main":
        return branch
    return "latest"


def _rewrite_readme_raw_urls(owner: str, repo: str, ref: str) -> bool:
    """Rewrite all init-script raw GitHub URLs in README.md to owner/repo/ref."""
    if not _README_PATH.exists():
        raise FileNotFoundError("README.md not found in repository root.")

    content = _README_PATH.read_text(encoding="utf-8")

    def _replacement(match: re.Match[str]) -> str:
        extension = match.group(1)
        return (
            f"https://raw.githubusercontent.com/{owner}/{repo}/{ref}/"
            f"install.{extension}"
        )

    updated = _URL_PATTERN.sub(_replacement, content)
    if updated == content:
        _LOG.info("README URLs already point to %s/%s at ref '%s'.", owner, repo, ref)
        return False

    _README_PATH.write_text(updated, encoding="utf-8")
    _LOG.info("Updated README raw URLs to %s/%s at ref '%s'.", owner, repo, ref)
    return True


def _rewrite_cargo_version(version: str) -> bool:
    """Update Cargo.toml package.version to match the resolved release tag."""
    if not _CARGO_TOML_PATH.exists():
        raise FileNotFoundError("Cargo.toml not found in repository root.")

    content = _CARGO_TOML_PATH.read_text(encoding="utf-8")
    updated_lines: list[str] = []
    in_package_section = False
    replaced = False

    for line in content.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            in_package_section = stripped == "[package]"
        if in_package_section and not replaced:
            match = _CARGO_VERSION_PATTERN.match(stripped)
            if match:
                current_version = match.group("version")
                if current_version == version:
                    _LOG.info("Cargo.toml version already set to %s.", version)
                    return False
                prefix, suffix = match.group(1), match.group(3)
                line = f"{prefix}{version}{suffix}"
                replaced = True
        updated_lines.append(line)

    if not replaced:
        raise RuntimeError("Could not find package.version entry in Cargo.toml.")

    _CARGO_TOML_PATH.write_text("\n".join(updated_lines) + "\n", encoding="utf-8")
    _LOG.info("Updated Cargo.toml version to %s.", version)
    return True


def _commit_all_changes(message: str) -> bool:
    """Stage all changes and commit when there is anything to commit."""
    repo = git.Repo(".")
    repo.git.add(A=True)
    if not repo.is_dirty(index=True, working_tree=True, untracked_files=True):
        _LOG.info("No changes to commit.")
        return False
    repo.index.commit(message)
    _LOG.info("Created commit: %s", message)
    return True


def _push_commit() -> None:
    """Push current branch to upstream remote."""
    repo = git.Repo(".")
    repo.remotes.origin.push()
    _LOG.info("Pushed branch to remote.")


def _create_tag(tag: str) -> None:
    """Create a lightweight git tag."""
    repo = git.Repo(".")
    repo.create_tag(tag)
    _LOG.info("Created tag: %s", tag)


def _push_tag(tag: str) -> None:
    """Push a single git tag to origin."""
    repo = git.Repo(".")
    repo.remotes.origin.push(tag)
    _LOG.info("Pushed tag: %s", tag)


def _resolve_message(user_message: str, default_message: str) -> str:
    """Resolve a generated message when message=generate."""
    if user_message == "generate":
        return default_message
    return user_message


def _run_commit_command(message: str, push: bool) -> None:
    owner, repo = _detect_repo_slug()
    ref = _resolve_ref_for_commit()
    _rewrite_readme_raw_urls(owner=owner, repo=repo, ref=ref)
    resolved = _resolve_message(
        user_message=message,
        default_message=f"chore: sync README raw URLs to {owner}/{repo}/{ref}",
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
    resolved_version = _version_from_tag(resolved_tag)
    ref = _resolve_ref_for_commit()
    _LOG.info("Using tag: %s", resolved_tag)
    _rewrite_readme_raw_urls(owner=owner, repo=repo, ref=ref)
    _rewrite_cargo_version(resolved_version)
    resolved = _resolve_message(
        user_message=message,
        default_message=f"chore: sync README raw URLs to {owner}/{repo}/{ref}",
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
            "for install scripts."
        )
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    commit_parser = subparsers.add_parser(
        "commit",
        help="Rewrite README URLs to latest tag on main, else current branch.",
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
