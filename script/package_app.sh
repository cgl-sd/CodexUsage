#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexUsage"
BUNDLE_ID="dev.codexusage.CodexUsage"
MIN_SYSTEM_VERSION="14.0"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICONSET="$DIST_DIR/$APP_NAME.iconset"
ICON_FILE="$APP_RESOURCES/AppIcon.icns"
DMG_STAGING="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
ZIP_PATH="$DIST_DIR/$APP_NAME.zip"

rm -rf "$DIST_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

swift build -c release --product "$APP_NAME"
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.4</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

mkdir -p "$ICONSET"
swift - "$ICONSET" <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation

let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
let specs: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func drawIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { bounds in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
        ctx.setShouldAntialias(true)

        let rect = bounds.insetBy(dx: size * 0.07, dy: size * 0.07)
        let radius = size * 0.22
        let path = CGPath(
            roundedRect: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height),
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )

        let colors = [
            CGColor(red: 0.06, green: 0.10, blue: 0.13, alpha: 1.0),
            CGColor(red: 0.09, green: 0.18, blue: 0.16, alpha: 1.0),
        ] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
        ctx.restoreGState()

        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
        ctx.setLineWidth(max(1, size * 0.012))
        ctx.addPath(path)
        ctx.strokePath()

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let ringLine = size * 0.09
        let ringRadius = size * 0.27
        let green = CGColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)

        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
        ctx.setLineWidth(ringLine)
        ctx.setLineCap(.round)
        ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        ctx.strokePath()

        ctx.setStrokeColor(green)
        ctx.setLineWidth(ringLine)
        ctx.addArc(center: center, radius: ringRadius, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * 0.78, clockwise: true)
        ctx.strokePath()

        let r = ringRadius
        let p0 = CGPoint(x: center.x - r * 0.44, y: center.y - r * 0.02)
        let p1 = CGPoint(x: center.x - r * 0.10, y: center.y - r * 0.34)
        let p2 = CGPoint(x: center.x + r * 0.48, y: center.y + r * 0.30)
        ctx.setStrokeColor(green)
        ctx.setLineWidth(size * 0.045)
        ctx.setLineJoin(.round)
        ctx.move(to: p0)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.strokePath()

        return true
    }
}

for (name, size) in specs {
    let image = drawIcon(size: size)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Failed to render \(name)")
    }
    try png.write(to: iconset.appendingPathComponent(name))
}
SWIFT
iconutil -c icns "$ICONSET" -o "$ICON_FILE"
rm -rf "$ICONSET"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  /usr/bin/codesign --force --sign - --timestamp=none "$APP_BUNDLE"
else
  /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
fi
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"
rm -rf "$DMG_STAGING"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  /usr/bin/codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
fi

echo "Created:"
echo "  $APP_BUNDLE"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
