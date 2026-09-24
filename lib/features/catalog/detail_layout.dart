import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/poster.dart';

/// Estructura común de las fichas de película y serie: fondo con la imagen
/// de la obra atenuada, póster, título, datos, sinopsis, acciones y, debajo,
/// contenido extra (temporadas y episodios).
class DetailLayout extends StatelessWidget {
  const DetailLayout({
    super.key,
    required this.title,
    required this.posterUrl,
    required this.icon,
    this.backdropUrl,
    this.meta = const [],
    this.plot,
    this.credits = const [],
    this.actions = const [],
    this.below,
    this.loading = false,
  });

  final String title;
  final String? posterUrl;
  final String? backdropUrl;
  final IconData icon;

  /// Año, duración, género, puntaje…
  final List<String> meta;
  final String? plot;

  /// Pares etiqueta/valor: director, reparto, país.
  final List<(String, String)> credits;
  final List<Widget> actions;
  final Widget? below;

  /// Se muestra una barra de carga mientras llega la ficha completa.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final backdrop = backdropUrl ?? posterUrl;
    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).maybePop(),
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (backdrop != null)
              Opacity(
                opacity: 0.18,
                child: Image.network(
                  backdrop,
                  fit: BoxFit.cover,
                  cacheWidth: 960,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x660D1117), AppColors.background],
                  stops: [0, 0.7],
                ),
              ),
            ),
            SafeArea(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Volver (Esc)',
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (loading)
                    const SliverToBoxAdapter(
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(48, 16, 48, 24),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 240,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Poster(
                                url: posterUrl,
                                title: title,
                                icon: icon,
                              ),
                            ),
                          ),
                          const SizedBox(width: 36),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title, style: text.headlineMedium),
                                if (meta.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    meta.join('   ·   '),
                                    style: text.bodyMedium?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                                if (actions.isNotEmpty) ...[
                                  const SizedBox(height: 24),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: actions,
                                  ),
                                ],
                                if (plot != null) ...[
                                  const SizedBox(height: 24),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 760,
                                    ),
                                    child: Text(plot!, style: text.bodyLarge),
                                  ),
                                ],
                                if (credits.isNotEmpty) ...[
                                  const SizedBox(height: 20),
                                  for (final (label, value) in credits)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: '$label: ',
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                            TextSpan(text: value),
                                          ],
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ?below,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
