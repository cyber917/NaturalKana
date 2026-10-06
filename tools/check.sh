#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cache="$root/.build-local"
mkdir -p "$cache/modules" "$cache/cache" "$cache/config" "$cache/security"
export CLANG_MODULE_CACHE_PATH="$cache/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$cache/modules"
args=(--disable-sandbox --disable-xctest --package-path "$root/NaturalSuggestCore" --scratch-path "$cache/build" --cache-path "$cache/cache" --config-path "$cache/config" --security-path "$cache/security")
if [[ "$(xcode-select -p)" == */CommandLineTools ]]; then
  sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
  if [[ -d "$sdk" ]]; then args+=(--sdk "$sdk"); fi
  plugin=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
  if [[ -f "$plugin" ]]; then args+=(-Xswiftc -load-plugin-library -Xswiftc "$plugin"); fi
fi
swift test "${args[@]}"
python3 "$root/tools/test_refresh.py"
python3 -m py_compile "$root/eval/run.py" "$root/tools/refresh_lexicon.py"
binary="$(find "$cache/build" -type f -name natural-suggest -perm -111 | head -1)"
python3 "$root/eval/run.py" --binary "$binary"
