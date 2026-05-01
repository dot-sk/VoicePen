#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/publish-release.sh <version>

Example:
  scripts/publish-release.sh 1.1.0

The script:
  - checks out and updates main;
  - verifies the release tag does not exist;
  - creates and pushes v<version>;
  - prints the GitHub Actions release workflow URL.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

raw_version="${1:-}"
if [[ -z "$raw_version" ]]; then
  usage
  exit 64
fi

version="${raw_version#v}"
if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+){1,2}([.-][0-9A-Za-z]+)?$ ]]; then
  echo "Invalid version: $raw_version" >&2
  echo "Use something like 1.1.0 or v1.1.0." >&2
  exit 64
fi

tag="v$version"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required: https://cli.github.com/" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean. Commit or stash changes before publishing a release." >&2
  git status --short
  exit 1
fi

git fetch origin main --tags --prune
git checkout main
git pull --ff-only origin main

if git rev-parse --verify "$tag" >/dev/null 2>&1; then
  echo "Local tag already exists: $tag" >&2
  exit 1
fi

if git ls-remote --exit-code --tags origin "$tag" >/dev/null 2>&1; then
  echo "Remote tag already exists: $tag" >&2
  exit 1
fi

git tag "$tag"
git push origin "$tag"

echo
echo "Pushed $tag."
echo "Release workflow:"
echo "https://github.com/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/actions/workflows/release.yml"
