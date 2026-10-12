#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
version="${VERSION:-0.1.1}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION must be X.Y.Z" >&2; exit 1; }
identity="${SIGNING_IDENTITY:--}"
[[ "${1:-}" == "" || "${1:-}" == "--skip-build" ]] || { echo "Unknown option" >&2; exit 1; }
if [[ -n "${NOTARY_PROFILE:-}" && "$identity" == "-" ]]; then
    echo "Notarization requires a Developer ID identity" >&2
    exit 1
fi
swift scripts/generate-icon.swift
iconutil -c icns .build/CalendarBar.iconset -o Resources/AppIcon.icns
if [[ "${1:-}" != "--skip-build" ]]; then
    swift build -c release --arch arm64 --arch x86_64
fi
bin_dir="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
app="$PWD/dist/Calendar Bar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/CalendarBar" "$app/Contents/MacOS/CalendarBar"
cp Resources/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$app/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
fi
if [[ "$identity" == "-" ]]; then
    codesign --force --sign - "$app"
else
    certificate_id="$(openssl x509 -in Resources/SigningCertificate.pem -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
    signing_args=()
    if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then
        signing_args+=(--keychain "$SIGNING_KEYCHAIN")
    fi
    if [[ "$identity" == "$certificate_id" ]]; then
        requirement="designated => identifier \"io.github.calendar-bar\" and certificate leaf = H\"$certificate_id\""
        codesign --force --options runtime --timestamp=none --sign "$identity" \
            --requirements "=$requirement" "${signing_args[@]}" "$app"
        codesign --verify --strict --test-requirement "=identifier \"io.github.calendar-bar\" and certificate leaf = H\"$certificate_id\"" "$app"
    else
        codesign --force --options runtime --timestamp --sign "$identity" "${signing_args[@]}" "$app"
    fi
fi
codesign --verify --deep --strict "$app"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
cp docs/INSTALL.txt "$stage/Read me.txt"
dmg="$PWD/dist/CalendarBar-$version.dmg"
hdiutil create -volname "Calendar Bar" -srcfolder "$stage" -ov -format UDZO "$dmg"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    [[ "$identity" != "-" ]] || { echo "Notarization requires a Developer ID identity" >&2; exit 1; }
    xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
fi
(cd dist && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
printf 'Created %s\n' "$dmg"
