#!/usr/bin/env bash
# Firma ad hoc el .app de release y arma el .dmg (con acceso directo a
# Aplicaciones). Uso, después de `flutter build macos --release`:
#
#   packaging/macos/crear_dmg.sh 1.0.0 [carpeta_de_salida]
#
# Sin cuenta de desarrollador de Apple: la firma es ad hoc y el usuario
# habilita la app una vez (docs/instalacion.md).
set -euo pipefail

VERSION=${1:?Uso: crear_dmg.sh VERSION [SALIDA]}
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
SALIDA=$(mkdir -p "${2:-$RAIZ/dist}" && cd "${2:-$RAIZ/dist}" && pwd)
APP="$RAIZ/build/macos/Build/Products/Release/EvemTv.app"
[[ -d "$APP" ]] || { echo "Falta $APP: ejecuta 'flutter build macos --release'." >&2; exit 1; }

# La versión del .app debe ser la del release.
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
[[ "$PLIST_VERSION" == "$VERSION" ]] || { echo "ERROR: el .app es la versión $PLIST_VERSION, no $VERSION." >&2; exit 1; }

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Arquitecturas: $(lipo -archs "$APP/Contents/MacOS/EvemTv")"

TRABAJO=$(mktemp -d)
trap 'rm -rf "$TRABAJO"' EXIT
ditto "$APP" "$TRABAJO/EvemTv.app"
ln -s /Applications "$TRABAJO/Aplicaciones"

DMG="$SALIDA/EvemTv-$VERSION-macos.dmg"
rm -f "$DMG"
hdiutil create -volname "EvemTv $VERSION" -srcfolder "$TRABAJO" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG"
hdiutil verify "$DMG"
echo "Listo: $DMG"
