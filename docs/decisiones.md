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
  errores remotos.
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
  Toda operación asíncrona que depende de la sesión (abrir un perfil,
  actualizar los datos de la cuenta y, en adelante, catálogo y EPG) toma un
  `SessionToken` al empezar y descarta su resultado si la época cambió. Un
  solo mecanismo en lugar de parches por pantalla.
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

