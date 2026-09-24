// Respuestas y listas INVENTADAS para TV en vivo. Dominios reservados y
// nombres ficticios. Las listas M3U van como texto aquí porque el
// .gitignore excluye los archivos *.m3u.
import 'dart:convert';

String b64(String s) => base64.encode(utf8.encode(s));

/// Categorías con rarezas: id numérico, nombre nulo, elemento inválido.
const String liveCategoriesJson = '''
[
  {"category_id": "1", "category_name": "Noticias", "parent_id": 0},
  {"category_id": 2, "category_name": null, "parent_id": 0},
  {"category_name": "Sin id"},
  "basura"
]
''';

/// Canales con tipos inconsistentes.
const String liveStreamsJson = '''
[
  {"num": 1, "name": "Canal Uno", "stream_type": "live", "stream_id": 101,
   "stream_icon": "http://img.example.com/1.png", "epg_channel_id": "uno.example",
   "category_id": "1", "tv_archive": 1},
  {"num": "2", "name": "Canal Dos", "stream_id": "102", "stream_icon": "",
   "epg_channel_id": null, "category_id": 1, "tv_archive": "0"},
  {"num": null, "name": "", "stream_id": "103", "stream_icon": "file:///etc/x.png"},
  {"name": "Sin stream_id"},
  {"name": "Id negativo", "stream_id": -5}
]
''';

String shortEpgJson() => jsonEncode({
  'epg_listings': [
    {
      'title': b64('Programa Siguiente'),
      'description': b64('Descripción del siguiente'),
      'start_timestamp': '1767229200', // 2026-01-01 01:00 UTC
      'stop_timestamp': '1767232800',
    },
    {
      'title': b64('Noticiero Ficticio'),
      'description': b64('Resumen del día'),
      'start_timestamp': 1767225600, // 2026-01-01 00:00 UTC
      'stop_timestamp': 1767229200,
    },
    {
      'title': 'Texto sin base64',
      'start_timestamp': '1767232800',
      'stop_timestamp': '1767236400',
    },
    {'title': b64('Sin horario')},
    {
      'title': b64('Fin antes del inicio'),
      'start_timestamp': '1767236400',
      'stop_timestamp': '1767232800',
    },
  ],
});

const String m3uFull = '''
﻿#EXTM3U url-tvg="http://epg.example.com/guia.xml"\r
#EXTINF:-1 tvg-id="uno.example" tvg-chno="1" tvg-logo="http://img.example.com/1.png" group-title="Noticias",Canal Uno\r
http://stream.example.com/live/u/p/1.ts\r
#EXTINF:-1 tvg-logo="data:image/png;base64,xx" group-title="Deportes, Fútbol",Canal Dos, con coma\r
#EXTVLCOPT:http-user-agent=Algo
http://stream.example.com/canal2.m3u8

#EXTINF:0 tvg-name="Nombre por atributo",
http://stream.example.com/canal3
#EXTINF:-1,Canal con EXTGRP
#EXTGRP:Música
http://stream.example.com/canal4.ts
http://stream.example.com/sin-extinf.ts
#EXTINF:-1 group-title="Películas",Película Ficticia
http://stream.example.com/movie/u/p/10.mkv
#EXTINF:-1 group-title="Series",Episodio Ficticio
http://stream.example.com/series/u/p/20.mp4
#EXTINF:-1,Línea rota sin URL
#EXTINF:-1,Esquema no permitido
file:///etc/passwd
#EXTINF:-1 group-title="Noticias",Canal Uno repetido
http://stream.example.com/live/u/p/1.ts
''';
