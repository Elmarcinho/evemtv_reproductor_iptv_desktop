import '../../domain/entities/account_info.dart';
import '../../domain/entities/profile.dart';
import '../../domain/repositories/content_source.dart';
import 'xtream_account_parser.dart';
import 'xtream_client.dart';

/// Fuente de contenido Xtream Codes.
class XtreamSource implements ContentSource {
  XtreamSource(this._client, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final XtreamClient _client;
  final DateTime Function() _clock;

  @override
  SourceType get type => SourceType.xtream;

  /// Login: valida `auth == 1`, estado `Active` y vencimiento. Con un solo
  /// reintento para no hacer esperar demasiado si el servidor está caído.
  @override
  Future<AccountInfo> verify() async {
    final info = XtreamAccountParser.parse(
      await _client.get(null, maxRetries: 1),
    );
    XtreamAccountParser.ensureUsable(info, now: _clock());
    return info;
  }

  @override
  Future<AccountInfo> fetchAccountInfo() async =>
      XtreamAccountParser.parse(await _client.get(null));
}
