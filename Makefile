# Master of Defense remake -- data pipeline, tests and platform exports.
# Run `make help` for the list of targets.

SHELL := /bin/bash
.DEFAULT_GOAL := help

# --- Tools ---------------------------------------------------------------------------------
GODOT ?= $(or $(shell command -v godot 2>/dev/null),/Applications/Godot.app/Contents/MacOS/Godot)
PYTHON ?= python3
ADB ?= adb

# --- Paths ---------------------------------------------------------------------------------
PROJECT := godot
DATA_DIR ?= MasterOfDefense_unpacked/Data
BUILD_DIR ?= build
WEB_DIR := $(BUILD_DIR)/web
ANDROID_DIR := $(BUILD_DIR)/android
IOS_DIR := $(BUILD_DIR)/ios

# Exports are written relative to $(PROJECT) (see export_presets.cfg), so paths get a `../`.
WEB_OUT := $(WEB_DIR)/index.html
APK_DEBUG := $(ANDROID_DIR)/MasterOfDefense-debug.apk
APK_RELEASE := $(ANDROID_DIR)/MasterOfDefense-release.apk
APK_EMULATOR := $(ANDROID_DIR)/MasterOfDefense-emulator.apk
IOS_OUT := $(IOS_DIR)/MasterOfDefense.ipa
IOS_XCODEPROJ := $(IOS_DIR)/MasterOfDefense.xcodeproj
IOS_TEAM_ID ?=
ANDROID_PACKAGE := org.masterofdefense.remake
# Trimmed release template built from the Godot sources (tools/build_android_template.sh).
# When it exists, `android-release` exports with the "Android Custom" preset (which points
# custom_template/release at it); otherwise with the stock "Android" preset.
ANDROID_TEMPLATE := $(BUILD_DIR)/templates/android_release.apk
ANDROID_RELEASE_PRESET = $(if $(wildcard $(ANDROID_TEMPLATE)),Android Custom,Android)
GODOT_SRC ?=

# Release APK signing: Godot reads these from the environment during a headless export.
# export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=... _USER=... _PASSWORD=...
# Without them `android-release` signs with the editor's debug keystore (the one `android` uses).
GODOT_EDITOR_SETTINGS := $(wildcard $(HOME)/Library/Application\ Support/Godot/editor_settings-4.*.tres)
ANDROID_DEBUG_KEYSTORE ?= $(or $(shell sed -nE 's|^export/android/debug_keystore = "(.*)"|\1|p' $(GODOT_EDITOR_SETTINGS) 2>/dev/null | tail -1),$(HOME)/Library/Application Support/Godot/keystores/debug.keystore)
ANDROID_DEBUG_KEYSTORE_USER ?= androiddebugkey
ANDROID_DEBUG_KEYSTORE_PASS ?= $(or $(shell sed -nE 's|^export/android/debug_keystore_pass = "(.*)"|\1|p' $(GODOT_EDITOR_SETTINGS) 2>/dev/null | tail -1),android)
WEB_PORT ?= 8060
TEST_FILTER ?=

GODOT_HEADLESS := $(GODOT) --headless --path $(PROJECT)

# --- Help ----------------------------------------------------------------------------------
.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | sort | awk -F ':.*## ' '{printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Variables: GODOT=$(GODOT)"
	@echo "           DATA_DIR=$(DATA_DIR) BUILD_DIR=$(BUILD_DIR) WEB_PORT=$(WEB_PORT)"

# --- Data pipeline (original assets -> Godot) ----------------------------------------------
.PHONY: data assets import reimport pipeline defold defold-run defold-web defold-android
data: ## Export tables, paths and texts from the unpacked original to godot/data
	$(PYTHON) tools/export_godot_data.py $(DATA_DIR) $(PROJECT)/data

assets: ## Convert B3D/MD2 models, textures and sounds to godot/assets
	$(PYTHON) tools/convert_all.py $(DATA_DIR) $(PROJECT)

import: ## Import resources headlessly (fills .godot/imported)
	$(GODOT_HEADLESS) --import

reimport: ## Drop the import cache and import everything again (after changing an import script)
	rm -rf $(PROJECT)/.godot/imported
	$(MAKE) import

pipeline: data assets import ## Full pipeline: data + assets + import

defold: ## Export all locations + entities for the Defold port (defold/, needs godot/assets and data)
	$(PYTHON) defold/tools/export_defold.py

defold-run: defold ## Build the Defold port with bob and run it (ARGS="--config=main.demo=1", VARIANT=debug for the log)
	defold/tools/bob.sh run $(ARGS)

defold-web: defold ## Bundle the Defold port for the browser into build/defold-web
	defold/tools/bob.sh web

defold-android: defold ## Bundle the Defold port as an .apk (debug keystore) into build/defold-android
	defold/tools/bob.sh android

# --- Icons ---------------------------------------------------------------------------------
ICON_PNG := $(PROJECT)/icons/icon_1024.png
ICON_PNGS := $(addprefix $(PROJECT)/icons/,icon_256.png android_main_192.png android_fg_432.png android_bg_432.png android_mono_432.png ios_app_store_1024.png)

.PHONY: icon icons
icon: check-assets ## Re-render icons/icon_1024.png from the Military tower model (needs a window)
	$(GODOT) --path $(PROJECT) -s res://tools/render_icon.gd

icons: $(ICON_PNGS) ## Derive the Android / App Store launcher PNGs (godot/icons) from icons/icon_1024.png

$(ICON_PNGS): $(ICON_PNG) $(PROJECT)/tools/make_icons.gd
	$(GODOT_HEADLESS) -s res://tools/make_icons.gd

# --- Tests and running ---------------------------------------------------------------------
.PHONY: test test-godot test-tools test-sim run
test: test-godot test-tools test-sim ## Run all tests

test-godot: ## Headless GDScript tests (TEST_FILTER=test_towers to narrow)
	$(GODOT_HEADLESS) -s res://tests/run_tests.gd $(if $(TEST_FILTER),-- --filter=$(TEST_FILTER))

test-tools: ## Python tests of the conversion tools
	$(PYTHON) -m unittest discover -s tools/tests -v

test-sim: ## Headless tests of the Defold port's Lua simulation (needs lua and godot/data)
	@command -v lua >/dev/null || { echo "lua not found: skipping test-sim"; exit 0; }
	lua defold/tests/run_sim_tests.lua

run: ## Run the game on the desktop (ARGS="--location=1 --debug")
	$(GODOT) --path $(PROJECT) $(if $(ARGS),-- $(ARGS))

# --- Export preconditions ------------------------------------------------------------------
.PHONY: check-assets check-templates
check-assets:
	@test -f $(PROJECT)/assets/manifest.json || { echo "godot/assets is missing: run 'make assets' (needs $(DATA_DIR))"; exit 1; }

check-templates: ## Verify the export templates for this Godot version are installed
	@ver=$$($(GODOT) --version | sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?)\.([a-z]+).*/\1.\3/'); \
	dir="$$HOME/Library/Application Support/Godot/export_templates/$$ver"; \
	test -d "$$dir" || { echo "export templates for $$ver not found in $$dir"; exit 1; }; \
	for f in web_nothreads_release.zip web_nothreads_debug.zip android_release.apk android_debug.apk ios.zip; do \
		test -f "$$dir/$$f" || { echo "template $$f missing in $$dir"; exit 1; }; \
	done; echo "export templates $$ver: ok"

# --- Web -----------------------------------------------------------------------------------
WEB_ZIP := $(BUILD_DIR)/MasterOfDefense-web.zip

.PHONY: web web-debug web-zip serve-web
web: check-assets check-templates icons import ## Export the release web build to build/web
	mkdir -p $(WEB_DIR)
	$(GODOT_HEADLESS) --export-release "Web" ../$(WEB_OUT)
	@test -f $(WEB_OUT) && test -f $(WEB_DIR)/index.wasm || { echo "web export failed"; exit 1; }
	@du -sh $(WEB_DIR)

web-zip: web ## Export the release web build and pack it into build/MasterOfDefense-web.zip
	rm -f $(WEB_ZIP)
	cd $(WEB_DIR) && zip -r -X -9 $(CURDIR)/$(WEB_ZIP) . -x '.DS_Store' -x '*/.DS_Store'
	@ls -lh $(WEB_ZIP)

web-debug: check-assets check-templates icons import ## Export the debug web build to build/web
	mkdir -p $(WEB_DIR)
	$(GODOT_HEADLESS) --export-debug "Web" ../$(WEB_OUT)
	@test -f $(WEB_OUT) && test -f $(WEB_DIR)/index.wasm || { echo "web export failed"; exit 1; }

serve-web: ## Serve build/web over HTTP (WEB_PORT, default 8060)
	@test -f $(WEB_OUT) || { echo "no web build: run 'make web'"; exit 1; }
	@echo "http://localhost:$(WEB_PORT)/"
	cd $(WEB_DIR) && $(PYTHON) -m http.server $(WEB_PORT)

# --- Android -------------------------------------------------------------------------------
.PHONY: android android-release android-emulator android-template android-install android-run android-log android-info
android-template: ## Build the trimmed release template from the Godot sources (GODOT_SRC=/path/to/godot, tag 4.7.2-stable)
	@test -n "$(GODOT_SRC)" || { echo "set GODOT_SRC to a checkout of godotengine/godot at 4.7.2-stable"; exit 1; }
	tools/build_android_template.sh $(GODOT_SRC) $(dir $(ANDROID_TEMPLATE))

android: check-assets check-templates icons import ## Export the debug APK (arm64, debug keystore)
	mkdir -p $(ANDROID_DIR)
	$(GODOT_HEADLESS) --export-debug "Android" ../$(APK_DEBUG)
	@test -f $(APK_DEBUG) || { echo "android export failed"; exit 1; }
	@ls -lh $(APK_DEBUG)

android-release: check-assets check-templates icons import ## Export the release APK (custom template if built, else stock; GODOT_ANDROID_KEYSTORE_RELEASE_*, else the debug key)
	@mkdir -p $(ANDROID_DIR)
	@echo "preset: $(ANDROID_RELEASE_PRESET)$(if $(wildcard $(ANDROID_TEMPLATE)), ($(ANDROID_TEMPLATE)), (stock template; 'make android-template' builds the trimmed one))"
	@if [ -n "$$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" ]; then \
		test -f "$$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" || { echo "keystore not found: $$GODOT_ANDROID_KEYSTORE_RELEASE_PATH"; exit 1; }; \
		signed_with="release keystore $$GODOT_ANDROID_KEYSTORE_RELEASE_PATH"; \
	else \
		ks="$(ANDROID_DEBUG_KEYSTORE)"; \
		test -f "$$ks" || { echo "debug keystore not found: $$ks (open the Android export in the editor once)"; exit 1; }; \
		export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$$ks"; \
		export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$(ANDROID_DEBUG_KEYSTORE_USER)"; \
		export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(ANDROID_DEBUG_KEYSTORE_PASS)"; \
		signed_with="DEBUG keystore $$ks"; \
	fi; \
	$(GODOT_HEADLESS) --export-release "$(ANDROID_RELEASE_PRESET)" ../$(APK_RELEASE); \
	test -f $(APK_RELEASE) || { echo "android export failed"; exit 1; }; \
	ls -lh $(APK_RELEASE); \
	case "$$signed_with" in DEBUG*) \
		echo "WARNING: $(APK_RELEASE) is signed with the $$signed_with -- not for distribution;"; \
		echo "         set GODOT_ANDROID_KEYSTORE_RELEASE_PATH, _USER and _PASSWORD for a release key";; \
	esac

android-emulator: check-assets check-templates icons import ## Export the debug APK for the emulator (forces gl_compatibility: it cannot present Vulkan)
	mkdir -p $(ANDROID_DIR)
	$(GODOT_HEADLESS) --export-debug "Android Emulator" ../$(APK_EMULATOR)
	@test -f $(APK_EMULATOR) || { echo "android export failed"; exit 1; }
	@ls -lh $(APK_EMULATOR)

android-install: ## Install the debug APK on the connected device (APK=... for another one)
	$(ADB) install -r $(or $(APK),$(APK_DEBUG))

android-run: ## Launch the game on the connected device
	$(ADB) shell monkey -p $(ANDROID_PACKAGE) -c android.intent.category.LAUNCHER 1

android-log: ## Follow the Godot log of the connected device
	$(ADB) logcat -s godot

android-info: ## Print package, version, orientation and native code of the debug APK
	@aapt=$$(ls -d "$${ANDROID_HOME:-$$HOME/Library/Android/sdk}"/build-tools/*/aapt 2>/dev/null | tail -1); \
	test -n "$$aapt" || { echo "aapt not found in the Android SDK"; exit 1; }; \
	"$$aapt" dump badging $(APK_DEBUG) 2>/dev/null | grep -E "^(package|application-label:|native-code|sdkVersion|targetSdkVersion|supports-screens|launchable-activity)"

# --- iOS -----------------------------------------------------------------------------------
.PHONY: ios ios-open
ios: check-assets check-templates icons import ## Export the Xcode project to build/ios (IOS_TEAM_ID=XXXXXXXXXX once; sign in Xcode)
	@if [ -n "$(IOS_TEAM_ID)" ]; then \
		sed -i '' 's|^application/app_store_team_id=.*|application/app_store_team_id="$(IOS_TEAM_ID)"|' $(PROJECT)/export_presets.cfg; \
	fi
	@grep -q '^application/app_store_team_id=""' $(PROJECT)/export_presets.cfg && \
		{ echo "App Store Team ID is empty: run 'make ios IOS_TEAM_ID=<team id>' (stored in godot/export_presets.cfg)"; exit 1; } || true
	mkdir -p $(IOS_DIR)
	$(GODOT_HEADLESS) --export-release "iOS" ../$(IOS_OUT)
	@test -d $(IOS_XCODEPROJ) || { echo "ios export failed"; exit 1; }
	@du -sh $(IOS_DIR)

ios-open: ## Open the exported Xcode project
	open $(IOS_XCODEPROJ)

# --- All platforms and cleanup -------------------------------------------------------------
.PHONY: all clean clean-import
all: web android ios ## Export web, Android (debug) and iOS

clean: ## Remove build/
	rm -rf $(BUILD_DIR)

clean-import: ## Remove the Godot import cache (.godot)
	rm -rf $(PROJECT)/.godot
