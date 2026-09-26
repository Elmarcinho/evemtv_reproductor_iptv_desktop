; Instalador de EvemTv para Windows (Inno Setup 6). Lo compila el workflow
; de release:
;
;   iscc /DAppVersion=1.0.0 /DSourceDir=<carpeta Release> /O<salida> evemtv.iss
;
; Se instala por usuario (sin pedir permisos de administrador); quien quiera
; instalar para todos puede elegirlo en el primer paso.

#ifndef AppVersion
  #error Falta /DAppVersion=x.y.z
#endif
#ifndef SourceDir
  #error Falta /DSourceDir=<carpeta de la compilacion Release>
#endif

[Setup]
; Identificador fijo del producto: no cambiar (las actualizaciones lo usan
; para reemplazar la versión instalada).
AppId={{7F903258-FFCF-4A34-A750-A45C88CE25CF}
AppName=EvemTv
AppVersion={#AppVersion}
AppVerName=EvemTv {#AppVersion}
AppPublisher=Godebol
AppPublisherURL=https://github.com/Elmarcinho/evemtv_reproductor_iptv_desktop
AppSupportURL=https://github.com/Elmarcinho/evemtv_reproductor_iptv_desktop
AppUpdatesURL=https://github.com/Elmarcinho/evemtv_reproductor_iptv_desktop/releases
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\EvemTv
DefaultGroupName=EvemTv
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputBaseFilename=EvemTv-{#AppVersion}-windows-x64-instalador
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\evemtv.exe
UninstallDisplayName=EvemTv
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Cierra EvemTv si está abierta al actualizar.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Toda la carpeta de la compilación: evemtv.exe, DLL de Flutter, de mpv y
; del runtime de Visual C++, y la carpeta data\.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\EvemTv"; Filename: "{app}\evemtv.exe"
Name: "{autodesktop}\EvemTv"; Filename: "{app}\evemtv.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\evemtv.exe"; Description: "{cm:LaunchProgram,EvemTv}"; Flags: nowait postinstall skipifsilent

; Al desinstalar se conservan las cuentas y ajustes (carpeta de datos y
; almacén de credenciales de Windows), como en una actualización. Para
; borrarlos, se cierran las sesiones dentro de la app antes de desinstalar.
