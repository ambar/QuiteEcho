.PHONY: build run clean

APP_NAME    = QuiteEcho
BUILD_DIR   = .build/release
APP_BUNDLE  = $(APP_NAME).app

UV_BIN ?= $(shell which uv)

build:
	swift build -c release
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/"
	@cp Resources/Info.plist "$(APP_BUNDLE)/Contents/"
	@cp scripts/asr_worker.py "$(APP_BUNDLE)/Contents/Resources/"
	@cp "$(UV_BIN)" "$(APP_BUNDLE)/Contents/Resources/uv"
	@chmod +x "$(APP_BUNDLE)/Contents/Resources/uv"
	@codesign --force --deep --sign - "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

run: build
	@open "$(APP_BUNDLE)"

dev:
	swift build
	@.build/debug/$(APP_NAME)

clean:
	swift package clean
	@rm -rf "$(APP_BUNDLE)" build dist asr_worker.spec
