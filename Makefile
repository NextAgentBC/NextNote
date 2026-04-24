.PHONY: gen build build-fast build-release xcodebuild-app xcodebuild-debug run run-fast launch clean sign help release release-signed notarize

# Build output lives in build.nosync/ — the .nosync suffix tells iCloud
# Documents to skip the directory, preventing multi-GB .app bundles from
# trying to sync up to CloudKit (which was erroring with "Quota exceeded"
# and polluting Console with FileProvider errors).
BUILD_DIR := build.nosync
CONFIG ?= Debug
SCHEME := nextNote
APP_NAME := NextNote
APP_BUNDLE := $(APP_NAME).app
APP_PATH := $(BUILD_DIR)/Build/Products/$(CONFIG)/$(APP_BUNDLE)

VERSION := $(shell awk '/MARKETING_VERSION/ {gsub(/"/,""); gsub(/,/,""); print $$NF}' project.yml | head -1)

# Developer ID Application — override on the command line if you need a
# different team: `make release-signed SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"`
SIGN_IDENTITY ?= Developer ID Application: MMC Wellness Group Inc. (WA4JUD762R)
# Keychain profile holding Apple-ID + app-specific password for notarytool.
# Set up once with:
#   xcrun notarytool store-credentials nextNote-notary \
#     --apple-id "you@example.com" --team-id "WA4JUD762R" --password "app-specific-pwd"
NOTARY_PROFILE ?= nextNote-notary

help:
	@echo "NextNote build targets:"
	@echo "  make gen             — regenerate nextNote.xcodeproj via xcodegen"
	@echo "  make build           — xcodebuild Debug (ad-hoc signed)"
	@echo "  make build-fast      — Debug build without regenerating xcodeproj"
	@echo "  make build-release   — xcodebuild Release (ad-hoc signed)"
	@echo "  make run             — build + launch NextNote.app"
	@echo "  make run-fast        — build-fast + launch NextNote.app"
	@echo "  make release         — ad-hoc signed dist/NextNote-<VER>.{zip,dmg}"
	@echo "  make release-signed  — Developer-ID-signed + notarized + stapled dist/"
	@echo "                         (needs SIGN_IDENTITY + NOTARY_PROFILE configured)"
	@echo "  make clean           — remove generated project and build products"

gen:
	xcodegen generate

# Disable xcodebuild's own codesign (it fails when iCloud tags the .app bundle
# with protected com.apple.fileprovider.fpfs#P xattrs that codesign rejects as
# "resource fork, Finder information, or similar detritus"). We sign after.
build: gen
	@$(MAKE) xcodebuild-app CONFIG=Debug
	@$(MAKE) sign CONFIG=Debug

# Fast path for normal Swift/UI iteration. Use `make gen` or `make build`
# after changing project.yml, package dependencies, entitlements, or resources.
build-fast:
	@$(MAKE) xcodebuild-app CONFIG=Debug
	@$(MAKE) sign CONFIG=Debug

build-release: gen
	@$(MAKE) xcodebuild-app CONFIG=Release
	@$(MAKE) sign CONFIG=Release

xcodebuild-debug:
	@$(MAKE) xcodebuild-app CONFIG=Debug

xcodebuild-app:
	@if command -v xcbeautify >/dev/null 2>&1; then \
		set -o pipefail; \
		xcodebuild \
			-project nextNote.xcodeproj \
			-scheme $(SCHEME) \
			-configuration $(CONFIG) \
			-destination 'platform=macOS' \
			-derivedDataPath $(BUILD_DIR) \
			CODE_SIGNING_ALLOWED=NO \
			CODE_SIGN_IDENTITY="" \
			build | xcbeautify; \
	else \
		xcodebuild \
			-project nextNote.xcodeproj \
			-scheme $(SCHEME) \
			-configuration $(CONFIG) \
			-destination 'platform=macOS' \
			-derivedDataPath $(BUILD_DIR) \
			CODE_SIGNING_ALLOWED=NO \
			CODE_SIGN_IDENTITY="" \
			build; \
	fi

# Strip xattrs (ditto --noextattr) then ad-hoc sign with the entitlements
# xcodebuild generated. This survives iCloud re-tagging between rebuilds.
sign:
	@APP="$(APP_PATH)"; \
	if [ ! -d "$$APP" ]; then echo "sign: $$APP not found"; exit 1; fi; \
	ENT=$$(find $(BUILD_DIR) -name "$(APP_BUNDLE).xcent" | head -1); \
	TMP=$$(mktemp -d)/$(APP_BUNDLE); \
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
	@$(MAKE) launch

run-fast: build-fast
	@$(MAKE) launch

launch:
	@APP="$(APP_PATH)"; \
	if [ ! -d "$$APP" ]; then echo "$$APP not found"; exit 1; fi; \
	pkill -9 -x nextNote 2>/dev/null || true; \
	pkill -9 -x "$(APP_NAME)" 2>/dev/null || true; \
	open -n "$$APP"

clean:
	rm -rf nextNote.xcodeproj $(BUILD_DIR) dist

# Package the built .app into dist/ as both a zip (fast, small) and a DMG
# (nice drag-to-Applications UX). `ditto` strips xattrs so Gatekeeper
# doesn't choke on iCloud's fileprovider tags.
DMG_STAGING := $(BUILD_DIR)/dmg-staging

release: build-release
	@echo "Packaging NextNote $(VERSION)…"
	@rm -rf dist $(DMG_STAGING)
	@mkdir -p dist $(DMG_STAGING)
	@APP="$(BUILD_DIR)/Build/Products/Release/$(APP_BUNDLE)"; \
	if [ ! -d "$$APP" ]; then echo "release: $$APP not found"; exit 1; fi; \
	cp -R "$$APP" "$(DMG_STAGING)/NextNote.app"; \
	cp LICENSE "$(DMG_STAGING)/LICENSE.txt"; \
	cp NOTICE "$(DMG_STAGING)/NOTICE.txt"; \
	{ \
	  echo "NextNote $(VERSION)"; \
	  echo ""; \
	  echo "════════════════════════════════════════════════════════════"; \
	  echo "INSTALL"; \
	  echo "════════════════════════════════════════════════════════════"; \
	  echo ""; \
	  echo "1. Drag NextNote.app into /Applications."; \
	  echo ""; \
	  echo "2. FIRST LAUNCH — Gatekeeper will block the app because it's"; \
	  echo "   ad-hoc signed (no paid Apple Developer ID). Fix it ONCE:"; \
	  echo ""; \
	  echo "   Easiest — paste this in Terminal (Applications → Utilities):"; \
	  echo ""; \
	  echo "     xattr -dr com.apple.quarantine /Applications/NextNote.app"; \
	  echo ""; \
	  echo "   Then double-click NextNote. Done."; \
	  echo ""; \
	  echo "   GUI alternative:"; \
	  echo "     a) Double-click NextNote → dialog says \"cannot be opened\""; \
	  echo "     b) Open System Settings → Privacy & Security"; \
	  echo "     c) Scroll down — see \"NextNote was blocked…\" → Open Anyway"; \
	  echo "     d) Enter your password, then click Open in the next dialog"; \
	  echo ""; \
	  echo "   The app is open source, not malware — the warning is Apple's"; \
	  echo "   default for any app not signed with a \$$99/year Developer ID."; \
	  echo ""; \
	  echo "3. Welcome screen lets you pick folders for Notes / Media / Ebooks,"; \
	  echo "   or click \"Use Defaults for All\" to auto-create them under"; \
	  echo "   ~/Documents/nextNote/."; \
	  echo ""; \
	  echo "════════════════════════════════════════════════════════════"; \
	  echo "OPTIONAL TOOLS"; \
	  echo "════════════════════════════════════════════════════════════"; \
	  echo ""; \
	  echo "  brew install yt-dlp ffmpeg      # YouTube downloads"; \
	  echo "  brew install ollama             # local LLM provider"; \
	  echo ""; \
	  echo "════════════════════════════════════════════════════════════"; \
	  echo ""; \
	  echo "Docs:    https://github.com/NextAgentBC/NextNote"; \
	  echo "License: Apache 2.0 (see LICENSE.txt + NOTICE.txt)"; \
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

# ────────────────────────────────────────────────────────────────────────────
# Developer-ID signed + notarized release.
#
# Prerequisites (one-time):
#   1. Paid Apple Developer Program account.
#   2. Developer ID Application certificate installed in the login Keychain.
#      Verify with: security find-identity -v -p codesigning
#   3. App-specific password at appleid.apple.com → Security.
#   4. Store the notary credential in the keychain (one-time):
#        xcrun notarytool store-credentials nextNote-notary \
#          --apple-id "you@example.com" \
#          --team-id  "WA4JUD762R" \
#          --password "xxxx-xxxx-xxxx-xxxx"
#
# Override identity / profile via env if needed:
#   make release-signed SIGN_IDENTITY="Developer ID Application: Foo (XXXX)" \
#                       NOTARY_PROFILE=my-profile
#
# Result: dist/NextNote-<VER>.{zip,dmg} — double-click and run, zero warnings.
# ────────────────────────────────────────────────────────────────────────────

release-signed: build-release
	@echo "▶ Signing NextNote $(VERSION) with: $(SIGN_IDENTITY)"
	@rm -rf dist $(DMG_STAGING)
	@mkdir -p dist $(DMG_STAGING)
	@APP="$(BUILD_DIR)/Build/Products/Release/$(APP_BUNDLE)"; \
	if [ ! -d "$$APP" ]; then echo "release-signed: $$APP not found"; exit 1; fi; \
	STAGED="$(DMG_STAGING)/NextNote.app"; \
	cp -R "$$APP" "$$STAGED"; \
	echo "  → deep codesign with hardened runtime + timestamp"; \
	codesign --force --deep --options runtime --timestamp \
		--entitlements nextNote/nextNote.release.entitlements \
		--sign "$(SIGN_IDENTITY)" \
		"$$STAGED" || exit 1; \
	echo "  → verify signature"; \
	codesign --verify --deep --strict --verbose=2 "$$STAGED" || exit 1; \
	echo "  → zip for notarytool upload"; \
	ZIP="$(DMG_STAGING)/notary-upload.zip"; \
	ditto -c -k --keepParent "$$STAGED" "$$ZIP"; \
	echo "  → submit to Apple notary service (this takes 1–5 minutes)…"; \
	xcrun notarytool submit "$$ZIP" \
		--keychain-profile "$(NOTARY_PROFILE)" \
		--wait || exit 1; \
	echo "  → staple notarization ticket onto app"; \
	xcrun stapler staple "$$STAGED" || exit 1; \
	xcrun stapler validate "$$STAGED" || exit 1; \
	rm -f "$$ZIP"; \
	echo "  → package LICENSE + NOTICE + README"; \
	cp LICENSE "$(DMG_STAGING)/LICENSE.txt"; \
	cp NOTICE "$(DMG_STAGING)/NOTICE.txt"; \
	{ \
	  echo "NextNote $(VERSION)"; \
	  echo ""; \
	  echo "1. Drag NextNote.app into /Applications."; \
	  echo "2. Double-click to launch — that's it."; \
	  echo "   (Signed and notarized by Apple; no Gatekeeper warnings.)"; \
	  echo ""; \
	  echo "3. Pick folders for Notes / Media / Ebooks on the Welcome screen,"; \
	  echo "   or click \"Use Defaults for All\"."; \
	  echo ""; \
	  echo "Optional tools:"; \
	  echo "  brew install yt-dlp ffmpeg      # YouTube downloads"; \
	  echo "  brew install ollama             # local LLM provider"; \
	  echo ""; \
	  echo "Docs:    https://github.com/NextAgentBC/NextNote"; \
	  echo "License: Apache 2.0 (see LICENSE.txt + NOTICE.txt)"; \
	} > "$(DMG_STAGING)/README.txt"; \
	ln -s /Applications "$(DMG_STAGING)/Applications"; \
	echo "  → zip for release"; \
	ditto --norsrc --noextattr --noacl -c -k --keepParent "$$STAGED" "dist/NextNote-$(VERSION).zip"; \
	echo "  → build DMG"; \
	hdiutil create -volname "NextNote $(VERSION)" \
		-srcfolder "$(DMG_STAGING)" \
		-ov -format UDZO \
		"dist/NextNote-$(VERSION).dmg" >/dev/null; \
	echo "  → submit DMG to notary service (second pass)…"; \
	xcrun notarytool submit "dist/NextNote-$(VERSION).dmg" \
		--keychain-profile "$(NOTARY_PROFILE)" \
		--wait || exit 1; \
	echo "  → staple DMG"; \
	xcrun stapler staple "dist/NextNote-$(VERSION).dmg" || exit 1; \
	xcrun stapler validate "dist/NextNote-$(VERSION).dmg" || exit 1; \
	rm -rf "$(DMG_STAGING)"
	@echo ""
	@echo "✅ Signed + notarized release ready:"
	@ls -lh dist/
