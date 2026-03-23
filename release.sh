#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# ─── Config ───
APP_NAME="Flock"
BUNDLE="Flock.app"
REPO="Divagation/flock"

# ─── Version ───
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: ./release.sh <version>"
  echo "  e.g. ./release.sh 0.2.0"
  exit 1
fi

echo "Building Flock v${VERSION}..."

# ─── Build ───
swift build -c release 2>&1

# ─── Assemble .app bundle ───
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp .build/release/Flock "$BUNDLE/Contents/MacOS/Flock"
cp AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"

# Write Info.plist with correct version
cat > "$BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Flock</string>
  <key>CFBundleIdentifier</key>
  <string>com.baa.flock</string>
  <key>CFBundleExecutable</key>
  <string>Flock</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticTermination</key>
  <false/>
  <key>LSUIElement</key>
  <false/>
  <key>NSDesktopFolderUsageDescription</key>
  <string>Flock terminal sessions need file access.</string>
  <key>NSDocumentsFolderUsageDescription</key>
  <string>Flock terminal sessions need file access.</string>
  <key>NSDownloadsFolderUsageDescription</key>
  <string>Flock terminal sessions need file access.</string>
  <key>NSRemovableVolumesUsageDescription</key>
  <string>Flock terminal sessions need file access.</string>
</dict>
</plist>
PLIST

# ─── Codesign (ad-hoc) ───
codesign --force --sign - --deep "$BUNDLE"

# ─── Create ZIP for distribution ───
ZIP_NAME="Flock-${VERSION}-mac.zip"
rm -f "$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$ZIP_NAME"
SHA256=$(shasum -a 256 "$ZIP_NAME" | awk '{print $1}')

echo ""
echo "Built: $ZIP_NAME"
echo "SHA256: $SHA256"

# ─── Create GitHub Release ───
echo ""
echo "Creating GitHub release v${VERSION}..."

NOTES="## Flock v${VERSION}

Parallel Claude Code terminal multiplexer for macOS.

### Install

\`\`\`
brew tap divagation/flock
brew install --cask flockapp
\`\`\`

Or download \`${ZIP_NAME}\`, unzip, and drag to Applications.

### SHA256
\`\`\`
${SHA256}  ${ZIP_NAME}
\`\`\`"

gh release create "v${VERSION}" "$ZIP_NAME" \
  --repo "$REPO" \
  --title "Flock v${VERSION}" \
  --notes "$NOTES"

echo ""
echo "Release created: https://github.com/${REPO}/releases/tag/v${VERSION}"

# ─── Update Homebrew tap ───
echo ""
echo "Updating Homebrew cask..."

TAP_DIR=$(mktemp -d)
git clone --depth 1 https://github.com/Divagation/homebrew-flock.git "$TAP_DIR"

cat > "$TAP_DIR/Casks/flockapp.rb" << CASK
cask "flockapp" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/Divagation/flock/releases/download/v#{version}/Flock-#{version}-mac.zip"
  name "Flock"
  desc "Parallel Claude Code terminal multiplexer"
  homepage "https://github.com/Divagation/flock"

  depends_on macos: ">= :ventura"

  app "Flock.app"

  binary "#{appdir}/Flock.app/Contents/MacOS/Flock", target: "flock"

  zap trash: [
    "~/Library/Preferences/com.baa.flock.plist",
    "~/Library/Saved Application State/com.baa.flock.savedState",
  ]
end
CASK

cd "$TAP_DIR"
git add -A
git commit -m "Update Flock to v${VERSION}"
git push
cd -
rm -rf "$TAP_DIR"

echo ""
echo "Done. Install with:"
echo "  brew tap divagation/flock"
echo "  brew install --cask flockapp"
