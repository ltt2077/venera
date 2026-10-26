part of 'components.dart';

class PopUpWidget<T> extends PopupRoute<T> {
  PopUpWidget(this.widget);

  final Widget widget;

  @override
  Color? get barrierColor => Colors.black54;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => "exit";

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    var height = MediaQuery.of(context).size.height * 0.9;
    bool showPopUp = MediaQuery.of(context).size.width > 500;
    final glassOn = Glass.shouldBlur(context);
    Widget page = Navigator(
      onGenerateRoute: (settings) => PageRouteBuilder(
        settings: settings,
        opaque: !glassOn,
        pageBuilder: (context, animation, secondaryAnimation) => widget,
      ),
    );
    Widget sheet = Container(
      decoration: showPopUp
          ? BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              boxShadow: context.brightness == ui.Brightness.dark
                  ? [
                      BoxShadow(
                        color: Colors.white.withAlpha(50),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.toOpacity(0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
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
                  ? const BorderRadius.all(Radius.circular(12))
                  : BorderRadius.zero,
              elevationShadow: false,
              opacity: App.isAndroid ? 0.55 : null,
              child: page,
            )
          : Material(child: page),
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
    final header = Container(
            height: 56 + context.padding.top,
            padding: EdgeInsets.only(top: context.padding.top),
            width: double.infinity,
            decoration: BoxDecoration(
              color: glassOn
                  ? Glass.fillColor(context)
                  : (top
                      ? null
                      : Theme.of(context).colorScheme.surfaceTint.withAlpha(20)),
              border: glassOn
                  ? Border(
                      bottom: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .toOpacity(0.4),
                        width: 0.6,
                      ),
                    )
                  : null,
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 8,
                ),
                Tooltip(
                  message: "Back".tl,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_sharp),
                    onPressed: () =>
                        context.canPop() ? context.pop() : App.pop(),
                  ),
                ),
                const SizedBox(
                  width: 16,
                ),
                Text(
                  widget.title,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                if (widget.tailing != null) ...widget.tailing!,
                const SizedBox(width: 8),
              ],
            ),
          );
    final column = Column(
        children: [
          glassOn
              ? BlurEffect(blur: Glass.blurSigma(context), child: header)
              : header,
          NotificationListener<ScrollNotification>(
            onNotification: (notifications) {
              if (notifications.metrics.axisDirection != AxisDirection.down) {
                return false;
              }
              if (notifications.metrics.pixels ==
                      notifications.metrics.minScrollExtent &&
                  !top) {
                setState(() {
                  top = true;
                });
              } else if (notifications.metrics.pixels !=
                      notifications.metrics.minScrollExtent &&
                  top) {
                setState(() {
                  top = false;
                });
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
    if (glassOn) {
      return Material(color: Colors.transparent, child: column);
    }
    return Material(child: column);
  }
}
