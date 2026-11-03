#!/bin/zsh
# 生成 PWA 图标（icons/icon-192.png、icons/icon-512.png）
# 用法：./tools/gen-icons.sh
set -euo pipefail

cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 本机可能出现「CommandLineTools 的 swiftc 比默认 SDK 旧」，逐个 SDK 试到能编为止
build() {
  local src=$1 out=$2 sdk
  if swiftc -O "$src" -o "$out" 2>/dev/null; then return 0; fi
  for sdk in $(find /Library/Developer/CommandLineTools/SDKs \
                    /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs \
                    -maxdepth 1 -name 'MacOSX*.sdk' 2>/dev/null | sort -r); do
    if swiftc -sdk "$sdk" -O "$src" -o "$out" 2>/dev/null; then return 0; fi
  done
  echo "swiftc failed — no usable macOS SDK found" >&2
  return 1
}

build tools/icon.swift "$TMP/icon"

mkdir -p icons
"$TMP/icon" "$TMP/icon-1024.png" 1024 >/dev/null
sips -z 192 192 "$TMP/icon-1024.png" --out icons/icon-192.png >/dev/null
sips -z 512 512 "$TMP/icon-1024.png" --out icons/icon-512.png >/dev/null
echo "icons/icon-192.png, icons/icon-512.png"
