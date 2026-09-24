// Respuestas de ejemplo INVENTADAS con las rarezas típicas de los paneles
// Xtream. Dominios reservados (.invalid, example.com) y datos ficticios.

/// Respuesta "de manual": tipos correctos.
const String loginOk = '''
{
  "user_info": {
    "username": "usuario_demo",
    "password": "clave_demo",
    "message": "",
    "auth": 1,
    "status": "Active",
    "exp_date": "4102444800",
    "is_trial": "0",
    "active_cons": "1",
    "created_at": "1704067200",
    "max_connections": "2",
    "allowed_output_formats": ["m3u8", "ts", "rtmp"]
  },
  "server_info": {
    "url": "panel.example.com",
    "port": "8080",
    "https_port": "8443",
    "server_protocol": "http",
    "timezone": "America/Argentina/Buenos_Aires",
    "timestamp_now": 1767225600,
    "time_now": "2026-01-01 00:00:00"
  }
}
''';

/// Panel con tipos inconsistentes: números como texto o reales, nulos,
/// `[]` en lugar de objeto y formatos como objeto con claves numéricas.
const String loginMessyTypes = '''
{
  "user_info": {
    "auth": "1",
    "status": "active",
    "exp_date": null,
    "is_trial": 1,
    "active_cons": 0,
    "created_at": "",
    "max_connections": 1.0,
    "allowed_output_formats": {"0": "ts", "1": "m3u8"}
  },
  "server_info": []
}
''';

/// Credenciales incorrectas, tal como responden muchos paneles.
const String loginAuthZero = '{"user_info": {"auth": 0}}';

/// Otras respuestas de credenciales incorrectas.
const String loginEmptyList = '[]';

const String loginExpired = '''
{"user_info": {"auth": 1, "status": "Expired", "exp_date": "946684800"}}
''';

const String loginActiveButPastDate = '''
{"user_info": {"auth": 1, "status": "Active", "exp_date": "946684800"}}
''';

const String loginBanned = '{"user_info": {"auth": 1, "status": "Banned"}}';

/// Un servidor que no es un panel Xtream.
const String htmlPage =
    '<!DOCTYPE html><html><body>Página de ejemplo</body></html>';

/// Cabecera de una lista M3U ficticia.
const String m3uHead = '''
#EXTM3U url-tvg="http://epg.example.com/guia.xml"
#EXTINF:-1 tvg-id="canal1" tvg-logo="http://img.example.com/1.png" group-title="Noticias",Canal Uno
http://stream.example.com/canal1.ts
''';
