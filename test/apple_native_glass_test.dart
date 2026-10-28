import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/apple_native_glass.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    AppleNativeGlass.supported = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppleNativeGlass.channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  test(
    'Apple systems select native effects only after a capability reply',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            AppleNativeGlass.channel,
            (call) async => true,
          );
      await AppleNativeGlass.initialize();
      expect(AppleNativeGlass.supported, true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            AppleNativeGlass.channel,
            (call) async => false,
          );
      await AppleNativeGlass.initialize();
      expect(AppleNativeGlass.supported, false);
    },
  );

  test(
    'missing plugins and non-Apple systems keep the existing fallback',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await AppleNativeGlass.initialize();
      expect(AppleNativeGlass.supported, false);
      AppleNativeGlass.supported = true;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await AppleNativeGlass.initialize();
      expect(AppleNativeGlass.supported, false);
    },
  );

  testWidgets(
    'decorative native glass does not intercept Flutter button taps',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform_views,
            (_) async => null,
          );
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: AppleGlassSurface(
              radius: 20,
              child: SizedBox(
                width: 200,
                height: 60,
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('Tap'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Tap'));
      expect(taps, 1);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
