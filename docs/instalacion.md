# Cómo instalar EvemTv

EvemTv es un reproductor: **no trae listas, canales ni contenido**. Para usarlo
necesitas tu propio servicio IPTV (usuario, contraseña y URL del servidor, o
una lista M3U).

Descarga el archivo de tu sistema desde la página de
[versiones publicadas](https://github.com/Elmarcinho/evemtv_reproductor_iptv_desktop/releases/latest):

| Sistema | Archivo |
|---|---|
| Windows 10 u 11 (64 bits) | `EvemTv-X.Y.Z-windows-x64-instalador.exe` (recomendado) o `EvemTv-X.Y.Z-windows-x64-portable.zip` |
| macOS 12 o posterior (Apple Silicon e Intel) | `EvemTv-X.Y.Z-macos.dmg` |
| Linux de 64 bits (Ubuntu 22.04, Debian 12, Fedora 36 o posteriores) | `EvemTv-X.Y.Z-linux-x86_64.AppImage` |

La app todavía no está firmada con un certificado de pago de Microsoft ni de
Apple. Por eso Windows y macOS muestran un aviso la primera vez. Abajo se
explica cómo abrirla igualmente.

---

## Windows

### Con el instalador

1. Abre `EvemTv-X.Y.Z-windows-x64-instalador.exe`.
2. Si el navegador avisa que el archivo "no se descarga habitualmente", elige
   **Conservar** (en Edge: menú **⋯** del archivo → **Conservar** → **Conservar
   de todas formas**).
3. **Aviso de SmartScreen** ("Windows protegió su PC"):
   1. Haz clic en **Más información**.
   2. Comprueba que diga *Aplicación: EvemTv-X.Y.Z-windows-x64-instalador.exe*.
   3. Haz clic en **Ejecutar de todas formas**.
4. Sigue los pasos del instalador. No pide permisos de administrador: se
   instala solo para tu usuario, salvo que elijas "para todos los usuarios".
5. Abre EvemTv desde el menú Inicio o desde el acceso directo del escritorio.

### Versión portable (.zip)

1. Haz clic derecho en el `.zip` → **Extraer todo…**. No la abras desde
   dentro del `.zip`: tiene que estar descomprimida completa.
2. Entra en la carpeta `EvemTv` y abre `evemtv.exe`. Si aparece SmartScreen,
   sigue el paso 3 de arriba.

Las cuentas y ajustes se guardan en tu usuario de Windows (no en la carpeta
de la versión portable). Las contraseñas quedan en el Administrador de
credenciales de Windows.

### Actualizar y desinstalar

- **Actualizar:** cuando haya una versión nueva, la app muestra un aviso con
  el botón **Descargar**. Instala la nueva encima de la anterior: tus cuentas
  se conservan.
- **Desinstalar:** *Configuración → Aplicaciones → Aplicaciones instaladas →
  EvemTv → Desinstalar*. Para borrar también tus cuentas guardadas, antes de
  desinstalar cierra la sesión de cada cuenta dentro de la app.

---

## macOS

### Instalar

1. Abre `EvemTv-X.Y.Z-macos.dmg`.
2. Arrastra **EvemTv** a la carpeta **Aplicaciones** (el acceso directo que
   aparece en la misma ventana).
3. Expulsa el disco "EvemTv" (botón ⏏ en el Finder).

### Abrir por primera vez ("Abrir igualmente")

La primera vez, macOS muestra un mensaje como *"No se abrió 'EvemTv'"* o
*"Apple no pudo verificar que 'EvemTv' esté libre de malware"*. Es normal en
apps sin certificado de Apple de pago. Para habilitarla, una sola vez:

1. En el mensaje, haz clic en **OK** o **Listo** (no en "Mover a la
   papelera").
2. Abre **Ajustes del Sistema → Privacidad y seguridad**.
3. Baja hasta la sección **Seguridad**. Verás: *"Se bloqueó el uso de
   'EvemTv' porque no es de un desarrollador identificado"*.
4. Haz clic en **Abrir igualmente**.
5. Confirma con **Abrir igualmente** (o **Abrir**) y escribe la contraseña de
   tu Mac si la pide.

Desde entonces EvemTv abre normalmente con doble clic.

- **En macOS 14 (Sonoma) o anterior** también funciona: clic derecho (o
  Control + clic) sobre EvemTv en Aplicaciones → **Abrir** → **Abrir**.
- **Si no aparece el botón "Abrir igualmente"**: vuelve a intentar abrir la
  app y entra en *Privacidad y seguridad* justo después (el botón se muestra
  durante un rato tras el intento). Como último recurso, en la app
  **Terminal**:

  ```bash
  xattr -dr com.apple.quarantine /Applications/EvemTv.app
  ```

### Llavero

Al guardar una cuenta, macOS puede preguntar si *EvemTv quiere usar
información confidencial guardada en el llavero*. Escribe la contraseña de tu
Mac y elige **Permitir siempre**. Después de cada actualización la pregunta
puede repetirse una vez (la firma de la app cambia con cada versión).

### Actualizar y desinstalar

- **Actualizar:** descarga el `.dmg` nuevo desde el aviso de la app y
  arrastra EvemTv a Aplicaciones reemplazando la anterior. Puede que tengas
  que repetir "Abrir igualmente".
- **Desinstalar:** arrastra EvemTv desde Aplicaciones a la papelera. Para
  borrar también tus cuentas, cierra antes la sesión de cada una dentro de la
  app.

---

## Linux (AppImage)

El AppImage trae el motor de video (libmpv) incluido: no hace falta instalar
mpv.

1. Descarga `EvemTv-X.Y.Z-linux-x86_64.AppImage`.
2. Dale permiso de ejecución:
   - con el explorador de archivos: clic derecho → **Propiedades →
     Permisos → Permitir ejecutar como programa**; o
   - en una terminal: `chmod +x EvemTv-X.Y.Z-linux-x86_64.AppImage`
3. Ábrelo con doble clic o con `./EvemTv-X.Y.Z-linux-x86_64.AppImage`.

Requisitos del sistema (vienen instalados en los escritorios habituales):

- **Un llavero activo** (GNOME Keyring o KWallet) para guardar las
  contraseñas. Sin llavero, la app avisa y no guarda nada en texto plano.
- **libva** para la decodificación de video por hardware (paquete `libva2`).
  Sin ella, la app no puede abrir el motor de video.
- Si al abrirlo aparece un error de **FUSE**, ábrelo así:
  `./EvemTv-X.Y.Z-linux-x86_64.AppImage --appimage-extract-and-run`
  (o instala `fuse3`).

Para que aparezca en el menú de aplicaciones puedes usar una herramienta como
Gear Lever o AppImageLauncher.

- **Actualizar:** descarga el AppImage nuevo desde el aviso de la app y borra
  el anterior.
- **Desinstalar:** borra el archivo. Para borrar también tus cuentas, cierra
  antes la sesión de cada una dentro de la app.

---

## Comprobar la descarga (opcional)

Cada versión publica `SHA256SUMS.txt` con la huella SHA-256 de cada archivo.
Para comprobar que tu descarga está completa y no fue alterada, calcula la
huella y compárala con la de ese archivo:

- **Windows** (PowerShell): `Get-FileHash .\EvemTv-X.Y.Z-windows-x64-instalador.exe`
- **macOS**: `shasum -a 256 EvemTv-X.Y.Z-macos.dmg`
- **Linux**: `sha256sum -c SHA256SUMS.txt --ignore-missing` (en la carpeta de
  la descarga)

Descarga EvemTv solo desde
`github.com/Elmarcinho/evemtv_reproductor_iptv_desktop` o desde el botón
**Descargar** de la propia app.
