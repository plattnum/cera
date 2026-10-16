#!/usr/bin/env bash
# Builds Cera in release mode and wraps it in build/Cera.app.
#   --zip      also writes build/Cera.zip for distribution.
#   --release  signs with a Developer ID, has Apple notarize the app, staples the ticket,
#              and writes build/Cera.zip, so downloaded copies open without a warning.
#
# --release settings, from the environment:
#   CERA_SIGN_IDENTITY     the signing identity; defaults to the keychain's first
#                          "Developer ID Application" certificate.
#   CERA_NOTARY_PROFILE    notarytool credentials saved with `xcrun notarytool
#                          store-credentials`; defaults to "cera-notary".
#   CERA_NOTARY_KEYCHAIN   the keychain holding that profile, if not the login keychain.
set -euo pipefail

cd "$(dirname "$0")/.."

zip=false
release=false
for arg in "$@"; do
    case "$arg" in
        --zip) zip=true ;;
        --release) zip=true; release=true ;;
        *) echo "usage: $0 [--zip] [--release]" >&2; exit 2 ;;
    esac
done

swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/Cera.app"
ZIP="build/Cera.zip"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Cera" "$APP/Contents/MacOS/Cera"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Theme fonts (open-licensed; their LICENSE files travel with them).
cp -R Sources/Cera/Resources/Fonts "$APP/Contents/Resources/Fonts"
# The `cera` terminal command; Homebrew links it onto the PATH.
cp scripts/cera "$APP/Contents/Resources/cera"

make_zip() {
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
}

if $release; then
    identity="${CERA_SIGN_IDENTITY:-$(security find-identity -v -p codesigning |
        sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
    if [[ -z "$identity" ]]; then
        echo "No Developer ID Application certificate found; set CERA_SIGN_IDENTITY." >&2
        exit 1
    fi
    notary=(--keychain-profile "${CERA_NOTARY_PROFILE:-cera-notary}")
    [[ -n "${CERA_NOTARY_KEYCHAIN:-}" ]] && notary+=(--keychain "$CERA_NOTARY_KEYCHAIN")

    # Notarization requires the hardened runtime and a secure timestamp.
    codesign --force --options runtime --timestamp --sign "$identity" "$APP"
    codesign --verify --strict "$APP"

    make_zip
    echo "Submitting to Apple for notarization (usually a few minutes)..."
    xcrun notarytool submit "$ZIP" "${notary[@]}" --wait --output-format json > build/notary.json || true
    if ! grep -q '"status" *: *"Accepted"' build/notary.json; then
        cat build/notary.json >&2
        id=$(sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' build/notary.json | head -1)
        [[ -n "$id" ]] && xcrun notarytool log "$id" "${notary[@]}" >&2
        echo "Notarization failed." >&2
        exit 1
    fi

    # Attach the ticket to the app so it opens offline too, then zip the stapled app.
    xcrun stapler staple "$APP"
    make_zip
    spctl --assess --type execute --verbose "$APP"
    echo "Built $ZIP (signed by $identity, notarized)"
else
    # Ad-hoc signature so the bundle launches on this Mac without a developer ID.
    codesign --force --sign - "$APP"
    if $zip; then
        make_zip
        echo "Built $ZIP"
    fi
fi

echo "Built $APP"
