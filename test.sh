#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-regbo/lfp-env}"
CUTOFF="${CUTOFF:-0.1.75}"
DELETE_TAGS="${DELETE_TAGS:-1}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

version_le() {
  [ "$1" = "$2" ] && return 0
  local first
  first="$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)"
  [ "$first" = "$1" ]
}

require_cmd gh
require_cmd python3

printf 'Checking GitHub auth for %s\n' "$REPO" >&2
gh repo view "$REPO" --json viewerPermission >/dev/null

release_json="$(gh api "repos/${REPO}/releases?per_page=100")"

python3 - <<'PY' "$release_json" "$CUTOFF" "$DELETE_TAGS" "$REPO"
import json
import subprocess
import sys

releases = json.loads(sys.argv[1])
cutoff = sys.argv[2]
delete_tags = sys.argv[3] == "1"
repo = sys.argv[4]

def norm(tag: str):
    if not tag.startswith("v"):
        return None
    parts = tag[1:].split(".")
    if not all(part.isdigit() for part in parts):
        return None
    return tuple(int(part) for part in parts)

cutoff_v = norm("v" + cutoff if not cutoff.startswith("v") else cutoff)
if cutoff_v is None:
    raise SystemExit(f"Invalid cutoff version: {cutoff}")

targets = []
for rel in releases:
    tag = rel["tag_name"]
    parsed = norm(tag)
    if parsed is None:
        continue
    if parsed <= cutoff_v:
        targets.append((tag, rel["id"]))

if not targets:
    print("No matching releases found.")
    raise SystemExit(0)

def run_gh_delete(path: str, description: str):
    result = subprocess.run(
        ["gh", "api", "--method", "DELETE", path],
        text=True,
        capture_output=True,
    )
    if result.returncode == 0:
        return

    combined_output = f"{result.stdout}{result.stderr}"
    if "404" in combined_output or "Not Found" in combined_output:
        print(f"Skipping missing {description}")
        return

    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    raise SystemExit(result.returncode)

print("Will delete releases:")
for tag, rel_id in targets:
    print(f"  {tag} (release id {rel_id})")

for tag, rel_id in targets:
    print(f"Deleting release {tag}")
    run_gh_delete(
        f"repos/{repo}/releases/{rel_id}",
        f"release {tag}",
    )
    if delete_tags:
        print(f"Deleting remote tag {tag}")
        run_gh_delete(
            f"repos/{repo}/git/refs/tags/{tag}",
            f"tag {tag}",
        )

print("Done.")
PY