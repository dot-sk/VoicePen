PROJECT := VoicePen.xcodeproj
SCHEME := VoicePen
DESTINATION := platform=macOS
DERIVED_DATA := /private/tmp/VoicePenDerivedData
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
APP := $(DERIVED_DATA)/Build/Products/Debug/VoicePen.app

.PHONY: help build test run clean-derived resolve-packages

help:
	@printf "VoicePen commands:\n"
	@printf "  make build            Build the macOS app\n"
	@printf "  make test             Run unit tests\n"
	@printf "  make run              Build and launch the app\n"
	@printf "  make resolve-packages Resolve Swift package dependencies\n"
	@printf "  make clean-derived    Remove derived data used by these commands\n"

build:
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild build \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)"

test:
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild test \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-only-testing:VoicePenTests

run: build
	open "$(APP)"

resolve-packages:
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild -resolvePackageDependencies \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-derivedDataPath "$(DERIVED_DATA)"

clean-derived:
	rm -rf "$(DERIVED_DATA)"
