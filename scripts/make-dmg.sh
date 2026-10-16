#!/bin/zsh
# Gera build/Chillbar-<versão>.dmg: abrir e arrastar o Chillbar para Aplicativos.
set -e
cd "${0:A:h}/.."

scripts/build-app.sh
app="build/Chillbar.app"
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")
volume="Chillbar"
dmg="build/Chillbar-$version.dmg"
staging=$(mktemp -d)
scratch="$staging/rw.dmg"

# Conteúdo: o app, um atalho para Aplicativos e o fundo (oculto)
mkdir -p "$staging/content/.background"
cp -R "$app" "$staging/content/"
ln -s /Applications "$staging/content/Applications"
# TIFF com as duas resoluções: o Finder usa a 2x em telas Retina
tiffutil -cathidpicheck build/assets/dmg-background.png build/assets/dmg-background@2x.png \
    -out "$staging/content/.background/background.tiff" 2>/dev/null

hdiutil detach "/Volumes/$volume" -quiet 2>/dev/null || true
hdiutil create -quiet -srcfolder "$staging/content" -volname "$volume" -fs HFS+ -format UDRW -ov "$scratch"
device=$(hdiutil attach -readwrite -noverify -noautoopen "$scratch" | awk '/Apple_HFS/ {print $1}')

# Layout da janela (tamanho, fundo e posição dos ícones). Precisa de permissão para
# controlar o Finder; se for negada, o DMG funciona igual, só sem o layout.
osascript <<APPLESCRIPT || echo "Aviso: layout do Finder não aplicado (permissão de automação)."
tell application "Finder"
    tell disk "$volume"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        -- 600×400 de conteúdo + barra de título
        set the bounds of container window to {200, 120, 800, 548}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "Chillbar.app" of container window to {150, 235}
        set position of item "Applications" of container window to {450, 235}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$device" -quiet
rm -f "$dmg"
hdiutil convert -quiet "$scratch" -format UDZO -imagekey zlib-level=9 -o "$dmg"
rm -rf "$staging"
echo "Pronto: $dmg"
