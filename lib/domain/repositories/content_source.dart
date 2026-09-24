import '../entities/account_info.dart';
import '../entities/live.dart';
import '../entities/profile.dart';

/// Contrato común de las fuentes de contenido. Xtream y M3U lo implementan
/// para que la interfaz no dependa del tipo de fuente. En las fases
/// siguientes se agregan VOD, series y EPG completa.
abstract interface class ContentSource {
  SourceType get type;

  /// Comprueba que la fuente responde y las credenciales son válidas, y
  /// devuelve los datos de la cuenta si la fuente los ofrece. Lanza
  /// `AppFailure` con un mensaje claro si algo falla.
  Future<AccountInfo?> verify();

  /// Datos de la cuenta, o `null` si la fuente no los ofrece (M3U).
  Future<AccountInfo?> fetchAccountInfo();

  /// Categorías de TV en vivo.
  Future<List<ContentCategory>> liveCategories();

  /// Canales de una categoría, o todos si [categoryId] es `null`.
  Future<List<LiveChannel>> liveChannels({String? categoryId});

  /// Programa actual y siguientes de un canal (EPG corta). Lista vacía si la
  /// fuente no tiene guía para ese canal.
  Future<List<EpgEntry>> shortEpg(LiveChannel channel, {int limit = 4});

  /// URLs para reproducir un canal. [allowedFormats] son los formatos que
  /// permite la cuenta (`allowed_output_formats`); vacío = desconocidos.
  PlaybackCandidates liveStream(
    LiveChannel channel, {
    List<String> allowedFormats = const [],
  });
}
