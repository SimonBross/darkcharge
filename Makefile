# Builds DarkCharge.app from the Swift package. The bundle goes to build.noindex so
# Spotlight skips it; `make install` removes it once it's copied to /Applications.
#
#   make app       build build.noindex/DarkCharge.app
#   make test      run the tests
#   make install   copy the app into /Applications and start it
#   make release   Developer ID sign, notarize and zip build.noindex/DarkCharge.zip
#
# `make app` signs ad hoc, which is enough on this Mac. `make release` needs the Developer
# ID certificate in the keychain and notarytool credentials stored once with:
#   xcrun notarytool store-credentials darkcharge --apple-id <apple id> --team-id <team id>

APP      = build.noindex/DarkCharge.app
ZIP      = build.noindex/DarkCharge.zip
SIGN    ?= -
RELEASE_IDENTITY ?= Developer ID Application: Simon Bross (3FH4ZHNZV2)
NOTARY_PROFILE   ?= darkcharge
# Notarization needs a secure timestamp; ad hoc signing can't have one.
TIMESTAMP = $(if $(filter -,$(SIGN)),--timestamp=none,--timestamp)
BIN_DIR  = $(shell swift build -c release --show-bin-path)
SOURCES  = Package.swift $(shell find Sources -name '*.swift')

all: app

app: $(APP)

test:
	swift test

$(APP): $(SOURCES) Bundle/Info.plist Bundle/com.darkcharge.daemon.plist icon/DarkCharge.icns
	swift build -c release --product DarkCharge
	swift build -c release --product DarkChargeHelper
	rm -rf $@
	mkdir -p $@/Contents/MacOS $@/Contents/Resources $@/Contents/Library/LaunchDaemons
	cp $(BIN_DIR)/DarkCharge $(BIN_DIR)/DarkChargeHelper $@/Contents/MacOS/
	cp Bundle/Info.plist $@/Contents/
	cp Bundle/com.darkcharge.daemon.plist $@/Contents/Library/LaunchDaemons/
	cp icon/DarkCharge.icns $@/Contents/Resources/
	# Inside out: the helper first, then the app that contains it.
	codesign --force --options runtime $(TIMESTAMP) -s "$(SIGN)" $@/Contents/MacOS/DarkChargeHelper
	codesign --force --options runtime $(TIMESTAMP) -s "$(SIGN)" $@

# App icon: rendered from icon/make_icon.swift, then scaled to every size macOS wants.
icon/DarkCharge.icns: icon/make_icon.swift
	rm -rf icon/DarkCharge.iconset
	mkdir -p icon/DarkCharge.iconset
	swift icon/make_icon.swift icon/icon_1024.png
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s icon/icon_1024.png --out icon/DarkCharge.iconset/icon_$${s}x$${s}.png >/dev/null; \
		sips -z $$((s*2)) $$((s*2)) icon/icon_1024.png --out icon/DarkCharge.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns -o $@ icon/DarkCharge.iconset
	rm -rf icon/DarkCharge.iconset

# Updates the app in place rather than deleting and copying it, so its login item and
# helper registration keep pointing at it; --delete drops files the new build no longer has.
install: $(APP)
	-osascript -e 'tell application "DarkCharge" to quit' 2>/dev/null
	rsync -a --delete $(APP)/ /Applications/DarkCharge.app/
	# Leave only one DarkCharge.app, or the Apps overview lists the build copy too.
	rm -rf $(APP)
	open /Applications/DarkCharge.app

# A clean build, signed with the Developer ID, notarized by Apple, with the ticket stapled
# so it opens without a network check. The result is the zip to attach to a GitHub release.
release:
	rm -rf build.noindex
	$(MAKE) app SIGN="$(RELEASE_IDENTITY)"
	ditto -c -k --keepParent $(APP) $(ZIP)
	xcrun notarytool submit $(ZIP) --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple $(APP)
	rm $(ZIP)
	ditto -c -k --keepParent $(APP) $(ZIP)
	spctl --assess --type execute --verbose $(APP)
	@echo "Release ready: $(ZIP)"

clean:
	rm -rf .build build.noindex icon/DarkCharge.icns

.PHONY: all app test install release clean
