#!/usr/bin/env bash
# Actualiza assets/certs/cacert.pem con el paquete de certificados raíz de
# Mozilla que publica curl.se y verifica su SHA-256. Primer paso de cada
# release (docs/fase5_checklist.md). Con --verificar solo comprueba que el
# del repositorio sea el vigente (lo usa el workflow de release).
set -euo pipefail

cd "$(dirname "$0")/.."
DEST=assets/certs/cacert.pem
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

curl -fsSL --proto '=https' --tlsv1.2 -o "$TMP/cacert.pem" https://curl.se/ca/cacert.pem
curl -fsSL --proto '=https' --tlsv1.2 -o "$TMP/cacert.pem.sha256" https://curl.se/ca/cacert.pem.sha256

esperado=$(awk '{print $1}' "$TMP/cacert.pem.sha256")
obtenido=$(sha256sum "$TMP/cacert.pem" | awk '{print $1}')
if [[ "$esperado" != "$obtenido" ]]; then
  echo "ERROR: el SHA-256 del paquete descargado no coincide con el publicado." >&2
  exit 1
fi

fecha=$(grep -m1 '^## Certificate data from Mozilla as of:' "$TMP/cacert.pem" | sed 's/^## Certificate data from Mozilla as of: //')
cantidad=$(grep -c 'BEGIN CERTIFICATE' "$TMP/cacert.pem")

if [[ "${1:-}" == "--verificar" ]]; then
  if cmp -s "$TMP/cacert.pem" "$DEST"; then
    echo "Certificados al día (datos de Mozilla: $fecha)."
    exit 0
  fi
  actual=$(grep -m1 '^## Certificate data from Mozilla as of:' "$DEST" | sed 's/^## Certificate data from Mozilla as of: //')
  echo "::error title=Certificados desactualizados::El repositorio tiene los datos de Mozilla del $actual y curl.se publica los del $fecha. Ejecuta tool/actualizar_certificados.sh, haz commit y vuelve a crear el tag." >&2
  exit 1
fi

if cmp -s "$TMP/cacert.pem" "$DEST"; then
  echo "Sin cambios: $DEST ya es el vigente (datos de Mozilla: $fecha, $cantidad certificados)."
else
  cp "$TMP/cacert.pem" "$DEST"
  echo "Actualizado $DEST (datos de Mozilla: $fecha, $cantidad certificados, SHA-256 $obtenido)."
  echo "Anota la fecha en docs/decisiones.md, sección 12."
fi
