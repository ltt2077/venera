part of 'components.dart';

/// iOS UIKit overlay dock driven by [VeneraNativeDock] (UIGlassEffect on FlutterView).
/// Not a Flutter UiKitView — those cannot feed Impeller pixels into UIGlassEffect.
class NativeGlassDock {
  NativeGlassDock._();

  static const _channel = MethodChannel('venera/native_dock');
  static bool? _supported;
  static void Function(int index)? _onSelect;
  static bool _handlerBound = false;

  static Future<bool> isSupported() async {
    if (!App.isIOS) return false;
    if (_supported != null) return _supported!;
    try {
      _supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      _supported = false;
    } on PlatformException {
      _supported = false;
    }
    return _supported!;
  }

  static void bind(void Function(int index) onSelect) {
    _onSelect = onSelect;
    if (_handlerBound) return;
    _handlerBound = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSelect') {
        final idx = call.arguments;
        final i = idx is int ? idx : (idx is num ? idx.toInt() : null);
        if (i != null) _onSelect?.call(i);
      }
      return null;
    });
  }

  static Future<void> show({
    required List<String> labels,
    required List<String> symbols,
    required int index,
    required bool dark,
    required double radius,
    required double hPad,
    required double height,
    required double bottomPad,
    required double safeBottom,
  }) async {
    if (!App.isIOS) return;
    try {
      await _channel.invokeMethod<void>('show', {
        'labels': labels,
        'symbols': symbols,
        'index': index,
        'dark': dark,
        'radius': radius,
        'hPad': hPad,
        'height': height,
        'bottomPad': bottomPad,
        'safeBottom': safeBottom,
      });
    } catch (e, s) {
      Log.error('NativeGlassDock', e.toString(), s);
    }
  }

  static Future<void> setIndex(int index) async {
    if (!App.isIOS) return;
    try {
      await _channel.invokeMethod<void>('setIndex', index);
    } catch (_) {}
  }

  static Future<void> hide() async {
    if (!App.isIOS) return;
    try {
      await _channel.invokeMethod<void>('hide');
    } catch (_) {}
  }

  static String symbolForName(String label, IconData icon) {
    final l = label.toLowerCase();
    if (l.contains('home') || l.contains('主页') || l.contains('首页')) return 'house.fill';
    if (l.contains('favorite') || l.contains('收藏') || l.contains('local_activity')) {
      return 'ticket.fill';
    }
    if (l.contains('explore') || l.contains('发现') || l.contains('探索')) return 'safari.fill';
    if (l.contains('categor') || l.contains('分类')) return 'square.grid.2x2.fill';
    final n = icon.codePoint;
    if (n == Icons.home.codePoint || n == Icons.home_outlined.codePoint) return 'house.fill';
    if (n == Icons.local_activity.codePoint || n == Icons.local_activity_outlined.codePoint) {
      return 'ticket.fill';
    }
    if (n == Icons.explore.codePoint || n == Icons.explore_outlined.codePoint) return 'safari.fill';
    if (n == Icons.category.codePoint || n == Icons.category_outlined.codePoint) {
      return 'square.grid.2x2.fill';
    }
    return 'circle.fill';
  }
}

