import '../entities/account_info.dart';
import '../entities/profile.dart';

/// Contrato común de las fuentes de contenido. Xtream y M3U lo implementan
/// para que la interfaz no dependa del tipo de fuente. En las fases
/// siguientes se agregan categorías, canales, VOD, series y EPG.
abstract interface class ContentSource {
  SourceType get type;

  /// Comprueba que la fuente responde y las credenciales son válidas, y
  /// devuelve los datos de la cuenta si la fuente los ofrece. Lanza
  /// `AppFailure` con un mensaje claro si algo falla.
  Future<AccountInfo?> verify();

  /// Datos de la cuenta, o `null` si la fuente no los ofrece (M3U).
  Future<AccountInfo?> fetchAccountInfo();
}
