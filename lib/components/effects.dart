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
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.mirror,
        ),
        child: child,
      ),
    );
  }
}
