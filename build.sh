#!/bin/bash
# Local source build; installed upgrades must retain their signing identity.
set -euo pipefail
cd "$(dirname "$0")"
case "${1:-}" in
    ""|--install) ;;
    --help|-h)
        printf '%s\n' 'Usage: ./build.sh [--install]' \
            'SIGNING_IDENTITY: codesign identity (or - for a local ad-hoc build).' \
            'PORTMAN_SOURCE: optional source override; defaults to Modules/Portman.' \
            'Installed updates stop if the existing signing requirement differs.'
        exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
esac
SIGN_ID="${SIGNING_IDENTITY:-}"
if [ -z "$SIGN_ID" ]; then
    if security find-identity -p codesigning | /usr/bin/grep -Fq '"InputStats Self-Signed"'; then
        SIGN_ID="InputStats Self-Signed"
    else
        SIGN_ID="-"
        echo 'Local ad-hoc build. Use a stable SIGNING_IDENTITY to preserve permissions across updates.' >&2
    fi
fi
swift build -c release --scratch-path .build-mactoys
STAGE=$(mktemp -d "$PWD/.package.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/InputStats.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build-mactoys/release/InputStats "$APP/Contents/MacOS/InputStats"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/NotesEditor "$APP/Contents/Resources/NotesEditor"
swift scripts/make-icon.swift "$STAGE/AppIcon.iconset"
iconutil -c icns "$STAGE/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
PORTMAN_SOURCE="${PORTMAN_SOURCE:-$PWD/Modules/Portman}"
if [ ! -f "$PORTMAN_SOURCE/portman/__main__.py" ]; then
    echo "Portman source not found: $PORTMAN_SOURCE" >&2; exit 1
fi
mkdir -p "$APP/Contents/Resources/Portman/portman"
cp "$PORTMAN_SOURCE"/portman/*.py "$APP/Contents/Resources/Portman/portman/"
cp -R "$PORTMAN_SOURCE/portman/static" "$APP/Contents/Resources/Portman/portman/"
codesign --force --sign "$SIGN_ID" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
# Packaging replacement is restricted to this project's generated app.
python3 scripts/install.py "$APP" "$PWD/InputStats.app"
if [ "${1:-}" = "--install" ]; then
    python3 scripts/install.py "$PWD/InputStats.app" /Applications/InputStats.app --installed
fi
if [ "${1:-}" = "--install" ]; then
    printf '%s\n' 'Installed. Run: open /Applications/MacToys.app'
else
    printf '%s\n' 'Built: InputStats.app. Install with ./build.sh --install before granting permissions.'
fi
