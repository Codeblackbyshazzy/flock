#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# ─── Config ───
APP_NAME="Flock"
BUNDLE="Flock.app"
REPO="Divagation/flock"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Brandon Anderson (U74MP7DDQC)}"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-Developer ID Installer: Brandon Anderson (U74MP7DDQC)}"
NOTARIZE_PROFILE="flock-notarize"

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
cp Resources/zsh-autosuggestions.zsh "$BUNDLE/Contents/Resources/zsh-autosuggestions.zsh"

# Write Info.plist from source with injected version
sed -e "s/<string>0\.[0-9]*\.[0-9]*<\/string>/<string>${VERSION}<\/string>/g" \
  Info.plist > "$BUNDLE/Contents/Info.plist"

# ─── Sign with Developer ID + hardened runtime ───
codesign --force --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --entitlements Flock.entitlements \
    --timestamp \
    "$BUNDLE/Contents/MacOS/Flock"

codesign --force --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --entitlements Flock.entitlements \
    --timestamp \
    "$BUNDLE"

codesign --verify --deep --strict "$BUNDLE"
echo "Signature: valid"

# ─── Create ZIP for distribution ───
ZIP_NAME="Flock-${VERSION}-mac.zip"
rm -f "$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$ZIP_NAME"

# ─── Notarize ───
echo ""
echo "Submitting for notarization..."

SUBMIT_OUTPUT=$(xcrun notarytool submit "$ZIP_NAME" \
    --keychain-profile "$NOTARIZE_PROFILE" \
    --wait \
    --timeout 600 2>&1)

echo "$SUBMIT_OUTPUT"

if echo "$SUBMIT_OUTPUT" | grep -q "status: Invalid"; then
    SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
    echo ""
    echo "Notarization failed. Fetching log..."
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARIZE_PROFILE"
    exit 1
fi

echo "Notarization succeeded."

# ─── Staple ───
xcrun stapler staple "$BUNDLE"

# Re-create ZIP with stapled app
rm -f "$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$ZIP_NAME"
SHA256=$(shasum -a 256 "$ZIP_NAME" | awk '{print $1}')

echo ""
echo "Built: $ZIP_NAME (notarized + stapled)"
echo "SHA256: $SHA256"

# ─── Build .pkg installer ───
PKG_NAME="Flock-${VERSION}-mac.pkg"
echo ""
echo "Building installer package..."

# Build component pkg (installs Flock.app to /Applications)
pkgbuild --root "$BUNDLE" \
    --identifier "com.baa.flock" \
    --version "$VERSION" \
    --install-location "/Applications/Flock.app" \
    --sign "$INSTALLER_IDENTITY" \
    --timestamp \
    "$PKG_NAME"

# Notarize the pkg
echo "Submitting pkg for notarization..."
PKG_SUBMIT=$(xcrun notarytool submit "$PKG_NAME" \
    --keychain-profile "$NOTARIZE_PROFILE" \
    --wait \
    --timeout 600 2>&1)

echo "$PKG_SUBMIT"

if echo "$PKG_SUBMIT" | grep -q "status: Invalid"; then
    echo "Pkg notarization failed!"
    exit 1
fi

xcrun stapler staple "$PKG_NAME"
echo "Built: $PKG_NAME (notarized + stapled)"

# ─── Create GitHub Release ───
echo ""
echo "Creating GitHub release v${VERSION}..."

NOTES="## Flock v${VERSION}

Parallel Claude Code terminal multiplexer for macOS.

### Install

Download the \`.pkg\` installer or \`${ZIP_NAME}\`, unzip, and drag to Applications.

### SHA256
\`\`\`
${SHA256}  ${ZIP_NAME}
\`\`\`"

gh release create "v${VERSION}" "$ZIP_NAME" "$PKG_NAME" \
  --repo "$REPO" \
  --title "Flock v${VERSION}" \
  --notes "$NOTES"

echo ""
echo "Release created: https://github.com/${REPO}/releases/tag/v${VERSION}"

# ─── Update version.json for auto-updater ───
echo "Updating version.json..."

cat > docs/version.json <<VJEOF
{
  "version": "${VERSION}",
  "url": "https://divagation.github.io/flock/thanks.html",
  "notes": "Flock v${VERSION} is available. Visit the download page to get the latest .pkg installer."
}
VJEOF

# Also update the fallback version constant in source
sed -i '' "s/static let current = \"[^\"]*\"/static let current = \"${VERSION}\"/" \
  Sources/Flock/UpdateChecker.swift

# ─── Push docs/ to deploy auto-updater ───
echo "Pushing docs/ to GitHub Pages..."
git add docs/version.json
git commit -m "Update version.json for v${VERSION}" --allow-empty
git push origin main

echo ""
echo "Done. Release live at: https://github.com/${REPO}/releases/tag/v${VERSION}"
echo ""
echo "REMINDER: Update localChangelog in Sources/Flock/UpdateChecker.swift with release notes for v${VERSION}"
