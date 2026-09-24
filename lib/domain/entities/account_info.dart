/// Estado de la cuenta según el panel.
enum AccountStatus {
  active('Activa'),
  expired('Vencida'),
  banned('Bloqueada'),
  disabled('Deshabilitada'),
  unknown('Desconocido');

  const AccountStatus(this.label);
  final String label;

  static AccountStatus parse(String? raw) => switch (raw?.toLowerCase()) {
    'active' => AccountStatus.active,
    'expired' => AccountStatus.expired,
    'banned' => AccountStatus.banned,
    'disabled' => AccountStatus.disabled,
    _ => AccountStatus.unknown,
  };
}

/// Datos de la cuenta que se muestran en la pantalla de inicio. No incluye
/// usuario ni contraseña.
class AccountInfo {
  const AccountInfo({
    required this.authenticated,
    required this.status,
    this.expiresAt,
    this.createdAt,
    this.isTrial = false,
    this.activeConnections,
    this.maxConnections,
    this.allowedOutputFormats = const [],
    this.serverTimezone,
  });

  final bool authenticated;
  final AccountStatus status;

  /// `null` = sin fecha de vencimiento.
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final bool isTrial;
  final int? activeConnections;
  final int? maxConnections;

  /// Formatos de reproducción permitidos (`m3u8`, `ts`, `rtmp`).
  final List<String> allowedOutputFormats;
  final String? serverTimezone;

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && expiresAt!.isBefore(now);
}
