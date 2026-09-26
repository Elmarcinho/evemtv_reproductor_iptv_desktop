# Checklist de la Fase 5 (empaquetado y releases)

Pendientes acordados para la Fase 5. Cada release debe repasar la sección
**"Antes de cada release"**.

## Antes de cada release

- [ ] **Primer paso: actualizar el paquete de certificados raíz de Mozilla**
      (`assets/certs/cacert.pem`), que usa mpv para verificar HTTPS en
      Windows, macOS y el AppImage. Un paquete viejo puede rechazar
      servidores válidos o seguir confiando en autoridades retiradas:

      ```bash
      tool/actualizar_certificados.sh   # descarga, verifica el SHA-256 y reemplaza
      ```

      Anotar la fecha de los datos de Mozilla que imprime en
      `docs/decisiones.md`, sección 12, y hacer commit. El workflow de
      release lo vuelve a comprobar y **no publica** si no está al día.
- [ ] Workflow en verde en Linux, Windows y macOS, incluidas las pruebas de
      integración (almacén seguro real, TLS de mpv, temporales).
- [ ] Revisar que el diff del release no contenga credenciales, URLs de
      paneles ni datos reales (el repositorio es público).
- [ ] Actualizar `version` en `pubspec.yaml` y `AppConfig.version` (un test
      comprueba que coincidan; el tag debe ser `v` + esa versión).
- [ ] Probar los instaladores del último run **sin tag** del workflow
      "Release" (artefactos `windows`, `macos`, `linux`), con reproducción
      real de un canal y una película en cada sistema.
- [ ] Recién entonces, crear y subir el tag (`git tag v1.0.0 && git push
      origin v1.0.0`): el workflow publica el release.
- [ ] Publicar en `godebol.com/api/evemtv/version` la nueva
      `ultima_version` y el enlace de `descarga` (de `github.com/Elmarcinho`
      o `godebol.com`; otro se ignora). Subir `minima` solo si la versión
      anterior deja de funcionar: quien la tenga ve 3 días de aviso y
      después la app se bloquea hasta actualizar.
- [ ] **Obligatorio: probar en un Mac real** abrir y cerrar varias
      películas y varios canales seguidos (al menos 10 de cada uno, con
      pantalla completa y volviendo al catálogo), sin cierres inesperados ni
      pantallas negras, y con la memoria estable (Monitor de Actividad). No
      se publica sin esta prueba: en el runner de macOS de CI la textura de
      video no funciona (sin OpenGL acelerado la app se cierra en
      media_kit_video; docs/decisiones.md §16).
- [ ] **Probar los reproductores a mano con escalado de pantalla 125 % y
      150 %** (Windows: *Configuración → Pantalla → Escala*; macOS:
      *Pantallas → resolución "Más espacio/Texto más grande"*; GNOME:
      *Pantallas → Escala*). El barrido automático de tamaños
      (`test/responsive_sweep_test.dart`) no cubre los reproductores
      (necesitan mpv). En cada escala, con una película y un canal en vivo:
      - reproductor en ventana y en pantalla completa (F / doble clic / Esc);
      - barra de controles completa y legible: tiempo, volumen, pistas de
        audio y subtítulos, botón de volver;
      - menús de pistas y lista de canales sin cortes ni textos encimados;
      - mini reproductor de En vivo y paso a pantalla grande;
      - al menos una vez en la ventana mínima (800×450) y maximizada en
        1366×768 al 150 % (911×512 lógicos).
      - **en un Mac real**: abrir y cerrar varias películas seguidas (en el
        runner de macOS de CI la app se detiene al abrir un video con
        textura; hay que descartar que pase en equipos reales).
- [ ] **Comprobar la decodificación por hardware en Windows y macOS**
      (en Linux ya se comprobó: `vaapi`). Leer `hwdec-current` durante una
      reproducción 1080p H.264 y HEVC (`MediaKitEngine.hwdecCurrent()`, que
      expone `test_driver/perf_app.dart` como `requestData('hwdec')`; el
      conductor actual mide CPU solo en Linux, para Windows y macOS hay que
      quitarle esa parte). Se espera `d3d11va` en Windows y `videotoolbox`
      en macOS; `no` significa decodificación por software.

## Pendientes de la Fase 5

- [x] Windows: instalador con Inno Setup y versión portable `.zip`
      (`packaging/windows/evemtv.iss`; runtime de Visual C++ incluido).
- [x] macOS: `.dmg` con firma ad-hoc (`packaging/macos/crear_dmg.sh`) y guía
      en `docs/instalacion.md` (*Abrir igualmente*).
- [x] Probar el Keychain con el `.app` **release** firmado: paso
      "Keychain con el .app de release firmado" del workflow de release.
- [x] Linux: AppImage con libmpv incluido, `.desktop` e ícono
      (`packaging/linux/crear_appimage.sh`, decisiones §19). El script
      falla si falta mimalloc. Usa `cacert.pem` (su GnuTLS no encuentra los
      certificados fuera de Debian/Ubuntu).
- [x] GitHub Actions: empaquetar las tres plataformas y publicar en
      GitHub Releases con `SHA256SUMS.txt` (`.github/workflows/release.yml`).
- [x] Aviso de actualización dentro de la app (`godebol.com/api/evemtv/version`).
      Bajo `minima`: 3 días de plazo con aviso cerrable y después bloqueo
      con descarga, instrucciones y guía; nunca bloquea sin respuesta del
      servidor (decisiones §19).
- [ ] Interruptor para desactivar el aviso normal en Ajustes (cuando exista
      la pantalla de Ajustes; el obligatorio no se desactiva).
- [ ] Probar a mano el AppImage en una distribución que no sea Ubuntu
      (Fedora o similar): reproducir un canal HTTPS.
