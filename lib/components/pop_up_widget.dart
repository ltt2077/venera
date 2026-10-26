part of 'components.dart';

class PopUpWidget<T> extends PopupRoute<T> {
  PopUpWidget(this.widget);

  final Widget widget;

  @override
  Color? get barrierColor => Colors.black38;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => "exit";

  @override
  bool get opaque => false;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    var height = MediaQuery.of(context).size.height * 0.9;
    bool showPopUp = MediaQuery.of(context).size.width > 500;
    final glassOn = Glass.shouldBlur(context);
    // Nested navigator for sub-pages inside the sheet. Keep routes OPAQUE so
    // popping the only page cannot leave a blank glass hole (white screen).
    Widget page = Navigator(
      onGenerateRoute: (settings) => PageRouteBuilder(
        settings: settings,
        opaque: true,
        pageBuilder: (context, animation, secondaryAnimation) =>
            _PopUpPageBackground(glassOn: glassOn, child: widget),
      ),
    );
    Widget sheet = Container(
      decoration: showPopUp
          ? BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              boxShadow: context.brightness == ui.Brightness.dark
                  ? [
                      BoxShadow(
                        color: Colors.white.withAlpha(40),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.toOpacity(0.14),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
            )
          : null,
      clipBehavior: showPopUp ? Clip.antiAlias : Clip.none,
      width: showPopUp ? 500 : double.infinity,
      height: showPopUp ? height : double.infinity,
      child: glassOn
          ? GlassSurface(
              borderRadius: showPopUp
                  ? const BorderRadius.all(Radius.circular(16))
                  : BorderRadius.zero,
              elevationShadow: false,
              quality: Glass.qualityFor(preferred: GlassQuality.standard),
              child: page,
            )
          : Material(
              color: Theme.of(context).colorScheme.surface,
              child: page,
            ),
    );
    Widget body = PopupIndicatorWidget(child: sheet);
    if (App.isIOS) {
      body = IOSBackGestureDetector(
        enabledCallback: () => true,
        gestureWidth: 20.0,
        onStartPopGesture: () =>
            IOSBackGestureController(controller!, navigator!),
        child: body,
      );
    }
    if (showPopUp) {
      return MediaQuery.removePadding(
        removeTop: true,
        context: context,
        child: Center(
          child: body,
        ),
      );
    }
    return body;
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 350);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return FadeTransition(
      opacity: animation.drive(
        Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.ease)),
      ),
      child: child,
    );
  }
}

/// Ensures nested navigator pages paint a coherent theme-aware surface so a
/// mistaken inner pop does not flash pure white / black.
class _PopUpPageBackground extends StatelessWidget {
  const _PopUpPageBackground({required this.glassOn, required this.child});

  final bool glassOn;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: glassOn ? Colors.transparent : scheme.surface,
      child: child,
    );
  }
}

class PopupIndicatorWidget extends InheritedWidget {
  const PopupIndicatorWidget({super.key, required super.child});

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) => false;

  static PopupIndicatorWidget? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<PopupIndicatorWidget>();
  }
}

Future<T> showPopUpWidget<T>(BuildContext context, Widget widget) async {
  return await Navigator.of(context, rootNavigator: true)
      .push(PopUpWidget(widget));
}

/// Pop the enclosing [PopUpWidget] route (root navigator), returning [result].
/// Prefer this over [BuildContext.pop] inside pop-up pages — the sheet hosts a
/// nested [Navigator] whose only route must not be popped (that caused the
/// Cloud Sync "Save → white screen" bug).
void popPopUp<T>(BuildContext context, [T? result]) {
  final nav = Navigator.of(context, rootNavigator: true);
  if (nav.canPop()) {
    nav.pop(result);
    return;
  }
  if (context.mounted && Navigator.of(context).canPop()) {
    Navigator.of(context).pop(result);
  }
}

class PopUpWidgetScaffold extends StatefulWidget {
  const PopUpWidgetScaffold(
      {required this.title, required this.body, this.tailing, super.key});

  final Widget body;
  final List<Widget>? tailing;
  final String title;

  @override
  State<PopUpWidgetScaffold> createState() => _PopUpWidgetScaffoldState();
}

class _PopUpWidgetScaffoldState extends State<PopUpWidgetScaffold> {
  bool top = true;

  @override
  Widget build(BuildContext context) {
    final glassOn = Glass.shouldBlur(context);
    final scheme = Theme.of(context).colorScheme;
    final header = Container(
      height: 56 + context.padding.top,
      padding: EdgeInsets.only(top: context.padding.top),
      width: double.infinity,
      decoration: BoxDecoration(
        color: glassOn
            ? Colors.transparent
            : (top ? null : scheme.surfaceTint.withAlpha(20)),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.toOpacity(glassOn ? 0.35 : 0.2),
            width: 0.6,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Tooltip(
            message: "Back".tl,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_sharp),
              onPressed: () => popPopUp(context),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
          ),
          if (widget.tailing != null) ...widget.tailing!,
          const SizedBox(width: 8),
        ],
      ),
    );
    final column = Column(
      children: [
        header,
        NotificationListener<ScrollNotification>(
          onNotification: (notifications) {
            if (notifications.metrics.axisDirection != AxisDirection.down) {
              return false;
            }
            if (notifications.metrics.pixels ==
                    notifications.metrics.minScrollExtent &&
                !top) {
              setState(() => top = true);
            } else if (notifications.metrics.pixels !=
                    notifications.metrics.minScrollExtent &&
                top) {
              setState(() => top = false);
            }
            return false;
          },
          child: MediaQuery.removePadding(
            removeTop: true,
            context: context,
            child: Expanded(child: widget.body),
          ),
        ),
        SizedBox(
          height: MediaQuery.of(context).viewInsets.bottom -
                      0.05 * MediaQuery.of(context).size.height >
                  0
              ? MediaQuery.of(context).viewInsets.bottom -
                  0.05 * MediaQuery.of(context).size.height
              : 0,
        )
      ],
    );
    return Material(
      color: glassOn ? Colors.transparent : scheme.surface,
      child: column,
    );
  }
}
