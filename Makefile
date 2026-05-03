SHELL := /bin/bash

PROJECT := VoicePen.xcodeproj
SCHEME := VoicePen
DESTINATION := platform=macOS
DERIVED_DATA := /private/tmp/VoicePenDerivedData
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
CONFIGURATION ?= Debug
APP := $(DERIVED_DATA)/Build/Products/Debug/VoicePen.app
PACKAGE_CONFIGURATION := Release
PACKAGE_DIR := $(DERIVED_DATA)/Package
PACKAGE_ZIP := $(PACKAGE_DIR)/VoicePen-macOS-unsigned.zip
APPCAST_DIR := $(DERIVED_DATA)/Appcast
APPCAST_FILE := $(APPCAST_DIR)/appcast.xml
XCODEBUILD_CI_SIGNING := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
CODESIGN_IDENTITY ?= -
CODESIGN_FLAGS ?= --force --deep
FORMAT_PATHS := Package.swift VoicePen VoicePenTests VoicePenIntegrationTests VoicePenUITests
SWIFT_FORMAT := xcrun swift-format
SWIFTLINT ?= swiftlint
SWIFTLINT_CACHE := .swiftlint-cache
PERIPHERY ?= periphery
XCODEBUILD_FORMATTER ?= xcbeautify

.PHONY: help build package appcast prepare-release publish-release format format-check lint lint-fix swiftlint swiftlint-fix dead-code install-hooks check test integration-test validate-specs run clean-derived resolve-packages

help:
	@printf "VoicePen commands:\n"
	@printf "  make build            Build the macOS app\n"
	@printf "  make package          Build a downloadable unsigned app zip\n"
	@printf "  make appcast          Generate a Sparkle appcast for PACKAGE_ZIP\n"
	@printf "  make prepare-release VERSION=1.1.0 [BUILD=42]\n"
	@printf "  make publish-release VERSION=1.1.0\n"
	@printf "  make format           Format Swift source with swift-format\n"
	@printf "  make format-check     Check Swift formatting without changing files\n"
	@printf "  make lint             Run SwiftLint checks\n"
	@printf "  make lint-fix         Auto-fix Swift formatting and SwiftLint issues\n"
	@printf "  make dead-code        Run Periphery unused-code analysis\n"
	@printf "  make install-hooks    Enable repository pre-commit hooks\n"
	@printf "  make check            Run lint and unit tests\n"
	@printf "  make test             Validate specs and run non-hosted unit tests\n"
	@printf "  make integration-test Run hosted app integration tests\n"
	@printf "  make validate-specs   Validate spec files and index links\n"
	@printf "  make run              Build and launch the app\n"
	@printf "  make resolve-packages Resolve Swift package dependencies\n"
	@printf "  make clean-derived    Remove derived data used by these commands\n"

build:
	@set -o pipefail; \
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild build \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		$(XCODEBUILD_CI_SIGNING) | if command -v "$(XCODEBUILD_FORMATTER)" >/dev/null 2>&1; then "$(XCODEBUILD_FORMATTER)"; else cat; fi

package:
	$(MAKE) build CONFIGURATION="$(PACKAGE_CONFIGURATION)"
	codesign $(CODESIGN_FLAGS) --sign "$(CODESIGN_IDENTITY)" "$(DERIVED_DATA)/Build/Products/$(PACKAGE_CONFIGURATION)/VoicePen.app"
	rm -rf "$(PACKAGE_DIR)"
	mkdir -p "$(PACKAGE_DIR)"
	ditto -c -k --sequesterRsrc --keepParent "$(DERIVED_DATA)/Build/Products/$(PACKAGE_CONFIGURATION)/VoicePen.app" "$(PACKAGE_ZIP)"
	@printf "Created %s\n" "$(PACKAGE_ZIP)"

appcast:
	@test -n "$(DOWNLOAD_URL)" || (printf "Usage: make appcast DOWNLOAD_URL=https://github.com/.../VoicePen-macOS-unsigned.zip\n" >&2; exit 64)
	scripts/generate-appcast.sh "$(PACKAGE_ZIP)" "$(DOWNLOAD_URL)" "$(APPCAST_FILE)"

prepare-release:
	@test -n "$(VERSION)" || (printf "Usage: make prepare-release VERSION=1.1.0 [BUILD=42]\n" >&2; exit 64)
	@if [ -n "$(BUILD)" ]; then \
		scripts/prepare-release.sh "$(VERSION)" "$(BUILD)"; \
	else \
		scripts/prepare-release.sh "$(VERSION)"; \
	fi

publish-release:
	@test -n "$(VERSION)" || (printf "Usage: make publish-release VERSION=1.1.0\n" >&2; exit 64)
	scripts/publish-release.sh "$(VERSION)"

format:
	@xcrun --find swift-format >/dev/null || (printf "swift-format is required. Install Xcode 16+ or run brew install swift-format.\n" >&2; exit 127)
	$(SWIFT_FORMAT) format --configuration .swift-format --recursive --parallel --in-place $(FORMAT_PATHS)

format-check:
	@xcrun --find swift-format >/dev/null || (printf "swift-format is required. Install Xcode 16+ or run brew install swift-format.\n" >&2; exit 127)
	$(SWIFT_FORMAT) lint --configuration .swift-format --recursive --parallel --strict $(FORMAT_PATHS)

lint: swiftlint

lint-fix: format swiftlint-fix

swiftlint:
	@command -v "$(SWIFTLINT)" >/dev/null 2>&1 || (printf "SwiftLint is required. Install it with: brew install swiftlint\n" >&2; exit 127)
	DEVELOPER_DIR="$(DEVELOPER_DIR)" $(SWIFTLINT) lint --config .swiftlint.yml --cache-path "$(SWIFTLINT_CACHE)"

swiftlint-fix:
	@command -v "$(SWIFTLINT)" >/dev/null 2>&1 || (printf "SwiftLint is required. Install it with: brew install swiftlint\n" >&2; exit 127)
	DEVELOPER_DIR="$(DEVELOPER_DIR)" $(SWIFTLINT) lint --fix --config .swiftlint.yml --cache-path "$(SWIFTLINT_CACHE)"

dead-code:
	@command -v "$(PERIPHERY)" >/dev/null 2>&1 || (printf "Periphery is required. Install it with: brew install peripheryapp/periphery/periphery\n" >&2; exit 127)
	DEVELOPER_DIR="$(DEVELOPER_DIR)" $(PERIPHERY) scan --disable-update-check --config .periphery.yml -- \
		-destination "$(DESTINATION)" \
		$(XCODEBUILD_CI_SIGNING)

install-hooks:
	git config core.hooksPath .githooks
	chmod +x .githooks/pre-commit
	@printf "Git hooks enabled from .githooks\n"

check: lint test

test: validate-specs
	DEVELOPER_DIR="$(DEVELOPER_DIR)" swift test

integration-test:
	@set -o pipefail; \
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild test \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-only-testing:VoicePenIntegrationTests \
		$(XCODEBUILD_CI_SIGNING) | if command -v "$(XCODEBUILD_FORMATTER)" >/dev/null 2>&1; then "$(XCODEBUILD_FORMATTER)"; else cat; fi

validate-specs:
	bash scripts/validate-specs.sh

run: build
	open "$(APP)"

resolve-packages:
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild -resolvePackageDependencies \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-derivedDataPath "$(DERIVED_DATA)"

clean-derived:
	rm -rf "$(DERIVED_DATA)"
