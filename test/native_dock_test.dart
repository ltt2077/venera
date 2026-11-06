import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/native_dock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await NativeGlassDock.resetForTesting();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeGlassDock.channel, (call) async {
          calls.add(call);
          return call.method == 'isSupported' || call.method == 'show'
              ? true
              : null;
        });
  });
  tearDown(() async {
    await NativeGlassDock.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeGlassDock.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
  Future<void> show() => NativeGlassDock.show(
    labels: ['Home', 'Favorites'],
    symbols: ['house', 'heart'],
    actionLabels: ['Search', 'Settings'],
    actionSymbols: ['magnifyingglass', 'gearshape'],
    index: 0,
    dark: false,
    tint: 0xff0000ff,
    visible: true,
  );

  test(
    'rebuilds keep native controls; index and theme changes still update',
    () async {
      await show();
      await show();
      expect(calls.where((call) => call.method == 'show').length, 1);
      await NativeGlassDock.setIndex(1);
      expect(calls.last.arguments['index'], 1);
      await NativeGlassDock.setIndex(1);
      expect(calls.where((call) => call.method == 'show').length, 2);
    },
  );

  test(
    'root popups hide native controls and restore them after dismissal',
    () async {
      final root = MaterialPageRoute<void>(builder: (_) => const SizedBox());
      final popup = RawDialogRoute<void>(
        pageBuilder: (_, _, _) => const SizedBox(),
      );
      // NavigatorObserver only needs route identity for its presentation count.
      NativeGlassDock.rootObserver.didPush(root, null);
      await show();
      NativeGlassDock.rootObserver.didPush(popup, root);
      await NativeGlassDock.setVisible(true);
      expect(calls.last.method, 'hide');
      NativeGlassDock.rootObserver.didPop(popup, root);
      await NativeGlassDock.setVisible(true);
      expect(calls.last.method, 'show');
    },
  );

  test(
    'backgrounding hides chrome and resume restores the latest selection',
    () async {
      await show();
      await NativeGlassDock.setAppActive(false);
      expect(calls.last.method, 'hide');
      await NativeGlassDock.setIndex(1);
      expect(calls.last.method, 'hide');
      await NativeGlassDock.setAppActive(true);
      expect(calls.last.method, 'show');
      expect(calls.last.arguments['index'], 1);
    },
  );

  test(
    'a missing registrar is not permanently cached as unsupported',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            NativeGlassDock.channel,
            (_) async => throw MissingPluginException(),
          );
      expect(await NativeGlassDock.isSupported(), false);
      expect(NativeGlassDock.supportUnknown, true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeGlassDock.channel, (_) async => true);
      expect(await NativeGlassDock.isSupported(), true);
    },
  );
}
