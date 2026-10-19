#!/bin/bash
# Builds Bakdo.app into ./build and (with --install) copies it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="1.0.0"
APP="build/Bakdo.app"
FRAMEWORKS=(
  "Vendor/build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework"
  "Vendor/build-apple/llama.xcframework/macos-arm64_x86_64/llama.framework"
)

swift build -c release --arch arm64

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp .build/arm64-apple-macosx/release/Bakdo "$APP/Contents/MacOS/Bakdo"
for fw in "${FRAMEWORKS[@]}"; do
  name=$(basename "$fw" .framework)
  cp -R "$fw" "$APP/Contents/Frameworks/"
  # Apple Silicon only: drop the Intel slice and headers to keep the app small.
  bin="$APP/Contents/Frameworks/$name.framework/Versions/A/$name"
  lipo "$bin" -thin arm64 -output "$bin.thin" && mv "$bin.thin" "$bin"
  rm -rf "$APP/Contents/Frameworks/$name.framework/Versions/A/Headers" "$APP/Contents/Frameworks/$name.framework/Headers" \
         "$APP/Contents/Frameworks/$name.framework/Versions/A/Modules" "$APP/Contents/Frameworks/$name.framework/Modules"
done

# Icon is rendered from design/app-icon.svg (see design/README.md).
cp design/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Bakdo</string>
  <key>CFBundleDisplayName</key><string>Bakdo</string>
  <key>CFBundleIdentifier</key><string>app.bakdo.mac</string>
  <key>CFBundleExecutable</key><string>Bakdo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key><string>Bakdo listens while you hold the dictation key and turns your speech into text, entirely on this Mac.</string>
  <key>NSHumanReadableCopyright</key><string>Models: OpenAI Whisper + Oriserve Hindi2Hinglish, Qwen3.5 (Apache-2.0). Runtimes: whisper.cpp, llama.cpp (MIT).</string>
</dict>
</plist>
PLIST

# Ad-hoc signature (no developer certificate on this machine).
for fw in "$APP"/Contents/Frameworks/*.framework; do codesign --force --sign - "$fw"; done
codesign --force --sign - --identifier app.bakdo.mac "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Bakdo 2>/dev/null || true
  sleep 0.5
  rm -rf /Applications/Bakdo.app
  cp -R "$APP" /Applications/Bakdo.app
  echo "Installed /Applications/Bakdo.app"
fi
