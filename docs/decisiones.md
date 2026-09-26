# Decisiones técnicas

Registro de decisiones de arquitectura de EvemTv. Cada entrada explica qué se
eligió, qué se descartó y por qué.

## 1. Caché local: drift (SQLite) en lugar de hive

**Decisión:** `drift` 2.35 + `sqlite3` 3.x (SQLite incluido, sin
`sqlite3_flutter_libs`, que está en fin de vida).

**Motivos:**

- **EPG:** hay que consultar programas por canal y por rango horario
  ("qué hay ahora", "grilla de 18:00 a 22:00"). En SQLite eso es una consulta
  indexada; en un almacén clave-valor habría que cargar todo en memoria y
  filtrar. Una EPG XMLTV completa puede tener cientos de miles de programas.
- **Búsqueda global:** SQLite trae FTS5 (búsqueda de texto completo), rápida
  aun con decenas de miles de canales, películas y series.
- **Aislamiento por perfil:** todas las tablas llevan `profile_id`. Cerrar
  sesión borra todo lo de ese perfil con un `DELETE ... WHERE profile_id = ?`.
- **Migraciones con tipos verificados** a medida que el esquema crece.

**Descartado:**

- `hive`: sin versiones desde 2022, no soporta Dart 3.
- `hive_ce` (el fork mantenido): funciona, pero no tiene consultas por rango ni
  búsqueda de texto completo.
- `isar`: abandonado.

**Costo aceptado:** drift necesita generación de código (`build_runner` +
`drift_dev`). Es el único generador de código del proyecto.

**Qué NO se guarda en drift:** credenciales ni URLs de servidor. Solo
`profile_id` y nombre del perfil (ver sección 4).

## 2. Estado: Riverpod 3 sin generación de código

**Decisión:** `flutter_riverpod` con `Provider`, `Notifier` y `AsyncNotifier`
escritos a mano. Sin `riverpod_generator` ni `riverpod_annotation`.

**Motivos:**

- Un solo generador de código en el proyecto (el de drift): compilaciones más
  rápidas y menos archivos `.g.dart`.
- Los providers de esta app son pocos y simples; las anotaciones ahorrarían
  poco código.
- Riverpod 3 sin generación de código tiene soporte completo, no es una API
  secundaria.

**Modelos de datos:** también a mano, sin `json_serializable` ni `freezed`.
Los paneles Xtream devuelven tipos inconsistentes (`"1"` o `1`, `null`, `[]` en
lugar de `{}`) y el código generado es demasiado estricto. Se usan funciones
de lectura tolerantes, reforzadas por `strict-casts` en
`analysis_options.yaml`.

## 3. Instalador de Windows: Inno Setup en lugar de MSIX

**Decisión:** instalador `.exe` con Inno Setup, más una versión portable
`.zip`.

**Motivos:**

- MSIX exige firmar el paquete con un certificado confiable para instalarlo
  fuera de la Microsoft Store. Sin certificado, el usuario tiene que instalar
  uno a mano o activar el modo desarrollador.
- Inno Setup genera un instalador clásico que funciona sin firma (Windows
  SmartScreen muestra un aviso, que se puede pasar con "Más información →
  Ejecutar de todas formas").
- Se puede automatizar en GitHub Actions (`iscc` está disponible en los
  runners de Windows).

## 4. Credenciales solo en el almacén seguro del sistema

- URL del servidor, usuario y contraseña (y la URL M3U completa, que suele
  llevar credenciales en la query) se guardan **solo** en
  `flutter_secure_storage`.
- **macOS:** `usesDataProtectionKeychain: false`. El Keychain de protección de
  datos exige el entitlement `keychain-access-groups` con un Team ID, que no
  existe con firma ad-hoc. Se valida en el workflow de CI de la Fase 1.
- **Linux:** requiere un llavero activo (GNOME Keyring o KWallet). Si no hay,
  se muestra un error claro y **no** se guarda nada en texto plano.

## 5. Logs, errores y modelo de amenaza

### Modelo de amenaza

- **Los logs son locales.** Salen por la consola de desarrollo (debug) o por
  `dart:developer` (release). No se escriben a archivos compartidos ni se
  envían a ningún servicio: no hay telemetría, analytics ni reportes de
  errores remotos. (La única salida de datos de uso es el conteo diario de
  §18, que nunca lleva logs.)
- **Qué se protege:** que las credenciales (usuario, contraseña, URL del
  servidor, URL M3U) terminen en un texto que el usuario copie al pedir ayuda
  (issue en GitHub, foro, captura de pantalla) o que quede en la salida de la
  consola.
- **Fuera de alcance:** un atacante con acceso a la sesión del usuario o a su
  equipo. Ese atacante puede leer el almacén seguro del sistema abierto por
  la app o inspeccionar la memoria del proceso; el redactor no pretende
  defender contra eso.

### Primera barrera: no registrar datos externos

- El código **nunca** registra URLs, cuerpos de respuesta, JSON crudo ni
  textos externos. Se registran eventos propios y estructurados con
  `AppLogger.event('xtream.request', {'action': …, 'http': 401})`: tipo de
  acción, `stream_id`, formato, código HTTP.
- Los errores de red se convierten a `AppFailure` antes de registrarse. De un
  `AppFailure` se registra solo el tipo, el `detail` (armado por nuestro
  código) y el tipo de la causa, nunca su texto.
- Mensajes de Dio, mpv y otros errores externos: en release **solo el tipo**;
  en debug pasan por la segunda barrera y se recortan a 300 caracteres.
- `AppFailure.message` es siempre un texto fijo en español. La pantalla roja
  de error de Flutter se reemplaza por un texto fijo, también en debug.
- En release solo se registran advertencias y errores, sin stack traces.

### Segunda barrera: `Redactor`

Simple a propósito. **No decodifica la entrada** (decodificar rompía los
límites de los campos y creaba casos nuevos cada vez).

1. **Secretos registrados** (usuario, contraseña, URL del perfil activo). Al
   registrarse se generan sus variantes: literal, percent-encoding de
   componente y de query en mayúsculas y minúsculas, doble codificación de
   cada una, escape JSON (`\"`, `\\`, `\n`…) combinado con `\/` y con
   `\uXXXX` (mayúsculas o minúsculas), y la forma con `\uXXXX` para todo
   símbolo. Se reemplazan todas, de la más larga a la más corta.
2. **Secretos cortos** (menos de 3 caracteres): solo como token completo. El
   límite izquierdo es el inicio del texto, un carácter no alfanumérico, una
   secuencia `%XX` completa o un escape JSON; nunca una posición dentro de
   `%XX`.
3. **Patrones por formato**, cada uno sin decodificar: rutas Xtream (normal,
   `\/` y `%2F`), query y formularios (claves con letras codificadas como
   `%70assword`; el valor llega hasta `&`, `#`, espacio o comilla), JSON y
   `esquema://usuario:clave@`.

### Riesgo residual aceptado

El redactor **no** garantiza cubrir:

- Codificaciones triples o superiores, base64, u otras transformaciones de un
  secreto no registrado.
- Claves sensibles con separadores codificados (`%26password%3D…`) o dentro
  de JSON escapado dentro de otro string, si el valor no es un secreto
  registrado.
- Credenciales de un perfil que no es el activo (sus secretos no están
  registrados).
- Secretos de 1–2 caracteres pegados a otro texto alfanumérico.

Se acepta porque la primera barrera impide que esos textos lleguen al logger
y porque los logs no salen del equipo. Si en el futuro se agregan logs en
archivo o exportación de diagnósticos, este riesgo debe revisarse.

## 6. Motor de video con inicialización diferida

`MediaKit.ensureInitialized()` lanza una excepción si falta libmpv. No se
llama en `main()`, sino al primer intento de reproducir (`MediaEngine`), para
que login, perfiles y catálogo funcionen aunque el reproductor no esté
disponible. En ese caso se muestra un error claro al reproducir.

## 7. Cuentas, sesiones y URLs (Fase 1)

- **URL del servidor:** se exige `http://` o `https://` explícito. No se
  agrega un esquema por defecto para no adivinar (y no degradar a HTTP en
  silencio). Se normaliza: minúsculas, sin barra final, sin query ni
  fragmento, sin el endpoint si se pegó (`/player_api.php`, `/get.php`), y el
  puerto por defecto se omite (`http://host:80` = `http://host`). Se rechazan
  espacios, hosts mal formados, puertos fuera de rango y credenciales dentro
  de la URL.
- **Lista M3U:** se conserva la URL completa (ruta y query). Si es un
  `get.php?username=…&password=…` se ofrece ingresar como Xtream, que agrega
  EPG, películas y series. La verificación conserva como máximo 4 KB y exige
  que la primera línea con contenido sea `#EXTM3U` o `#EXTINF:`.
- **Números y fechas anómalos** (`NaN`, `Infinity`, `1e309`, fuera de ±2^53 o
  del rango de `DateTime`) se leen como ausentes, nunca lanzan.
- **Nombre visible del perfil:** el usuario de la cuenta (en M3U, el
  `username` de la query si lo tiene). Se lee del almacén seguro al mostrar
  el selector y se mantiene solo en memoria. En la base se guarda un nombre
  genérico ("Cuenta N"), que se muestra solo si el llavero no está
  disponible. Así la base no guarda usuario ni host del servidor.
- **Cambiar de cuenta** vuelve al selector sin borrar nada. **Cerrar sesión**
  borra credenciales y todos los datos locales de ese perfil (spec §5.7): para
  volver a usarlo hay que ingresar los datos de nuevo. La sesión termina
  **solo si el borrado se completó**; si el llavero falla, la sesión sigue
  abierta, se muestra el error y se puede reintentar.
- **Resultados obsoletos (época de sesión):** `SessionController` lleva un
  contador que cambia al abrir o terminar una sesión y al eliminar un perfil.
  Desde la revisión de la Fase 4 solo lo usa la apertura de un perfil (que
  ocurre fuera de toda sesión); lo demás vive en el contenedor de la sesión
  (ver §14).
- **Abrir un perfil guardado no espera al servidor:** se entra al inicio y los
  datos de la cuenta se cargan ahí, con "Reintentar" si fallan. Así un servidor
  caído no bloquea el acceso a la app.
- **Reintentos:** solo GET, ante timeouts, conexión caída o 5xx, con espera de
  0,8 s, 1,6 s… El login usa un solo reintento para no demorar el error. Los
  reintentos automáticos de Riverpod están desactivados para no duplicarlos.
- **Base de datos** en la carpeta de soporte de la app
  (`~/.local/share/com.evemtv.player/` en Linux, `~/Library/Application
  Support/com.evemtv.player/` en macOS, `%APPDATA%` en Windows), no en
  Documentos.
- **User-Agent** propio (`EvemTv/<versión>`); no se imita a otros
  reproductores.

## 8. CI desde la Fase 1

`.github/workflows/build.yml` corre en cada push y pull request:

- Linux: código generado de drift al día, formato, `flutter analyze`,
  `flutter test` y compilación.
- Windows: compilación y prueba del almacén seguro real.
- macOS: compilación, firma ad-hoc verificada y prueba del **Keychain real con
  firma ad-hoc** (`integration_test/secure_storage_test.dart`).

Solo compila y prueba; el empaquetado y la publicación son de la Fase 5.

## 9. TV en vivo y reproductor (Fase 2)

- **Carga progresiva:** primero las categorías; los canales se piden por
  categoría (al abrir se muestra la primera, no la lista completa). Las listas
  usan `ListView.builder` con altura fija de fila, así miles de canales no
  traban la interfaz. Las respuestas de más de 256 KB se decodifican en otro
  isolate.
- **Caché en memoria por sesión**, no en drift todavía. Las categorías y
  canales ya vistos quedan en memoria mientras dure la sesión y se descartan
  al cambiarla. La caché en disco llega con la búsqueda global (Fase 4, FTS5)
  y la EPG completa (Fase 6), que son las que necesitan el catálogo completo.
- **EPG corta** bajo demanda: solo para las filas visibles, con como máximo 4
  peticiones simultáneas y 5 minutos de caché. Si falla, la fila no muestra
  programa (no es un error para el usuario). Títulos en base64 decodificados
  solo si el resultado es UTF-8 válido.
- **Formato de vivo según `allowed_output_formats`:** `m3u8` y luego `ts`,
  solo los permitidos. Si la cuenta no informa formatos o solo permite otros
  (p. ej. `rtmp`), se prueban ambos. En cada reconexión se alterna el formato.
- **Reconexión automática:** ante error, fin del stream o carga trabada más de
  20 s, reintenta con esperas de 1, 2, 4, 8 y 15 s. Tras 30 s estable, el
  contador vuelve a cero. Agotados los intentos, muestra un error fijo con
  "Reintentar". Cambiar de canal cancela la reconexión pendiente.
- **mpv:** nivel de log `error` (sus mensajes incluyen la URL), User-Agent
  propio, `network-timeout` de 15 s. El motor se inicializa recién al
  reproducir (ver sección 6).
- **M3U:** la lista se descarga una vez por sesión (tope de 64 MB) y se
  parsea en otro isolate. Los canales se identifican con un hash FNV-1a de la
  URL (`m3u:<hash>`): estable para favoritos futuros y sin credenciales en
  claro. Las entradas con rutas `/movie/`, `/series/` o extensión de video se
  reservan para la Fase 3. Las listas no tienen EPG corta; la guía XMLTV de
  `url-tvg` se usará en la Fase 6.
- **Mini reproductor en En vivo:** un clic en un canal lo reproduce en el
  panel derecho; con el teclado, se reproduce al detenerse 600 ms en un canal
  (no se abre un stream por cada canal que se pasa). Doble clic, Enter o clic
  sobre el video abren la pantalla completa. Ambos usan **el mismo
  reproductor** (`livePlayerProvider`): pasar de uno a otro no corta ni
  reconecta. El reproductor se libera al salir de En vivo o cambiar de
  sesión. Si en pantalla completa se cambia de canal, la lista acompaña la
  selección al volver.
- **El panel del mini reproductor muestra el canal que suena**, no el
  seleccionado: al cambiar de categoría la selección pasa a otra lista pero el
  video sigue con el canal anterior, y el panel no debe contradecirlo. La
  fila del canal que suena lleva un indicador.
- **Pantalla completa:** lista de canales lateral (botón o tecla L) que marca
  el canal actual y permite saltar a cualquiera con un clic; un clic fuera de
  la lista la cierra. Sin botones de canal anterior/siguiente (se usan ↑/↓ o
  la lista). Todos los íconos de la barra comparten color y tamaño.
- **Atajos del reproductor:** Espacio pausa, F pantalla completa, Esc cierra
  la lista, sale de pantalla completa o vuelve, ↑/↓ cambian de canal, ←/→
  volumen, M silencio, L lista de canales. En la lista de En vivo: ↑/↓,
  Re Pág/Av Pág, Enter pantalla completa, Esc vuelve al inicio.

## 10. Películas y series (Fase 3)

- **Mismo patrón que En vivo:** categorías primero, elementos por categoría
  (se abre la primera), grilla perezosa de pósters y filtro por nombre. Una
  sola pantalla de catálogo (`CatalogScreen<T>`) sirve para ambos.
- **Fichas:** se muestra enseguida lo que ya se sabe (póster y nombre) y se
  completa con sinopsis, reparto, duración y fondo al llegar `get_vod_info` /
  `get_series_info`. Si la ficha falla, se puede reproducir igual.
- **Pósters:** `Image.network` decodificado al tamaño mostrado
  (`cacheWidth`), con caché en memoria de Flutter. Se descartó
  `cached_network_image` por ahora: agrega una base SQLite propia para la
  caché de disco y no hace falta para cargar bajo demanda. Se puede revisar
  si el consumo de red de los pósters resulta un problema.
- **Parseo tolerante de series:** `episodes` se acepta como objeto por
  temporada, lista de listas o lista plana; episodios repetidos se descartan;
  temporadas y episodios se ordenan. La extensión del contenedor solo se usa
  si es alfanumérica (evita alterar la ruta de la URL).
- **M3U:** las películas se agrupan por `group-title`; las series se arman
  a partir del nombre (`Serie S01 E02`, `Serie - S1E2 - Título`,
  `Serie 1x02`). Sin numeración, cada entrada es una serie de un episodio.
  Las listas no traen sinopsis ni reparto: ficha mínima.
- **Reproductor de películas y episodios:** barra de progreso con tiempos,
  pausa, volumen, pistas, pantalla completa. Teclado: Espacio, F, Esc,
  ←/→ ±10 s, ↑/↓ volumen, M silencio, N siguiente episodio.
- **Reconexión en VOD:** ante error, carga trabada 30 s o un "fin" que llega
  a más de 60 s del final real, reconecta (2, 4 y 8 s) y **vuelve a la
  posición donde se cortó**. El fin real muestra "Ver de nuevo" o, en series,
  el siguiente episodio con cuenta regresiva de 10 s (cancelable), también
  entre temporadas.
- **Errores de mpv no fatales:** mpv reporta como error cosas que no cortan
  la reproducción (p. ej. "Could not open codec" cuando falla la
  decodificación por hardware y sigue por software). Un error solo provoca
  reconexión si en 3 s el video no avanzó y no está en pausa por el usuario.
  Vale para vivo y VOD.
- **"Abierto" no es `playing`:** media_kit pone `playing = true` apenas se
  pide reproducir, antes de abrir el archivo. Un contenido cuenta como
  abierto recién cuando mpv informa duración o la posición avanza.
- **Contenido que no existe en el servidor:** si una película o episodio no
  llega a abrirse, se consulta el código HTTP pidiendo un solo byte. Con un
  4xx se informa "no disponible en el servidor" enseguida, sin reintentos.
- **Decodificación por hardware:** `hwdec=auto-safe` (recomendado por mpv)
  en lugar de `auto`, el valor por defecto de media_kit.
- **Reanudar:** el controlador ya acepta una posición inicial; "seguir
  viendo" (guardar la posición por perfil) llega en la Fase 4.

## 11. Favoritos (adelantado de la Fase 4)

- Canales, películas y series, **por perfil**, en la tabla `favorites` de
  drift. Se borran al cerrar sesión o eliminar el perfil (en la misma
  transacción y, además, con borrado en cascada).
- Se marcan con ★ en el panel del canal y en las fichas; se ven en la
  categoría fija **Favoritos** de En vivo, Películas y Series.
- Se guarda lo mínimo: id, nombre, categoría, número de canal, extensión y
  año. **Ninguna URL**, ni de stream ni de imagen: los logos y pósters
  suelen estar en el servidor del panel o llevar tokens (incluso
  codificados), y ningún filtro puede garantizar que no contengan
  credenciales. La imagen se resuelve en memoria desde la lista de la
  categoría del favorito, que ya queda cacheada durante la sesión.
- Esquema: v2 creó la tabla; v3 descarta la columna `image_url` (y las URLs
  que hubiera) y agrega `category_id`, conservando los favoritos.

## 12. Revisión de las Fases 2 y 3: reglas adicionales

- **TLS en mpv:** mpv trae `tls-verify=no` por defecto y la validación de
  Dio no cubre sus conexiones. Se fija `tls-verify=yes` al crear cada
  reproductor y se comprueba que quedó activa (si no, no se reproduce). El
  workflow prueba en Linux, Windows y macOS con el mpv real que un
  certificado autofirmado se rechaza **sin que llegue la petición** y que un
  HTTPS válido sigue reproduciendo (`integration_test/playback_tls_test.dart`).
- **Certificados raíz en Windows y macOS:** el libmpv que incluye media_kit
  en esas plataformas no encuentra los certificados del sistema; con
  `tls-verify=yes` rechazaba todo HTTPS, incluso válido (confirmado en CI).
  La app incluye el paquete de certificados raíz de Mozilla publicado por
  curl.se (`assets/certs/cacert.pem`, 121 certificados, datos de Mozilla al
  25/09/2026; se actualiza con `tool/actualizar_certificados.sh`) y se lo pasa a mpv con `tls-ca-file`. En Linux se usan los
  certificados del sistema (el libmpv de la distribución los encuentra).
  Consecuencia: en Windows y macOS no se confía en certificados raíz
  agregados a mano al sistema (p. ej. proxies corporativos). El paquete
  debe actualizarse periódicamente (ver README).
- **Sin archivos temporales con la URL:** `player.open` de media_kit 1.2.6
  escribe la lista (con la URL y sus credenciales) en un archivo temporal y
  lo borra 5 s después. Se abre con `loadfile` directo a mpv, sin tocar el
  disco; `stop()`/`play()` mantienen el estado de media_kit. La misma prueba
  de integración verifica que no queda nada en el directorio temporal.
- **Nada derivado de las URLs** llega a logs, pantalla ni base: el formato
  del log sale de un conjunto cerrado (`m3u8`, `ts`, `mp4`…; si no, `otro`);
  las entradas M3U sin título reciben un nombre genérico ("Canal sin
  nombre", "Película sin título"); en M3U tampoco se deriva la extensión.
- **Cola de EPG cancelable:** además del límite de 4 simultáneas, cada
  petición en espera se descarta si su fila ya no se ve, y al terminar la
  sesión la fuente cancela toda la cola (`ContentSource.dispose`).
- **Vivo, "estable":** el contador de reintentos vuelve a cero solo tras
  30 s de reproducción continua; carga o pausa reinician la cuenta.
- **VOD:** la posición pendiente se aplica con la duración de la apertura
  actual (media_kit emite 0 al reabrir); un fallo tardío de una apertura
  anterior no reinicia el contenido actual.
- **Series:** en M3U se reconocen por el nombre (`S01E02`, `1x02`) aunque la
  ruta no tenga `/series/` (salvo URLs claramente de vivo). En Xtream, una
  lista de listas sin `season` toma las temporadas declaradas.

## 13. Catálogo local, búsqueda, "seguir viendo" y caché de pósters (Fase 4)

- **Catálogo en drift por perfil** (`catalog_categories`, `catalog_items`,
  `catalog_sync`, esquema v4): nombres, ids, categoría, número, extensión,
  año y puntaje. **Sin URLs** (ni stream ni imagen), por la misma razón que
  los favoritos.
- **Actualización en segundo plano:** al abrir la sesión, cada tipo (vivo,
  películas, series) con más de 12 h se vuelve a descargar completo, de a
  uno. El JSON grande se decodifica en otro isolate y drift escribe en el
  suyo: la interfaz no se bloquea. Si la sesión termina a mitad de camino, la
  petición en curso se cancela y no sale ninguna otra (ver §14).
- **La búsqueda espera a la primera descarga:** mientras falte algún tipo y
  la descarga siga en curso, el campo queda deshabilitado con "Preparando la
  búsqueda" y el progreso (p. ej. "Descargando películas (2 de 3)"). Buscar
  antes daba "nada coincide" solo porque faltaba contenido. Lo escrito se
  conserva y se busca al terminar. En las actualizaciones siguientes se
  busca en el catálogo anterior mientras se descarga el nuevo. Si un tipo
  falla, se habilita igual y el mensaje dice qué falta. En la búsqueda se ve el estado y hay un botón
  "Actualizar".
- **La navegación sigue usando la red + memoria** (con imágenes); el
  catálogo local sirve para la búsqueda. Mostrar las listas desde la base
  obligaría a guardar URLs de imágenes o a mostrar listas sin imágenes.
- **Búsqueda global con FTS5** (`catalog_search`): sin tildes ni mayúsculas
  (`remove_diacritics`), cada palabra como prefijo y todas obligatorias. Lo
  que escribe el usuario nunca llega como sintaxis FTS: cada palabra va
  entre comillas, y los caracteres de control (U+0000–U+001F y
  U+007F–U+009F, incluido NUL) se tratan como separadores. Imágenes de los resultados resueltas en memoria solo para
  las filas visibles.
- **"Seguir viendo"** (`watch_progress`): posición y duración por película o
  episodio, sin URLs. Se guarda cada 10 s, al cambiar de episodio y al salir;
  con menos de 30 s no se guarda. Al pasar el 95 % (o faltar menos de 90 s)
  se quita y, en series, queda listo el siguiente episodio. Al reabrir se
  retoma 5 s antes, con un botón "Desde el principio".
- **Caché de pósters en disco:** sí conviene (cada apertura volvía a
  descargar miles de imágenes). Archivos nombrados con HMAC-SHA256 de la URL
  y una clave aleatoria por perfil en el almacén seguro: en disco no queda
  la URL, y sin la clave no se puede comprobar a qué URL corresponde un
  archivo (ni probar contraseñas candidatas). Solo se guardan los bytes de
  la imagen, 5 MB máximo cada una, 300 MB por perfil (se borran primero las
  menos usadas). Se borra con la clave al cerrar sesión. Sin llavero, se
  cargan de la red como antes. Validación y tope por escritura: ver §14.
- **Atajos de teclado:** un catálogo único (`ShortcutCatalog`) con los de
  cada pantalla; `?` o F1 muestran la ayuda (el `?` no se captura mientras se
  escribe en un campo). Sin botón visible, para no recargar los encabezados.
  Ctrl+F abre la búsqueda desde inicio, En vivo, Películas y Series.
- **Búsqueda global en el inicio** ("Explorar", junto a las tres secciones).
  En En vivo, Películas y Series solo está el filtro de la categoría
  elegida, con una etiqueta que la nombra ("Buscar en Favoritos"). Las flechas en los reproductores siguen la
  especificación: en vivo ↑/↓ canal y ←/→ volumen; en películas ←/→ ±10 s y
  ↑/↓ volumen.

## 14. Contenedor por sesión (revisión de la Fase 4)

La revisión encontró varios errores con la misma causa: operaciones de una
sesión que seguían vivas o leían "el perfil activo" después de cambiar de
perfil o cerrar sesión (el progreso de A escrito en B, valores de A
mostrados un instante en B, una descarga que recreaba la carpeta borrada,
la actualización del catálogo pidiendo datos tras cerrar sesión). En lugar
de parchear cada caso, el estado de la sesión tiene ahora **su propio
contenedor**.

- **`SessionScope`:** las rutas que necesitan sesión (inicio, En vivo y su
  reproductor, Películas, Series, fichas, búsqueda y reproductor de VOD)
  están bajo un `ShellRoute` envuelto en un `ProviderScope` nuevo por
  sesión (con clave por sesión). Todos los providers de la sesión declaran
  `dependencies` y dependen de `sessionContextProvider`, así que Riverpod
  los crea en ese contenedor. Al cambiar de perfil o cerrar sesión, el
  contenedor se destruye entero: se ejecutan todos sus `onDispose`
  (reproductor, temporizadores, cachés) y la sesión nueva empieza **sin
  ningún valor previo** (cargando, no con la lista del perfil anterior).
- **`SessionContext`** (perfil, credenciales, datos de la cuenta del login y
  `SessionLifetime`) es fijo durante la sesión. Los servicios que escriben
  (favoritos, progreso, catálogo, caché de imágenes) reciben el id del
  perfil **al crearse** y nunca vuelven a leer el perfil activo: una
  escritura que empezó en A termina en A. Si A se eliminó mientras tanto,
  la clave foránea la rechaza. Guardar la posición de A al salir por un
  cambio de perfil es correcto: es de A.
- **`SessionLifetime`:** se cierra al destruirse el contenedor. Lleva un
  `CancelToken` de Dio que usan todas las peticiones de la fuente (Xtream y
  M3U): al cerrarse, la petición en curso se corta y una nueva falla sin
  salir a la red. Las operaciones largas llaman a `ensureActive()` entre
  pasos (la actualización del catálogo, entre categorías y elementos).
- **Fuera de las sesiones** quedan solo: base de datos, almacén seguro, Dio,
  lista de perfiles, términos, la sesión activa (`sessionProvider`) y el
  registro de cachés de imágenes. La época de sesión se conserva solo para
  abrir un perfil desde el selector.
- **Diálogos:** los de la app no leen datos de sesión (usan el `ref` de la
  pantalla que los abre), así que no importa que se muestren en el
  navegador raíz.
- **Prueba de humo:** el flujo completo de la app recorre inicio, En vivo,
  Películas, Series y búsqueda dentro del contenedor real; un provider que
  olvide declarar sus dependencias se evalúa fuera de la sesión y la
  pantalla muestra un error, que la prueba detecta.

### Caché de imágenes

- **Solo se guardan imágenes válidas:** PNG, JPEG o WebP reconocidos por sus
  primeros bytes (no por la URL ni el `Content-Type`) **y** que el motor de
  Flutter decodifica (primer cuadro, a tamaño reducido). Una página HTML, un
  error del panel o cualquier otra cosa se muestra si se puede, pero nunca
  llega al disco. Un archivo inválido guardado por una versión anterior se
  descarta al leerlo.
- **Riesgo residual (metadatos):** no se reconstruyen los archivos para
  quitar metadatos (EXIF, XMP, ICC, comentarios). Es código binario delicado
  y el riesgo reproducido —guardar HTML u otro contenido que no es imagen—
  ya está cubierto. Un servidor podría incluir texto en los metadatos de
  una imagen válida y ese texto quedaría en disco, en la carpeta privada de
  la app, con nombre ilegible sin la clave, dentro del tope de 300 MB y
  borrado al cerrar sesión. Si en el futuro hiciera falta, la opción es
  volver a codificar la imagen decodificada (lo que descarta todo metadato)
  a costa de CPU y calidad.
- **Tope en cada escritura:** la caché lleva la cuenta de los bytes en
  disco (recontados al abrir) y las escrituras van de a una. Si la imagen
  nueva no entra, antes se borran las usadas hace más tiempo: los 300 MB se
  cumplen siempre, no solo tras una limpieza periódica.
- **Cierre:** `close()` rechaza cargas y escrituras nuevas, cancela las
  descargas y espera las operaciones en curso. Un registro por perfil, fuera
  de las sesiones, permite cerrarlas antes de borrar la carpeta, y también
  espera las inicializaciones pendientes (una lectura lenta del llavero no
  puede recrear la clave después de la limpieza).
- **Ids de perfil y restos:** la tabla `profiles` usa `AUTOINCREMENT`, así
  que dentro de una misma base un id eliminado **no se reutiliza**. Aun así,
  al crear un perfil se borran restos de caché y clave con su id, como
  protección adicional: el contador vive dentro de la base, pero la carpeta
  de imágenes y el llavero están fuera. Si la base se borra o se recrea (se
  borran los datos de la app a mano, una reinstalación que conserva el
  llavero, como pasa en macOS), los ids vuelven a empezar y un perfil nuevo
  heredaría las imágenes de otra cuenta. Si esos restos no se pueden
  borrar, el perfil no se crea.

### Orden del cierre de sesión

1. Cerrar la caché de imágenes del perfil (rechaza escrituras, cancela
   descargas, espera lo que estaba en curso).
2. Borrar credenciales y datos locales. Si falla, la caché se reabre, la
   sesión **sigue abierta** y se muestra el error para reintentar.
3. Terminar la sesión **que pidió el cierre** (se compara la instancia):
   si mientras tanto se cambió a otra cuenta, esa sigue abierta. Se
   destruye su contenedor.
4. Borrar la carpeta de imágenes y su clave, y **comprobar** que ya no
   existen. Si algo quedó, se avisa con el mensajero global de la app (la
   pantalla de inicio ya no existe): "Se cerró la sesión, pero no se
   pudieron borrar todas las imágenes guardadas de esta cuenta en el
   equipo." Nunca se informa éxito en ese caso. Lo mismo al eliminar una
   cuenta desde el selector (la tarjeta desaparece antes del aviso).

Los cierres y eliminaciones van **de a uno**: una segunda petición para el
mismo perfil reutiliza la que está en curso, una para otro perfil espera a
que termine, y un perfil que se está eliminando no se puede abrir.

La consulta HTTP de diagnóstico del reproductor de películas (el primer
byte, para distinguir un 404 de un fallo pasajero) usa un token enlazado al
del reproductor y al de la sesión: al cerrar cualquiera de los dos, la
conexión se corta en lugar de esperar la respuesta o el tiempo límite.

## 15. Inicio: barra superior, secciones y novedades

- **Barra superior:** logo, búsqueda global con forma de campo (abre la
  pantalla de búsqueda; Ctrl+F) y, a la derecha, usuario y fecha de
  vencimiento juntos (solo la fecha; en amarillo si faltan menos de 7 días,
  en rojo si venció o está bloqueada). Cambiar cuenta, cerrar sesión y
  actualizar los datos de la cuenta están en el menú del usuario. El resto
  de los datos de la cuenta ya no se muestra.
- **Secciones compactas** (En vivo, Películas, Series): icono a la
  izquierda, nombre y la cantidad del catálogo local ("1.240 canales").
  Nada arranca resaltado: el foco está en la pantalla y la primera flecha
  entra a los controles, que desde ahí muestran el foco como siempre.
- **Arreglo según "Seguir viendo":**
  - Sin nada a medio ver: secciones grandes arriba y, debajo, tres
    carruseles alineados con ellas (uno por columna): películas nuevas,
    series nuevas y "Mejor valoradas" (películas y series por puntaje del
    servidor, de los últimos 5 años si hay suficientes). En cada columna,
    la tarjeta del frente, el título de la sección y los datos quedan
    centrados; las de atrás asoman a la izquierda. Un clic en la tarjeta
    abre la ficha.
  - Con algo a medio ver: "Seguir viendo" ocupa el área principal y las
    novedades pasan a una columna compacta a la derecha.
  - Hasta saber cuál corresponde se muestran solo las secciones, y el cambio
    se anima con un fundido: no se ve un arreglo y enseguida el otro.
- **Novedades ("estrenos recién agregados"):** carruseles de tarjetas
  apiladas con las películas y series del año en curso, primero las que el
  servidor subió último (fecha de alta). Así no aparecen películas viejas
  subidas hace poco (esas están en "Recién agregadas"), y entre los
  estrenos se ve primero lo más fresco del servidor. Salen del
  catálogo local (año y orden del servidor) y los pósters se resuelven en
  memoria desde la lista de su categoría: no se guarda ninguna URL. El año
  sale del reloj (el 1 de enero pasa solo al nuevo). Si hay menos de 6 del
  año, se suman las del anterior ("Películas recientes"); si aun así
  faltan, o el panel no informa años, se completa con las de mejor puntaje
  ("Películas destacadas"). Los paneles no informan qué es lo más visto:
  el puntaje es lo más cercano. Sin nada que mostrar, ese carrusel no
  aparece. Muchos paneles no llenan el año: se toma del
  nombre si viene como "(2026)", "[2026]" o "- 2026" (un número suelto al
  final no cuenta: "Blade Runner 2049"). Al mostrarlo se limpia el nombre:
  sin el año ni etiquetas técnicas del final ("FHD", "4K", "Latino"…).
- **Carga:** resolver los pósters obliga a pedir la lista de cada categoría
  al servidor, lo que puede tardar al abrir la app; mientras tanto se ven
  tarjetas de muestra con un pulso suave en el mismo lugar.
- **Avance:** cada tarjeta queda 3 s al frente; una barra fina se llena
  mientras tanto y un contador indica la posición ("3 / 12"). Se detiene
  con el mouse encima o con el foco. Sin flechas: un clic en la barra salta
  a esa parte de la lista, un clic en una tarjeta de atrás la trae al
  frente, y ← / → y Enter funcionan con el teclado. El texto sobre el póster
  lleva un degradado fuerte para no mezclarse con el del propio póster.

### "Recién agregadas"

- Categoría fija en Películas y Series (junto a Favoritos): lo último que
  agregó el servidor, hasta 200. Sale de la lista completa en memoria
  ordenada por la fecha de alta que informa el panel (`added` en
  películas; en series, `last_modified`, que también cambia al sumar
  episodios). Sin fecha van al final; en listas M3U, que no la traen, se
  usa el orden inverso de la lista.
- La fecha también se guarda en el catálogo local (columna `added`,
  esquema v5; no es un dato sensible) y ordena los carruseles dentro de
  cada año. La migración borra la marca de actualización del catálogo para
  que se descargue de nuevo, ya con fechas, al abrir la sesión.

### Anuncio del desarrollador

- Excepción a la neutralidad (CLAUDE.md §8) pedida y aprobada por el dueño
  del proyecto, a sabiendas de sus riesgos: la app deja de ser un
  reproductor 100 % neutral, y el número de WhatsApp queda en el
  repositorio público.
- Banner verde en el inicio, debajo de las novedades (o de "Seguir
  viendo"): "¿Buscas un servicio de IPTV?" / "Fútbol nacional e
  internacional, últimas películas y series del año." y el botón
  "Escríbenos", que abre `wa.me` con el mensaje ya escrito ("vi el anuncio
  en EvemTv"). Así se sabe qué contactos llegaron por la app sin rastrear a
  nadie: la app no envía nada por su cuenta.
- En el inicio (barra superior, junto al usuario) y en el encabezado de
  En vivo, Películas y Series (junto al filtro) es un botón chico con
  borde verde ("¿Buscas IPTV? +591 33217668"; en ventanas angostas,
  solo el número): siempre visible, sin ✕ y sin ocupar espacio del
  contenido. En el selector de cuentas y el login va el banner completo,
  sobre la firma. El número (`AppConfig.promoPhone`) está siempre a la
  vista, para quien ve la pantalla y quiere anotarlo; un test comprueba que
  coincide con el del enlace.
- En el banner completo, ✕ lo cierra solo hasta que se vuelve a abrir la
  app: no se guarda en ningún lado, así el anuncio aparece en cada
  apertura y quien no quiera verlo lo cierra cada vez. Si el enlace no se
  puede abrir, se avisa.
- El enlace se abre con `url_launcher` (paquete oficial de Flutter,
  mantenido; verificado en pub.dev: 6.3.2).

### Fichas: fondo y recomendaciones

- La imagen de fondo de la ficha se ve más (60 %), con un degradado que
  oscurece la izquierda (texto) y el pie (recomendaciones) para leer bien.
- **"Más de <categoría>"** al pie de las fichas de películas y series: de
  su misma categoría (lista ya en memoria, sin peticiones nuevas), primero
  las que comparten palabras del título (sagas y secuelas), luego las de
  año cercano y mejor puntaje. Los paneles no informan géneros en las
  listas: comparar por género exigiría pedir la ficha de cada candidata al
  servidor, así que se usa la categoría, que en la mayoría de los paneles
  ya agrupa por género.

## 16. Tamaños de ventana y recursos

### Tamaños de ventana

- **Mínimo de la ventana: 800×450** (antes 960×600). Con el escalado de
  Windows, una pantalla de 1366×768 al 150 % ofrece 911×512 lógicos; con
  la barra de tareas y el título, la ventana maximizada queda cerca de
  911×450. El mínimo anterior no entraba.
- **Barrido fijo** (`test/responsive_sweep_test.dart`): 800×450, 911×512
  (1366×768 al 150 %), 1093×614 (1366×768 al 125 %), 1280×720 (1920×1080 al
  150 %), 1366×768, 1920×1080, 2560×1440 y 3840×2160. En cada tamaño
  recorre selector de cuentas (vacío y con cuentas), login, inicio (con y
  sin "Seguir viendo"), En vivo, Películas, Series, búsqueda y las fichas,
  y falla si algo desborda.
- Ajustes: la barra del inicio y los encabezados achican márgenes, filtro y
  buscador (en muy poco ancho, solo la lupa); las tarjetas de sección pasan
  a un formato compacto; las celdas de pósters le dan al póster lo que deja
  el texto; en En vivo, "Pantalla completa" queda como icono en paneles
  angostos; el selector de cuentas se desplaza en ventanas bajas.

### Recursos

- **Sin redibujado continuo en el inicio.** Los carruseles avanzan con un
  temporizador (no con una animación): entre un avance y otro no se dibuja
  nada, salvo la transición de 420 ms. La barra de avance es estática (la
  posición en la lista). Se detienen con la ventana inactiva (sin foco) o
  minimizada, con otra pantalla encima, y con el mouse o el foco encima.
  Las barras de "Seguir viendo" son estáticas.
- **"Recién agregadas"** consulta a la base local solo las últimas 50 (por
  fecha de alta) en vez de descargar la lista completa; el póster de cada
  celda se busca solo cuando la celda se ve.
- **Listas de categorías en memoria: solo las últimas 10 usadas**
  (canales, películas y series; `CategoryListCache`). Las demás se liberan
  y, si se vuelven a abrir, se piden otra vez al servidor. Una lista que se
  está mostrando no se pierde: se libera cuando deja de verse.
- **Medición** (modo perfil, servidor ficticio local con 2.000 canales,
  24.000 películas y 8.000 series; ver `integration_test/README.md`):

  | Momento | CPU antes | CPU después | Memoria antes | Memoria después |
  |---|---|---|---|---|
  | Inicio en reposo | 75,8 % (60 cuadros/s) | 30,1 % (19 cuadros/s) | 305 MB | 305 MB |
  | Inicio minimizado | 75,9 % (60 cuadros/s) | 0,0 % (0 cuadros/s) | 304 MB | 305 MB |
  | Catálogo grande (todas, desplazamiento, 12 categorías, recién agregadas) | 61,3 % | 61,7 % | 347 MB | 347 MB |
  | Sesión larga (60 categorías) | 65,1 % | 58,9 % | 402 MB | 382 MB |
  | Reproducción 720p | 34,8 % | 29,7 % | 432 MB | 424 MB |

  CPU en % de un núcleo (Ryzen 7 3700U, Linux, Wayland). Las diferencias de
  ±5 puntos en reproducción son variación entre corridas. En reposo, el
  30 % restante son las transiciones de los tres carruseles (una cada 3 s).
  El "inicio tras navegar" medido por el conductor queda en 0 % porque la
  ventana vuelve sin foco (GNOME no deja que un programa se la dé) y los
  carruseles se pausan, como se pidió.

### Decodificación por hardware (mpv)

- `hwdec=auto-safe` (ver `createVideoController`): mpv usa solo los
  decodificadores por hardware que considera estables (VA-API en Linux,
  D3D11VA en Windows, VideoToolbox en macOS) y, si no hay, sigue por
  software. Comprobado en Linux leyendo `hwdec-current` durante la
  reproducción (servidor ficticio, Ryzen 7 3700U / Radeon Vega, Wayland):

  | Video | `hwdec-current` | CPU (1 núcleo) |
  |---|---|---|
  | 720p H.264 | `vaapi` | 30–31 % |
  | 1080p H.264 | `vaapi` | 30–37 % |
  | 1080p HEVC | `vaapi` | 31–37 % |

  La CPU que queda es la de la app (interfaz, copia al lienzo de Flutter,
  red, audio), no la decodificación. En Windows y macOS falta comprobarlo
  en equipos reales (checklist de la Fase 5).
- **Memoria tras cerrar el reproductor (Linux): resuelta con mimalloc.**
  - Síntoma: cada película abierta y cerrada dejaba memoria tomada; con 20
    aperturas de un 1080p la app pasó de 496 a 631 MB y seguía subiendo.
  - Descartado: la referencia de diagnóstico al último reproductor
    (`MediaKitEngine.current`) ahora es débil; y `dispose` del Player (que
    libera también el VideoController y su textura) se llama en todos los
    caminos: volver/Esc y error (al cerrar la pantalla), cierre antes de
    terminar de crearse, y cambio de sesión (se destruye el contenedor).
  - Aislado con `test_driver/leak_bench.dart` (15 ciclos cada variante):
    crece incluso **solo con el Player, sin textura** (8,4 MB por ciclo);
    con la textura, 8,6 MB; decodificando por software, 31 MB. `malloc_trim`
    devolvía buena parte: es el asignador de glibc reteniendo y
    fragmentando la memoria de mpv/FFmpeg, no la textura ni nuestro
    código. Es el problema conocido de media_kit en Linux
    (media-kit/media-kit#68); su corrección recomendada es enlazar
    **mimalloc**, que media_kit_libs_linux ya compila. La corrección de
    fugas posterior a 1.2.6 (media-kit/media-kit#1446, sin publicar) es de
    pocos bytes por llamada y no explica esto.
  - Con mimalloc (`linux/CMakeLists.txt`): banco aislado 0,5–1,4 MB por
    ciclo y estable; app completa, 20 aperturas: 390 → 394 MB. Tras cerrar
    el reproductor la memoria vuelve a bajar (434 → 391 MB).
  - Aviso: el autor de media_kit comentó (07/2026) que mimalloc provocaba un
    cierre inesperado con Flutter 3.44.0. Con Flutter 3.47.5 no se reprodujo
    (compilaciones de depuración, perfil y release, y todas las pruebas de
    reproducción). Si al actualizar Flutter apareciera, quitar la línea de
    `linux/CMakeLists.txt` y, como mitigación, reutilizar un único
    reproductor en lugar de crear uno por película.
  - Seguimiento en CI: `integration_test/player_memory_test.dart` abre y
    cierra 20 veces un 720p en Linux, Windows y macOS y publica la memoria
    tras cada cierre; falla si los últimos 10 ciclos crecen más de 6 MB por
    ciclo (con glibc midió 9,0; con mimalloc, 0,6).
    Mediciones en CI: Linux (software, sin GPU) 1,6–3,7 MB por ciclo;
    Windows estable (baja al final); macOS, solo el Player, 0,4.
  - **macOS en CI, causa confirmada:** con la textura, la app se cierra al
    abrir el video. El registro del sistema (que el workflow ahora guarda y
    resume si el paso falla) muestra `media_kit_video/OpenGLHelpers.swift:25:
    Fatal error: Unexpectedly found nil while unwrapping an Optional value`.
    Esa línea pide a macOS un formato OpenGL **acelerado por hardware**
    (`kCGLPFAAccelerated`) y fuerza el resultado (`pixelFormat!`): la VM del
    runner no tiene ese renderizador, macOS devuelve nulo y la app se cae.
    No es un fallo de nuestro código ni una fuga. En un Mac real con GPU
    existe ese formato; pero **cualquier Mac sin OpenGL acelerado** (otras
    máquinas virtuales, algunos escritorios remotos) sufriría el mismo
    cierre. Mitigación posible: reportarlo a media_kit y proponer que, si
    falla, reintente sin `kCGLPFAAccelerated` (renderizador por software) en
    vez de cerrar la app; mientras tanto, la prueba obligatoria en un Mac
    real queda en el checklist de la Fase 5. (No quedó informe `.ips`: el
    motivo sale del registro del sistema.)
  - **Riesgo conocido (aceptado por ahora):** en un Mac sin OpenGL
    acelerado por hardware, abrir un video cierra la app. Texto del issue
    para media_kit en `docs/issue_media_kit_opengl.md` (lo publica el dueño
    del proyecto).

## 17. Carpeta de datos y ediciones — DESCARTADA

> **Descartada (09/2026):** EvemTv es una sola app libre, sin ediciones ni
> restricciones. Se conserva el análisis como referencia por si se retoma.
> Sigue vigente solo la primera viñeta (compañía "EvemTv" en Windows).

- **Windows:** la compañía del ejecutable (`CompanyName` en
  `windows/runner/Runner.rc`) vuelve a ser **EvemTv**. En Windows la carpeta
  de datos es `%APPDATA%\<compañía>\<producto>`: al poner "Godebol" había
  pasado a `Godebol\EvemTv`, y cambiarla después de publicar haría perder
  las cuentas guardadas al actualizar. La firma "Desarrollado por Godebol"
  sigue en la app y en el copyright (que no cambia la carpeta).
- **(Descartado) Ediciones: cada edición, su carpeta de datos y su llavero.**
  Si en un mismo equipo están instaladas la edición libre y la de Godebol,
  no deben compartir base de datos, caché de imágenes ni credenciales.
  Ejemplo de nombres: `EvemTv\EvemTv` (libre) y `EvemTv\EvemTv-Godebol`.
  Qué determina cada cosa hoy (comprobado en las fuentes de los paquetes):

  | Plataforma | Carpeta de datos | Llavero |
  |---|---|---|
  | Windows | `%APPDATA%\CompanyName\ProductName` (Runner.rc) | archivo cifrado en esa carpeta + clave en el Administrador de credenciales con nombre `key_<BINARY_NAME>_…` (o `STORAGE_PREFIX` de CMake) |
  | macOS | contenedor del bundle id (`PRODUCT_BUNDLE_IDENTIFIER`) | Keychain con servicio `flutter_secure_storage_service` por defecto: **igual en todas las apps** |
  | Linux | `~/.local/share/<APPLICATION_ID>` | libsecret con etiqueta y cuenta derivadas de `APPLICATION_ID` |

  Por lo tanto, cada edición necesita: `ProductName` propio en Windows y un
  `BINARY_NAME` o `STORAGE_PREFIX` propio (si no, comparten la clave del
  Administrador de credenciales); bundle id propio **y** `accountName`
  propio en `MacOsOptions` en macOS; y `APPLICATION_ID` propio en Linux.
  Las claves internas (`profile.<id>.credentials`, `…image_cache_key`)
  pueden seguir igual porque quedan dentro del espacio de cada edición.
  Hay que probarlo con las dos ediciones instaladas a la vez en cada
  plataforma: una no debe ver ni borrar las cuentas de la otra.

## 18. Conteo de uso anónimo (Fase 4.5)

Reemplaza la regla "sin telemetría" **solo** para este conteo mínimo
(CLAUDE.md §5.4). La app sigue funcionando con cualquier servicio: no hay
restricciones ni el conteo condiciona nada.

- **Qué se envía:** `POST https://godebol.com/api/evemtv/ping` con JSON de
  a lo sumo tres campos (el servidor rechaza con 400 cualquier otro):
  - `install_id`: UUID v4 creado en la primera ejecución, guardado en las
    preferencias locales (por instalación, no por perfil; no es secreto).
  - `os`: `windows`, `macos` o `linux`.
  - `account_hash`: SHA-256 (hex en minúsculas) de
    `"usuario_en_minúsculas|host"` de la cuenta abierta, con el host en
    minúsculas y sin esquema ni puerto (p. ej. `demo|panel.example.com`).
    Sin cuenta abierta, o si la cuenta no tiene usuario (una lista M3U sin
    `username`), el campo se omite.
  - Nunca el usuario, la contraseña ni la URL. Un test comprueba el cuerpo.
- **Cuándo:** una vez por día (UTC), y solo después de aceptar los
  términos, que lo informan (versión 2 de los términos: quien ya los
  aceptó los vuelve a ver). Al abrir una cuenta se envía con su huella; si
  en 60 s desde que se abre la app no se abre ninguna, se envía sin huella.
  Si el del día salió sin huella y después se abre una cuenta, se envía
  **uno más** ese día, con ella (como máximo dos por día; ninguna otra
  cuenta ni reapertura lo repite). Los envíos van en fila, así el de la
  cuenta no se pierde si el de "app abierta" todavía está en curso.
- **Si falla** (sin internet, 4xx, 5xx, 429): se ignora, sin reintentos en
  esa ejecución; se vuelve a intentar en la próxima apertura o al día
  siguiente. Nunca afecta el uso de la app.
- **Solo release** envía a godebol.com. En depuración, perfil y tests está
  desactivado, salvo que se pase
  `--dart-define=USAGE_PING_URL=http://127.0.0.1:18080/…`.
- **Logs:** solo el evento (`usage.ping` enviado/fallido y el código HTTP o
  el tipo de error), nunca el hash ni el id.
- **Alcance de la privacidad (dicho con precisión):** el hash no permite
  leer el usuario, pero **no es anónimo en sentido estricto**: es el mismo
  para la misma cuenta en cualquier equipo y, como los nombres de usuario y
  los hosts se pueden adivinar, quien conozca una cuenta y su servidor
  puede comprobar si esa cuenta usa la app. Por eso los términos lo
  describen como "una huella de la cuenta calculada a partir de tu usuario
  y del servidor", sin llamarlo anónimo.


## 19. Instaladores, release y aviso de actualización (Fase 5)

**Versión:** 1.0.0. Vive en `pubspec.yaml` y en `AppConfig.version`; un test
comprueba que coincidan y el workflow de release rechaza un tag que no sea
`v` + la versión de `pubspec.yaml`.

### Workflow de release (`.github/workflows/release.yml`)

- **Con tag `vX.Y.Z`:** comprueba la versión y que el paquete de
  certificados de Mozilla sea el vigente (primer paso; si no, no publica),
  corre análisis y tests, arma y prueba los instaladores de las tres
  plataformas, calcula `SHA256SUMS.txt` y crea el release. Solo el paso de
  publicación tiene permiso de escritura (`GITHUB_TOKEN`); no hay secretos.
- **Sin tag** (cambios en `packaging/` o a mano desde Actions): igual pero
  sin publicar; los instaladores quedan como artefactos 7 días para
  probarlos antes del tag.
- **Runners fijos** (nunca `*-latest`, para que la imagen no cambie sin
  aviso): `ubuntu-24.04`, `windows-2025` y `macos-26` en los dos
  workflows, y `ubuntu-22.04` para el AppImage. Cambiarlos es una decisión
  explícita: se prueba en una rama y se anota aquí.
- **Pruebas de humo:** Windows instala en silencio, abre la app 20 s y
  desinstala; macOS monta el `.dmg`, verifica la firma y abre la app 20 s;
  Linux abre el AppImage 20 s. En ninguna se reproduce video (en la VM de
  macOS no se puede, §16): la reproducción con los instaladores se prueba a
  mano (docs/fase5_checklist.md).

### Windows

- **Inno Setup** (§3), **por usuario** (`PrivilegesRequired=lowest`, sin
  UAC; se puede elegir "para todos"). `AppId` fijo: las versiones nuevas se
  instalan encima. Al desinstalar se conservan cuentas y ajustes.
- **Runtime de Visual C++** (`msvcp140`, `vcruntime140`, `vcruntime140_1`)
  copiado junto al `.exe` (despliegue local de la app): abre aunque el
  equipo no tenga el redistribuible.
- **Portable `.zip`:** la misma carpeta. Los datos siguen en
  `%APPDATA%\EvemTv\EvemTv` y las contraseñas en el Administrador de
  credenciales: "portable" es el programa, no los datos.

### macOS

- `.dmg` con firma **ad hoc** (sin cuenta de Apple) y acceso directo a
  Aplicaciones. El usuario la habilita una vez con *Abrir igualmente*
  (docs/instalacion.md).
- **Keychain con el `.app` de release firmado:** el workflow compila en
  release, con los mismos entitlements y firma ad hoc que la app publicada,
  un punto de entrada de prueba (`test_driver/keychain_release_check.dart`)
  que escribe, lee y borra un valor ficticio con el mismo
  `secureStorageProvider`. La prueba de integración de depuración sigue en
  el workflow de compilación.
- Con firma ad hoc, la "identidad" de la app cambia en cada versión: macOS
  puede volver a pedir permiso para el llavero tras actualizar (documentado
  para el usuario). Se resuelve con un certificado de Developer ID.

### Linux: AppImage con libmpv incluido

- Se compila en **Ubuntu 22.04** (glibc 2.35): funciona en Ubuntu 22.04,
  Debian 12, Fedora 36 o posteriores. El libmpv de 22.04 es más viejo
  (0.34) que el del workflow de compilación: el job de release corre con él
  la prueba de reproducción y TLS antes de empaquetar.
- `packaging/linux/crear_appimage.sh` copia la compilación release y usa
  **linuxdeploy** (`--deploy-deps-only`) para incluir libmpv, ffmpeg y sus
  dependencias. Herramientas (linuxdeploy, appimagetool y el runtime de
  AppImage) en versiones fijas, verificadas por SHA-256.
- **Se toman del sistema** (`packaging/linux/excluir.txt`): GTK/GLib (la app
  usa el GTK del escritorio), X11/Wayland/GL/Vulkan (deben coincidir con los
  controladores), **libva** (un libva viejo no reconoce controladores nuevos:
  se perdería la decodificación por hardware) y PipeWire. **Se incluyen**
  VDPAU, OpenCL, libpulse, las extensiones de X y **libjack** (que la lista
  por defecto de AppImage excluye, pero sin ella libmpv no carga y muchos
  escritorios no la traen). El script falla si a libmpv le falta algo que no
  esté incluido ni tomado del sistema a propósito.
- `AppRun` fija `LIBMPV_LIBRARY_PATH` a la copia incluida: media_kit abre
  libmpv por nombre desde Dart y, si no, podría cargar otra del sistema.
- **Certificados:** el GnuTLS incluido busca los certificados en la ruta de
  Debian (en Fedora u openSUSE no los encontraría); dentro del AppImage
  (variable `APPIMAGE`) mpv usa `cacert.pem`, como en Windows y macOS.
- El script falla si el ejecutable no enlaza **mimalloc** (§16).
- `libdartjni.so` (de `path_provider_android`) pide `libjvm`, pero en Linux
  nunca se carga: no se incluye Java.
- Medido en Ubuntu 24.04: ~96 MB.

### Aviso de actualización

- `GET https://godebol.com/api/evemtv/version` →
  `{ "ultima_version", "descarga", "minima" }`. Sin datos de la cuenta ni
  de la instalación (solo el User-Agent `EvemTv/x.y.z`). Primera consulta a
  los 3 s de abrir la app y luego cada 12 h. Si falla, se ignora.
- **Versión nueva:** tarjeta abajo a la derecha con **Descargar** y ✕
  (cerrada hasta la próxima apertura, o hasta que aparezca otra versión).
- **Instalada < `minima`:** primero, **3 días de plazo** desde la primera
  vez que se detectó: la tarjeta pasa a "Actualización obligatoria" con
  *"Debes actualizar antes del dd/mm/aaaa"* y se puede cerrar (vuelve en la
  próxima apertura). La fecha de primera detección se guarda en las
  preferencias locales **por versión mínima**
  (`update_minimum_seen = "2.0.0|<fecha UTC>"`): si `minima` cambia, el
  plazo empieza de nuevo. Una fecha guardada "en el futuro" (reloj
  cambiado) no alarga el plazo.
- **Plazo vencido:** pantalla de bloqueo que tapa la app, sin cerrar ni
  teclado ni mouse para lo de abajo, con **Descargar**, instrucciones de
  instalación del sistema (SmartScreen, *Abrir igualmente*, permiso de
  ejecución del AppImage) y un **enlace visible a la guía**
  (`docs/instalacion.md` en GitHub). Si había un video en curso, se sale
  del reproductor. Si el plazo vence con la app abierta, se bloquea en ese
  momento.
- **Nunca se bloquea por no poder consultar:** el bloqueo solo aparece tras
  una respuesta válida del servidor en esa ejecución. Sin internet, con el
  servidor caído (4xx/5xx) o con una respuesta rara, la app funciona
  normal, aunque el plazo guardado ya haya vencido.
- **Solo se abren enlaces** `https://` de `github.com/Elmarcinho/…` o
  `godebol.com` (sin usuario, contraseña ni puerto raro). Otro enlace se
  reemplaza por la página de releases del repositorio. Se vuelve a
  comprobar justo antes de abrirlo.
- **Solo release** consulta godebol.com; en depuración está desactivado
  salvo `--dart-define=UPDATE_CHECK_URL=http://127.0.0.1:18080/…`.
- Versiones comparadas por número (`1.10.0 > 1.9.0`); tolera `v1.2`,
  `1.2.3+4` y campos raros sin romper nada.
- Los términos (versión 3) lo mencionan. Todavía no hay pantalla de Ajustes:
  el interruptor para desactivar el aviso normal queda pendiente para
  cuando exista (el de la versión mínima no se podrá desactivar).
