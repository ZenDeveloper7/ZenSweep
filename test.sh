#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
BUILD="${ZENSWEEP_BUILD_DIR:-$ROOT/.build}"
mkdir -p "$BUILD"
export CLANG_MODULE_CACHE_PATH="$BUILD/clang-cache"
SOURCES=(Models Scanner CleanupService ScanService HistoryStore AppModel Motion Theme LogoArtwork)
FILES=()
for SOURCE in "${SOURCES[@]}"; do FILES+=("$ROOT/Sources/ZenSweep/$SOURCE.swift"); done
swiftc -parse-as-library -swift-version 5 -module-cache-path "$BUILD/swift-cache" "${FILES[@]}" "$ROOT/Tests/ZenSweepTests/CleanupTests.swift" "$ROOT/Tests/ZenSweepTests/FeatureTests.swift" -o "$BUILD/CleanupTests"
"$BUILD/CleanupTests"
