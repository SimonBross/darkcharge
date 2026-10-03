# Builds DarkCharge.app from the Swift package. The bundle goes to build.noindex so
# Spotlight doesn't list it next to the copy in /Applications.
#
#   make app       build build.noindex/DarkCharge.app
#   make test      run the tests
#   make install   copy the app into /Applications and start it
#
# Signing is ad hoc by default. For a release, pass a Developer ID identity:
#   make app SIGN="Developer ID Application: …"

APP      = build.noindex/DarkCharge.app
SIGN    ?= -
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
	codesign --force --options runtime --timestamp=none -s "$(SIGN)" $@/Contents/MacOS/DarkChargeHelper
	codesign --force --options runtime --timestamp=none -s "$(SIGN)" $@

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
	open /Applications/DarkCharge.app

clean:
	rm -rf .build build.noindex icon/DarkCharge.icns

.PHONY: all app test install clean
