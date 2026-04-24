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
	@echo "Packaging nextNote $(VERSION)…"
	@rm -rf dist $(DMG_STAGING)
	@mkdir -p dist $(DMG_STAGING)
	@APP=$$(find $(BUILD_DIR) -name "nextNote.app" -type d | head -1); \
	if [ -z "$$APP" ]; then echo "release: nextNote.app not found"; exit 1; fi; \
	ditto --norsrc --noextattr --noacl -c -k --keepParent "$$APP" "dist/nextNote-$(VERSION).zip"; \
	cp -R "$$APP" "$(DMG_STAGING)/"; \
	ln -s /Applications "$(DMG_STAGING)/Applications"; \
	hdiutil create -volname "nextNote $(VERSION)" \
		-srcfolder "$(DMG_STAGING)" \
		-ov -format UDZO \
		"dist/nextNote-$(VERSION).dmg" >/dev/null; \
	rm -rf "$(DMG_STAGING)"
	@echo ""
	@ls -lh dist/
