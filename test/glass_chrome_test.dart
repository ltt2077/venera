import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/apple_native_glass.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/appdata.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    AppleNativeGlass.supported = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  testWidgets('reduced motion and high contrast disable profiled blur', (
    tester,
  ) async {
    appdata.settings['liquidGlass'] = true;
    for (final media in [
      const MediaQueryData(disableAnimations: true),
      const MediaQueryData(highContrast: true),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: media,
            child: const BlurEffect(
              useGlassProfile: true,
              child: SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(AppleGlassSurface), findsNothing);
    }
  });

  testWidgets('an empty context menu does not create a broken route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMenuX(context, const Offset(100, 100), []),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('native flyout uses one surface and keeps its actions tappable', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    AppleNativeGlass.supported = true;
    appdata.settings['liquidGlass'] = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform_views,
          (_) async => null,
        );
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: FlyoutContent(
            title: 'Flyout',
            content: const Text('Content'),
            actions: [
              TextButton(onPressed: () => taps++, child: const Text('Apply')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AppleGlassSurface), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.tap(find.text('Apply'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
