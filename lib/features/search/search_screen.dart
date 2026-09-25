import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
import '../../core/widgets/keyboard_help.dart';
import '../../core/widgets/state_views.dart';
import '../../domain/entities/catalog.dart';
import '../catalog/catalog_images.dart';
import '../live/widgets/channel_logo.dart';
import '../player/live_player_screen.dart';
import 'catalog_sync.dart';

abstract final class SearchScreenTiming {
  /// Espera tras la última tecla antes de buscar.
  static const Duration debounce = Duration(milliseconds: 250);
}

/// Búsqueda global en vivo, películas y series (catálogo local, FTS5).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  /// Texto con el que abrir (p. ej. desde "Buscar «…» en todo el catálogo").
  final String? initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  final _field = FocusNode(debugLabel: 'buscar');
  Timer? _debounce;
  late String _query = widget.initialQuery?.trim() ?? '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(SearchScreenTiming.debounce, () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _open(CatalogEntry e) {
    switch (e.kind) {
      case ContentKind.live:
        context.push(
          AppRoutes.livePlayer,
          extra: LiveStart(channels: [e.toChannel()]),
        );
      case ContentKind.movie:
        context.push(AppRoutes.movieDetail, extra: e.toMovie());
      case ContentKind.series:
        context.push(AppRoutes.seriesDetail, extra: e.toSeries());
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(catalogSyncProvider);
    // En la primera descarga del catálogo no se busca: el resultado sería
    // "nada coincide" solo porque falta contenido. Lo escrito se conserva y
    // se busca en cuanto termina.
    final ready = sync.searchReady;
    ref.listen(catalogSyncProvider.select((s) => s.searchReady), (_, now) {
      if (now) _field.requestFocus();
    });
    final results = !ready || _query.isEmpty
        ? null
        : ref.watch(searchResultsProvider(_query));

    return ScreenShortcuts(
      title: 'Búsqueda',
      help: ShortcutCatalog.search,
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            context.canPop() ? context.pop() : context.go(AppRoutes.home),
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Volver (Esc)',
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.go(AppRoutes.home),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _field,
                        autofocus: true,
                        enabled: ready,
                        onChanged: _onChanged,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (v) => setState(() => _query = v.trim()),
                        decoration: InputDecoration(
                          hintText: ready
                              ? 'Buscar canales, películas y series'
                              : 'Preparando la búsqueda…',
                          prefixIcon: const Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _SyncStatus(state: sync),
              const Divider(),
              Expanded(
                child: !ready
                    ? _Preparing(state: sync)
                    : results == null
                    ? const _Hint()
                    : results.when(
                        loading: () => const LoadingView(),
                        error: (e, _) => ErrorView(error: e),
                        data: (r) => r.isEmpty
                            ? Center(
                                child: Text(
                                  sync.isComplete
                                      ? 'Nada coincide con "$_query".'
                                      : 'Nada coincide con "$_query" en lo '
                                            'descargado. Falta: '
                                            '${_missing(sync)}. Usa "Actualizar" '
                                            'para reintentar.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              )
                            : _Results(results: r, onOpen: _open),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _missing(CatalogSyncState s) => [
  for (final k in ContentKind.values)
    if (!s.info.containsKey(k)) k.label.toLowerCase(),
].join(', ');

/// Primera descarga del catálogo: la búsqueda espera a que termine.
class _Preparing extends StatelessWidget {
  const _Preparing({required this.state});

  final CatalogSyncState state;

  @override
  Widget build(BuildContext context) {
    final total = ContentKind.values.length;
    final done = state.info.length;
    final current = state.current;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Preparando la búsqueda',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              current == null
                  ? 'Leyendo el catálogo guardado…'
                  : 'Descargando ${current.label.toLowerCase()} '
                        '(${done + 1} de $total). La primera vez puede tardar '
                        'unos minutos; después se actualiza sola.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: state.loaded ? done / total : null),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) => const Center(
    child: Text(
      'Escribe parte del nombre. No importan tildes ni mayúsculas.',
      style: TextStyle(color: AppColors.textSecondary),
    ),
  );
}

/// Estado del catálogo local: cuándo se actualizó y si se está actualizando.
class _SyncStatus extends ConsumerWidget {
  const _SyncStatus({required this.state});

  final CatalogSyncState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AppColors.textSecondary);
    final oldest = state.info.values
        .map((i) => i.syncedAt)
        .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    final String message;
    if (state.running) {
      message =
          'Actualizando el catálogo para la búsqueda'
          '${state.current == null ? '' : ' (${state.current!.label.toLowerCase()})'}…';
    } else if (oldest == null) {
      message = 'El catálogo para la búsqueda todavía no está disponible.';
    } else {
      message =
          'Catálogo actualizado el ${DateFormatEs.dateTime(oldest)}'
          '${state.failed.isEmpty ? '' : ' · no se pudo actualizar: '
                    '${state.failed.map((k) => k.label.toLowerCase()).join(', ')}'}';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(72, 0, 24, 8),
      child: Row(
        children: [
          if (state.running) ...[
            const SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(message, style: text)),
          TextButton.icon(
            onPressed: state.running
                ? null
                : () =>
                      ref.read(catalogSyncProvider.notifier).sync(force: true),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Actualizar'),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.results, required this.onOpen});

  final SearchResults results;
  final ValueChanged<CatalogEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final sections = [
      for (final kind in ContentKind.values)
        if ((results.byKind[kind] ?? const []).isNotEmpty)
          (kind: kind, items: results.byKind[kind]!),
    ];
    return CustomScrollView(
      slivers: [
        for (final s in sections) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                '${s.kind.label} (${s.items.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          SliverList.builder(
            itemCount: s.items.length,
            itemBuilder: (context, i) =>
                _ResultRow(entry: s.items[i], onOpen: onOpen),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _ResultRow extends ConsumerWidget {
  const _ResultRow({required this.entry, required this.onOpen});

  final CatalogEntry entry;
  final ValueChanged<CatalogEntry> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Imagen resuelta solo para las filas visibles.
    final image = ref
        .watch(
          catalogImageProvider((
            kind: entry.kind,
            categoryId: entry.categoryId,
            id: entry.id,
          )),
        )
        .value;
    final category = entry.categoryId == null
        ? null
        : ref.watch(categoryNamesProvider(entry.kind)).value?[entry.categoryId];
    final meta = [
      ?category,
      if (entry.year != null) '${entry.year}',
      if (entry.rating != null) '★ ${entry.rating!.toStringAsFixed(1)}',
    ].join('  ·  ');
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => onOpen(entry),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          children: [
            ChannelLogo(url: image, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(switch (entry.kind) {
              ContentKind.live => Icons.play_arrow_rounded,
              _ => Icons.chevron_right_rounded,
            }, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
