import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/state_views.dart';
import '../../../domain/entities/profile.dart';
import '../application/auth_service.dart';

/// Selector de cuentas guardadas, al iniciar la app.
class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(48, 40, 48, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppLogo(),
              const SizedBox(height: 32),
              Text(
                'Elige una cuenta',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: profiles.when(
                  loading: () => const LoadingView(),
                  error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(profilesProvider),
                  ),
                  data: (list) => list.isEmpty
                      ? const _EmptyProfiles()
                      : _ProfileGrid(profiles: list),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyProfiles extends StatelessWidget {
  const _EmptyProfiles();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.person_add_alt_1_rounded,
            size: 56,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            'Todavía no hay cuentas guardadas',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Agrega tu cuenta Xtream Codes o una lista M3U para empezar.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            autofocus: true,
            onPressed: () => context.go(AppRoutes.login),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Agregar cuenta'),
          ),
        ],
      ),
    );
  }
}

class _ProfileGrid extends StatelessWidget {
  const _ProfileGrid({required this.profiles});

  final List<Profile> profiles;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        mainAxisExtent: 168,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: profiles.length + 1,
      itemBuilder: (context, i) => i < profiles.length
          ? _ProfileCard(profile: profiles[i], autofocus: i == 0)
          : const _AddProfileCard(),
    );
  }
}

class _ProfileCard extends ConsumerStatefulWidget {
  const _ProfileCard({required this.profile, this.autofocus = false});

  final Profile profile;
  final bool autofocus;

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await ref.read(authServiceProvider).open(widget.profile);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(userMessageFor(e))));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: Text(
          'Se borrarán de este equipo las credenciales y los datos guardados '
          'de "${_displayName()}".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(authServiceProvider).removeProfile(widget.profile);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(userMessageFor(e))));
    }
  }

  String _displayName() =>
      ref.watch(profileDisplayNameProvider(widget.profile.id)).value ??
      widget.profile.name;

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        autofocus: widget.autofocus,
        onTap: _open,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.accent.withValues(alpha: 0.18),
                    child: Icon(
                      profile.type == SourceType.xtream
                          ? Icons.dns_rounded
                          : Icons.playlist_play_rounded,
                      color: AppColors.accent,
                    ),
                  ),
                  const Spacer(),
                  if (_opening)
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    PopupMenuButton<void>(
                      tooltip: 'Opciones',
                      icon: const Icon(Icons.more_vert_rounded),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          onTap: _remove,
                          child: const Text('Eliminar cuenta'),
                        ),
                      ],
                    ),
                ],
              ),
              const Spacer(),
              Text(
                _displayName(),
                style: text.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                profile.lastUsedAt == null
                    ? profile.type.label
                    : '${profile.type.label} · usada el '
                          '${DateFormatEs.date(profile.lastUsedAt!)}',
                style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddProfileCard extends StatelessWidget {
  const _AddProfileCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go(AppRoutes.login),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 32, color: AppColors.textSecondary),
              SizedBox(height: 8),
              Text(
                'Agregar cuenta',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
