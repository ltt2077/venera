part of 'components.dart';

/// Liquid-glass helpers. Toggle via settings key `liquidGlass` (default ON).
///
/// Android note: a translucent fill alone looks like a flat Material card.
/// We combine BackdropFilter blur with a visible frosted gradient mesh so the
/// glass read is obvious even when little content sits behind the chrome.
class Glass {
  Glass._();

  static bool get enabled {
    final v = appdata.settings['liquidGlass'];
    if (v is bool) return v;
    return true;
  }

  static bool shouldBlur(BuildContext context) {
    if (!enabled) return false;
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return true;
    if (mq.highContrast || mq.boldText) return false;
    return true;
  }

  static double blurSigma(BuildContext context) {
    if (!shouldBlur(context)) return 0;
    if (App.isIOS) return 28;
    if (App.isMacOS) return 40;
    if (App.isWindows || App.isLinux) return 36;
    // Android Impeller: push sigma hard so frost is unmistakable.
    return 48;
  }

  static double fillOpacity(BuildContext context) {
    if (!shouldBlur(context)) return 1.0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (App.isIOS) return dark ? 0.48 : 0.55;
    if (App.isMacOS) return dark ? 0.42 : 0.52;
    if (App.isWindows || App.isLinux) return dark ? 0.48 : 0.58;
    // Android: keep fill thin so blur + mesh show through.
    return dark ? 0.28 : 0.34;
  }

  static Color fillColor(BuildContext context, {Color? base}) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Prefer surfaceContainerLowest so light/dark stay coherent (no dark chrome
    // on light cards).
    final c = base ??
        (dark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest);
    return c.toOpacity(fillOpacity(context));
  }

  static Border? highlightBorder(BuildContext context, {double radius = 12}) {
    if (!shouldBlur(context)) return null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    if (App.isIOS || App.isMacOS || App.isAndroid) {
      return Border.all(
        color: dark
            ? Colors.white.toOpacity(0.22)
            : Colors.white.toOpacity(0.65),
        width: 0.8,
      );
    }
    return Border.all(
      color: dark
          ? scheme.outlineVariant.toOpacity(0.55)
          : scheme.outlineVariant.toOpacity(0.35),
      width: 0.7,
    );
  }

  static List<BoxShadow> softShadow(BuildContext context) {
    if (!shouldBlur(context)) return const [];
    final dark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.toOpacity(dark ? 0.32 : 0.10),
        blurRadius: App.isDesktop ? 28 : 20,
        offset: const Offset(0, 10),
      ),
    ];
  }

  /// Soft color orbs painted *behind* the blur so frost is always visible.
  static Widget frostedMesh(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? [
                        scheme.primary.toOpacity(0.22),
                        scheme.tertiary.toOpacity(0.12),
                        scheme.surface.toOpacity(0.55),
                      ]
                    : [
                        scheme.primary.toOpacity(0.18),
                        scheme.secondary.toOpacity(0.12),
                        Colors.white.toOpacity(0.55),
                      ],
              ),
            ),
          ),
          Positioned(
            top: -40,
            right: -20,
            child: _orb(
              size: 140,
              color: scheme.primary.toOpacity(dark ? 0.35 : 0.28),
            ),
          ),
          Positioned(
            bottom: -30,
            left: -30,
            child: _orb(
              size: 160,
              color: scheme.tertiary.toOpacity(dark ? 0.28 : 0.22),
            ),
          ),
          Positioned(
            top: 80,
            left: 40,
            child: _orb(
              size: 90,
              color: scheme.secondary.toOpacity(dark ? 0.22 : 0.18),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _orb({required double size, required Color color}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.toOpacity(0)],
        ),
      ),
    );
  }
}

/// Frosted glass panel used for nav chrome, cards, dialogs, flyouts, sheets.
/// Does NOT wrap comic page content — only chrome.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.margin,
    this.clipBehavior = Clip.antiAlias,
    this.opacity,
    this.blur,
    this.border,
    this.color,
    this.elevationShadow = true,
    this.showMesh = true,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Clip clipBehavior;
  final double? opacity;
  final double? blur;
  final BoxBorder? border;
  final Color? color;
  final bool elevationShadow;
  /// Paint frosted gradient orbs under the blur (needed on Android sheets).
  final bool showMesh;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.zero;
    final useGlass = Glass.shouldBlur(context);
    final sigma = blur ?? (useGlass ? Glass.blurSigma(context) : 0);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final fill = color ??
        (useGlass
            ? Glass.fillColor(context)
            : scheme.surface);
    final effectiveFill = color != null
        ? fill
        : (useGlass
            ? (dark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest)
                .toOpacity(opacity ?? Glass.fillOpacity(context))
            : scheme.surface);
    final boxBorder = border ?? Glass.highlightBorder(context);

    Widget panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: useGlass ? effectiveFill : fill,
        borderRadius: radius == BorderRadius.zero ? null : radius,
        border: useGlass ? boxBorder : null,
        boxShadow: elevationShadow ? Glass.softShadow(context) : null,
        gradient: useGlass
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.toOpacity(dark ? 0.14 : 0.42),
                  effectiveFill,
                  (dark ? Colors.black : Colors.white)
                      .toOpacity(dark ? 0.18 : 0.08),
                ],
                stops: const [0.0, 0.45, 1.0],
              )
            : null,
      ),
      child: child,
    );

    if (sigma > 0) {
      final clipped = ClipRRect(
        borderRadius: radius == BorderRadius.zero
            ? BorderRadius.zero
            : radius,
        clipBehavior: clipBehavior,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            if (showMesh)
              Positioned.fill(child: Glass.frostedMesh(context)),
            // Real backdrop blur of whatever is behind this panel.
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: sigma,
                  sigmaY: sigma,
                  tileMode:
                      App.isAndroid ? TileMode.clamp : TileMode.mirror,
                ),
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            // Extra soft blur of the mesh itself (fake frost if backdrop empty).
            if (showMesh && App.isAndroid)
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: 18,
                    sigmaY: 18,
                    tileMode: TileMode.decal,
                  ),
                  child: Opacity(
                    opacity: 0.55,
                    child: Glass.frostedMesh(context),
                  ),
                ),
              ),
            panel,
          ],
        ),
      );
      if (margin != null) {
        return Padding(padding: margin!, child: clipped);
      }
      return clipped;
    }

    if (radius != BorderRadius.zero) {
      panel = ClipRRect(
        borderRadius: radius,
        clipBehavior: clipBehavior,
        child: panel,
      );
    }
    if (margin != null) {
      panel = Padding(padding: margin!, child: panel);
    }
    return panel;
  }
}

/// Convenience: wrap chrome that already had BlurEffect + translucent surface.
class GlassChrome extends StatelessWidget {
  const GlassChrome({
    super.key,
    required this.child,
    this.borderRadius,
    this.color,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (!Glass.shouldBlur(context)) {
      return Material(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: borderRadius,
        child: child,
      );
    }
    return GlassSurface(
      borderRadius: borderRadius,
      color: color ?? Glass.fillColor(context),
      elevationShadow: false,
      showMesh: false,
      child: child,
    );
  }
}

/// Theme-aware glass card for settings lists (replaces opaque Material Card).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.margin,
    this.padding,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    final body = GlassSurface(
      borderRadius: radius,
      margin: margin ?? const EdgeInsets.only(bottom: 8),
      padding: padding,
      elevationShadow: true,
      showMesh: true,
      child: Material(
        color: Colors.transparent,
        child: onTap == null
            ? child
            : InkWell(
                borderRadius: radius,
                onTap: onTap,
                child: child,
              ),
      ),
    );
    return body;
  }
}
