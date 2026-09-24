// Respuestas INVENTADAS de películas y series, con las rarezas típicas de
// los paneles Xtream. Títulos y personas ficticios; dominios reservados.

const String vodStreamsJson = '''
[
  {"num": 1, "name": "Película Ficticia Uno", "stream_type": "movie",
   "stream_id": 501, "stream_icon": "http://img.example.com/p1.jpg",
   "rating": "7.4", "category_id": "10", "container_extension": "mkv",
   "year": "2021"},
  {"name": "Película Dos", "stream_id": "502", "stream_icon": "",
   "rating": 0, "category_id": 10, "container_extension": "MP4"},
  {"name": "Extensión peligrosa", "stream_id": 503,
   "container_extension": "mp4/../../x", "rating": "11"},
  {"name": "Sin id"},
  "basura"
]
''';

/// `info` completo, con duración en segundos y backdrop como lista.
const String vodInfoJson = '''
{
  "info": {
    "movie_image": "http://img.example.com/p1-grande.jpg",
    "plot": "Una historia inventada para las pruebas.",
    "genre": "Drama",
    "cast": "Actriz Uno, Actor Dos",
    "director": "Directora Ficticia",
    "releasedate": "2021-03-15",
    "duration_secs": "6300",
    "duration": "01:45:00",
    "backdrop_path": ["", "http://img.example.com/fondo.jpg"],
    "country": "País Imaginario"
  },
  "movie_data": {"stream_id": 501, "container_extension": "mkv"}
}
''';

/// Panel sin metadatos: `info` llega como lista vacía.
const String vodInfoEmptyJson = '{"info": [], "movie_data": []}';

const String seriesJson = '''
[
  {"num": 1, "name": "Serie Ficticia", "series_id": 700,
   "cover": "http://img.example.com/s1.jpg", "rating": "8,2",
   "category_id": "20", "releaseDate": "2019-09-01"},
  {"name": "Serie sin portada", "series_id": "701", "cover": null},
  {"name": "Sin id"}
]
''';

/// Episodios como objeto por temporada, con temporadas desordenadas y un
/// episodio repetido.
const String seriesInfoMapJson = '''
{
  "seasons": [
    {"season_number": 1, "name": "Temporada Uno", "cover_big": "http://img.example.com/t1.jpg"},
    {"season_number": 2, "name": ""}
  ],
  "info": {
    "plot": "Trama ficticia.",
    "genre": "Comedia",
    "cast": "Elenco Inventado",
    "backdrop_path": "http://img.example.com/fondo-serie.jpg"
  },
  "episodes": {
    "2": [
      {"id": "9003", "episode_num": 1, "title": "T2 Episodio 1",
       "container_extension": "mp4", "season": 2, "info": {"duration": "45:00"}}
    ],
    "1": [
      {"id": "9002", "episode_num": "2", "title": "Episodio Dos",
       "container_extension": "mkv", "info": {"duration_secs": 2700,
       "plot": "Sinopsis dos", "movie_image": "http://img.example.com/e2.jpg"}},
      {"id": 9001, "episode_num": 1, "title": "Episodio Uno",
       "container_extension": "mkv", "info": []},
      {"id": 9001, "episode_num": 1, "title": "Repetido"},
      {"title": "Sin id"}
    ]
  }
}
''';

/// Otros paneles: episodios como lista de listas.
const String seriesInfoListJson = '''
{
  "seasons": [],
  "info": [],
  "episodes": [
    [{"id": 1, "episode_num": 1, "season": 1, "title": "A"}],
    [{"id": 2, "episode_num": 1, "season": 2, "title": "B"}]
  ]
}
''';

const String m3uVod = '''
#EXTM3U
#EXTINF:-1 tvg-logo="http://img.example.com/c1.png" group-title="Noticias",Canal Uno
http://stream.example.com/live/u/p/1.ts
#EXTINF:-1 tvg-logo="http://img.example.com/m1.jpg" group-title="Estrenos",Película Ficticia (2022)
http://stream.example.com/movie/u/p/10.mkv
#EXTINF:-1 group-title="Clásicos",Otra Película
http://stream.example.com/peliculas/otra.mp4
#EXTINF:-1 tvg-logo="http://img.example.com/s1.jpg" group-title="Series",Serie Ficticia S01 E02 Segundo
http://stream.example.com/series/u/p/102.mp4
#EXTINF:-1 group-title="Series",Serie Ficticia S01E01
http://stream.example.com/series/u/p/101.mp4
#EXTINF:-1 group-title="Series",Serie Ficticia - S02 E01 - Vuelta
http://stream.example.com/series/u/p/201.mp4
#EXTINF:-1 group-title="Series",Otra Serie 1x03
http://stream.example.com/series/u/p/303.mkv
#EXTINF:-1 group-title="Series",Especial sin numeración
http://stream.example.com/series/u/p/999.mp4
''';
