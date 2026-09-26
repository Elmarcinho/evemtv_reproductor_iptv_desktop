import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/category_list.dart';
import '../../domain/entities/catalog.dart';
import '../../domain/entities/live.dart';
import 'parental.dart';

/// Texto de una espera: "1 minuto", "2 minutos", "45 segundos".
String waitText(Duration d) {
  if (d.inSeconds < 60) {
    final s = d.inSeconds < 1 ? 1 : d.inSeconds;
    return s == 1 ? '1 segundo' : '$s segundos';
  }
  final m = (d.inSeconds / 60).ceil();
  return m == 1 ? '1 minuto' : '$m minutos';
}

/// Mensaje para un resultado fallido, o `null` si salió bien.
String? parentalErrorText(ParentalResult result, {String what = 'PIN'}) =>
    switch (result) {
      ParentalOk() => null,
      ParentalWrong(:final attemptsLeft) =>
        attemptsLeft <= 1
            ? '$what incorrecto. Te queda 1 intento antes de tener que '
                  'esperar.'
            : '$what incorrecto. Te quedan $attemptsLeft intentos.',
      ParentalWait(:final remaining) =>
        'Demasiados intentos fallidos. Espera ${waitText(remaining)} y '
            'vuelve a intentarlo.',
      ParentalInvalidPin() => 'El PIN nuevo debe tener 4 números.',
    };

/// Botón del pie de las categorías: "Contenido adulto" (con candado) pide
/// el PIN para mostrarlo; desbloqueado, "Bloquear de nuevo".
class ParentalButton extends ConsumerWidget {
  const ParentalButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref.watch(parentalProvider.select((s) => s.unlocked));
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: unlocked
          ? TextButton.icon(
              onPressed: () => ref.read(parentalProvider.notifier).lock(),
              icon: const Icon(Icons.lock_rounded, size: 18),
              label: const Text('Bloquear de nuevo'),
            )
          : TextButton.icon(
              onPressed: () => unlockAdultContent(context, ref),
              icon: const Icon(Icons.lock_outline_rounded, size: 18),
              label: const Text('Contenido adulto'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
            ),
    );
  }
}

/// Pide el PIN para mostrar el contenido adulto. Si se desbloqueó con el
/// PIN por defecto, sugiere cambiarlo ("Cambiar PIN" / "Ahora no").
Future<void> unlockAdultContent(BuildContext context, WidgetRef ref) async {
  ParentalResult? outcome;
  final ok = await showPinDialog(
    context,
    title: 'Contenido adulto',
    message:
        'Escribe el PIN del control parental para mostrar el contenido '
        'para adultos. Se volverá a ocultar al cerrar la app o cambiar de '
        'cuenta.',
    action: (pin) async =>
        outcome = await ref.read(parentalProvider.notifier).unlock(pin),
  );
  if (!ok || !context.mounted) return;
  if (outcome case ParentalOk(suggestChangePin: true)) {
    final change = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambia el PIN'),
        content: const Text(
          'Tu PIN todavía es 0000, el que viene de fábrica. Cualquiera '
          'puede adivinarlo: te recomendamos elegir uno propio.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cambiar PIN'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (change == true) {
      await showChangePinDialog(context, ref, knownPin: '0000');
    } else {
      ref.read(parentalProvider.notifier).dismissSuggestion();
    }
  }
}

/// Oculta una categoría a mano, tras confirmarlo.
Future<void> blockCategory(
  BuildContext context,
  WidgetRef ref,
  ContentKind kind,
  ContentCategory category,
) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Ocultar categoría'),
      content: Text(
        '«${category.name}» se ocultará junto con el contenido para '
        'adultos. Para volver a mostrarla necesitarás el PIN del control '
        'parental.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Ocultar'),
        ),
      ],
    ),
  );
  if (confirm == true) {
    await ref.read(parentalProvider.notifier).blockCategory(kind, category.id);
  }
}

/// Quita el bloqueo manual de una categoría: pide el PIN.
Future<bool> unblockCategory(
  BuildContext context,
  WidgetRef ref,
  ContentKind kind,
  String categoryId,
  String name,
) => showPinDialog(
  context,
  title: 'Volver a mostrar «$name»',
  message:
      'Escribe el PIN del control parental para quitar el bloqueo de '
      'esta categoría.',
  action: (pin) => ref
      .read(parentalProvider.notifier)
      .unblockCategory(kind, categoryId, pin),
);

/// Cambiar el PIN: el actual (salvo que se acabe de escribir, [knownPin]),
/// el nuevo y su confirmación.
Future<bool> showChangePinDialog(
  BuildContext context,
  WidgetRef ref, {
  String? knownPin,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => _ChangePinDialog(knownPin: knownPin),
  );
  if (ok == true && context.mounted) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('PIN cambiado.')));
  }
  return ok == true;
}

/// "Olvidé mi PIN": con la contraseña de la cuenta IPTV, vuelve a 0000.
Future<bool> showResetPinDialog(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => _SecretDialog(
      title: 'Olvidé mi PIN',
      message:
          'Escribe la contraseña de tu cuenta IPTV (la que usaste para '
          'entrar en esta cuenta). El PIN volverá a ser 0000 y después '
          'podrás cambiarlo.',
      label: 'Contraseña de la cuenta',
      what: 'Contraseña',
      pin: false,
      action: (password) =>
          ref.read(parentalProvider.notifier).resetPinWithPassword(password),
      confirmLabel: 'Restablecer PIN',
    ),
  );
  if (ok == true && context.mounted) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('El PIN volvió a ser 0000.')));
  }
  return ok == true;
}

/// Pide el PIN y ejecuta [action]; con "Olvidé mi PIN". `true` si salió
/// bien.
Future<bool> showPinDialog(
  BuildContext context, {
  required String title,
  required String message,
  required Future<ParentalResult> Function(String pin) action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => _SecretDialog(
      title: title,
      message: message,
      label: 'PIN',
      what: 'PIN',
      pin: true,
      action: action,
      confirmLabel: 'Aceptar',
      showForgot: true,
    ),
  );
  return ok == true;
}

/// Diálogo de un solo dato secreto (PIN o contraseña).
class _SecretDialog extends ConsumerStatefulWidget {
  const _SecretDialog({
    required this.title,
    required this.message,
    required this.label,
    required this.what,
    required this.pin,
    required this.action,
    required this.confirmLabel,
    this.showForgot = false,
  });

  final String title;
  final String message;
  final String label;
  final String what;
  final bool pin;
  final Future<ParentalResult> Function(String value) action;
  final String confirmLabel;
  final bool showForgot;

  @override
  ConsumerState<_SecretDialog> createState() => _SecretDialogState();
}

class _SecretDialogState extends ConsumerState<_SecretDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _controller.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.action(_controller.text);
    if (!mounted) return;
    if (result is ParentalOk) {
      Navigator.of(context).pop(true);
      return;
    }
    _controller.clear();
    setState(() {
      _busy = false;
      _error = parentalErrorText(result, what: widget.what);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: true,
              enabled: !_busy,
              keyboardType: widget.pin ? TextInputType.number : null,
              maxLength: widget.pin ? 4 : null,
              inputFormatters: widget.pin
                  ? [FilteringTextInputFormatter.digitsOnly]
                  : null,
              decoration: InputDecoration(
                labelText: widget.label,
                errorText: _error,
                errorMaxLines: 3,
                counterText: '',
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.showForgot)
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await showResetPinDialog(context, ref);
                  },
            child: const Text('Olvidé mi PIN'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _ChangePinDialog extends ConsumerStatefulWidget {
  const _ChangePinDialog({this.knownPin});

  final String? knownPin;

  @override
  ConsumerState<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends ConsumerState<_ChangePinDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!ParentalConfig.isValidPin(_next.text)) {
      setState(() => _error = 'El PIN nuevo debe tener 4 números.');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = 'Los dos PIN nuevos no coinciden.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(parentalProvider.notifier)
        .changePin(widget.knownPin ?? _current.text, _next.text);
    if (!mounted) return;
    if (result is ParentalOk) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = parentalErrorText(result, what: 'PIN actual');
    });
  }

  Widget _field(TextEditingController c, String label, {bool focus = false}) =>
      TextField(
        controller: c,
        autofocus: focus,
        obscureText: true,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        maxLength: 4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, counterText: ''),
        onSubmitted: (_) => _submit(),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar PIN'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'El PIN protege el contenido para adultos de esta cuenta. '
              'Elige 4 números fáciles de recordar para ti y difíciles de '
              'adivinar para otros.',
            ),
            const SizedBox(height: 12),
            if (widget.knownPin == null)
              _field(_current, 'PIN actual', focus: true),
            _field(_next, 'PIN nuevo', focus: widget.knownPin != null),
            _field(_confirm, 'Repite el PIN nuevo'),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Acciones de control parental para la lista de categorías de [kind].
CategoryParentalActions parentalActionsFor(
  BuildContext context,
  WidgetRef ref,
  ContentKind kind,
) {
  final parental = ref.watch(parentalProvider);
  return CategoryParentalActions(
    isBlocked: (c) => parental.isBlockedCategory(kind, c),
    isAutomatic: ParentalState.isAutomatic,
    onBlock: (c) => blockCategory(context, ref, kind, c),
    onUnblock: (c) => unblockCategory(context, ref, kind, c.id, c.name),
  );
}
