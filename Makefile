.PHONY: build run dmg clean release

APP_NAME    = QuiteEcho
BUILD_DIR   = .build/release
APP_BUNDLE  = $(APP_NAME).app
DIST_DIR    = dist
DMG_FILE    = $(DIST_DIR)/$(APP_NAME).dmg

UV_BIN ?= $(shell which uv)

define assemble_app
	@rm -rf "$(1)"
	@mkdir -p "$(1)/Contents/MacOS"
	@mkdir -p "$(1)/Contents/Resources"
	@cp "$(BUILD_DIR)/$(APP_NAME)" "$(1)/Contents/MacOS/"
	@cp Resources/Info.plist "$(1)/Contents/"
	@cp Resources/AppIcon.icns "$(1)/Contents/Resources/"
	@cp scripts/asr_worker.py "$(1)/Contents/Resources/"
	@cp "$(UV_BIN)" "$(1)/Contents/Resources/uv"
	@chmod +x "$(1)/Contents/Resources/uv"
	@codesign --force --deep --sign - "$(1)"
endef

build:
	@test -n "$(UV_BIN)" || (echo "Error: uv not found. Run: make build UV_BIN=/path/to/uv" && exit 1)
	swift build -c release
	$(call assemble_app,$(APP_BUNDLE))
	@echo "Built $(APP_BUNDLE)"

run: build
	@open "$(APP_BUNDLE)"

dev:
	swift build
	@.build/debug/$(APP_NAME)

dmg:
	@test -n "$(UV_BIN)" || (echo "Error: uv not found. Run: make dmg UV_BIN=/path/to/uv" && exit 1)
	swift build -c release
	$(call assemble_app,$(DIST_DIR)/$(APP_NAME).app)
	@rm -rf "$(DIST_DIR)/dmg" "$(DMG_FILE)"
	@mkdir -p "$(DIST_DIR)/dmg"
	@cp -r "$(DIST_DIR)/$(APP_NAME).app" "$(DIST_DIR)/dmg/"
	@ln -s /Applications "$(DIST_DIR)/dmg/Applications"
	@hdiutil create -volname "$(APP_NAME)" -srcfolder "$(DIST_DIR)/dmg" -ov -format UDZO "$(DMG_FILE)"
	@rm -rf "$(DIST_DIR)/dmg" "$(DIST_DIR)/$(APP_NAME).app"
	@echo "Built $(DMG_FILE)"

clean:
	swift package clean
	@rm -rf "$(APP_BUNDLE)" "$(DIST_DIR)"

release:
	@test -n "$(VERSION)" || (echo "Usage: make release VERSION=1.0.0" && exit 1)
	@bash scripts/bump-version.sh $(VERSION)
	@git add Resources/Info.plist Sources/QuiteEcho/MainWindow.swift pyproject.toml
	@git commit -m "Release v$(VERSION)"
	@git tag "v$(VERSION)"
	@echo "Done. Run 'git push && git push --tags' to trigger the release workflow."
