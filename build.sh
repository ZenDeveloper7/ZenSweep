#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
BUILD="${ZENSWEEP_BUILD_DIR:-$ROOT/.build}"
DEST="${ZENSWEEP_OUTPUT_DIR:-$ROOT/..}"
mkdir -p "$BUILD" "$DEST"
export CLANG_MODULE_CACHE_PATH="$BUILD/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD/swift-cache"
FLAGS=(--package-path "$ROOT" --scratch-path "$BUILD/swiftpm" --cache-path "$BUILD/cache" --config-path "$BUILD/config" --security-path "$BUILD/security" --disable-sandbox)
swift build "${FLAGS[@]}" -c release -debug-info-format none
BIN="$(swift build "${FLAGS[@]}" -c release -debug-info-format none --show-bin-path)"
APP="$DEST/ZenSweep.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ZenSweep" "$APP/Contents/MacOS/ZenSweep"
/usr/libexec/PlistBuddy -c 'Clear dict' "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleName='ZenSweep', CFBundleDisplayName='ZenSweep', CFBundleIdentifier='in.builtbyzen.ZenSweep', CFBundleExecutable='ZenSweep', CFBundlePackageType='APPL', CFBundleShortVersionString='0.2.0', CFBundleVersion='2', CFBundleIconFile='ZenSweep', LSMinimumSystemVersion='14.0', NSHighResolutionCapable=True, NSPrincipalClass='NSApplication', NSDocumentsFolderUsageDescription='Scan folders you select to find large files and show storage usage.', NSDownloadsFolderUsageDescription='Scan downloads you select to find large files.'), f)
PY
swiftc -parse-as-library -module-cache-path "$BUILD/swift-cache" "$ROOT/Sources/ZenSweep/LogoArtwork.swift" "$ROOT/Tools/MakeIcon.swift" -o "$BUILD/MakeIcon"
"$BUILD/MakeIcon" "$BUILD/icon.png"
cp "$BUILD/icon.png" "$DEST/ZenSweep-logo.png"
mkdir -p "$BUILD/ZenSweep.iconset"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$BUILD/icon.png" --out "$BUILD/ZenSweep.iconset/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$BUILD/icon.png" --out "$BUILD/ZenSweep.iconset/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
python3 - "$BUILD/ZenSweep.iconset" "$APP/Contents/Resources/ZenSweep.icns" <<'PYICON'
from pathlib import Path
import struct, sys
root = Path(sys.argv[1])
chunks = []
for kind, filename in [('icp4', 'icon_16x16.png'), ('icp5', 'icon_32x32.png'), ('ic07', 'icon_128x128.png'), ('ic08', 'icon_256x256.png'), ('ic09', 'icon_512x512.png'), ('ic10', 'icon_512x512@2x.png')]:
    data = (root / filename).read_bytes()
    chunks.append(kind.encode() + struct.pack('>I', len(data) + 8) + data)
payload = b''.join(chunks)
Path(sys.argv[2]).write_bytes(b'icns' + struct.pack('>I', len(payload) + 8) + payload)
PYICON
codesign --force --sign - "$APP"
echo "$APP"
