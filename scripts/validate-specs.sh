#!/usr/bin/env bash
set -u

failures=0

fail() {
  printf "spec validation error: %s\n" "$1" >&2
  failures=$((failures + 1))
}

section_has_content() {
  local file="$1"
  local section="$2"

  awk -v section="$section" '
    $0 == "## " section { inside = 1; next }
    inside && /^## / { exit }
    inside && $0 ~ /[^[:space:]]/ { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$file"
}

section_has_list_item() {
  local file="$1"
  local section="$2"

  awk -v section="$section" '
    $0 == "## " section { inside = 1; next }
    inside && /^## / { exit }
    inside && /^- / { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$file"
}

frontmatter_value() {
  local file="$1"
  local key="$2"

  awk -v key="$key" '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---" { exit }
    inside && $0 ~ "^" key ": " {
      sub("^" key ": ", "")
      print
      exit
    }
  ' "$file"
}

frontmatter_has_key() {
  local file="$1"
  local key="$2"

  awk -v key="$key" '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---" { exit }
    inside && $0 ~ "^" key ":" { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$file"
}

frontmatter_has_list_value() {
  local file="$1"
  local key="$2"

  awk -v key="$key" '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---" { exit }
    inside && $0 == key ":" { in_list = 1; next }
    in_list && /^[^[:space:]-]/ { exit }
    in_list && /^  - .+/ { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$file"
}

require_section() {
  local file="$1"
  local section="$2"

  if ! grep -q "^## ${section}$" "$file"; then
    fail "$file is missing section: $section"
    return
  fi

  if ! section_has_content "$file" "$section"; then
    fail "$file has an empty section: $section"
  fi
}

index_file="Specs/index.md"

if [ ! -f "$index_file" ]; then
  fail "Specs/index.md is missing"
fi

spec_files=()
while IFS= read -r file; do
  spec_files+=("$file")
done < <(find Specs -maxdepth 1 -type f -name '*.md' ! -name 'README.md' ! -name 'index.md' | sort)

if [ "${#spec_files[@]}" -eq 0 ]; then
  fail "Specs contains no spec files"
fi

required_sections=(
  "Problem"
  "Behavior"
  "Acceptance Criteria"
  "Examples"
  "Test Mapping"
  "Notes"
  "Open Questions"
)

for file in "${spec_files[@]}"; do
  if [ "$(sed -n '1p' "$file")" != "---" ]; then
    fail "$file must start with YAML frontmatter"
  fi

  if ! awk 'NR > 1 && $0 == "---" { found = 1; exit } END { exit found ? 0 : 1 }' "$file"; then
    fail "$file frontmatter is missing closing delimiter"
  fi

  if ! grep -q '^# .\+' "$file"; then
    fail "$file is missing a top-level title"
  fi

  for section in "${required_sections[@]}"; do
    require_section "$file" "$section"
  done

  for field in "id" "status" "updated" "tests"; do
    if ! frontmatter_has_key "$file" "$field"; then
      fail "$file frontmatter is missing: $field"
    fi
  done

  id="$(frontmatter_value "$file" "id")"
  if ! printf "%s\n" "$id" | grep -Eq '^(SPEC|BUG)-[0-9]{3}$'; then
    fail "$file has an invalid id value"
  fi

  status="$(frontmatter_value "$file" "status")"
  if ! printf "%s\n" "$status" | grep -Eq '^(draft|active|implemented|superseded)$'; then
    fail "$file has an invalid status value"
  fi

  updated="$(frontmatter_value "$file" "updated")"
  if ! printf "%s\n" "$updated" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    fail "$file has an invalid updated value"
  fi

  tests_value="$(frontmatter_value "$file" "tests")"
  if [ "$tests_value" != "[]" ] && ! frontmatter_has_list_value "$file" "tests"; then
    fail "$file tests must be [] or a YAML list"
  fi

  if [ "$status" = "implemented" ] && [ "$tests_value" = "[]" ]; then
    fail "$file has status implemented but no tests"
  fi

  if [ "$tests_value" != "[]" ]; then
    while IFS= read -r test_path; do
      case "$test_path" in
        VoicePenTests/*|VoicePenIntegrationTests/*|VoicePenUITests/*)
          ;;
        *)
          fail "$file test path must be under VoicePenTests/, VoicePenIntegrationTests/, or VoicePenUITests/: $test_path"
          ;;
      esac

      if [ ! -f "$test_path" ]; then
        fail "$file references missing test file: $test_path"
      fi
    done < <(
      awk '
        NR == 1 && $0 == "---" { inside = 1; next }
        inside && $0 == "---" { exit }
        inside && $0 == "tests:" { in_list = 1; next }
        in_list && /^[^[:space:]-]/ { exit }
        in_list && /^  - .+/ {
          sub(/^  - /, "")
          print
        }
      ' "$file"
    )
  fi

  if ! section_has_list_item "$file" "Acceptance Criteria"; then
    fail "$file Acceptance Criteria must contain at least one list item"
  fi

  if ! section_has_list_item "$file" "Test Mapping"; then
    fail "$file Test Mapping must contain at least one list item"
  fi

  if [ -f "$index_file" ]; then
    base_name="$(basename "$file")"
    if ! grep -q "(${base_name})" "$index_file"; then
      fail "$file is not referenced from Specs/index.md"
    fi
  fi
done

if [ -f "$index_file" ]; then
  while IFS= read -r target; do
    case "$target" in
      http://*|https://*)
        continue
        ;;
      Specs/*)
        resolved="$target"
        ;;
      *)
        resolved="Specs/$target"
        ;;
    esac

    if [ ! -f "$resolved" ]; then
      fail "$index_file references missing file: $target"
    fi
  done < <(grep -Eo '\]\([^)]+\.md\)' "$index_file" | sed -E 's/^\]\((.*)\)$/\1/' || true)
fi

if [ "$failures" -gt 0 ]; then
  exit 1
fi

printf "Spec validation passed (%s specs).\n" "${#spec_files[@]}"
