#!/bin/bash
# Reproducible local build. Does not install an input source or change xcode-select.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cache="${NATURALKANA_BUILD_CACHE:-$root/.build-local/macos}"
mkdir -p "$cache/modules" "$cache/cache" "$cache/config" "$cache/security"
export CLANG_MODULE_CACHE_PATH="$cache/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$cache/modules"
project="$root/upstream/azooKey-macos"
mode="${1:---compile-only}"
if [[ "$mode" != --compile-only && "$mode" != --signed ]]; then
  echo 'Usage: build_macos.sh [--compile-only|--signed]'; exit 2
fi
signing=(CODE_SIGNING_ALLOWED=NO)
if [[ "$mode" == --signed ]]; then
  python3 "$root/tools/verify_mac_models.py"
  : "${NATURALKANA_TEAM_ID:?Set your actual Xcode development team ID before a signed build}"
  # A new bundle ID has no provisioning profile yet; let Xcode create it on the first signed build.
  signing=(-allowProvisioningUpdates CODE_SIGN_STYLE=Automatic "DEVELOPMENT_TEAM=$NATURALKANA_TEAM_ID")
fi
swift build --package-path "$project/Core" --scratch-path "$cache/packages" \
  --cache-path "$cache/cache" --config-path "$cache/config" --security-path "$cache/security" \
  --product ConverterServer -c release
products="$(swift build --package-path "$project/Core" --scratch-path "$cache/packages" -c release --show-bin-path)"
xcodebuild -project "$project/azooKeyMac.xcodeproj" -scheme azooKeyMac \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$cache/native" -clonedSourcePackagesDirPath "$cache/packages" \
  -skipPackageUpdates "${signing[@]}" "NATURALKANA_CONVERTER_PRODUCTS_DIR=$products" build
echo "Build output: $cache/native/Build/Products/Release/azooKeyMac.app"
if [[ "$mode" == --compile-only ]]; then
  echo 'Compile-only output is unsigned and is not ready for installation.'
fi
