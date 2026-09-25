import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/server_url.dart';
import '../../../core/widgets/keyboard_help.dart';
import '../../../core/widgets/state_views.dart';
import '../application/auth_service.dart';

/// Alta de una cuenta: Xtream Codes (usuario, contraseña y URL) o lista M3U.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _xtreamForm = GlobalKey<FormState>();
  final _m3uForm = GlobalKey<FormState>();

  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _m3uUrl = TextEditingController();

  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  XtreamFromPlaylist? _xtreamSuggestion;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() => _error = null);
    });
    _m3uUrl.addListener(_detectXtreamInPlaylist);
  }

  @override
  void dispose() {
    for (final c in [_url, _username, _password, _m3uUrl]) {
      c.dispose();
    }
    _tabs.dispose();
    super.dispose();
  }

  /// Si la URL M3U es un `get.php` de un panel Xtream, sugiere el ingreso
  /// Xtream (que además trae EPG, películas y series).
  void _detectXtreamInPlaylist() {
    XtreamFromPlaylist? suggestion;
    try {
      suggestion = ServerUrl.tryExtractXtream(
        ServerUrl.validatePlaylist(_m3uUrl.text),
      );
    } on InvalidUrlFailure {
      suggestion = null;
    }
    // Igualdad de registro: compara servidor, usuario **y contraseña**, así
    // corregir solo la contraseña actualiza la sugerencia.
    if (suggestion != _xtreamSuggestion) {
      setState(() => _xtreamSuggestion = suggestion);
    }
  }

  void _useXtreamSuggestion() {
    final s = _xtreamSuggestion;
    if (s == null) return;
    _url.text = s.server.toString();
    _username.text = s.username;
    _password.text = s.password;
    _tabs.animateTo(0);
  }

  String? _required(String? v, String message) =>
      (v == null || v.trim().isEmpty) ? message : null;

  String? _validateServer(String? v) {
    try {
      ServerUrl.normalizeXtream(v ?? '');
      return null;
    } on InvalidUrlFailure catch (e) {
      return e.message;
    }
  }

  String? _validatePlaylist(String? v) {
    try {
      ServerUrl.validatePlaylist(v ?? '');
      return null;
    } on InvalidUrlFailure catch (e) {
      return e.message;
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    final isXtream = _tabs.index == 0;
    final form = isXtream ? _xtreamForm : _m3uForm;
    if (!(form.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authServiceProvider);
    try {
      if (isXtream) {
        await auth.addXtream(
          url: _url.text,
          username: _username.text,
          password: _password.text,
        );
      } else {
        await auth.addM3u(url: _m3uUrl.text);
      }
      // Al abrirse la sesión, el router lleva al inicio.
    } on Object catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasProfiles = ref.watch(profilesProvider).value?.isNotEmpty ?? false;
    return Scaffold(
      body: ScreenShortcuts(
        title: 'Agregar cuenta',
        help: const [
          (keys: 'Tab', action: 'Pasar de un campo a otro'),
          (keys: 'Enter', action: 'Conectar'),
        ],
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (hasProfiles && !_busy) context.go(AppRoutes.profiles);
          },
        },
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const AppLogo(height: 56),
                          const Spacer(),
                          if (hasProfiles)
                            TextButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => context.go(AppRoutes.profiles),
                              icon: const Icon(Icons.arrow_back_rounded),
                              label: const Text('Volver'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Agregar cuenta',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      TabBar(
                        controller: _tabs,
                        tabs: const [
                          Tab(text: 'Xtream Codes'),
                          Tab(text: 'Lista M3U'),
                        ],
                      ),
                      const SizedBox(height: 24),
                      AnimatedBuilder(
                        animation: _tabs,
                        builder: (context, _) => _tabs.index == 0
                            ? _buildXtreamForm()
                            : _buildM3uForm(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        ErrorBanner(message: _error!),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Conectar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildXtreamForm() {
    return Form(
      key: _xtreamForm,
      child: AutofillGroup(
        child: Column(
          children: [
            TextFormField(
              controller: _url,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'URL del servidor',
                hintText: 'http://servidor:puerto',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
              validator: _validateServer,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _username,
              enabled: !_busy,
              autocorrect: false,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(
                labelText: 'Usuario',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (v) => _required(v, 'Ingresa el usuario.'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              enabled: !_busy,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _showPassword
                      ? 'Ocultar contraseña'
                      : 'Mostrar contraseña',
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Ingresa la contraseña.' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildM3uForm() {
    return Form(
      key: _m3uForm,
      child: Column(
        children: [
          TextFormField(
            controller: _m3uUrl,
            enabled: !_busy,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'URL de la lista M3U / M3U8',
              hintText: 'http://servidor/lista.m3u',
              prefixIcon: Icon(Icons.playlist_play_rounded),
            ),
            validator: _validatePlaylist,
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_xtreamSuggestion != null) ...[
            const SizedBox(height: 12),
            _XtreamSuggestion(onUse: _busy ? null : _useXtreamSuggestion),
          ],
        ],
      ),
    );
  }
}

class _XtreamSuggestion extends StatelessWidget {
  const _XtreamSuggestion({required this.onUse});

  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.tips_and_updates_outlined, color: AppColors.accent),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Esta lista parece de un servidor Xtream Codes. Ingresando como '
              'Xtream tendrás guía de programación, películas y series.',
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onUse, child: const Text('Usar Xtream')),
        ],
      ),
    );
  }
}
