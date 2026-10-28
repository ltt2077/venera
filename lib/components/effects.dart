part of 'components.dart';

class BlurEffect extends StatelessWidget {
  final Widget child;

  final double blur;

  final BorderRadius? borderRadius;

  /// When true and [blur] is the default, use [Glass.blurSigma] if liquid glass is on.
  final bool useGlassProfile;

  const BlurEffect({
    required this.child,
    this.borderRadius,
    this.blur = 15,
    this.useGlassProfile = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (useGlassProfile && Glass.usesNative(context)) {
      return GlassSurface(borderRadius: borderRadius, child: child);
    }
    var sigma = blur;
    if (useGlassProfile && Glass.shouldBlur(context)) {
      sigma = Glass.blurSigma(context);
    } else if (!Glass.enabled && useGlassProfile) {
      sigma = 0;
    }
    if (sigma <= 0) {
      if (borderRadius != null) {
        return ClipRRect(
          borderRadius: borderRadius!,
          child: child,
        );
      }
      return child;
    }
    // Clip + BackdropFilter. On Android, prefer clamp tile mode — mirror can
    // look like a solid slab when Impeller samples edge pixels aggressively.
    final tile = App.isAndroid ? TileMode.clamp : TileMode.mirror;
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: tile,
        ),
        child: child,
      ),
    );
  }
}
