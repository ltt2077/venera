import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// System UIKit tab/navigation controls. Content stays in Flutter.
class NativeGlassDock {
  NativeGlassDock._();
  static const channel = MethodChannel('venera/native_dock');
  static final rootObserver = NativeChromeRouteObserver();
  static bool? _supported;
  static void Function(int)? _onSelect;
  static void Function(int)? _onAction;
  static Map<String, Object>? _arguments;
  static String? _signature;
  static bool _requestedVisible = false;
  static bool _blocked = false;
  static bool _active = true;
  static Future<void> _pending = Future.value();

  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool get supportUnknown => _supported == null;

  static Future<bool> isSupported() async {
    if (!isIOS) return false;
    if (_supported != null) return _supported!;
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        _supported = await channel.invokeMethod<bool>('isSupported') ?? false;
        return _supported!;
      } on MissingPluginException {
        // Registration can finish after Dart starts. Do not cache this as NO.
        if (attempt < 5)
          await Future<void>.delayed(const Duration(milliseconds: 50));
      } on PlatformException {
        return false;
      }
    }
    return false;
  }

  static void bind({
    required void Function(int) onSelect,
    required void Function(int) onAction,
  }) {
    _onSelect = onSelect;
    _onAction = onAction;
    channel.setMethodCallHandler((call) async {
      if (!_requestedVisible || _blocked || !_active) return null;
      final argument = call.arguments;
      if (argument is! int) return null;
      if (call.method == 'onSelect') _onSelect?.call(argument);
      if (call.method == 'onAction') _onAction?.call(argument);
      return null;
    });
  }

  static Future<void> show({
    required List<String> labels,
    required List<String> symbols,
    required List<String> actionLabels,
    required List<String> actionSymbols,
    required int index,
    required bool dark,
    required int tint,
    required bool visible,
  }) {
    _arguments = {
      'labels': labels,
      'symbols': symbols,
      'actionLabels': actionLabels,
      'actionSymbols': actionSymbols,
      'index': index,
      'dark': dark,
      'tint': tint,
    };
    _requestedVisible = visible;
    return _synchronize();
  }

  static Future<void> setIndex(int index) {
    if (_arguments != null) _arguments = {..._arguments!, 'index': index};
    return _synchronize();
  }

  static Future<void> setVisible(bool visible) {
    if (_requestedVisible == visible) return _pending;
    _requestedVisible = visible;
    return _synchronize();
  }

  static Future<void> setAppActive(bool active) {
    if (_active == active) return _pending;
    _active = active;
    return _synchronize();
  }

  static Future<void> _setBlocked(bool blocked) {
    if (_blocked == blocked) return _pending;
    _blocked = blocked;
    return _synchronize();
  }

  static Future<void> hide() => setVisible(false);

  static Future<void> _synchronize() {
    _pending = _pending.then((_) async {
      if (!isIOS) return;
      final visible =
          _requestedVisible && !_blocked && _active && _arguments != null;
      final signature = visible ? jsonEncode(_arguments) : 'hidden';
      if (_signature == signature) return;
      try {
        if (visible) {
          final attached = await channel.invokeMethod<bool>('show', _arguments);
          if (attached == true) _signature = signature;
        } else {
          await channel.invokeMethod<void>('hide');
          _signature = signature;
        }
      } on MissingPluginException {
        _signature = null;
      } on PlatformException {
        _signature = null;
      }
    });
    return _pending;
  }

  static void unbind() {
    _onSelect = null;
    _onAction = null;
    hide();
  }

  @visibleForTesting
  static Future<void> resetForTesting() async {
    await _pending;
    _supported = null;
    _arguments = null;
    _signature = null;
    _requestedVisible = false;
    _blocked = false;
    _active = true;
    _onSelect = null;
    _onAction = null;
    rootObserver.clear();
    channel.setMethodCallHandler(null);
  }

  static String symbolForName(String label, IconData icon) {
    final text = label.toLowerCase();
    if (icon.codePoint == Icons.home.codePoint ||
        icon.codePoint == Icons.home_outlined.codePoint)
      return 'house';
    if (icon.codePoint == Icons.local_activity.codePoint ||
        icon.codePoint == Icons.local_activity_outlined.codePoint)
      return 'heart';
    if (icon.codePoint == Icons.explore.codePoint ||
        icon.codePoint == Icons.explore_outlined.codePoint)
      return 'safari';
    if (icon.codePoint == Icons.category.codePoint ||
        icon.codePoint == Icons.category_outlined.codePoint)
      return 'square.grid.2x2';
    if (icon.codePoint == Icons.search.codePoint) return 'magnifyingglass';
    if (icon.codePoint == Icons.settings.codePoint) return 'gearshape';
    if (text.contains('home')) return 'house';
    return 'circle';
  }
}

class NativeChromeRouteObserver extends NavigatorObserver {
  final _routes = <Route<dynamic>>{};
  void _changed() => NativeGlassDock._setBlocked(_routes.length > 1);
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _routes.remove(oldRoute);
    if (newRoute != null) _routes.add(newRoute);
    _changed();
  }

  @visibleForTesting
  void clear() => _routes.clear();
}
