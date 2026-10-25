part of 'components.dart';

/// Liquid-glass helpers. Toggle via settings key `liquidGlass` (default ON).
/// Platform profiles:
/// - iOS: stronger blur, lighter fill, soft highlight border (Cupertino-like)
/// - Android: Material translucent surfaces + dynamic color harmony
/// - macOS/Windows/Linux: acrylic / mica-like denser blur for sidebars, title bar, sheets
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
    // Fall back to opaque surfaces under high-contrast / bold-text a11y modes.
    if (mq.highContrast || mq.boldText) return false;
    return true;
  }

  static double blurSigma(BuildContext context) {
    if (!shouldBlur(context)) return 0;
    if (App.isIOS) return 28;
    if (App.isMacOS) return 40; // desktop acrylic
    if (App.isWindows || App.isLinux) return 36;
    return 24; // Android Material glass
  }

  static double fillOpacity(BuildContext context) {
    if (!shouldBlur(context)) return 1.0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (App.isIOS) return dark ? 0.55 : 0.62;
    if (App.isMacOS) return dark ? 0.48 : 0.58; // frosted title/sidebar
    if (App.isWindows || App.isLinux) return dark ? 0.52 : 0.64;
    return dark ? 0.72 : 0.78; // Android slightly denser
  }

  static Color fillColor(BuildContext context, {Color? base}) {
    final scheme = Theme.of(context).colorScheme;
    final c = base ?? scheme.surface;
    return c.toOpacity(fillOpacity(context));
  }

  static Border? highlightBorder(BuildContext context, {double radius = 12}) {
    if (!shouldBlur(context)) return null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    if (App.isIOS || App.isMacOS) {
      return Border.all(
        color: dark
            ? Colors.white.toOpacity(0.18)
            : Colors.white.toOpacity(0.55),
        width: 0.6,
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
        color: Colors.black.toOpacity(dark ? 0.28 : 0.08),
        blurRadius: App.isDesktop ? 24 : 16,
        offset: const Offset(0, 8),
      ),
    ];
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

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.zero;
    final useGlass = Glass.shouldBlur(context);
    final sigma = blur ?? (useGlass ? Glass.blurSigma(context) : 0);
    final fill = color ??
        Theme.of(context).colorScheme.surface.toOpacity(
              opacity ?? (useGlass ? Glass.fillOpacity(context) : 1.0),
            );
    final boxBorder = border ?? Glass.highlightBorder(context);

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius == BorderRadius.zero ? null : radius,
        border: boxBorder,
        boxShadow: elevationShadow ? Glass.softShadow(context) : null,
      ),
      child: child,
    );

    if (sigma > 0) {
      content = BlurEffect(
        blur: sigma,
        borderRadius: radius == BorderRadius.zero ? null : radius,
        child: content,
      );
    } else if (radius != BorderRadius.zero) {
      content = ClipRRect(
        borderRadius: radius,
        clipBehavior: clipBehavior,
        child: content,
      );
    }

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }
    return content;
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
      child: child,
    );
  }
}
