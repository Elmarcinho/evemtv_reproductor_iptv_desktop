import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/text_format.dart';
import '../../domain/entities/catalog.dart';
import '../images/poster.dart';
import '../search/catalog_sync.dart';
import 'featured.dart';

/// Abre la ficha de una novedad.
void openFeatured(BuildContext context, CatalogEntry entry) {
  switch (entry.kind) {
    case ContentKind.movie:
      context.push(AppRoutes.movieDetail, extra: entry.toMovie());
    case ContentKind.series:
      context.push(AppRoutes.seriesDetail, extra: entry.toSeries());
    case ContentKind.live:
      break;
  }
}

String _typeLine(CatalogEntry entry) => [
  entry.kind == ContentKind.movie ? 'Película' : 'Serie',
  if (entry.year != null) '${entry.year}',
].join(' · ');

String _kindNoun(ContentKind kind) =>
    kind == ContentKind.movie ? 'Películas' : 'Series';

/// Qué mostrar de las novedades de un tipo: las tarjetas, la muestra de
/// carga o nada (sin novedades).
sealed class _FeaturedView {
  const _FeaturedView();
}

class _Loading extends _FeaturedView {
  const _Loading();
}

class _Hidden extends _FeaturedView {
  const _Hidden();
}

class _Ready extends _FeaturedView {
  const _Ready(this.items, this.title);
  final List<FeaturedItem> items;
  final String title;
}

/// [kind] `null` = "Mejor valoradas" (películas y series juntas).
_FeaturedView _watchFeatured(WidgetRef ref, ContentKind? kind) {
  final featured = ref.watch(
    kind == null ? topRatedProvider : featuredProvider(kind),
  );
  final preparing = ref.watch(
    catalogSyncProvider.select(
      (s) =>
          !s.loaded ||
          (s.running &&
              (kind == null ? !s.isComplete : !s.info.containsKey(kind))),
    ),
  );
  final items = featured.value ?? const <FeaturedItem>[];
  if (items.isEmpty) {
    return preparing || featured.isLoading ? const _Loading() : const _Hidden();
  }
  return _Ready(
    items,
    kind == null
        ? 'Mejor valoradas'
        : FeaturedRules.title(_kindNoun(kind), items),
  );
}

/// Carrusel compacto de novedades (columna derecha del inicio), con el
/// título sobre la tarjeta del frente.
class FeaturedCarousel extends ConsumerWidget {
  const FeaturedCarousel({
    super.key,
    required this.kind,
    this.cardHeight = 420,
  });

  final ContentKind kind;
  final double cardHeight;

  /// Tiempo de cada tarjeta al frente.
  static const Duration interval = Duration(seconds: 3);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (_watchFeatured(ref, kind)) {
      _Hidden() => const SizedBox.shrink(),
      _Loading() => _Frame(
        title: '${_kindNoun(kind)} nuevas',
        child: CarouselSkeleton(cardHeight: cardHeight),
      ),
      _Ready(:final items, :final title) => _Frame(
        title: title,
        child: StackedCarousel(
          items: items,
          cardHeight: cardHeight,
          onOpen: (entry) => openFeatured(context, entry),
        ),
      ),
    };
  }
}

/// Novedades destacadas (área principal del inicio): la pila de tarjetas
/// con más tarjetas asomando detrás y, debajo, el título y los datos de la
/// del frente. La tarjeta del frente, el título de la sección y los datos
/// quedan centrados en su columna.
class FeaturedHero extends ConsumerStatefulWidget {
  const FeaturedHero({super.key, this.kind, required this.cardHeight});

  /// `null` = "Mejor valoradas" (películas y series juntas).
  final ContentKind? kind;
  final double cardHeight;

  /// Alto del título y los datos debajo de la pila.
  static const double infoHeight = 84;

  @override
  ConsumerState<FeaturedHero> createState() => _FeaturedHeroState();
}

class _FeaturedHeroState extends ConsumerState<FeaturedHero> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    const g = StackGeometry.hero;
    final h = widget.cardHeight;
    final cardW = h * 2 / 3;
    final behindW = g.behind * g.peek;
    final kind = widget.kind;
    final loadingTitle = kind == null
        ? 'Mejor valoradas'
        : '${_kindNoun(kind)} nuevas';
    final view = _watchFeatured(ref, kind);
    if (view is _Hidden) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        // La tarjeta del frente queda centrada; las de atrás asoman a la
        // izquierda (si no entran, la pila se corre lo necesario).
        final left = ((maxW - cardW) / 2 - behindW).clamp(
          0.0,
          (maxW - g.widthFor(h)).clamp(0.0, double.infinity),
        );
        final title = switch (view) {
          _Ready(:final title) => title,
          _ => loadingTitle,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(left: left + behindW),
              child: SizedBox(
                width: cardW,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: EdgeInsets.only(left: left),
              child: switch (view) {
                _Ready(:final items) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StackedCarousel(
                      items: items,
                      cardHeight: h,
                      geometry: g,
                      showCaption: false,
                      onChanged: (i) => setState(() => _index = i),
                      onOpen: (entry) => openFeatured(context, entry),
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: behindW),
                      child: SizedBox(
                        width: cardW,
                        height: FeaturedHero.infoHeight,
                        child: _HeroInfo(
                          item: items[_index.clamp(0, items.length - 1)],
                        ),
                      ),
                    ),
                  ],
                ),
                _ => CarouselSkeleton(cardHeight: h, geometry: g),
              },
            ),
          ],
        );
      },
    );
  }
}

/// Título y datos de la novedad al frente (debajo de la pila). Se abre con
/// un clic en la tarjeta. Cambia con un fundido.
class _HeroInfo extends StatelessWidget {
  const _HeroInfo({required this.item});

  final FeaturedItem item;

  @override
  Widget build(BuildContext context) {
    final entry = item.entry;
    final text = Theme.of(context).textTheme;
    final rating = entry.rating;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: Column(
        key: ValueKey('${entry.kind.name}:${entry.id}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            TextFormat.displayName(entry.name),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _typeLine(entry),
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (rating != null && rating > 0) ...[
                const SizedBox(width: 12),
                const Icon(
                  Icons.star_rounded,
                  size: 18,
                  color: AppColors.favorite,
                ),
                const SizedBox(width: 4),
                Text(
                  rating.toStringAsFixed(1),
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      child,
    ],
  );
}

/// Forma de la pila: cuántas tarjetas asoman detrás de la del frente y
/// cuánto asoma cada una.
class StackGeometry {
  const StackGeometry({required this.behind, required this.peek});

  /// Columna compacta del inicio.
  static const compact = StackGeometry(behind: 2, peek: 28);

  /// Novedades destacadas: más tarjetas atrás, más separadas.
  static const hero = StackGeometry(behind: 4, peek: 34);

  final int behind;
  final double peek;

  double widthFor(double cardHeight) => cardHeight * 2 / 3 + behind * peek;
}

/// Tarjetas de muestra con la forma del carrusel, con un pulso suave,
/// mientras cargan las novedades.
class CarouselSkeleton extends StatefulWidget {
  const CarouselSkeleton({
    super.key,
    required this.cardHeight,
    this.geometry = StackGeometry.compact,
  });

  final double cardHeight;
  final StackGeometry geometry;

  @override
  State<CarouselSkeleton> createState() => _CarouselSkeletonState();
}

class _CarouselSkeletonState extends State<CarouselSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.45,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sin animaciones del sistema, quieto.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.value = 0.7;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.cardHeight;
    final w = h * 2 / 3;
    final g = widget.geometry;
    return Semantics(
      label: 'Cargando novedades',
      child: FadeTransition(
        opacity: _pulse,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: h,
              width: g.widthFor(h),
              child: Stack(
                children: [
                  for (var level = g.behind; level >= 0; level--)
                    Positioned(
                      left: (g.behind - level) * g.peek,
                      top: h * StackedCarousel.shrink * level / 2,
                      width: w * (1 - StackedCarousel.shrink * level),
                      height: h * (1 - StackedCarousel.shrink * level),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color.lerp(
                            AppColors.surfaceHigh,
                            AppColors.background,
                            0.3 * level,
                          ),
                          borderRadius: BorderRadius.circular(
                            StackedCarousel.radius,
                          ),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: level == 0
                            ? const Center(
                                child: Icon(
                                  Icons.movie_filter_outlined,
                                  size: 40,
                                  color: AppColors.textSecondary,
                                ),
                              )
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: StackedCarousel.progressHeight),
          ],
        ),
      ),
    );
  }
}

/// Tarjetas apiladas: la del frente completa y las siguientes asomando
/// por detrás a la izquierda. Debajo, una barra que se llena mientras la
/// tarjeta está al frente y un contador ("3 / 12").
///
/// Avanza sola cada [FeaturedCarousel.interval] y se detiene con el mouse
/// encima o con el foco; ← / → y Enter con el teclado. Un clic en la del
/// frente la abre, un clic en una de atrás la trae al frente y un clic en
/// la barra salta a esa parte de la lista.
class StackedCarousel extends StatefulWidget {
  const StackedCarousel({
    super.key,
    required this.items,
    required this.onOpen,
    this.cardHeight = 420,
    this.showCaption = true,
    this.onChanged,
    this.geometry = StackGeometry.compact,
  });

  /// Forma de la pila.
  final StackGeometry geometry;

  final List<FeaturedItem> items;
  final ValueChanged<CatalogEntry> onOpen;
  final double cardHeight;

  /// Título sobre la tarjeta del frente (el destacado lo muestra al lado).
  final bool showCaption;

  /// Índice de la tarjeta que pasa al frente.
  final ValueChanged<int>? onChanged;

  /// Cuánto se achica cada nivel hacia atrás.
  static const double shrink = 0.08;

  static const double radius = 16;

  /// Alto de la barra de avance y el contador debajo de las tarjetas.
  static const double progressHeight = 32;

  static double widthFor(double cardHeight) =>
      StackGeometry.compact.widthFor(cardHeight);

  @override
  State<StackedCarousel> createState() => _StackedCarouselState();
}

class _StackedCarouselState extends State<StackedCarousel>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  bool _hovered = false;
  bool _focused = false;

  /// Tiempo de la tarjeta al frente: al completarse, pasa a la siguiente.
  late final AnimationController _progress =
      AnimationController(vsync: this, duration: FeaturedCarousel.interval)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _go(1);
        });

  int get _count => widget.items.length;

  @override
  void initState() {
    super.initState();
    _resume();
  }

  @override
  void didUpdateWidget(StackedCarousel old) {
    super.didUpdateWidget(old);
    if (_index >= _count) {
      // La lista se acortó: vuelve a la primera y lo avisa, así la ficha
      // de al lado sigue mostrando la tarjeta del frente.
      _index = 0;
      _progress.value = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged?.call(_index);
      });
    }
    _resume();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  /// Sigue el avance automático, salvo con el mouse encima o el foco.
  void _resume() {
    if (_count < 2 || _hovered || _focused) {
      _progress.stop();
      return;
    }
    if (!_progress.isAnimating) _progress.forward();
  }

  void _show(int index) {
    if (_count == 0) return;
    setState(() => _index = index % _count);
    widget.onChanged?.call(_index);
    _progress.value = 0;
    _resume();
  }

  void _go(int delta) {
    if (_count < 2) return;
    _show(_index + delta);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        _go(1);
      case LogicalKeyboardKey.arrowLeft:
        _go(-1);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.select:
        widget.onOpen(widget.items[_index].entry);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.cardHeight;
    final w = h * 2 / 3;
    // De atrás hacia adelante: la del frente se pinta última.
    final order = [for (var i = 0; i < _count; i++) i]
      ..sort((a, b) => _depth(b).compareTo(_depth(a)));

    return Focus(
      onKeyEvent: _onKey,
      onFocusChange: (f) {
        _focused = f;
        _resume();
      },
      child: MouseRegion(
        onEnter: (_) {
          _hovered = true;
          _resume();
        },
        onExit: (_) {
          _hovered = false;
          _resume();
        },
        child: SizedBox(
          width: widget.geometry.widthFor(h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: h,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final i in order) _positioned(i, _depth(i), w, h),
                  ],
                ),
              ),
              _ProgressBar(
                count: _count,
                index: _index,
                progress: _progress,
                onSeek: _show,
                indent: widget.geometry.behind * widget.geometry.peek,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 0 = al frente, 1 = justo detrás, …
  int _depth(int i) => (i - _index) % _count;

  Widget _positioned(int i, int depth, double w, double h) {
    final item = widget.items[i];
    final g = widget.geometry;
    final visible = depth <= g.behind;
    final level = visible ? depth : g.behind;
    final scale = 1 - StackedCarousel.shrink * level;
    final cardH = h * scale;
    const duration = Duration(milliseconds: 420);
    const curve = Curves.easeOutCubic;
    return AnimatedPositioned(
      key: ValueKey('${item.entry.kind.name}:${item.entry.id}'),
      duration: duration,
      curve: curve,
      left: (g.behind - level) * g.peek,
      top: (h - cardH) / 2,
      width: w * scale,
      height: cardH,
      child: AnimatedOpacity(
        duration: duration,
        opacity: visible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: _Card(
            item: item,
            depth: level,
            caption: widget.showCaption && depth == 0,
            posterWidth: w,
            onTap: () => depth == 0 ? widget.onOpen(item.entry) : _show(i),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.item,
    required this.depth,
    required this.caption,
    required this.onTap,
    required this.posterWidth,
  });

  /// Ancho de la tarjeta al frente: el póster se decodifica siempre a ese
  /// tamaño (si siguiera el ancho animado, se volvería a decodificar en
  /// cada cuadro).
  final double posterWidth;
  final FeaturedItem item;
  final int depth;
  final bool caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final entry = item.entry;
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(StackedCarousel.radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(StackedCarousel.radius),
        child: Material(
          color: AppColors.surfaceHigh,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Poster(
                  url: item.posterUrl,
                  title: TextFormat.displayName(entry.name),
                  width: posterWidth,
                  icon: entry.kind == ContentKind.movie
                      ? Icons.movie_outlined
                      : Icons.video_library_outlined,
                ),
                // Las de atrás, más oscuras.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 420),
                  color: Colors.black.withValues(alpha: 0.28 * depth),
                ),
                // Título y tipo, solo en la del frente. Degradado fuerte
                // para que no se mezcle con el texto del propio póster.
                Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: caption ? 1 : 0,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0, 0.45, 1],
                          colors: [
                            Color(0x00000000),
                            Color(0xCC000000),
                            Color(0xF2000000),
                          ],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            TextFormat.displayName(entry.name),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _typeLine(entry),
                            style: text.bodySmall?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Barra fina que se llena mientras la tarjeta está al frente (el total
/// representa toda la lista) y el contador "3 / 12". Un clic salta a esa
/// parte de la lista.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.count,
    required this.index,
    required this.progress,
    required this.onSeek,
    required this.indent,
  });

  /// Sangría izquierda: la barra va bajo la tarjeta del frente.
  final double indent;
  final int count;
  final int index;
  final Animation<double> progress;
  final ValueChanged<int> onSeek;

  @override
  Widget build(BuildContext context) {
    if (count < 2) {
      return const SizedBox(height: StackedCarousel.progressHeight);
    }
    final label = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: AppColors.textSecondary);
    return SizedBox(
      height: StackedCarousel.progressHeight,
      child: Padding(
        padding: EdgeInsets.only(left: indent),
        child: Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => GestureDetector(
                  key: const ValueKey('barra-novedades'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => onSeek(
                    (d.localPosition.dx / constraints.maxWidth * count)
                        .floor()
                        .clamp(0, count - 1),
                  ),
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 3,
                        child: AnimatedBuilder(
                          animation: progress,
                          builder: (context, _) => LinearProgressIndicator(
                            value: (index + progress.value) / count,
                            backgroundColor: AppColors.border,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('${index + 1} / $count', style: label),
          ],
        ),
      ),
    );
  }
}
