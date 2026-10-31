import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// OS-composited chrome via UIGlassEffect / NSGlassEffectView platform views.
class AppleNativeGlass {
  static const channel = MethodChannel('venera/native_glass');
  static bool supported = false;
  static bool _checked = false;

  static Future<void> initialize() async {
    supported = false;
    _checked = false;
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      _checked = true;
      return;
    }
    // UIScene / implicit engine can register channels slightly after Dart starts.
    for (var i = 0; i < 20; i++) {
      try {
        supported = await channel.invokeMethod<bool>('isSupported') ?? false;
        _checked = true;
        if (supported || i >= 5) return;
      } on MissingPluginException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      } on PlatformException {
        supported = false;
        _checked = true;
        return;
      }
    }
    _checked = true;
  }

  /// Lazy re-probe if startup raced the native registrar.
  static Future<bool> ensureSupported() async {
    if (_checked && supported) return true;
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      return false;
    }
    try {
      supported = await channel.invokeMethod<bool>('isSupported') ?? false;
      _checked = true;
    } on MissingPluginException {
      // keep prior
    } on PlatformException {
      supported = false;
      _checked = true;
    }
    return supported;
  }
}

class AppleGlassSurface extends StatefulWidget {
  const AppleGlassSurface({
    super.key,
    required this.child,
    this.radius = 0,
    this.interactive,
    this.style = 'regular',
  });
  final Widget child;
  final double radius;
  /// When null, interactive defaults to true for rounded chrome (dock / cards).
  final bool? interactive;
  final String style;

  @override
  State<AppleGlassSurface> createState() => _AppleGlassSurfaceState();
}

class _AppleGlassSurfaceState extends State<AppleGlassSurface> {
  MethodChannel? _viewChannel;
  Map<String, Object>? _lastParams;

  Map<String, Object> _params() => {
        'radius': widget.radius,
        'dark': Theme.of(context).brightness == Brightness.dark,
        'interactive': widget.interactive ?? widget.radius > 0,
        'style': widget.style,
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
  void initState() {
    super.initState();
    // Re-check support after first frame in case startup raced registration.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final was = AppleNativeGlass.supported;
      await AppleNativeGlass.ensureSupported();
      if (mounted && was != AppleNativeGlass.supported) {
        setState(() {});
      }
    });
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
