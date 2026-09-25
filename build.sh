#!/bin/sh
# Build and install Audiobookshelf into ~/Applications/Audiobookshelf.app.
# The bundle is assembled from scratch each time: packaging/Info.plist, the
# cached icon (packaging/makeicon.swift), and Resources/ (fonts, strings,
# images) which the app loads through Bundle.main.
#
# Signing: set SIGN_IDENTITY to a code-signing identity in your keychain (a
# self-signed one is enough) so the Local Network grant survives rebuilds.
# Without one the app is signed ad hoc, which works but re-asks after rebuilds.
set -e
cd "$(dirname "$0")"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Audiobookshelf"

if [ ! -f packaging/Audiobookshelf.icns ]; then
  swift packaging/makeicon.swift packaging/Audiobookshelf.icns Resources/images/logo.png || true
fi

STAGE="dist/Audiobookshelf.app"
rm -rf dist
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp packaging/Info.plist "$STAGE/Contents/Info.plist"
cp "$BIN" "$STAGE/Contents/MacOS/Audiobookshelf"
[ -f packaging/Audiobookshelf.icns ] && cp packaging/Audiobookshelf.icns "$STAGE/Contents/Resources/"
cp -R Resources/Fonts Resources/strings Resources/images "$STAGE/Contents/Resources/"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"

IDENTITY="${SIGN_IDENTITY:-Aeon Local}"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
  codesign --force --deep -s "$IDENTITY" "$STAGE"
else
  echo "note: no '$IDENTITY' identity, ad-hoc signing (set SIGN_IDENTITY to use one)"
  codesign --force --deep -s - "$STAGE"
fi
codesign --verify --strict "$STAGE"

if pgrep -x Audiobookshelf >/dev/null; then
  osascript -e 'quit app "Audiobookshelf"' || true
  for _ in 1 2 3 4 5 6; do pgrep -x Audiobookshelf >/dev/null || break; sleep 0.5; done
fi
DEST="$HOME/Applications/Audiobookshelf.app"
rm -rf "$DEST"
cp -R "$STAGE" "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
echo "installed: $DEST"
