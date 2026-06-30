#!/bin/bash
# Builds ZenControl and packages it into a proper macOS .app bundle so that
# Bluetooth (NSBluetoothAlwaysUsageDescription) and menu-bar behaviour work.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="ZenControl.app"
BIN_NAME="ZenControl"

echo "▸ swift build ($CONFIG)…"
swift build -c "$CONFIG"
BIN_PATH=".build/$CONFIG/$BIN_NAME"

echo "▸ assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>ZenControl</string>
    <key>CFBundleDisplayName</key>     <string>ZenControl</string>
    <key>CFBundleIdentifier</key>      <string>com.zenhizer.zencontrol</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>ZenControl</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
        <string>ZenControl talks to your Sennheiser headphones over Bluetooth to read and change settings such as noise control, transparency and battery.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
        <string>ZenControl talks to your Sennheiser headphones over Bluetooth.</string>
</dict>
</plist>
PLIST

# Codesign with a stable identity so the TCC Bluetooth grant persists across rebuilds.
# Falls back to ad-hoc if no Apple Development cert is present.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development|Developer ID Application/{print $2; exit}')}"
if [ -n "$IDENTITY" ]; then
    echo "▸ codesigning as: $IDENTITY"
    codesign --force --deep --sign "$IDENTITY" "$APP" >/dev/null 2>&1 \
        && echo "  signed" || { echo "  (signing failed, ad-hoc)"; codesign --force --deep --sign - "$APP" >/dev/null 2>&1; }
else
    echo "▸ codesigning (ad-hoc)…"
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"
fi

echo "✓ Built $(pwd)/$APP"
echo "  Run with:  open $APP        (or)   ./$APP/Contents/MacOS/ZenControl"
