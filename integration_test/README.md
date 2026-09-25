# Pruebas de integración

Corren con el motor real de cada plataforma (mpv, almacén seguro del
sistema). En CI: `.github/workflows/build.yml`.

| Archivo | Qué comprueba |
|---|---|
| `secure_storage_test.dart` | Guardar, leer y borrar credenciales ficticias en el almacén seguro real (Keychain con firma ad-hoc, DPAPI, libsecret). |
| `playback_tls_test.dart` | mpv tiene `tls-verify=yes`; rechaza un certificado autofirmado **sin enviar la ruta** (que llevaría credenciales); reproduce un HTTPS con certificado válido; y abrir una URL no la deja escrita en archivos temporales. |

```bash
flutter test integration_test -d linux     # necesita un llavero activo
flutter test integration_test/playback_tls_test.dart -d linux
```

## Material de prueba (`tls_fixture.dart`, `assets/tls_probe.mkv`)

Todo es ficticio y existe solo para estas pruebas:

- `assets/tls_probe.mkv`: video sintético de 3 s (patrón de prueba y un
  tono), sin contenido de ningún proveedor. La prueba (b) lo descarga por
  HTTPS desde `raw.githubusercontent.com` (certificado válido); en CI se
  usa la URL del commit exacto (`TLS_VALID_URL`).
- Certificado **autofirmado** para `127.0.0.1` y su clave: no protege nada;
  está para comprobar que mpv lo rechaza.

Regenerar:

```bash
ffmpeg -f lavfi -i testsrc=size=64x64:rate=10 -f lavfi -i sine=frequency=440:sample_rate=22050 \
  -t 3 -c:v libx264 -preset ultrafast -crf 40 -c:a aac -b:a 16k tls_probe.mkv
openssl req -x509 -newkey rsa:2048 -nodes -days 36500 -subj "/CN=127.0.0.1" \
  -addext "subjectAltName=IP:127.0.0.1,DNS:localhost" -keyout key.pem -out cert.pem
```

## Medición de rendimiento (`test_driver/perf_app*.dart`)

Mide CPU y memoria de la app real en **modo perfil** contra un servidor
Xtream **ficticio** local (`test_driver/fake_panel.dart`: 2.000 canales,
24.000 películas, 8.000 series) en tres momentos: inicio en reposo,
navegar un catálogo grande y reproducir un video 720p. No es parte de CI.

La medición se toma desde afuera del proceso (`/proc/<pid>`), con la app
dibujando como siempre: el arnés de `integration_test` dibuja cuadros sin
parar y no sirve para medir el reposo. Los datos de la app (base, llavero,
imágenes) van a una carpeta temporal, nunca a los del usuario.

```bash
# Material sintético (patrón de prueba de ffmpeg) en una carpeta cualquiera:
ffmpeg -f lavfi -i testsrc2=size=1280x720:rate=30 -f lavfi -i sine=frequency=440 \
  -t 120 -c:v libx264 -preset veryfast -crf 28 -c:a aac -movflags +faststart perf_video.mp4
ffmpeg -f lavfi -i testsrc2=size=300x450 -frames:v 1 poster.jpg
ffmpeg -f lavfi -i testsrc2=size=1280x720 -frames:v 1 backdrop.jpg

PERF_ASSETS=/ruta/a/esa/carpeta PERF_LABEL=prueba \
  flutter drive --profile -d linux \
  --driver=test_driver/perf_app_test.dart --target=test_driver/perf_app.dart
# Resultados: /ruta/a/esa/carpeta/perf_results.txt
```

Solo Linux. La ventana de la app se abre durante unos minutos: conviene
dejarla visible y no usar el equipo mientras mide.
