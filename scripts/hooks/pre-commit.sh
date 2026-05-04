#!/usr/bin/env bash
set -euo pipefail

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SWIFTLINT_CACHE="${SWIFTLINT_CACHE:-.swiftlint-cache}"
export DEVELOPER_DIR

swift_files="$(git diff --cached --name-only --diff-filter=ACMR | grep -E '\.swift$' | grep -v '^Vendor/' || true)"

if [[ -z "${swift_files}" ]]; then
    exit 0
fi

while IFS= read -r file; do
    [[ -z "${file}" ]] && continue
    [[ -f "${file}" ]] || continue
    if ! git diff --quiet -- "${file}"; then
        printf "pre-commit: %s has unstaged changes. Stage or stash them before committing.\n" "${file}" >&2
        exit 1
    fi
done <<< "${swift_files}"

if ! xcrun --find swift-format >/dev/null 2>&1; then
    printf "swift-format is required. Install Xcode 16+ or run brew install swift-format.\n" >&2
    exit 127
fi

while IFS= read -r file; do
    [[ -z "${file}" ]] && continue
    [[ -f "${file}" ]] || continue
    xcrun swift-format format --configuration .swift-format --in-place "${file}"
    git add "${file}"
done <<< "${swift_files}"

while IFS= read -r file; do
    [[ -z "${file}" ]] && continue
    [[ -f "${file}" ]] || continue
    xcrun swift-format lint --configuration .swift-format --strict "${file}"
done <<< "${swift_files}"

if ! command -v swiftlint >/dev/null 2>&1; then
    printf "SwiftLint is required. Install it with: brew install swiftlint\n" >&2
    exit 127
fi

while IFS= read -r file; do
    [[ -z "${file}" ]] && continue
    [[ -f "${file}" ]] || continue
    swiftlint lint --fix --config .swiftlint.yml --cache-path "${SWIFTLINT_CACHE}" --quiet "${file}"
    git add "${file}"
done <<< "${swift_files}"

while IFS= read -r file; do
    [[ -z "${file}" ]] && continue
    [[ -f "${file}" ]] || continue
    swiftlint lint --config .swiftlint.yml --cache-path "${SWIFTLINT_CACHE}" --quiet "${file}"
done <<< "${swift_files}"
