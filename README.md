# EvemTv

Reproductor IPTV de escritorio para **Windows, macOS y Linux**, hecho en Flutter.
Compatible con servidores que usan la API de Xtream Codes y con listas M3U/M3U8.

> EvemTv es solo un reproductor: **no incluye listas, canales ni contenido**.
> Cada usuario es responsable del servicio y del contenido al que accede.

Estado: **Fase 5** (versión 1.0.0: instaladores para las tres plataformas).
Para instalar la app ya compilada, ver [`docs/instalacion.md`](docs/instalacion.md). Ver [`CLAUDE.md`](CLAUDE.md) para la especificación completa.

## Requisitos

- Flutter estable (probado con 3.47.5 / Dart 3.13.4): `flutter doctor`
- Soporte de escritorio habilitado:
  `flutter config --enable-linux-desktop --enable-macos-desktop --enable-windows-desktop`

### Linux

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
  libmpv-dev mpv libsecret-1-dev gnome-keyring
```

- `libmpv` es el motor de video (media_kit). Al compilar desde el código se usa
  la del sistema; el AppImage publicado trae la suya.
- `libsecret` y un llavero activo (GNOME Keyring o KWallet) son necesarios para
  guardar las credenciales. Sin llavero, la app muestra un error y no guarda
  nada en texto plano.

### macOS

- Xcode y CocoaPods / Swift Package Manager (según versión de Flutter).
- macOS 12 o superior.

### Windows

- Visual Studio 2022 con la carga de trabajo "Desarrollo para el escritorio con C++".

## Ejecutar

```bash
flutter pub get
flutter run -d linux     # o -d macos / -d windows
```

## Compilar

```bash
flutter build linux --release     # build/linux/x64/release/bundle/
flutter build macos --release     # build/macos/Build/Products/Release/EvemTv.app
flutter build windows --release   # build/windows/x64/runner/Release/
```

Cada plataforma se compila en su propio sistema operativo (o en GitHub Actions).

## Empaquetar y publicar

Los instaladores se arman con los scripts de `packaging/`, después de la
compilación release de cada sistema:

```bash
packaging/linux/crear_appimage.sh 1.0.0     # dist/EvemTv-1.0.0-linux-x86_64.AppImage (libmpv incluido)
packaging/macos/crear_dmg.sh 1.0.0          # dist/EvemTv-1.0.0-macos.dmg (firma ad hoc)
# Windows (Inno Setup 6):
iscc /DAppVersion=1.0.0 /DSourceDir=%CD%\build\windows\x64\runner\Release /Odist packaging\windows\evemtv.iss
```

El workflow `.github/workflows/release.yml` hace todo esto en GitHub Actions:

- **Con un tag `vX.Y.Z`** (debe coincidir con `version` de `pubspec.yaml`):
  verifica los certificados, corre análisis y tests, arma y prueba los
  instaladores de las tres plataformas y los publica en GitHub Releases con
  `SHA256SUMS.txt`.
- **Sin tag** (cambios en `packaging/` o a mano desde Actions): lo mismo sin
  publicar; los instaladores quedan como artefactos del run por 7 días.

Pasos de cada release: [`docs/fase5_checklist.md`](docs/fase5_checklist.md).

## Calidad

```bash
flutter analyze
flutter test                              # tests unitarios y de widgets
flutter test integration_test -d linux    # almacén seguro real del sistema
```

Si cambias las tablas de `lib/data/storage/app_database.dart`, regenera el
código de drift:

```bash
dart run build_runner build --delete-conflicting-outputs
```

GitHub Actions (`.github/workflows/build.yml`) analiza, prueba y compila
Linux, Windows y macOS en cada push.

## Datos locales

- Credenciales: almacén seguro del sistema.
- Perfiles y preferencias (sin credenciales): `evemtv.sqlite` en la carpeta de
  soporte de la app (en Linux, `~/.local/share/com.evemtv.player/`).

## Ícono y logo

El logo original está en `assets/branding/logo_source.png`. Los íconos de
Windows (`.ico`), macOS (`AppIcon`) y Linux, y el logo de la interfaz, se
generan con:

```bash
python3 tool/generate_icons.py   # requiere Pillow
```

## Certificados raíz (Windows, macOS y AppImage)

mpv usa `assets/certs/cacert.pem` para verificar HTTPS en Windows, macOS y
el AppImage de Linux (ver `docs/decisiones.md`, sección 12). Se actualiza
antes de cada release (el workflow de release no publica si no está al día):

```bash
tool/actualizar_certificados.sh              # descarga, verifica el SHA-256 y reemplaza
tool/actualizar_certificados.sh --verificar  # solo comprueba que sea el vigente
```

## Estructura

```
lib/
  core/       config, tema, errores, router, logger con redacción
  data/       xtream, m3u, epg, storage
  domain/     entidades y contratos de repositorio
  features/   auth, live, movies, series, player, search, favorites, settings
```

## Seguridad

- Las credenciales se guardan solo en el almacén seguro del sistema
  (Keychain, Credential Manager, libsecret).
- Todos los logs pasan por un redactor que enmascara usuarios, contraseñas y
  tokens (`/live/***/***/123.m3u8`).
- Sin telemetría ni analytics, salvo un conteo de uso mínimo una vez al día
  (sistema operativo, id de la instalación y una huella de la cuenta; nunca
  usuario ni contraseña), informado en los términos. Ver `docs/decisiones.md` §18.
- El aviso de actualización consulta `godebol.com/api/evemtv/version` sin
  datos de la cuenta, y solo abre descargas de `github.com/Elmarcinho` o
  `godebol.com` (`docs/decisiones.md` §19).
- **No subas credenciales, URLs de servidores ni listas reales al repositorio.**
  Los tests usan solo datos inventados y dominios reservados (`example.com`, `.invalid`).
