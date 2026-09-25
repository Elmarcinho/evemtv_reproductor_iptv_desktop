// Servidor Xtream FICTICIO local con un catálogo sintético grande, para
// medir el rendimiento (ver test_driver/perf_app_test.dart). Todo es
// inventado: 127.0.0.1, usuario y clave ficticios, video y pósters
// generados con ffmpeg (patrón de prueba).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const int liveCount = 2000;
const int movieCount = 24000;
const int seriesCount = 8000;
const int vodCategories = 60;

// --- Servidor Xtream ficticio ---------------------------------------------

class FakePanel {
  FakePanel(this.video, this.poster, this.backdrop);

  final File video;
  final List<int> poster;
  final List<int> backdrop;
  late final HttpServer server;
  late final String base;
  final Map<String, String> _cache = {};

  Future<void> start(int port) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    base = 'http://127.0.0.1:${server.port}';
    server.listen(_handle);
  }

  String img(String id) => '$base/img/$id.jpg';

  String _json(String key, Object Function() build) =>
      _cache[key] ??= jsonEncode(build());

  int _year(int i) => 2026 - (i % 7);

  String _body(Map<String, String> q) {
    final category = q['category_id'];
    switch (q['action']) {
      case null:
        return jsonEncode({
          'user_info': {
            'username': 'usuarioPerf',
            'auth': 1,
            'status': 'Active',
            'exp_date': '4102444800',
            'max_connections': '1',
            'active_cons': '0',
            'allowed_output_formats': ['m3u8', 'ts'],
          },
          'server_info': {'timezone': 'UTC'},
        });
      case 'get_live_categories':
        return _json(
          'lc',
          () => [
            for (var c = 1; c <= 40; c++)
              {'category_id': '$c', 'category_name': 'Canales $c'},
          ],
        );
      case 'get_live_streams':
        return _json(
          'ls$category',
          () => [
            for (var i = 1; i <= liveCount; i++)
              if (category == null || '${i % 40 + 1}' == category)
                {
                  'num': i,
                  'name': 'Canal Ficticio $i',
                  'stream_id': i,
                  'stream_icon': img('c$i'),
                  'category_id': '${i % 40 + 1}',
                },
          ],
        );
      case 'get_vod_categories':
        return _json(
          'vc',
          () => [
            for (var c = 1; c <= vodCategories; c++)
              {
                'category_id': '$c',
                'category_name': 'Categoría ${c.toString().padLeft(2, '0')}',
              },
          ],
        );
      case 'get_vod_streams':
        return _json(
          'vs$category',
          () => [
            for (var i = 1; i <= movieCount; i++)
              if (category == null || '${i % vodCategories + 1}' == category)
                {
                  'num': i,
                  'name': 'Película Ficticia $i (${_year(i)})',
                  'stream_id': i,
                  'stream_icon': img('m$i'),
                  'rating': '${(i % 90) / 10 + 1}',
                  'added': '${1735689600 + i * 600}',
                  'category_id': '${i % vodCategories + 1}',
                  'container_extension': 'mp4',
                },
          ],
        );
      case 'get_vod_info':
        return jsonEncode({
          'info': {
            'plot': 'Sinopsis ficticia para medir el rendimiento.',
            'genre': 'Drama',
            'duration_secs': 7200,
            'backdrop_path': ['$base/backdrop.jpg'],
          },
          'movie_data': {
            'stream_id': q['vod_id'],
            'name': 'Película Ficticia ${q['vod_id']}',
            'container_extension': 'mp4',
          },
        });
      case 'get_series_categories':
        return _json(
          'sc',
          () => [
            for (var c = 1; c <= 30; c++)
              {'category_id': '$c', 'category_name': 'Series $c'},
          ],
        );
      case 'get_series':
        return _json(
          'ss$category',
          () => [
            for (var i = 1; i <= seriesCount; i++)
              if (category == null || '${i % 30 + 1}' == category)
                {
                  'num': i,
                  'name': 'Serie Ficticia $i (${_year(i)})',
                  'series_id': i,
                  'cover': img('s$i'),
                  'rating': '${(i % 80) / 10 + 1}',
                  'last_modified': '${1735689600 + i * 900}',
                  'category_id': '${i % 30 + 1}',
                },
          ],
        );
      case 'get_short_epg':
        return '{"epg_listings": []}';
      default:
        return '[]';
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    final response = request.response;
    try {
      if (path.endsWith('player_api.php')) {
        response.headers.contentType = ContentType.json;
        response.write(_body(request.uri.queryParameters));
      } else if (path.startsWith('/img/')) {
        response.headers.contentType = ContentType('image', 'jpeg');
        response.add(poster);
      } else if (path == '/backdrop.jpg') {
        response.headers.contentType = ContentType('image', 'jpeg');
        response.add(backdrop);
      } else if (path.startsWith('/movie/')) {
        await _serveVideo(request);
        return;
      } else {
        response.statusCode = 404;
      }
    } finally {
      await response.close();
    }
  }

  /// Video con soporte de rangos (mpv los usa para avanzar).
  Future<void> _serveVideo(HttpRequest request) async {
    final response = request.response;
    final length = await video.length();
    var start = 0;
    var end = length - 1;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    final match = range == null
        ? null
        : RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
    if (match != null) {
      start = int.tryParse(match.group(1)!) ?? 0;
      end = int.tryParse(match.group(2)!) ?? end;
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$length',
      );
    }
    response.headers
      ..contentType = ContentType('video', 'mp4')
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..contentLength = end - start + 1;
    try {
      await response.addStream(video.openRead(start, end + 1));
    } on Object {
      // El cliente cortó (normal al buscar o cerrar).
    }
    await response.close().catchError((Object _) {});
  }
}
