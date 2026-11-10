.PHONY: build install run zip icon sounds banner clean

build:
	scripts/build.sh

install:
	scripts/build.sh --install

run: build
	PASTE_DEBUG=1 build/Paste.app/Contents/MacOS/Paste

zip:
	scripts/build.sh --zip

icon:
	swift scripts/make_icon.swift assets/MacintoshSkeletalFilled.otf assets
	iconutil -c icns assets/AppIcon.iconset -o Resources/AppIcon.icns
	rm -rf assets/AppIcon.iconset
	sips -Z 512 assets/AppIcon-1024.png --out docs/icon.png >/dev/null

sounds:
	python3 scripts/make_sounds.py Resources

banner:
	uv run --with fonttools scripts/banner.py --skeletal assets/MacintoshSkeletalFilled.otf

clean:
	rm -rf .build build
