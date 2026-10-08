#!/bin/bash
# Builds the menu-bar helper ("NaturalKana Helper.app") from NaturalSuggestCore.
#   tools/build_macos_helper.sh               unsigned compile check
#   tools/build_macos_helper.sh IDENTITY      signed with that codesigning identity (SHA-1 or name)
# Run tools/rebrand.py first so Info.plist and entitlements carry your identifiers.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
identity="${1:-}"
package="$root/NaturalSuggestCore"
scratch="$root/.build-local/helper-build"
app="${NATURALKANA_HELPER_OUT:-$root/.build-local/helper}/NaturalKana Helper.app"

swift build --package-path "$package" --scratch-path "$scratch" -c release --arch arm64 --product NaturalKanaHelper
bin="$(swift build --package-path "$package" --scratch-path "$scratch" -c release --arch arm64 --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/NaturalKanaHelper" "$app/Contents/MacOS/NaturalKanaHelper"
cp -R "$bin/NaturalSuggestCore_NaturalSuggestCore.bundle" "$app/Contents/Resources/"
cp "$package/Sources/NaturalKanaHelper/Info.plist" "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist" >/dev/null

if [[ -n "$identity" ]]; then
  # The app-group entitlement shares settings with the input method; it must match your Team.
  codesign --force --timestamp=none --sign "$identity" \
    --entitlements "$package/Sources/NaturalKanaHelper/NaturalKanaHelper.entitlements" "$app"
  codesign --verify --strict "$app"
else
  codesign --force --sign - "$app"
  echo 'Unsigned (ad-hoc) build: for compile checks only; it cannot share settings with the input method.'
fi
echo "Helper: $app"
