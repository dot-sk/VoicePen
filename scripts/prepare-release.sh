#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/prepare-release.sh <version> [build]

Examples:
  scripts/prepare-release.sh 1.1.0
  scripts/prepare-release.sh v1.1.0 42

The script:
  - checks out and updates main;
  - creates release/v<version>;
  - updates MARKETING_VERSION and CURRENT_PROJECT_VERSION;
  - commits, pushes, and opens a GitHub pull request.
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

build="${2:-$(date -u +%Y%m%d%H%M)}"
if [[ ! "$build" =~ ^[0-9]+$ ]]; then
  echo "Invalid build number: $build" >&2
  echo "Build number must be numeric." >&2
  exit 64
fi

tag="v$version"
branch="release/$tag"
project_file="VoicePen.xcodeproj/project.pbxproj"

if [[ ! -f "$project_file" ]]; then
  echo "Run this from the VoicePen repository root." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required: https://cli.github.com/" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean. Commit or stash changes before preparing a release." >&2
  git status --short
  exit 1
fi

git fetch origin main --prune
git checkout main
git pull --ff-only origin main

if git rev-parse --verify "$branch" >/dev/null 2>&1; then
  echo "Local branch already exists: $branch" >&2
  exit 1
fi

if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  echo "Remote branch already exists: $branch" >&2
  exit 1
fi

git checkout -b "$branch"

perl -0pi -e "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $version;/g" "$project_file"
perl -0pi -e "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $build;/g" "$project_file"

git add "$project_file"
git commit -m "chore: 🚀 prepare $tag"
git push -u origin "$branch"

gh pr create \
  --base main \
  --head "$branch" \
  --title "Prepare $tag" \
  --body "## Summary
- bump VoicePen version to $version
- set build number to $build

## Release after merge
\`\`\`bash
git checkout main
git pull --ff-only origin main
git tag $tag
git push origin $tag
\`\`\`

Pushing the tag starts the Release workflow, attaches the downloadable unsigned macOS zip, and publishes the Sparkle appcast to GitHub Pages."

echo
echo "Release PR created for $tag."
echo "After it is merged, push tag $tag to create the GitHub Release package and update appcast."
