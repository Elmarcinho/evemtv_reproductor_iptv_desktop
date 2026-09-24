import '../entities/account_info.dart';
import '../entities/live.dart';
import '../entities/profile.dart';
import '../entities/vod.dart';

/// Contrato común de las fuentes de contenido. Xtream y M3U lo implementan
/// para que la interfaz no dependa del tipo de fuente.
abstract interface class ContentSource {
  SourceType get type;

  /// Comprueba que la fuente responde y las credenciales son válidas, y
  /// devuelve los datos de la cuenta si la fuente los ofrece. Lanza
  /// `AppFailure` con un mensaje claro si algo falla.
  Future<AccountInfo?> verify();

  /// Datos de la cuenta, o `null` si la fuente no los ofrece (M3U).
  Future<AccountInfo?> fetchAccountInfo();

  // --- TV en vivo ---

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

  // --- Películas ---

  Future<List<ContentCategory>> vodCategories();

  /// Películas de una categoría, o todas si [categoryId] es `null`.
  Future<List<VodItem>> vodItems({String? categoryId});

  /// Ficha completa. Si la fuente no tiene más datos, devuelve la ficha
  /// mínima con lo que ya trae [item].
  Future<VodDetail> vodDetail(VodItem item);

  PlaybackCandidates movieStream(VodItem item);

  // --- Series ---

  Future<List<ContentCategory>> seriesCategories();

  /// Series de una categoría, o todas si [categoryId] es `null`.
  Future<List<SeriesItem>> seriesItems({String? categoryId});

  /// Temporadas y episodios.
  Future<SeriesDetail> seriesDetail(SeriesItem series);

  PlaybackCandidates episodeStream(Episode episode);
}
