# Optional machine-specific variables; never committed.
-include Makefile.local

PYTHON ?= python3
ENV ?= dev
PLATFORM ?= auto
DEVICE ?=
API_URL ?= $(TYPEFLUX_API_URL)
MODE ?= debug
APK_MODE ?= profile
SCREENSHOT_DIR ?= build/screenshots
PREVIEW_FONT ?= $(TYPEFLUX_PREVIEW_FONT)
APK ?= build/app/outputs/flutter-apk/app-arm64-v8a-$(APK_MODE).apk

export FLUTTER TYPEFLUX_TOOLS API_URL
TOOL = $(PYTHON) scripts/flutter_tool.py
APP = $(TOOL) --environment "$(ENV)" --platform "$(PLATFORM)" --device "$(DEVICE)"

.DEFAULT_GOAL := help
.PHONY: help config run local dev dev-nas dev-macbook dev-macmini prod android ios windows deps doctor devices emulators emulator analyze test coverage format format-check tool-test check screenshots build apk apk-debug apk-release apk-verify ios-build windows-build clean

help: ## List commands (ENV=local|dev|dev-nas|dev-macbook|dev-macmini|prod, PLATFORM=auto|android|ios|windows)
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_0-9-]+:.*## / {printf "%-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

config: ## Show resolved tools, API and launch command without starting the app
	$(APP) --dry-run run --$(MODE) $(RUN_ARGS)

run: ## Start attached to this terminal (default: dev server, Flutter device selection)
	$(APP) run --$(MODE) $(RUN_ARGS)

local: ## Start against local API (Android emulator: 10.0.2.2; others: 127.0.0.1)
	$(MAKE) run ENV=local

dev: ## Start against the shared HTTPS development API
	$(MAKE) run ENV=dev

dev-nas: ## Start against the NAS API on the local network
	$(MAKE) run ENV=dev-nas

dev-macbook: ## Start against the MacBook API on the local network
	$(MAKE) run ENV=dev-macbook

dev-macmini: ## Start against the Mac mini API on the local network
	$(MAKE) run ENV=dev-macmini

prod: ## Start against the production API
	$(MAKE) run ENV=prod

android: ## Start on a connected Android device; use DEVICE when more than one is connected
	$(MAKE) run PLATFORM=android

ios: ## Start on a connected iPhone or running iOS simulator (macOS only)
	$(MAKE) run PLATFORM=ios

windows: ## Start the Windows app (Windows host only)
	$(MAKE) run PLATFORM=windows

deps: ## Restore locked Flutter dependencies
	$(TOOL) pub get --enforce-lockfile

doctor: ## Inspect the Flutter/native toolchain
	$(TOOL) doctor -v

devices: ## List connected devices
	$(TOOL) devices

emulators: ## List installed emulators
	$(TOOL) emulators

emulator: ## Launch an installed emulator: make emulator EMULATOR=<id>
	$(TOOL) launch-emulator "$(EMULATOR)"

analyze: ## Run Dart static analysis
	$(TOOL) analyze --no-pub

test: ## Run Flutter tests (optional TEST_ARGS='test/some_test.dart')
	$(TOOL) test --no-pub $(TEST_ARGS)

coverage: ## Run all Flutter tests and write coverage/lcov.info
	$(TOOL) test --no-pub --coverage $(TEST_ARGS)

format: ## Format Dart sources and tests
	$(TOOL) dart format lib test

format-check: ## Check Dart formatting without editing files
	$(TOOL) dart format --output=none --set-exit-if-changed lib test

tool-test: ## Verify environment/device/toolchain command routing
	$(PYTHON) -m unittest discover -s scripts/tests -v

check: ## Run tooling tests, format check, analysis and full coverage in order
	$(MAKE) tool-test
	$(MAKE) deps
	$(MAKE) format-check
	$(MAKE) analyze
	$(MAKE) coverage

screenshots: ## Export the Flutter fixture screenshots; optionally set PREVIEW_FONT
	$(TOOL) --render-dir "$(SCREENSHOT_DIR)" --preview-font "$(PREVIEW_FONT)" test --no-pub test/mobile_design_test.dart test/auth_screenshots_test.dart test/settings_screenshots_test.dart test/expanded_screenshots_test.dart

build: apk ## Build the ARM64 Android profile test package

apk: ## Build ARM64 APK (APK_MODE=debug|profile|release, default: profile)
	$(APP) build apk --$(APK_MODE) --target-platform android-arm64 --split-per-abi --android-project-arg=force-version-code-ignoring-abi=true $(BUILD_ARGS)

apk-debug: ## Build a development APK
	$(MAKE) apk APK_MODE=debug

apk-release: ## Build a release-mode APK (signing is still development-only)
	$(MAKE) apk APK_MODE=release

apk-verify: ## Verify APK ZIP, ARM64 contents, signature and metadata (optional APK=path)
	$(TOOL) verify-apk "$(APK)"

ios-build: ## Build the iOS simulator app without signing (macOS only)
	$(APP) build ios --simulator --debug --no-codesign $(BUILD_ARGS)

windows-build: ## Build Windows debug app (Windows host only)
	$(APP) build windows --debug $(BUILD_ARGS)

clean: ## Remove generated Flutter build outputs
	$(TOOL) clean
