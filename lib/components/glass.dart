part of 'components.dart';

/// Liquid-glass helpers backed by [liquid_glass_widgets] (real shader glass).
/// Toggle via settings key `liquidGlass` (default ON).
///
/// Quality strategy (Android mid-range first):
/// - Nav / app bars → [GlassQuality.premium] (or adaptive downgrade)
/// - Sheets / popups → [GlassQuality.standard]
/// - Dense list cards (Cloud Sync rows) → [GlassQuality.minimal]
class Glass {
  Glass._();

  static bool usesNative(BuildContext context) =>
      AppleNativeGlass.supported && shouldBlur(context);

  static bool get enabled {
    final v = appdata.settings['liquidGlass'];
    if (v is bool) return v;
    return true;
  }

  static bool shouldBlur(BuildContext context) {
    if (!enabled) return false;
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return true;
    if (mq.highContrast || mq.boldText || mq.disableAnimations) return false;
    return true;
  }

  static double _num(String key, double fallback) {
    final v = appdata.settings[key];
    if (v is num) return v.toDouble();
    return fallback;
  }

  static String get qualityMode {
    final v = appdata.settings['liquidGlassQuality'];
    if (v is String && v.isNotEmpty) return v;
    return 'adaptive';
  }

  /// Resolve quality for a chrome tier. Fixed presets override adaptive.
  static GlassQuality qualityFor({GlassQuality preferred = GlassQuality.standard}) {
    switch (qualityMode) {
      case 'premium':
        return GlassQuality.premium;
      case 'standard':
        return GlassQuality.standard;
      case 'minimal':
        return GlassQuality.minimal;
      default:
        return preferred;
    }
  }

  static double get dockHPad => _num('liquidGlassDockMargin', 16);
  static double get dockRadius => _num('liquidGlassDockRadius', 28);

  static LiquidGlassSettings settingsFor(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark
        ? LiquidGlassSettings.ios27Dark
        : LiquidGlassSettings.ios27Light;

    final blur = _num('liquidGlassBlur', base.blur);
    final frost = _num('liquidGlassFrost', base.frost);
    final thickness = _num('liquidGlassThickness', base.thickness);
    final refraction = _num('liquidGlassRefraction', base.refractiveIndex);
    final specular = _num('liquidGlassSpecular', base.rimLight);
    var opacity = _num('liquidGlassOpacity', base.glassColor.a);
    // Factory default in appdata is the light ios27 alpha (0.53). In dark mode
    // keep the package dark tint until the user moves the slider.
    if (dark && (opacity - 0.53).abs() < 0.001) {
      opacity = base.glassColor.a;
    }

    final baseColor = base.glassColor;
    final tint = baseColor.withValues(alpha: opacity.clamp(0.0, 1.0));

    return base.copyWith(
      blur: blur,
      frost: frost,
      thickness: thickness,
      refractiveIndex: refraction,
      rimLight: specular,
      lightIntensity: (specular * 0.35).clamp(0.0, 1.5),
      glowIntensity: (0.4 + specular * 0.4).clamp(0.0, 1.5),
      glassColor: tint,
    );
  }

  static GlassThemeData themeData() {
    // Prefer last known theme via settings-driven numbers only.
    final blur = _num('liquidGlassBlur', 0.6);
    final thickness = _num('liquidGlassThickness', 32);
    final q = qualityFor(preferred: GlassQuality.standard);
    return GlassThemeData.simple(
      blur: blur < 1 ? blur * 12 : blur, // theme helper expects softer scale
      thickness: thickness,
      quality: q,
    );
  }

  static void resetParams() {
    const defaults = {
      'liquidGlassBlur': 0.6,
      'liquidGlassFrost': 14.0,
      'liquidGlassOpacity': 0.53,
      'liquidGlassThickness': 32.0,
      'liquidGlassRefraction': 1.24,
      'liquidGlassSpecular': 1.0,
      'liquidGlassDockMargin': 16.0,
      'liquidGlassDockRadius': 28.0,
      'liquidGlassQuality': 'adaptive',
    };
    for (final e in defaults.entries) {
      appdata.settings[e.key] = e.value;
    }
    appdata.saveData();
  }

  static LiquidShape shape({double radius = 14}) =>
      LiquidRoundedSuperellipse(borderRadius: radius);

  /// Soft aurora wallpaper so refractive glass has colorful content to sample.
  /// Not a fake glass substitute — only a backdrop for the package shaders.
  static Widget wallpaper(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? [
                    scheme.surface,
                    Color.lerp(scheme.surface, scheme.primary, 0.35)!,
                    Color.lerp(scheme.surface, scheme.tertiary, 0.28)!,
                    scheme.surface,
                  ]
                : [
                    Color.lerp(Colors.white, scheme.primary, 0.18)!,
                    Color.lerp(Colors.white, scheme.secondary, 0.22)!,
                    Color.lerp(Colors.white, scheme.tertiary, 0.16)!,
                    Color.lerp(Colors.white, scheme.primary, 0.10)!,
                  ],
            stops: const [0.0, 0.35, 0.7, 1.0],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: -80,
              right: -40,
              child: _orb(220, scheme.primary.toOpacity(dark ? 0.45 : 0.32)),
            ),
            Positioned(
              bottom: -60,
              left: -50,
              child: _orb(260, scheme.tertiary.toOpacity(dark ? 0.38 : 0.26)),
            ),
            Positioned(
              top: 180,
              left: 40,
              child: _orb(140, scheme.secondary.toOpacity(dark ? 0.30 : 0.20)),
            ),
            // Soft vignette keeps text readable over bright orbs.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.15,
                  colors: [
                    Colors.transparent,
                    (dark ? Colors.black : Colors.white).toOpacity(dark ? 0.35 : 0.18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _orb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.toOpacity(0)]),
      ),
    );
  }

  // ---- legacy helpers kept for call sites that still read opacities ----
  static double blurSigma(BuildContext context) {
    if (!shouldBlur(context)) return 0;
    return 24;
  }

  static double fillOpacity(BuildContext context) {
    if (!shouldBlur(context)) return 1.0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? 0.28 : 0.34;
  }

  static Color fillColor(BuildContext context, {Color? base}) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = base ??
        (dark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest);
    return c.toOpacity(fillOpacity(context));
  }

  static Border? highlightBorder(BuildContext context, {double radius = 12}) {
    if (!shouldBlur(context)) return null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Border.all(
      color: Colors.white.toOpacity(dark ? 0.22 : 0.55),
      width: 0.7,
    );
  }

  static List<BoxShadow> softShadow(BuildContext context) {
    if (!shouldBlur(context)) return const [];
    final dark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.toOpacity(dark ? 0.28 : 0.08),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ];
  }
}

/// Soft full-screen aurora used behind transparent scaffolds.
class GlassWallpaper extends StatelessWidget {
  const GlassWallpaper({super.key});

  @override
  Widget build(BuildContext context) => Glass.wallpaper(context);
}

/// Frosted / refractive glass panel for nav chrome, sheets, cards.
/// Uses [AdaptiveGlass] from liquid_glass_widgets when enabled.
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
    this.quality = GlassQuality.standard,
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
  final bool showMesh;
  final GlassQuality quality;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.zero;
    final r = radius == BorderRadius.zero
        ? 0.0
        : (radius.topLeft.x > 0 ? radius.topLeft.x : 14.0);

    if (!Glass.shouldBlur(context)) {
      Widget panel = Material(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: radius == BorderRadius.zero ? null : radius,
        child: padding == null ? child : Padding(padding: padding!, child: child),
      );
      if (margin != null) panel = Padding(padding: margin!, child: panel);
      return panel;
    }

    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    if (Glass.usesNative(context)) {
      Widget native = AppleGlassSurface(
        radius: r,
        interactive: r > 0,
        style: 'regular',
        child: content,
      );
      if (margin != null) native = Padding(padding: margin!, child: native);
      return native;
    }

    final glass = AdaptiveGlass(
      shape: r > 0
          ? LiquidRoundedSuperellipse(borderRadius: r)
          : const LiquidRoundedRectangle(borderRadius: 0),
      settings: Glass.settingsFor(context),
      quality: Glass.qualityFor(preferred: quality),
      useOwnLayer: true,
      clipBehavior: clipBehavior,
      allowElevation: elevationShadow,
      child: content,
    );

    if (margin != null) {
      return Padding(padding: margin!, child: glass);
    }
    return glass;
  }
}

/// Convenience chrome wrapper (nav / app bars) — premium quality.
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
      color: color,
      elevationShadow: false,
      quality: Glass.qualityFor(preferred: GlassQuality.premium),
      child: child,
    );
  }
}

/// Theme-aware glass card for settings lists.
/// Uses package [GlassContainer.card] at [GlassQuality.minimal] so scrolling
/// Cloud Sync / settings lists stay smooth on mid Android.
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

    // Dense cells use a cheap theme fill; embedding a native view per row would
    // add hybrid-composition synchronization and defeat the chrome optimization.
    if (Glass.usesNative(context)) {
      return Card(
        color: Theme.of(context).colorScheme.surfaceContainerHigh.withValues(alpha: 0.72),
        margin: margin ?? const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: padding == null ? child : Padding(padding: padding!, child: child),
        ),
      );
    }

    if (!Glass.shouldBlur(context)) {
      return Card(
        margin: margin ?? const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: padding == null ? child : Padding(padding: padding!, child: child),
        ),
      );
    }

    Widget body = GlassContainer.card(
      useOwnLayer: true,
      quality: Glass.qualityFor(preferred: GlassQuality.minimal),
      settings: Glass.settingsFor(context),
      padding: padding ?? EdgeInsets.zero,
      margin: margin ?? const EdgeInsets.only(bottom: 8),
      shape: LiquidRoundedSuperellipse(borderRadius: 14),
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
