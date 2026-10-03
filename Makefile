BIN    = /usr/local/bin/darkcharge
PLIST  = /Library/LaunchDaemons/com.darkcharge.daemon.plist
LABEL  = system/com.darkcharge.daemon
APP    = build/DarkCharge.app

all: darkcharge $(APP)

darkcharge: cli/main.swift shared/Hardware.swift
	swiftc -O -framework IOKit -o $@ $^

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

$(APP): darkcharge app/main.swift shared/Hardware.swift app/Info.plist com.darkcharge.daemon.plist icon/DarkCharge.icns
	rm -rf $@
	mkdir -p $@/Contents/MacOS $@/Contents/Resources
	swiftc -O -framework AppKit -framework IOKit -o $@/Contents/MacOS/DarkCharge app/main.swift shared/Hardware.swift
	cp app/Info.plist $@/Contents/
	cp darkcharge com.darkcharge.daemon.plist icon/DarkCharge.icns $@/Contents/Resources/
	codesign --force --deep -s - $@

app: $(APP)

install: darkcharge
	-launchctl bootout $(LABEL) 2>/dev/null
	install -d /usr/local/bin
	install -m 755 darkcharge $(BIN)
	install -m 644 com.darkcharge.daemon.plist $(PLIST)
	launchctl bootstrap system $(PLIST)

uninstall:
	-launchctl bootout $(LABEL) 2>/dev/null
	-$(BIN) on
	rm -f $(BIN) $(PLIST)
	rm -rf "/Library/Application Support/DarkCharge"

clean:
	rm -rf darkcharge build icon/DarkCharge.icns

.PHONY: all app install uninstall clean
