# Release Checklist

Maintainer-facing notes for cutting a NextNote (Apache-2.0) release. Works for ad-hoc-signed distribution (free Apple ID / no developer program needed). If you later enroll in the Apple Developer Program, the notarization steps at the bottom become relevant.

---

## 1. Pre-flight

Bump versions in `project.yml` under `targets.nextNote.settings.base`:

```yaml
MARKETING_VERSION: "0.2.0"     # user-visible, shown in About
CURRENT_PROJECT_VERSION: "2"   # integer, increment every build shipped
```

Regenerate the project so Info.plist picks up the new values:

```sh
make gen
```

Update `CHANGELOG.md` (create if missing):

```md
## 0.2.0 — 2026-04-23
### Added
- Ebooks + Media roots separated from Notes
- Library menu with per-root Change / Reveal / Rescan
### Fixed
- Reader switching to wrong chapter when opening a different book
### Removed
- Voice dictation subsystem
```

Commit:

```sh
git commit -am "Release 0.2.0"
git tag v0.2.0
```

---

## 2. Build

```sh
make clean
make release
```

The `release` Makefile target (see below) produces:

- `dist/nextNote-<version>.zip`  — raw app bundle, zipped
- `dist/nextNote-<version>.dmg`  — disk image with Applications shortcut

---

## 3. Smoke test

Before uploading anywhere:

```sh
open dist/nextNote-<version>.dmg
```

Drag the app to `/Applications`, open it. Tick through:

- Welcome setup finishes, creates folders
- Open a note — edit, save, reopen
- Drop an `.epub` in Ebooks folder → Rescan Library → book appears
- Open a book — click a chapter, paging works
- Drop an `.mp3` in Media folder → rescan → click plays
- AI panel with your chosen provider — one round-trip works
- YouTube download (if `yt-dlp` installed)
- Settings round-trip (change something, quit, relaunch, verify persisted)
- Quit + relaunch — bookmarks resolved, no setup prompt

If anything is red, fix before shipping.

---

## 4. Push + GitHub release

```sh
git push origin main
git push origin v0.2.0
```

Create release on GitHub via the `gh` CLI:

```sh
gh release create v0.2.0 \
  dist/nextNote-0.2.0.dmg \
  dist/nextNote-0.2.0.zip \
  --title "nextNote 0.2.0" \
  --notes-file CHANGELOG.md
```

Or via the GitHub UI: **Releases → Draft a new release** → choose tag `v0.2.0`, paste changelog, upload both artifacts, **Publish**.

---

## 5. Post-release

- Bump MARKETING_VERSION to `0.3.0-dev` in `project.yml` for the next cycle.
- Announce wherever (Mastodon, X, Hacker News, r/macapps).

---

## Makefile `release` target

Add to `Makefile`:

```make
VERSION := $(shell awk '/MARKETING_VERSION/ {gsub(/"/,""); print $$2}' project.yml | head -1)

release: build
	@echo "Packaging nextNote $(VERSION)..."
	@rm -rf dist && mkdir -p dist
	@APP=$$(find $(BUILD_DIR) -name "nextNote.app" -type d | head -1); \
	if [ -z "$$APP" ]; then echo "nextNote.app not found"; exit 1; fi; \
	ditto --norsrc --noextattr --noacl -c -k --keepParent "$$APP" "dist/nextNote-$(VERSION).zip"; \
	hdiutil create -volname "nextNote" \
		-srcfolder "$$APP" \
		-ov -format UDZO \
		"dist/nextNote-$(VERSION).dmg"
	@echo "Artifacts:"
	@ls -lh dist/
```

The zip uses `ditto` so quarantine xattrs don't sneak in. The DMG is a compressed read-only image with just the `.app` inside.

If you want a prettier DMG with an **Applications** symlink side-by-side with the app:

```make
DMG_STAGING := build.nosync/dmg-staging

release: build
	@rm -rf dist $(DMG_STAGING) && mkdir -p dist $(DMG_STAGING)
	@APP=$$(find $(BUILD_DIR) -name "nextNote.app" -type d | head -1); \
	cp -R "$$APP" "$(DMG_STAGING)/"; \
	ln -s /Applications "$(DMG_STAGING)/Applications"; \
	ditto --norsrc --noextattr --noacl -c -k --keepParent "$$APP" "dist/nextNote-$(VERSION).zip"; \
	hdiutil create -volname "nextNote" \
		-srcfolder "$(DMG_STAGING)" \
		-ov -format UDZO \
		"dist/nextNote-$(VERSION).dmg"; \
	rm -rf "$(DMG_STAGING)"
	@echo "Artifacts:"
	@ls -lh dist/
```

---

## Ad-hoc signing — what users see

Because the build is signed with a dummy identity (not an Apple Developer ID), Gatekeeper treats it as unidentified. Users get one of:

1. **First-time right-click Open** — they right-click → Open, macOS shows "Are you sure", click Open. Works forever after.
2. **"App is damaged"** — happens if macOS couldn't even verify the signature. Workaround in the user guide: `xattr -dr com.apple.quarantine /Applications/nextNote.app`.

Document this in USER_GUIDE.md (already done).

---

## If / when you join the Apple Developer Program

$99/year unlocks Developer ID signing + notarization. Users see **zero** warnings, app opens like any commercial Mac app.

Set up once:

```sh
# In Xcode Preferences → Accounts, add your Apple ID.
# Find your Developer ID Application cert:
security find-identity -v -p codesigning

# Store app-specific password for notarytool:
xcrun notarytool store-credentials "nextNote-notary" \
    --apple-id "you@example.com" \
    --team-id "ABCDE12345" \
    --password "app-specific-password"
```

Replace the `sign` step in `Makefile` with:

```make
sign:
	codesign --force --sign "Developer ID Application: Your Name (ABCDE12345)" \
		--options runtime \
		--entitlements nextNote/nextNote.entitlements \
		--timestamp \
		"$(APP)"

notarize:
	ditto --norsrc --noextattr --noacl -c -k --keepParent "$(APP)" "$(APP).zip"
	xcrun notarytool submit "$(APP).zip" --keychain-profile "nextNote-notary" --wait
	xcrun stapler staple "$(APP)"
```

Then:

```sh
make build       # Debug build unchanged for dev
make release     # adds codesign + notarize + staple
```

Notarization round-trip is usually 1–5 minutes.

---

## Homebrew cask (future)

Once the project has a stable release cadence, consider publishing a Homebrew cask so users can install with `brew install --cask nextnote`. The cask formula is 10 lines of Ruby pointing at your latest GitHub release artifact.

Example `Casks/nextnote.rb` for a tap:

```ruby
cask "nextnote" do
  version "0.2.0"
  sha256 "<sha256 of the dmg>"
  url "https://github.com/<you>/nextNote/releases/download/v#{version}/nextNote-#{version}.dmg"
  name "nextNote"
  desc "Local-first Mac app for Markdown notes, EPUB reading, and media"
  homepage "https://github.com/<you>/nextNote"
  app "nextNote.app"
end
```

This goes in your own tap repo (`github.com/<you>/homebrew-<you>`), not the core Homebrew cask repo — core requires notarization + a stable reputation.
