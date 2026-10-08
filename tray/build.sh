#!/bin/bash
# Build the LocalJev menu bar app into tray/dist/LocalJev.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRAY="$ROOT/tray"
DIST="$TRAY/dist"
APP="$DIST/LocalJev.app"
SWIFT_BIN="$TRAY/.build/release/LocalJevTray"

echo "==> 1/4 compile localjev server (bun --compile)"
bun build --compile "$ROOT/src/index.ts" --outfile "$TRAY/localjev-bin"

echo "==> 2/4 build menu bar app (swift)"
swift build -c release --package-path "$TRAY"

echo "==> 3/4 assemble app bundle"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SWIFT_BIN" "$APP/Contents/MacOS/LocalJevTray"
cp "$TRAY/localjev-bin" "$APP/Contents/Resources/localjev"
chmod +x "$APP/Contents/Resources/localjev"
cp "$TRAY/Info.plist" "$APP/Contents/Info.plist"

echo "==> 4/4 ad-hoc codesign"
codesign --force --deep --sign - "$APP"

echo "done: $APP"
