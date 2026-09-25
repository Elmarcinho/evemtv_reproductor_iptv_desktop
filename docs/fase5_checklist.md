# Checklist de la Fase 5 (empaquetado y releases)

Pendientes acordados para la Fase 5. Cada release debe repasar la sección
**"Antes de cada release"**.

## Antes de cada release

- [ ] **Actualizar el paquete de certificados raíz de Mozilla**
      (`assets/certs/cacert.pem`), que usa mpv para verificar HTTPS en
      Windows y macOS. Un paquete viejo puede rechazar servidores válidos o
      seguir confiando en autoridades retiradas:

      ```bash
      curl -o assets/certs/cacert.pem https://curl.se/ca/cacert.pem
      curl -s https://curl.se/ca/cacert.pem.sha256   # debe coincidir con:
      sha256sum assets/certs/cacert.pem
      ```

      Anotar la fecha de los datos de Mozilla (encabezado del archivo) en
      `docs/decisiones.md`, sección 12.
- [ ] Workflow en verde en Linux, Windows y macOS, incluidas las pruebas de
      integración (almacén seguro real, TLS de mpv, temporales).
- [ ] Revisar que el diff del release no contenga credenciales, URLs de
      paneles ni datos reales (el repositorio es público).
- [ ] Actualizar `version` en `pubspec.yaml` y `AppConfig.version`.

## Pendientes de la Fase 5

- [ ] Windows: instalador con Inno Setup y versión portable `.zip`.
- [ ] macOS: `.dmg` con firma ad-hoc y guía en `docs/` para habilitar la app
      en *Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente*.
- [ ] Probar el Keychain con el `.app` **release** firmado (hoy la prueba de
      CI usa la compilación de depuración; observación de la revisión de la
      Fase 1).
- [ ] Linux: AppImage. Decidir si incluye libmpv (y, en ese caso, si ese
      libmpv encuentra los certificados del sistema o necesita
      `cacert.pem`, como Windows y macOS). Incluir el archivo `.desktop` y
      el ícono (en Wayland el panel lo toma de ahí).
- [ ] GitHub Actions: empaquetar las tres plataformas y publicar en
      GitHub Releases.
- [ ] Aviso de actualización dentro de la app (consulta de la última
      versión publicada, desactivable en Ajustes).
