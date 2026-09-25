# Reproductor IPTV de escritorio — Especificación del proyecto

## 1. Qué estamos construyendo

Una aplicación de escritorio para **Windows, macOS y Linux**, hecha en **Flutter**, que funciona como un reproductor IPTV neutral (al estilo IPTV Smarters). El usuario inicia sesión con **3 datos: usuario, contraseña y URL del servidor**, y la app muestra todo el contenido de su cuenta: TV en vivo con guía (EPG), películas y series.

Debe funcionar con **cualquier servicio compatible con la API de Xtream Codes** (`player_api.php`). Como segunda forma de ingreso, debe aceptar una **URL de lista M3U/M3U8**.

La app es un reproductor vacío: **no incluye listas, canales, contenido ni marcas de ningún proveedor**.

## 2. Stack técnico

- Flutter (canal estable, última versión) con soporte desktop habilitado: `windows`, `macos`, `linux`.
- Reproducción de video: **media_kit** + `media_kit_video` + `media_kit_libs_video` (motor mpv: HLS, MPEG-TS, HEVC, AC3/EAC3).
- HTTP: `dio`.
- Estado: `flutter_riverpod`.
- Navegación: `go_router`.
- Credenciales: `flutter_secure_storage` (Keychain en macOS, Credential Manager en Windows, libsecret en Linux).
- Caché local de catálogo y EPG: `drift` (SQLite) o `hive` — elegir uno y justificar.
- Ventana: `window_manager` (tamaño mínimo, pantalla completa).
- Parseo de EPG XMLTV: `xml`.

**Antes de agregar cualquier paquete, verificar en pub.dev que esté mantenido y usar la última versión estable compatible.** Si algún paquete de esta lista está abandonado, proponer una alternativa antes de usarla.

## 3. Arquitectura

Estructura por funcionalidades, con capas separadas:

```
lib/
  core/            # config, tema, errores, utilidades, logger con redacción
  data/
    xtream/        # cliente de la API Xtream, modelos, mapeo
    m3u/           # parser de listas M3U
    epg/           # parser XMLTV y EPG corta
    storage/       # secure storage, base de datos local
  domain/          # entidades y contratos (repositorios abstractos)
  features/
    auth/          # login, perfiles, cierre de sesión
    live/          # TV en vivo + EPG
    movies/        # VOD
    series/        # series, temporadas, episodios
    player/        # reproductor y controles
    search/
    favorites/
    settings/
  main.dart
```

La interfaz nunca llama a la API directamente: siempre a través de repositorios. Tanto Xtream como M3U implementan el mismo contrato de repositorio, para que la UI no dependa del tipo de fuente.

## 4. API de Xtream Codes (referencia)

Base: `{url}/player_api.php?username={u}&password={p}`

| Acción | Parámetro `action` |
|---|---|
| Login / info de cuenta | (sin action) → devuelve `user_info` y `server_info` |
| Categorías en vivo | `get_live_categories` |
| Canales en vivo | `get_live_streams` (opcional `category_id`) |
| Categorías de películas | `get_vod_categories` |
| Películas | `get_vod_streams` |
| Detalle de película | `get_vod_info&vod_id={id}` |
| Categorías de series | `get_series_categories` |
| Series | `get_series` |
| Detalle de serie | `get_series_info&series_id={id}` |
| EPG corta de un canal | `get_short_epg&stream_id={id}&limit={n}` |
| EPG completa | `{url}/xmltv.php?username={u}&password={p}` |

URLs de reproducción:

- En vivo: `{url}/live/{u}/{p}/{stream_id}.m3u8` (o `.ts` como respaldo)
- Película: `{url}/movie/{u}/{p}/{stream_id}.{container_extension}`
- Episodio: `{url}/series/{u}/{p}/{episode_id}.{container_extension}`

Reglas de robustez:

- Los paneles devuelven tipos inconsistentes (números como texto, campos nulos, arrays vacíos en lugar de objetos). Todos los modelos deben parsear de forma tolerante y nunca romper la app por un campo raro.
- Validar `user_info.auth == 1` y `status == "Active"`. Mostrar fecha de expiración y conexiones máximas/activas.
- Soportar URLs con y sin puerto, con y sin barra final, HTTP y HTTPS.
- Timeouts razonables y reintentos con espera progresiva. Mensajes de error claros en español (servidor caído, credenciales incorrectas, cuenta vencida, sin conexión).

## 5. Seguridad (obligatorio)

1. **Nunca** escribir credenciales, URLs de servidores reales ni datos de cuentas en el código, en archivos `.env`, en `--dart-define`, en tests ni en commits. Las credenciales de prueba se ingresan a mano en la pantalla de login al probar.
2. Credenciales guardadas **solo** en `flutter_secure_storage`. Nunca en SharedPreferences, base de datos, archivos planos ni caché.
3. **Logger con redacción**: toda URL que contenga usuario/contraseña debe registrarse enmascarada (ej. `/live/***/***/123.m3u8`). Ningún log, mensaje de error ni reporte muestra credenciales. En builds de release, logs mínimos.
4. No enviar telemetría, analytics ni reportes de errores a servicios de terceros.
5. No desactivar la validación de certificados TLS de forma global. HTTP se permite solo porque lo exige el servidor que el usuario ingresó.
6. Validar la URL de entrada: esquema `http`/`https`, formato correcto, sin espacios. Normalizarla antes de guardar.
7. Cerrar sesión borra credenciales, caché del catálogo y EPG de ese perfil.
8. PIN opcional de control parental para categorías marcadas por el usuario, guardado como hash.
9. En macOS, configurar los entitlements mínimos necesarios (cliente de red; permitir cargas HTTP arbitrarias porque los paneles suelen ser HTTP).

## 6. Funcionalidades

**Fase MVP:**

- Login con usuario, contraseña y URL (Xtream). Pestaña alternativa para URL M3U.
- Múltiples perfiles/cuentas guardadas, con selector al iniciar.
- Pantalla de inicio con acceso a En vivo, Películas y Series, y datos de la cuenta (vencimiento, conexiones).
- TV en vivo: categorías, lista de canales con logo, programa actual y siguiente (EPG corta), cambio rápido de canal con teclado.
- Películas y series: categorías, grilla con pósters, ficha de detalle, temporadas y episodios.
- Reproductor: pantalla completa, pausa, volumen, selección de pista de audio y subtítulos, barra de progreso para VOD, reconexión automática si se corta un canal en vivo.
- Búsqueda global en vivo, películas y series.
- Favoritos y "seguir viendo" (posición guardada por película/episodio), por perfil.
- Atajos de teclado: espacio (pausa), F (pantalla completa), flechas (volumen/adelantar), arriba/abajo (cambiar canal), Esc (salir de pantalla completa).

**Fase 2 (después del MVP):**

- Guía EPG completa en formato grilla (XMLTV), con caché.
- Catch-up / TV archive si el panel lo soporta (`tv_archive == 1`).
- Control parental con PIN.
- Tema claro/oscuro.

## 7. Interfaz

- Diseño oscuro, moderno y limpio, pensado para pantalla grande y uso con mouse y teclado.
- Todo el texto en **español**.
- Carga progresiva: mostrar categorías primero y cargar canales/pósters bajo demanda. Listas largas con virtualización (miles de canales no deben trabar la app).
- Estados de carga, vacío y error en todas las pantallas.

## 8. Neutralidad del producto

- Sin contenido, listas ni servidores precargados.
- Sin nombres ni logos de proveedores o marcas de IPTV.
- Pantalla de términos al primer inicio: la app es solo un reproductor; el usuario es responsable del servicio y contenido al que accede.
- **Excepción aprobada por el dueño del proyecto:** un anuncio propio del desarrollador (botón discreto en la barra superior del inicio y en el encabezado de En vivo, Películas y Series; banner en el selector de cuentas y el login) que invita a escribir por WhatsApp. Su texto y enlace viven solo en `AppConfig` (`promoTitle`, `promoSubtitle`, `promoUrl`); no se precargan listas, servidores ni credenciales, y la app no se conecta a ningún servicio por el anuncio (solo abre el enlace cuando el usuario pulsa "Escríbenos"). El banner se cierra con ✕ solo hasta la próxima apertura de la app.

## 9. Empaquetado y distribución

- **Windows**: instalador (MSIX o Inno Setup) y versión portable en .zip.
- **macOS**: `.dmg` con firma ad-hoc (sin cuenta de desarrollador por ahora). Incluir en `docs/` una guía para el usuario de cómo habilitar la app en *Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente*.
- **Linux**: AppImage. Documentar la dependencia de libmpv si aplica.
- GitHub Actions para compilar las tres plataformas y publicar en GitHub Releases.
- Aviso de actualización dentro de la app: consultar la última versión publicada y mostrar un botón de descarga (sin autoinstalación por ahora).

## 10. Calidad

- Tests unitarios del cliente Xtream y del parser M3U usando respuestas JSON/M3U de ejemplo **ficticias** (inventadas, sin datos reales).
- `flutter analyze` sin errores ni warnings.
- Código comentado en español donde la lógica no sea obvia.
- README con cómo instalar dependencias, correr en cada sistema y compilar.

## 11. Forma de trabajo

Trabajar por fases. Al terminar cada una: explicar qué se hizo, cómo probarlo y esperar confirmación antes de seguir.

- **Fase 0**: crear proyecto, habilitar desktop, instalar dependencias verificadas, estructura de carpetas, logger con redacción, tema base.
- **Fase 1**: login Xtream + M3U, validación, secure storage, perfiles, pantalla de inicio con datos de la cuenta.
- **Fase 2**: TV en vivo con categorías, EPG corta y reproductor básico.
- **Fase 3**: películas y series con fichas y reproducción.
- **Fase 4**: búsqueda, favoritos, seguir viendo, atajos de teclado.
- **Fase 5**: empaquetado para las 3 plataformas + GitHub Actions + aviso de actualización.
- **Fase 6**: EPG completa en grilla, catch-up, control parental.

Si algo de esta especificación es ambiguo o hay una mejor alternativa técnica, preguntar o proponerla antes de implementarla.
