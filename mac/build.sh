#!/bin/zsh
# 把 index.html 打包成 dist/Jot.app（双击即用）
# 用法：./mac/build.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
APP="$ROOT/dist/Jot.app"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 本机偶尔出现「CommandLineTools 的 swiftc 比 SDK 旧」导致编译失败，这里自动换一个能用的 SDK
compile() {
  local src=$1 out=$2
  if swiftc -O "$src" -o "$out" 2>"$TMP/err.log"; then return 0; fi
  local sdk
  for sdk in $(find /Library/Developer/CommandLineTools/SDKs \
                    /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs \
                    -maxdepth 1 -name 'MacOSX*.sdk' 2>/dev/null | sort -r); do
    if swiftc -sdk "$sdk" -O "$src" -o "$out" 2>>"$TMP/err.log"; then
      echo "  使用 SDK: ${sdk:t}"
      return 0
    fi
  done
  cat "$TMP/err.log" >&2
  return 1
}

echo "==> 编译图标生成器"
compile tools/icon.swift "$TMP/icon"
"$TMP/icon" "$TMP/icon_1024.png" 1024 >/dev/null

echo "==> 生成 AppIcon.icns"
mkdir -p "$TMP/AppIcon.iconset"
for spec in 16 32 128 256 512; do
  sips -z $spec $spec "$TMP/icon_1024.png" --out "$TMP/AppIcon.iconset/icon_${spec}x${spec}.png" >/dev/null
  sips -z $((spec*2)) $((spec*2)) "$TMP/icon_1024.png" --out "$TMP/AppIcon.iconset/icon_${spec}x${spec}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$TMP/AppIcon.icns"

echo "==> 编译应用"
compile mac/Jot.swift "$TMP/Jot"

echo "==> 组装 Jot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$TMP/Jot" "$APP/Contents/MacOS/Jot"
chmod +x "$APP/Contents/MacOS/Jot"
cp mac/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp index.html "$APP/Contents/Resources/index.html"
cp -R icons "$APP/Contents/Resources/icons"
cp "$TMP/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# 本地 ad-hoc 签名：不加也能开，加了之后系统更少弹「未知开发者」
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (跳过签名)"
touch "$APP"

echo "==> 完成：$APP"
echo "    双击打开，或拖到「应用程序」文件夹 / 程序坞"
