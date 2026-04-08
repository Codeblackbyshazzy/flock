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
# Copy plist and update version fields safely (avoid brittle regex edits).
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"

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

# Install to /Applications safely.
# IMPORTANT: Never delete/replace the app bundle while it's running.
INSTALL_PATH="${INSTALL_PATH:-/Applications/Flock.app}"

if pgrep -x "Flock" >/dev/null 2>&1; then
  echo ""
  echo "Flock is currently running."
  echo "To avoid crashing the running app, installation is blocked."
  echo "Quit Flock, then re-run this script to install to:"
  echo "  $INSTALL_PATH"
  echo ""
  echo "Tip: If you want to install alongside your current app, run:"
  echo "  INSTALL_PATH=\"/Applications/Flock Dev.app\" ./build.sh"
  exit 2
fi

TMP_APP="${INSTALL_PATH}.tmp"
rm -rf "$TMP_APP"
/usr/bin/ditto "$APP" "$TMP_APP"
rm -rf "$INSTALL_PATH"
mv "$TMP_APP" "$INSTALL_PATH"

# Also keep CLI symlink
mkdir -p ~/.local/bin
ln -sf "$(pwd)/.build/release/Flock" ~/.local/bin/flock

if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zprofile
fi

echo ""
echo "Done."
echo "  App:  $INSTALL_PATH (double-click or Spotlight)"
echo "  CLI:  flock"
