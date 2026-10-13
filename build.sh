#!/bin/bash
# VSPhone iOS — Build & Export IPA
# Chạy trên Mac có Xcode Command Line Tools
# Usage: ./build.sh [APPLE_ID_TEAM]
# Ví dụ: ./build.sh ABCDE12345

set -euo pipefail

SCHEME="VSPhone"
PROJECT="VSPhone.xcodeproj"
ARCHIVE="build/VSPhone.xcarchive"
EXPORT_DIR="build/IPA"
TEAM="${1:-}"  # Team ID từ Apple Developer Portal

echo "=== VSPhone iOS Build ==="

# 1. Clean
xcodebuild clean \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  2>&1 | tail -5

# 2. Archive
echo "→ Archiving..."
if [ -n "$TEAM" ]; then
  xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -destination "generic/platform=iOS" \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_STYLE=Automatic \
    2>&1 | grep -E "error:|warning:|Build|Archive" | tail -20
else
  # Không có Team ID → build unsigned (cho AltStore / TrollStore)
  xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -destination "generic/platform=iOS" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    AD_HOC_CODE_SIGNING_ALLOWED=YES \
    2>&1 | grep -E "error:|warning:|Build|Archive" | tail -20
fi

echo "→ Archive tạo tại: $ARCHIVE"

# 3. Export IPA
mkdir -p "$EXPORT_DIR"

if [ -n "$TEAM" ]; then
  cat > /tmp/vsphone_export_options.plist << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>ad-hoc</string>
  <key>teamID</key>
  <string>$TEAM</string>
  <key>compileBitcode</key>
  <false/>
  <key>thinning</key>
  <string>&lt;none&gt;</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist /tmp/vsphone_export_options.plist \
    -exportPath "$EXPORT_DIR" \
    2>&1 | grep -E "error:|Export|IPA" | tail -10
else
  # Manual IPA pack (unsigned)
  APP_PATH=$(find "$ARCHIVE/Products/Applications" -name "*.app" | head -1)
  mkdir -p /tmp/ipa_payload/Payload
  cp -r "$APP_PATH" /tmp/ipa_payload/Payload/
  cd /tmp/ipa_payload
  zip -r "VSPhone.ipa" Payload/
  mv "VSPhone.ipa" "$(pwd -P)/$(dirname "$0")/$EXPORT_DIR/"
  cd -
  rm -rf /tmp/ipa_payload
fi

IPA_PATH=$(find "$EXPORT_DIR" -name "*.ipa" | head -1)
echo ""
echo "✅ IPA: $IPA_PATH"
echo ""
echo "Cài lên iPhone:"
echo "  • AltStore:    mở AltStore → + → chọn IPA"
echo "  • TrollStore:  mở TrollStore → + → chọn IPA"
echo "  • Sideloadly:  kéo IPA vào Sideloadly"
