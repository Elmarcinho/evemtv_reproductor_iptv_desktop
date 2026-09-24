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

## 5. Logs y errores

- **Primera barrera:** no registrar nunca cuerpos de respuesta, JSON crudo ni
  excepciones completas del servidor. Los errores de red se convierten a
  `AppFailure` antes de registrarse.
- **Segunda barrera:** `Redactor` enmascara credenciales en todo lo que llega
  al logger. Primero reemplaza los secretos conocidos, luego decodifica
  (`%xx`, `\/`, `\uXXXX`) y al final aplica los patrones (rutas Xtream, pares
  clave/valor en query, formularios, JSON y `usuario:clave@host`).
- Los secretos de menos de 3 caracteres se enmascaran solo como palabra
  completa: reemplazar cada aparición de una contraseña `"1"` destruiría el
  log. Dentro de una URL igual quedan cubiertos por los patrones.
- `AppFailure.message` es siempre un texto fijo en español. El detalle
  técnico va en `detail` (armado por nuestro código) y solo al logger.
- La pantalla roja de error de Flutter se reemplaza por un texto fijo, también
  en debug.
- En release solo se registran advertencias y errores, sin stack traces, y de
  los errores que no son `AppFailure` solo se registra el tipo.

## 6. Motor de video con inicialización diferida

`MediaKit.ensureInitialized()` lanza una excepción si falta libmpv. No se
llama en `main()`, sino al primer intento de reproducir (`MediaEngine`), para
que login, perfiles y catálogo funcionen aunque el reproductor no esté
disponible. En ese caso se muestra un error claro al reproducir.
