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
XCODEBUILD_CI_SIGNING := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

.PHONY: help build package prepare-release publish-release test test-strict validate-specs run clean-derived resolve-packages

help:
	@printf "VoicePen commands:\n"
	@printf "  make build            Build the macOS app\n"
	@printf "  make package          Build a downloadable unsigned app zip\n"
	@printf "  make prepare-release VERSION=1.1.0 [BUILD=42]\n"
	@printf "  make publish-release VERSION=1.1.0\n"
	@printf "  make test             Run unit tests\n"
	@printf "  make test-strict      Validate specs and run unit tests\n"
	@printf "  make validate-specs   Validate spec files and index links\n"
	@printf "  make run              Build and launch the app\n"
	@printf "  make resolve-packages Resolve Swift package dependencies\n"
	@printf "  make clean-derived    Remove derived data used by these commands\n"

build:
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild build \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		$(XCODEBUILD_CI_SIGNING)

package:
	$(MAKE) build CONFIGURATION="$(PACKAGE_CONFIGURATION)"
	rm -rf "$(PACKAGE_DIR)"
	mkdir -p "$(PACKAGE_DIR)"
	ditto -c -k --keepParent "$(DERIVED_DATA)/Build/Products/$(PACKAGE_CONFIGURATION)/VoicePen.app" "$(PACKAGE_ZIP)"
	@printf "Created %s\n" "$(PACKAGE_ZIP)"

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

test:
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild test \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-only-testing:VoicePenTests \
		$(XCODEBUILD_CI_SIGNING)

validate-specs:
	bash scripts/validate-specs.sh

test-strict: validate-specs
	$(MAKE) test

run: build
	open "$(APP)"

resolve-packages:
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild -resolvePackageDependencies \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-derivedDataPath "$(DERIVED_DATA)"

clean-derived:
	rm -rf "$(DERIVED_DATA)"
