import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../data/providers.dart';
import '../../domain/entities/catalog.dart';
import '../../domain/entities/live.dart';
import '../../domain/entities/source_credentials.dart';
import '../../domain/parental/adult_content.dart';
import '../../domain/repositories/parental_repository.dart';
import '../auth/application/session.dart';
import '../search/catalog_sync.dart';
import 'pin_hash.dart';

/// Control parental (Fase 6; ver docs/decisiones.md §20).
///
/// - Bloqueado por defecto: el contenido de adultos (marcado por el panel,
///   por nombre de categoría o por el usuario) se **oculta** en todas las
///   pantallas.
/// - Se desbloquea con el PIN (por perfil; `0000` por defecto) hasta cerrar
///   la app, cambiar de cuenta o "Bloquear de nuevo": el estado vive en el
///   contenedor de la sesión y muere con ella.
abstract final class ParentalConfig {
  static const String defaultPin = '0000';

  /// Intentos fallidos antes de la primera espera.
  static const int freeAttempts = 5;

  /// Esperas sucesivas tras cada fallo a partir del quinto.
  static const List<Duration> waits = [
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 60),
  ];

  /// Espera tras [failures] intentos fallidos seguidos (cero si todavía no
  /// llegó a [freeAttempts]).
  static Duration waitAfter(int failures) {
    if (failures < freeAttempts) return Duration.zero;
    final i = failures - freeAttempts;
    return waits[i < waits.length ? i : waits.length - 1];
  }

  /// PIN válido: exactamente 4 números.
  static bool isValidPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);
}

/// Resultado de una operación con PIN o contraseña.
sealed class ParentalResult {
  const ParentalResult();
}

class ParentalOk extends ParentalResult {
  const ParentalOk({this.suggestChangePin = false});

  /// Se desbloqueó con el PIN por defecto y todavía no se dijo "Ahora no"
  /// en esta sesión: conviene sugerir cambiarlo.
  final bool suggestChangePin;
}

class ParentalWrong extends ParentalResult {
  const ParentalWrong({required this.attemptsLeft});

  /// Intentos que quedan antes de tener que esperar.
  final int attemptsLeft;
}

class ParentalWait extends ParentalResult {
  const ParentalWait(this.remaining);

  final Duration remaining;
}

/// El PIN nuevo no tiene 4 números.
class ParentalInvalidPin extends ParentalResult {
  const ParentalInvalidPin();
}

/// No se pudo guardar el cambio: queda lo anterior (el PIN anterior sigue
/// vigente).
class ParentalSaveFailed extends ParentalResult {
  const ParentalSaveFailed();
}

/// La sesión que abrió la operación ya terminó (se cambió de cuenta o se
/// cerró sesión): no se aplica nada, ni en ese perfil ni en otro.
class ParentalSessionClosed extends ParentalResult {
  const ParentalSessionClosed();
}

@immutable
class ParentalState {
  const ParentalState({
    this.loaded = false,
    this.unlocked = false,
    this.defaultPin = true,
    this.blocked = const {},
    this.suggestionDismissed = false,
  });

  final bool loaded;

  /// Contenido adulto visible en esta sesión.
  final bool unlocked;

  /// El PIN sigue siendo `0000`.
  final bool defaultPin;

  /// Categorías bloqueadas a mano.
  final Set<BlockedCategory> blocked;

  /// "Ahora no" a la sugerencia de cambiar el PIN, en esta sesión.
  final bool suggestionDismissed;

  /// `true` si la categoría se oculta ahora (de adultos por marca o por
  /// nombre, o bloqueada a mano).
  bool hidesCategory(ContentKind kind, ContentCategory category) =>
      !unlocked && isBlockedCategory(kind, category);

  /// `true` si la categoría está bloqueada, aunque ahora esté desbloqueado.
  bool isBlockedCategory(ContentKind kind, ContentCategory category) =>
      isAutomatic(category) || blocked.contains((kind: kind, id: category.id));

  /// De adultos sin que el usuario haga nada (marca del panel o nombre).
  static bool isAutomatic(ContentCategory category) =>
      category.adult || AdultContent.isAdultName(category.name);

  ParentalState copyWith({
    bool? loaded,
    bool? unlocked,
    bool? defaultPin,
    Set<BlockedCategory>? blocked,
    bool? suggestionDismissed,
  }) => ParentalState(
    loaded: loaded ?? this.loaded,
    unlocked: unlocked ?? this.unlocked,
    defaultPin: defaultPin ?? this.defaultPin,
    blocked: blocked ?? this.blocked,
    suggestionDismissed: suggestionDismissed ?? this.suggestionDismissed,
  );
}

/// Reloj del control parental (los tests lo reemplazan).
final parentalClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

class ParentalController extends Notifier<ParentalState> {
  /// Perfil y vida de la sesión, fijos: una operación empezada en esta
  /// sesión nunca escribe en otro perfil, y si la sesión terminó no escribe.
  late int _profileId;
  late SessionLifetime _lifetime;
  Future<void>? _loading;

  bool get _alive => ref.mounted && _lifetime.isActive;

  ParentalRepository get _repo => ref.read(parentalRepositoryProvider);
  DateTime _now() => ref.read(parentalClockProvider)().toUtc();

  @override
  ParentalState build() {
    final ctx = ref.watch(sessionContextProvider);
    _profileId = ctx.profileId;
    _lifetime = ctx.lifetime;
    _loading = null;
    Future.microtask(() {
      if (ref.mounted) unawaited(_ensureLoaded());
    });
    // Hasta leer lo guardado: bloqueado (lo automático ya se oculta).
    return const ParentalState();
  }

  Future<void> _ensureLoaded() => _loading ??= () async {
    try {
      final record = await _repo.read(_profileId);
      if (!ref.mounted) return;
      state = state.copyWith(
        loaded: true,
        defaultPin: record.pinHash == null,
        blocked: record.blocked,
      );
    } on Object catch (e) {
      AppLogger.w('No se pudo leer el control parental', e);
      if (ref.mounted) state = state.copyWith(loaded: true);
    }
  }();

  /// Muestra el contenido adulto si el PIN es correcto.
  Future<ParentalResult> unlock(String pin) async {
    final result = await _checkPin(pin);
    if (result is ParentalOk) {
      if (!_alive) return const ParentalSessionClosed();
      state = state.copyWith(unlocked: true);
      AppLogger.event('parental.unlock', const {});
      return ParentalOk(
        suggestChangePin: state.defaultPin && !state.suggestionDismissed,
      );
    }
    return result;
  }

  /// Vuelve a ocultar el contenido adulto.
  void lock() {
    state = state.copyWith(unlocked: false);
    AppLogger.event('parental.lock', const {});
  }

  /// "Ahora no": no volver a sugerir cambiar el PIN en esta sesión.
  void dismissSuggestion() {
    state = state.copyWith(suggestionDismissed: true);
  }

  /// Bloquea una categoría a mano (no pide PIN). `false` si no se pudo
  /// guardar (no cambia nada).
  Future<bool> blockCategory(ContentKind kind, String categoryId) async {
    await _ensureLoaded();
    if (!_alive) return false;
    final blocked = {...state.blocked, (kind: kind, id: categoryId)};
    if (!await _save((r) => r.copyWith(blocked: blocked))) return false;
    if (_alive) state = state.copyWith(blocked: blocked);
    AppLogger.event('parental.block_category', {'kind': kind});
    return true;
  }

  /// Quita el bloqueo manual de una categoría: pide el PIN.
  Future<ParentalResult> unblockCategory(
    ContentKind kind,
    String categoryId,
    String pin,
  ) async {
    final result = await _checkPin(pin);
    if (result is! ParentalOk) return result;
    if (!_alive) return const ParentalSessionClosed();
    final blocked = {...state.blocked}..remove((kind: kind, id: categoryId));
    if (!await _save((r) => r.copyWith(blocked: blocked))) {
      return const ParentalSaveFailed();
    }
    if (_alive) state = state.copyWith(blocked: blocked);
    AppLogger.event('parental.unblock_category', {'kind': kind});
    return const ParentalOk();
  }

  /// Cambia el PIN: pide el actual.
  Future<ParentalResult> changePin(String current, String next) async {
    if (!ParentalConfig.isValidPin(next)) return const ParentalInvalidPin();
    final result = await _checkPin(current);
    if (result is! ParentalOk) return result;
    if (!_alive) return const ParentalSessionClosed();
    // PBKDF2 con 20 000 rondas: unas decenas de milisegundos.
    final hash = PinHash.create(next);
    // Si no se guarda, el PIN anterior sigue vigente y se informa.
    if (!await _save((r) => r.copyWith(pinHash: hash))) {
      return const ParentalSaveFailed();
    }
    if (_alive) {
      state = state.copyWith(defaultPin: false, suggestionDismissed: true);
    }
    AppLogger.event('parental.pin_changed', const {});
    return const ParentalOk();
  }

  /// "Olvidé mi PIN": con la contraseña de la cuenta IPTV del perfil (la
  /// guardada en el almacén seguro), el PIN vuelve a `0000`. Los intentos
  /// fallidos cuentan igual que los del PIN.
  Future<ParentalResult> resetPinWithPassword(String password) async {
    await _ensureLoaded();
    if (!_alive) return const ParentalSessionClosed();
    final ParentalRecord record;
    try {
      record = await _repo.read(_profileId);
    } on Object catch (e) {
      AppLogger.w('No se pudo leer el control parental', e);
      return const ParentalSaveFailed();
    }
    final wait = _waitFor(record);
    if (wait != null) return ParentalWait(wait);
    var ok = false;
    try {
      final stored = await ref.read(credentialStoreProvider).read(_profileId);
      final expected = stored == null ? null : accountPassword(stored);
      ok =
          expected != null &&
          expected.isNotEmpty &&
          PinHash.constantTimeEquals(
            utf8.encode(password),
            utf8.encode(expected),
          );
    } on Object catch (e) {
      AppLogger.w('No se pudo leer la cuenta para restablecer el PIN', e);
    }
    if (!ok) return _fail(record);
    if (!_alive) return const ParentalSessionClosed();
    try {
      await _repo.write(
        _profileId,
        record.copyWith(clearPin: true, failedAttempts: 0, clearLock: true),
      );
    } on Object catch (e) {
      // El PIN anterior sigue vigente.
      AppLogger.w('No se pudo restablecer el PIN', e);
      return const ParentalSaveFailed();
    }
    if (_alive) state = state.copyWith(defaultPin: true);
    AppLogger.event('parental.pin_reset', const {});
    return const ParentalOk();
  }

  /// Contraseña de la cuenta IPTV: la de Xtream o, en una lista M3U, el
  /// parámetro `password` de su URL (si no tiene, la URL completa).
  @visibleForTesting
  static String? accountPassword(SourceCredentials credentials) =>
      switch (credentials) {
        XtreamCredentials(:final password) => password,
        M3uCredentials(:final playlist) =>
          playlist.queryParameters['password'] ?? playlist.toString(),
      };

  /// Comprueba el PIN y lleva la cuenta de intentos fallidos.
  Future<ParentalResult> _checkPin(String pin) async {
    await _ensureLoaded();
    if (!_alive) return const ParentalSessionClosed();
    final ParentalRecord record;
    try {
      record = await _repo.read(_profileId);
    } on Object catch (e) {
      // Sin poder leer el PIN guardado no se desbloquea nada.
      AppLogger.w('No se pudo leer el control parental', e);
      return const ParentalSaveFailed();
    }
    final wait = _waitFor(record);
    if (wait != null) return ParentalWait(wait);
    final stored = record.pinHash;
    final ok = stored == null
        ? PinHash.constantTimeEquals(
            utf8.encode(pin),
            utf8.encode(ParentalConfig.defaultPin),
          )
        : PinHash.verify(pin, stored);
    if (!ok) return _fail(record);
    if (record.failedAttempts != 0 || record.lockedUntil != null) {
      await _save((r) => r.copyWith(failedAttempts: 0, clearLock: true));
    }
    return const ParentalOk();
  }

  Duration? _waitFor(ParentalRecord record) {
    final until = record.lockedUntil;
    if (until == null) return null;
    final now = _now();
    if (!now.isBefore(until)) return null;
    final remaining = until.difference(now);
    // Una espera más larga que la máxima (reloj atrasado a mano) no puede
    // dejar el control trabado: se limita a la máxima.
    final max = ParentalConfig.waits.last;
    return remaining > max ? max : remaining;
  }

  Future<ParentalResult> _fail(ParentalRecord record) async {
    final failures = record.failedAttempts + 1;
    final wait = ParentalConfig.waitAfter(failures);
    await _save(
      (r) => r.copyWith(
        failedAttempts: failures,
        lockedUntil: wait == Duration.zero ? null : _now().add(wait),
        clearLock: wait == Duration.zero,
      ),
    );
    AppLogger.event('parental.failed_attempt', {'intentos': failures});
    if (wait != Duration.zero) return ParentalWait(wait);
    return ParentalWrong(attemptsLeft: ParentalConfig.freeAttempts - failures);
  }

  /// Guarda un cambio sobre lo último guardado. `false` si falló (y
  /// entonces no cambió nada) o si la sesión ya terminó.
  Future<bool> _save(ParentalRecord Function(ParentalRecord) change) async {
    if (!_alive) return false;
    try {
      final record = await _repo.read(_profileId);
      await _repo.write(_profileId, change(record));
      return true;
    } on Object catch (e) {
      AppLogger.w('No se pudo guardar el control parental', e);
      return false;
    }
  }
}

/// Control parental de la sesión: vive y muere con ella (cambiar de cuenta
/// vuelve a bloquear).
final parentalProvider = NotifierProvider<ParentalController, ParentalState>(
  ParentalController.new,
  dependencies: [sessionContextProvider],
);

/// Qué ocultar en las consultas al catálogo local (búsqueda, novedades,
/// "Recién agregadas") y en "Seguir viendo" y favoritos. Desbloqueado:
/// [HiddenContent.none]. Nunca falla: con un error se oculta lo que se pudo
/// calcular (siempre al menos lo marcado como de adultos).
final hiddenContentProvider = FutureProvider<HiddenContent>(
  (ref) async {
    final parental = ref.watch(parentalProvider);
    if (parental.unlocked) return HiddenContent.none;
    final profileId = ref.watch(sessionContextProvider).profileId;
    // Se recalcula cuando se actualiza el catálogo local.
    ref.watch(catalogSyncProvider.select((s) => s.info));
    final cache = ref.watch(catalogCacheProvider);
    final categories = <ContentKind, Set<String>>{};
    final adultItems = <ContentKind, Set<String>>{};
    final knownCategories = <ContentKind, Set<String>>{};
    final knownItems = <ContentKind, Set<String>>{};
    for (final kind in ContentKind.values) {
      try {
        final all = await cache.categories(profileId, kind);
        knownCategories[kind] = {for (final c in all) c.id};
        categories[kind] = {
          for (final c in all)
            if (parental.isBlockedCategory(kind, c)) c.id,
        };
        adultItems[kind] = await cache.adultItemIds(profileId, kind);
        knownItems[kind] = await cache.itemIds(profileId, kind);
      } on Object catch (e) {
        AppLogger.w('No se pudo calcular el contenido oculto', e);
      }
      // Las bloqueadas a mano, aunque todavía no estén en el catálogo local.
      categories[kind] = {
        ...?categories[kind],
        for (final b in parental.blocked)
          if (b.kind == kind) b.id,
      };
    }
    return HiddenContent(
      categories: categories,
      adultItems: adultItems,
      knownCategories: knownCategories,
      knownItems: knownItems,
    );
  },
  dependencies: [parentalProvider, sessionContextProvider, catalogSyncProvider],
);

/// Filtra una lista de categorías del proveedor según el control parental.
List<ContentCategory> visibleCategories(
  ParentalState parental,
  ContentKind kind,
  List<ContentCategory> all,
) => parental.unlocked
    ? all
    : [
        for (final c in all)
          if (!parental.hidesCategory(kind, c)) c,
      ];

/// Ids de las categorías ocultas de [kind] entre [all].
Set<String> hiddenCategoryIds(
  ParentalState parental,
  ContentKind kind,
  List<ContentCategory> all,
) => parental.unlocked
    ? const {}
    : {
        for (final c in all)
          if (parental.hidesCategory(kind, c)) c.id,
        for (final b in parental.blocked)
          if (b.kind == kind) b.id,
      };

/// Ids de las categorías ocultas de [kind], con las categorías del
/// proveedor de [allCategories]. Si no se pueden cargar, solo las
/// bloqueadas a mano (los elementos marcados como de adultos se filtran
/// igual por su marca).
Future<Set<String>> hiddenCategoryIdsOf(
  Ref ref,
  ParentalState parental,
  ContentKind kind,
  FutureProvider<List<ContentCategory>> allCategories,
) async {
  if (parental.unlocked) return const {};
  List<ContentCategory> all;
  try {
    all = await ref.watch(allCategories.future);
  } on Object {
    all = const [];
  }
  return hiddenCategoryIds(parental, kind, all);
}
