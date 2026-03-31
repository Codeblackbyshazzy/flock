#!/bin/bash
set -e

cd "$(dirname "$0")"

if [ ! -f VERSION ]; then
  echo "Missing VERSION file"
  exit 1
fi

VERSION="$(tr -d '[:space:]' < VERSION)"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Brandon Anderson (U74MP7DDQC)}"

echo "Building Flock..."
swift build -c release 2>&1

# Assemble .app bundle
APP="Flock.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp .build/release/Flock "$APP/Contents/MacOS/Flock"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/zsh-autosuggestions.zsh "$APP/Contents/Resources/zsh-autosuggestions.zsh"
/usr/bin/perl -0pe 's{(<key>CFBundleVersion</key>\s*<string>)[^<]+(</string>)}{$1'"$VERSION"'$2}g; s{(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+(</string>)}{$1'"$VERSION"'$2}g' \
  Info.plist > "$APP/Contents/Info.plist"

# Sign with Developer ID + hardened runtime
codesign --force --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --entitlements Flock.entitlements \
    --timestamp \
    "$APP/Contents/MacOS/Flock"

codesign --force --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --entitlements Flock.entitlements \
    --timestamp \
    "$APP"

codesign --verify --deep --strict "$APP"

# Install to /Applications (rm first — cp -R can't overwrite a running app)
rm -rf /Applications/Flock.app
cp -R "$APP" /Applications/Flock.app

# Also keep CLI symlink
mkdir -p ~/.local/bin
ln -sf "$(pwd)/.build/release/Flock" ~/.local/bin/flock

if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zprofile
fi

echo ""
echo "Done."
echo "  App:  /Applications/Flock.app (double-click or Spotlight)"
echo "  CLI:  flock"
