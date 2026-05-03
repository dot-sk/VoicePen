#!/usr/bin/env bash
set -euo pipefail

if upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
    base="${upstream}"
elif git rev-parse --verify origin/main >/dev/null 2>&1; then
    base="origin/main"
else
    printf "pre-push: no upstream or origin/main found, running make test.\n"
    make test
    exit 0
fi

changed_files="$(mktemp)"
trap 'rm -f "${changed_files}"' EXIT

git diff --name-only "${base}...HEAD" > "${changed_files}"

if scripts/code-impacting-changes.sh "${changed_files}"; then
    printf "pre-push: code-impacting changes found, running make test.\n"
    make test
else
    printf "pre-push: no code-impacting changes, skipping make test.\n"
fi
