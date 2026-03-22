#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building Flock..."
swift build -c release 2>&1

# Update .app bundle
APP="Flock.app"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp .build/release/Flock "$APP/Contents/MacOS/Flock"

# Re-sign (ad-hoc) so macOS doesn't complain
codesign --force --sign - "$APP" 2>/dev/null || true

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
