import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A small number of OS-composited chrome surfaces, never scrolling list cells.
class AppleNativeGlass {
  static const channel = MethodChannel('venera/native_glass');
  static bool supported = false;

  static Future<void> initialize() async {
    supported = false;
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS))
      return;
    try {
      supported = await channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      supported = false;
    } on MissingPluginException {
      supported = false;
    }
  }
}

class AppleGlassSurface extends StatefulWidget {
  const AppleGlassSurface({super.key, required this.child, this.radius = 0});
  final Widget child;
  final double radius;

  @override
  State<AppleGlassSurface> createState() => _AppleGlassSurfaceState();
}

class _AppleGlassSurfaceState extends State<AppleGlassSurface> {
  MethodChannel? _viewChannel;
  Map<String, Object>? _lastParams;

  Map<String, Object> _params() => {
    'radius': widget.radius,
    'dark': Theme.of(context).brightness == Brightness.dark,
  };

  void _update() {
    if (_viewChannel == null || !mounted) return;
    final params = _params();
    if (mapEquals(params, _lastParams)) return;
    _lastParams = params;
    _viewChannel!
        .invokeMethod<void>('update', params)
        .catchError((Object _) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(covariant AppleGlassSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void dispose() {
    _viewChannel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void created(int id) {
      if (!mounted) return;
      _viewChannel = MethodChannel('venera/native_glass/$id');
      _update();
    }

    final Widget background = defaultTargetPlatform == TargetPlatform.macOS
        ? AppKitView(
            viewType: 'venera/native_glass_surface',
            creationParams: _params(),
            creationParamsCodec: const StandardMessageCodec(),
            hitTestBehavior: PlatformViewHitTestBehavior.transparent,
            onPlatformViewCreated: created,
          )
        : UiKitView(
            viewType: 'venera/native_glass_surface',
            creationParams: _params(),
            creationParamsCodec: const StandardMessageCodec(),
            hitTestBehavior: PlatformViewHitTestBehavior.transparent,
            onPlatformViewCreated: created,
          );
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(child: ExcludeSemantics(child: background)),
        ),
        widget.child,
      ],
    );
  }
}
