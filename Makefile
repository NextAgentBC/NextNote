.PHONY: gen build run clean sign help release

# Build output lives in build.nosync/ — the .nosync suffix tells iCloud
# Documents to skip the directory, preventing multi-GB .app bundles from
# trying to sync up to CloudKit (which was erroring with "Quota exceeded"
# and polluting Console with FileProvider errors).
BUILD_DIR := build.nosync

VERSION := $(shell awk '/MARKETING_VERSION/ {gsub(/"/,""); gsub(/,/,""); print $$NF}' project.yml | head -1)

help:
	@echo "nextNote build targets:"
	@echo "  make gen      — regenerate nextNote.xcodeproj via xcodegen"
	@echo "  make build    — xcodebuild Debug (codesigns via post-step to survive iCloud xattrs)"
	@echo "  make run      — build + launch nextNote.app"
	@echo "  make release  — build + package dist/nextNote-<VERSION>.{zip,dmg}"
	@echo "  make clean    — remove generated project and build products"

gen:
	xcodegen generate

# Disable xcodebuild's own codesign (it fails when iCloud tags the .app bundle
# with protected com.apple.fileprovider.fpfs#P xattrs that codesign rejects as
# "resource fork, Finder information, or similar detritus"). We sign after.
build: gen
	xcodebuild \
		-project nextNote.xcodeproj \
		-scheme nextNote \
		-configuration Debug \
		-destination 'platform=macOS' \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGNING_ALLOWED=NO \
		CODE_SIGN_IDENTITY="" \
		build | xcbeautify || xcodebuild \
		-project nextNote.xcodeproj \
		-scheme nextNote \
		-configuration Debug \
		-destination 'platform=macOS' \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGNING_ALLOWED=NO \
		CODE_SIGN_IDENTITY="" \
		build
	@$(MAKE) sign

# Strip xattrs (ditto --noextattr) then ad-hoc sign with the entitlements
# xcodebuild generated. This survives iCloud re-tagging between rebuilds.
sign:
	@APP=$$(find $(BUILD_DIR) -name "nextNote.app" -type d | head -1); \
	if [ -z "$$APP" ]; then echo "sign: nextNote.app not found"; exit 1; fi; \
	ENT=$$(find $(BUILD_DIR) -name "nextNote.app.xcent" | head -1); \
	TMP=$$(mktemp -d)/nextNote.app; \
	ditto --norsrc --noextattr --noacl "$$APP" "$$TMP" && \
	rm -rf "$$APP" && \
	ditto --norsrc --noextattr --noacl "$$TMP" "$$APP" && \
	rm -rf "$$(dirname $$TMP)"; \
	if [ -n "$$ENT" ]; then \
		codesign --force --sign - --entitlements "$$ENT" --timestamp=none --generate-entitlement-der "$$APP"; \
	else \
		codesign --force --sign - --timestamp=none "$$APP"; \
	fi

run: build
	@APP=$$(find $(BUILD_DIR) -name "nextNote.app" -type d | head -1); \
	if [ -z "$$APP" ]; then echo "nextNote.app not found"; exit 1; fi; \
	pkill -9 -f nextNote 2>/dev/null || true; \
	open "$$APP"

clean:
	rm -rf nextNote.xcodeproj $(BUILD_DIR) dist

# Package the built .app into dist/ as both a zip (fast, small) and a DMG
# (nice drag-to-Applications UX). `ditto` strips xattrs so Gatekeeper
# doesn't choke on iCloud's fileprovider tags.
DMG_STAGING := $(BUILD_DIR)/dmg-staging

release: build
	@echo "Packaging NextNote $(VERSION)…"
	@rm -rf dist $(DMG_STAGING)
	@mkdir -p dist $(DMG_STAGING)
	@APP=$$(find $(BUILD_DIR) -name "nextNote.app" -type d | head -1); \
	if [ -z "$$APP" ]; then echo "release: nextNote.app not found"; exit 1; fi; \
	cp -R "$$APP" "$(DMG_STAGING)/NextNote.app"; \
	cp LICENSE "$(DMG_STAGING)/LICENSE.txt"; \
	cp NOTICE "$(DMG_STAGING)/NOTICE.txt"; \
	{ \
	  echo "NextNote $(VERSION)"; \
	  echo ""; \
	  echo "1. Drag NextNote.app into /Applications."; \
	  echo "2. First launch: right-click the app icon → Open."; \
	  echo "   macOS Gatekeeper asks once — click Open."; \
	  echo "   (Ad-hoc signed; this confirmation is only needed once.)"; \
	  echo ""; \
	  echo "3. The Welcome screen lets you pick folders for Notes / Media / Ebooks,"; \
	  echo "   or click \"Use Defaults for All\" to auto-create them under"; \
	  echo "   ~/Documents/nextNote/."; \
	  echo ""; \
	  echo "Optional tools:"; \
	  echo "  brew install yt-dlp ffmpeg      # YouTube downloads"; \
	  echo "  brew install ollama             # local LLM provider"; \
	  echo ""; \
	  echo "Docs: https://github.com/NextAgentBC/NextNote"; \
	  echo ""; \
	  echo "Licensed under Apache 2.0. See LICENSE.txt + NOTICE.txt."; \
	} > "$(DMG_STAGING)/README.txt"; \
	ln -s /Applications "$(DMG_STAGING)/Applications"; \
	ditto --norsrc --noextattr --noacl -c -k --keepParent "$(DMG_STAGING)/NextNote.app" "dist/NextNote-$(VERSION).zip"; \
	hdiutil create -volname "NextNote $(VERSION)" \
		-srcfolder "$(DMG_STAGING)" \
		-ov -format UDZO \
		"dist/NextNote-$(VERSION).dmg" >/dev/null; \
	rm -rf "$(DMG_STAGING)"
	@echo ""
	@ls -lh dist/
