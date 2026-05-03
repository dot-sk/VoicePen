#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 2 ]]; then
    git diff --name-only "$1" "$2"
elif [[ "$#" -eq 1 ]]; then
    cat "$1"
else
    cat
fi | grep -Eq '^(\.github/workflows/ci\.yml|\.periphery\.yml|\.swift-format|\.swiftlint\.yml|Makefile|Package\.resolved|Package\.swift|lefthook\.yml|scripts/|VoicePen(\.xcodeproj|IntegrationTests|Tests|UITests)?/)'
