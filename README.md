# EvemTv

Reproductor IPTV de escritorio para **Windows, macOS y Linux**, hecho en Flutter.
Compatible con servidores que usan la API de Xtream Codes y con listas M3U/M3U8.

> EvemTv es solo un reproductor: **no incluye listas, canales ni contenido**.
> Cada usuario es responsable del servicio y del contenido al que accede.

Estado: **Fase 3** (TV en vivo, películas y series). Ver [`CLAUDE.md`](CLAUDE.md) para la especificación completa.

## Requisitos

- Flutter estable (probado con 3.47.5 / Dart 3.13.4): `flutter doctor`
- Soporte de escritorio habilitado:
  `flutter config --enable-linux-desktop --enable-macos-desktop --enable-windows-desktop`

### Linux

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
  libmpv-dev mpv libsecret-1-dev gnome-keyring
```

- `libmpv` es el motor de video (media_kit). En Linux se usa la del sistema.
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
- Sin telemetría ni analytics.
- **No subas credenciales, URLs de servidores ni listas reales al repositorio.**
  Los tests usan solo datos inventados y dominios reservados (`example.com`, `.invalid`).
