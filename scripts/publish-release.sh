#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/publish-release.sh <version>

Example:
  scripts/publish-release.sh 1.1.0

The script:
  - checks out and updates release/v<version>;
  - verifies the release pull request exists, is open, and has green checks;
  - verifies the Xcode version matches <version> and the build number increased;
  - verifies the release tag does not exist;
  - creates and pushes v<version> from the release branch;
  - prints the GitHub Actions release workflow URL.

The release workflow expects:
  - repository secret SPARKLE_PRIVATE_KEY.
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
branch="release/$tag"
project_file="VoicePen.xcodeproj/project.pbxproj"

project_values() {
  local key="$1"
  grep -E "^[[:space:]]*$key = " "$project_file" \
    | sed -E "s/.*$key = ([^;]+);/\\1/" \
    | sort -u || true
}

project_values_from_text() {
  local key="$1"
  grep -E "^[[:space:]]*$key = " \
    | sed -E "s/.*$key = ([^;]+);/\\1/" \
    | sort -u || true
}

single_value() {
  local key="$1"
  local label="$2"
  local values="$3"
  local count

  count="$(printf "%s\n" "$values" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$count" != "1" ]]; then
    echo "Expected exactly one $key value in $label, found:" >&2
    if [[ -n "$values" ]]; then
      printf "%s\n" "$values" >&2
    else
      echo "<none>" >&2
    fi
    exit 1
  fi

  printf "%s\n" "$values"
}

require_numeric_build() {
  local build="$1"
  local label="$2"

  if [[ ! "$build" =~ ^[0-9]+$ ]]; then
    echo "Invalid CURRENT_PROJECT_VERSION in $label: $build" >&2
    echo "Build number must be numeric." >&2
    exit 1
  fi
}

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required: https://cli.github.com/" >&2
  exit 1
fi

if [[ ! -f "$project_file" ]]; then
  echo "Run this from the VoicePen repository root." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean. Commit or stash changes before publishing a release." >&2
  git status --short
  exit 1
fi

if ! git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  echo "Remote release branch does not exist: $branch" >&2
  echo "Run make prepare-release VERSION=$version first." >&2
  exit 1
fi

git fetch origin "$branch:refs/remotes/origin/$branch" --tags --prune

if git rev-parse --verify "$branch" >/dev/null 2>&1; then
  git checkout "$branch"
  git pull --ff-only origin "$branch"
else
  git checkout -b "$branch" "origin/$branch"
fi

local_head="$(git rev-parse HEAD)"
remote_head="$(git rev-parse "origin/$branch")"
if [[ "$local_head" != "$remote_head" ]]; then
  echo "Local $branch is not at origin/$branch." >&2
  echo "Run git pull --ff-only origin $branch and try again." >&2
  exit 1
fi

if ! pr_details="$(gh pr view "$branch" --json number,state,isDraft,url,baseRefName,headRefName --jq '[.number,.state,.isDraft,.url,.baseRefName,.headRefName] | @tsv' 2>/dev/null)"; then
  echo "No pull request found for $branch." >&2
  echo "Run make prepare-release VERSION=$version first." >&2
  exit 1
fi

IFS=$'\t' read -r pr_number pr_state pr_is_draft pr_url pr_base pr_head <<< "$pr_details"

if [[ "$pr_state" != "OPEN" ]]; then
  echo "Release pull request #$pr_number is not open: $pr_state" >&2
  exit 1
fi

if [[ "$pr_is_draft" == "true" ]]; then
  echo "Release pull request #$pr_number is still a draft." >&2
  exit 1
fi

if [[ "$pr_base" != "main" || "$pr_head" != "$branch" ]]; then
  echo "Release pull request #$pr_number must merge $branch into main." >&2
  echo "Current PR: $pr_head -> $pr_base" >&2
  exit 1
fi

if ! check_buckets="$(gh pr checks "$branch" --json bucket --jq '.[].bucket' 2>/dev/null)"; then
  echo "Release pull request checks are not green yet: $pr_url" >&2
  gh pr checks "$branch" || true
  exit 1
fi

if [[ -z "$(printf "%s\n" "$check_buckets" | sed '/^$/d')" ]]; then
  echo "No release pull request checks found for $branch." >&2
  echo "Wait for CI to start before publishing the tag." >&2
  exit 1
fi

if printf "%s\n" "$check_buckets" | grep -Ev '^(pass|skipping)$' >/dev/null; then
  echo "Release pull request checks are not green yet: $pr_url" >&2
  gh pr checks "$branch" || true
  exit 1
fi

if ! printf "%s\n" "$check_buckets" | grep -q '^pass$'; then
  echo "Release pull request has no passing checks yet: $pr_url" >&2
  exit 1
fi

marketing_version="$(single_value "MARKETING_VERSION" "$project_file" "$(project_values "MARKETING_VERSION")")"
if [[ "$marketing_version" != "$version" ]]; then
  echo "MARKETING_VERSION in $project_file is $marketing_version, expected $version." >&2
  exit 1
fi

build_number="$(single_value "CURRENT_PROJECT_VERSION" "$project_file" "$(project_values "CURRENT_PROJECT_VERSION")")"
require_numeric_build "$build_number" "$project_file"

previous_tag="$(git tag --list 'v[0-9]*' --sort=-version:refname | grep -vx "$tag" | head -n 1 || true)"
if [[ -n "$previous_tag" ]]; then
  if ! previous_project_file="$(git show "$previous_tag:$project_file")"; then
    echo "Could not read $project_file from previous release tag $previous_tag." >&2
    exit 1
  fi

  previous_build_number="$(single_value "CURRENT_PROJECT_VERSION" "$previous_tag:$project_file" "$(printf "%s\n" "$previous_project_file" | project_values_from_text "CURRENT_PROJECT_VERSION")")"
  require_numeric_build "$previous_build_number" "$previous_tag:$project_file"

  if (( 10#$build_number <= 10#$previous_build_number )); then
    echo "CURRENT_PROJECT_VERSION must increase for each release." >&2
    echo "$project_file has $build_number; $previous_tag has $previous_build_number." >&2
    exit 1
  fi
fi

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
echo "Pushed $tag from $branch."
echo "The Release workflow will attach the zip and publish the Sparkle appcast to GitHub Pages."
echo "Release workflow:"
echo "https://github.com/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/actions/workflows/release.yml"
