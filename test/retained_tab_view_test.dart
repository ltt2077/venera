import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/retained_tab_view.dart';

class Probe extends StatefulWidget {
  const Probe({super.key});
  @override
  State<Probe> createState() => ProbeState();
}

class ProbeState extends State<Probe> with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  int ticks = 0;
  @override
  void initState() {
    super.initState();
    controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..addListener(() => ticks++)
          ..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  testWidgets(
    'loads only visited tabs and retains state with inactive tickers muted',
    (tester) async {
      final keys = List.generate(4, (_) => GlobalKey<ProbeState>());
      Widget view(int index) => Directionality(
        textDirection: TextDirection.ltr,
        child: RetainedTabView(
          index: index,
          itemCount: 4,
          itemBuilder: (context, i) => Probe(key: keys[i]),
        ),
      );
      await tester.pumpWidget(view(2));
      expect(keys[2].currentState, isNotNull);
      expect(keys[0].currentState, isNull);
      expect(keys[1].currentState, isNull);
      expect(keys[3].currentState, isNull);
      final retained = keys[2].currentState!;
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(view(0));
      final inactiveTicks = retained.ticks;
      await tester.pump(const Duration(milliseconds: 100));
      expect(retained.ticks, inactiveTicks);
      expect(keys[2].currentState, same(retained));
      await tester.pumpWidget(view(2));
      await tester.pump(const Duration(milliseconds: 100));
      expect(keys[2].currentState, same(retained));
      expect(retained.ticks, greaterThan(inactiveTicks));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
