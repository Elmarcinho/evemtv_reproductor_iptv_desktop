#!/usr/bin/env bash
# Arma el AppImage de EvemTv a partir de `flutter build linux --release`,
# con libmpv y sus dependencias incluidas (salvo las del sistema, ver
# packaging/linux/excluir.txt). Uso:
#
#   packaging/linux/crear_appimage.sh 1.0.0 [carpeta_de_salida]
#
# Descarga linuxdeploy, appimagetool y el runtime de AppImage en versiones
# fijas y verifica su SHA-256 antes de usarlos.
set -euo pipefail

VERSION=${1:?Uso: crear_appimage.sh VERSION [SALIDA]}
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
SALIDA=$(mkdir -p "${2:-$RAIZ/dist}" && cd "${2:-$RAIZ/dist}" && pwd)
BUNDLE="$RAIZ/build/linux/x64/release/bundle"
TRABAJO="$RAIZ/build/appimage"
HERRAMIENTAS="$TRABAJO/herramientas"
APPDIR="$TRABAJO/EvemTv.AppDir"

[[ -x "$BUNDLE/evemtv" ]] || { echo "Falta $BUNDLE: ejecuta 'flutter build linux --release'." >&2; exit 1; }

# El AppImage debe salir de la compilación que enlaza mimalloc: sin él, la
# memoria crece con cada película (docs/decisiones.md §16).
if ! nm -D --defined-only "$BUNDLE/evemtv" 2>/dev/null | grep -q ' mi_malloc$' &&
   ! nm --defined-only "$BUNDLE/evemtv" 2>/dev/null | grep -q ' mi_malloc$'; then
  echo "ERROR: el ejecutable no incluye mimalloc (revisa linux/CMakeLists.txt)." >&2
  exit 1
fi

descargar() { # url sha256 destino
  if [[ ! -f "$3" ]] || ! echo "$2  $3" | sha256sum -c --status; then
    curl -fsSL --proto '=https' --tlsv1.2 -o "$3" "$1"
  fi
  echo "$2  $3" | sha256sum -c --quiet || { echo "ERROR: SHA-256 inesperado en $3" >&2; exit 1; }
  chmod +x "$3"
}
mkdir -p "$HERRAMIENTAS"
descargar https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-x86_64.AppImage \
  c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d "$HERRAMIENTAS/linuxdeploy"
descargar https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage \
  ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0 "$HERRAMIENTAS/appimagetool"
descargar https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64 \
  2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d "$HERRAMIENTAS/runtime-x86_64"

# Las herramientas son AppImages: en CI (sin FUSE) se extraen al vuelo.
export APPIMAGE_EXTRACT_AND_RUN=1

# Estructura: usr/bin tiene el ejecutable y data/; lib/ apunta a usr/lib,
# donde quedan las bibliotecas de Flutter y las dependencias.
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib"
cp -a "$BUNDLE/evemtv" "$BUNDLE/data" "$APPDIR/usr/bin/"
cp -a "$BUNDLE/lib/." "$APPDIR/usr/lib/"
ln -s ../lib "$APPDIR/usr/bin/lib"

EXCLUIR=()
while IFS= read -r patron; do
  [[ -z "$patron" || "$patron" == \#* ]] && continue
  EXCLUIR+=("--exclude-library=$patron")
done < "$RAIZ/packaging/linux/excluir.txt"
# libdartjni.so (de path_provider_android) pide libjvm, pero en Linux nunca
# se carga: no se incluye un Java.
EXCLUIR+=("--exclude-library=libjvm.so*")

# libjack está en la lista de exclusión por defecto de AppImage, pero libmpv
# no carga sin ella y muchos escritorios no la traen: se incluye a mano.
INCLUIR=()
for lib in libjack.so.0; do
  ruta=$(ldconfig -p | awk -v l="$lib" '$1 == l && /x86-64/ {print $NF; exit}')
  [[ -n "$ruta" ]] && INCLUIR+=("--library=$ruta")
done

"$HERRAMIENTAS/linuxdeploy" --appdir "$APPDIR" \
  --deploy-deps-only "$APPDIR/usr/bin/evemtv" \
  --deploy-deps-only "$APPDIR/usr/lib" \
  "${INCLUIR[@]}" "${EXCLUIR[@]}" -v${LINUXDEPLOY_VERBOSIDAD:-2}

# Comprueba que todo lo que libmpv necesita esté incluido o se tome a
# propósito del sistema (excluir.txt o la lista por defecto de AppImage):
# evita publicar un AppImage sin video.
DEL_SISTEMA=(libc.so* libm.so* libdl.so* libpthread.so* librt.so* libresolv.so*
  ld-linux* libstdc++* libgcc_s* libz.so* libasound* libfontconfig* libfreetype*
  libharfbuzz* libfribidi* libgmp* libusb-1.0* libcom_err* libgpg-error*
  libexpat* libuuid* libjvm.so*)
while IFS= read -r patron; do
  [[ -z "$patron" || "$patron" == \#* ]] || DEL_SISTEMA+=("$patron")
done < "$RAIZ/packaging/linux/excluir.txt"
faltan=$(cd "$APPDIR/usr/lib" && for f in libmpv.so.* libav*.so.*; do
  readelf -d "$f" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p'
done | sort -u | while read -r dep; do
  [[ -e "$APPDIR/usr/lib/$dep" ]] && continue
  for patron in "${DEL_SISTEMA[@]}"; do
    # shellcheck disable=SC2053  # comparación con comodines, a propósito
    [[ "$dep" == $patron ]] && continue 2
  done
  echo "$dep"
done)
if [[ -n "$faltan" ]]; then
  echo "ERROR: libmpv necesita bibliotecas que no quedaron incluidas: $faltan" >&2
  exit 1
fi

LIBMPV=$(cd "$APPDIR/usr/lib" && ls libmpv.so.* 2>/dev/null | head -n1)
[[ -n "$LIBMPV" ]] || { echo "ERROR: libmpv no quedó incluido." >&2; exit 1; }

# Entrada, acceso directo e ícono (en Wayland el panel los toma de aquí).
sed "s/@LIBMPV@/$LIBMPV/" "$RAIZ/packaging/linux/AppRun" > "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"
mkdir -p "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/256x256/apps"
cp "$RAIZ/packaging/linux/com.evemtv.player.desktop" "$APPDIR/usr/share/applications/"
cp "$RAIZ/assets/branding/icon_256.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/com.evemtv.player.png"
ln -sf usr/share/applications/com.evemtv.player.desktop "$APPDIR/com.evemtv.player.desktop"
ln -sf usr/share/icons/hicolor/256x256/apps/com.evemtv.player.png "$APPDIR/com.evemtv.player.png"
ln -sf com.evemtv.player.png "$APPDIR/.DirIcon"

SALIDA_APPIMAGE="$SALIDA/EvemTv-$VERSION-linux-x86_64.AppImage"
ARCH=x86_64 "$HERRAMIENTAS/appimagetool" --no-appstream \
  --runtime-file "$HERRAMIENTAS/runtime-x86_64" \
  "$APPDIR" "$SALIDA_APPIMAGE"
echo "Listo: $SALIDA_APPIMAGE (libmpv incluido: $LIBMPV)"
