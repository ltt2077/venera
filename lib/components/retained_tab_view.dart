import 'package:flutter/widgets.dart';

/// Builds tabs on first visit and retains their state with inactive tickers off.
class RetainedTabView extends StatefulWidget {
  const RetainedTabView({
    super.key,
    required this.index,
    required this.itemCount,
    required this.itemBuilder,
  }) : assert(itemCount > 0),
       assert(index >= 0 && index < itemCount);

  final int index;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<RetainedTabView> createState() => _RetainedTabViewState();
}

class _RetainedTabViewState extends State<RetainedTabView> {
  final _visited = <int>{};

  @override
  void initState() {
    super.initState();
    _visited.add(widget.index);
  }

  @override
  void didUpdateWidget(covariant RetainedTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.removeWhere((i) => i >= widget.itemCount);
    _visited.add(widget.index);
  }

  @override
  Widget build(BuildContext context) => IndexedStack(
    index: widget.index,
    sizing: StackFit.expand,
    children: List.generate(widget.itemCount, (i) {
      if (!_visited.contains(i)) return const SizedBox.shrink();
      return TickerMode(
        key: ValueKey(i),
        enabled: i == widget.index,
        child: Builder(builder: (context) => widget.itemBuilder(context, i)),
      );
    }),
  );
}
