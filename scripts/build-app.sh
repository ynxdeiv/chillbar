#!/bin/zsh
# Monta "build/Chillbar.app" a partir do SwiftPM, sem precisar do Xcode.
# A assinatura é ad-hoc (local); para distribuir, use Developer ID + notarização.
set -e
cd "${0:A:h}/.."
version=$(tr -d '[:space:]' < VERSION)

swift build -c release --product Chillbar
bin=$(swift build -c release --show-bin-path)

# Ícone desenhado em código (Sources/ChillbarAssets)
swift run -c release ChillbarAssets build/assets "$version" >/dev/null
iconutil -c icns build/assets/AppIcon.iconset -o build/assets/AppIcon.icns
app="build/Chillbar.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Chillbar" "$app/Contents/MacOS/Chillbar"
cp -R "$bin"/Chillbar_*.bundle "$app/Contents/Resources/"
cp build/assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Chillbar</string>
    <key>CFBundleIdentifier</key><string>io.github.ynxdeiv.Chillbar</string>
    <key>CFBundleName</key><string>Chillbar</string>
    <key>CFBundleDisplayName</key><string>Chillbar</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>pt-BR</string></array>
    <key>CFBundleAllowMixedLocalizations</key><true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Used to control your air conditioner directly over your Wi-Fi network.</string>
</dict>
</plist>
PLIST

# Textos do Info.plist em português (o inglês é a base)
mkdir -p "$app/Contents/Resources/en.lproj" "$app/Contents/Resources/pt-BR.lproj"
printf '"NSLocalNetworkUsageDescription" = "Used to control your air conditioner directly over your Wi-Fi network.";\n' \
    > "$app/Contents/Resources/en.lproj/InfoPlist.strings"
printf '"NSLocalNetworkUsageDescription" = "Para controlar o ar-condicionado diretamente pela sua rede Wi-Fi.";\n' \
    > "$app/Contents/Resources/pt-BR.lproj/InfoPlist.strings"

codesign --force --sign - --options runtime "$app"
echo "Pronto: $app"
