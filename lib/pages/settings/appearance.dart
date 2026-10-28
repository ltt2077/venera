part of 'settings_page.dart';

class AppearanceSettings extends StatefulWidget {
  const AppearanceSettings({super.key});

  @override
  State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  bool get _glassOn => (appdata.settings['liquidGlass'] ?? true) == true;

  void _rebuildGlass() {
    setState(() {});
    App.forceRebuild();
  }

  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Appearance".tl)),
        SelectSetting(
          title: "Theme Mode".tl,
          settingKey: "theme_mode",
          optionTranslation: {
            "system": "System".tl,
            "light": "Light".tl,
            "dark": "Dark".tl,
          },
          onChanged: () async {
            App.forceRebuild();
          },
        ).toSliver(),
        SelectSetting(
          title: "Theme Color".tl,
          settingKey: "color",
          optionTranslation: {
            "system": "System".tl,
            "red": "Red".tl,
            "pink": "Pink".tl,
            "purple": "Purple".tl,
            "green": "Green".tl,
            "orange": "Orange".tl,
            "blue": "Blue".tl,
          },
          onChanged: () async {
            await App.init();
            App.forceRebuild();
          },
        ).toSliver(),
        _SwitchSetting(
          title: "Liquid Glass".tl,
          subtitle:
              "Frosted translucent chrome (iOS / Android / macOS / Windows / Linux)"
                  .tl,
          settingKey: "liquidGlass",
          onChanged: () {
            _rebuildGlass();
          },
        ).toSliver(),
        if (_glassOn) ..._glassParamSlivers(),
      ],
    );
  }

  List<Widget> _glassParamSlivers() {
    final native = Glass.usesNative(context);
    return [
      SliverToBoxAdapter(
        child: ListTile(
          title: Text((native ? "System Glass" : "Liquid Glass Parameters").tl),
          subtitle: Text(
            (native
                    ? "The system manages the material. Dock layout remains adjustable."
                    : "Tune blur, tint, refraction and dock. Changes apply immediately.")
                .tl,
          ),
        ),
      ),
      if (!native) ...[
        SelectSetting(
          title: "Glass Quality".tl,
          settingKey: "liquidGlassQuality",
          optionTranslation: {
            "adaptive": "Adaptive".tl,
            "premium": "Premium (High)".tl,
            "standard": "Standard".tl,
            "minimal": "Power Saving (Minimal)".tl,
          },
          onChanged: _rebuildGlass,
        ).toSliver(),
        _SliderSetting(
          title: "Blur Strength".tl,
          settingsIndex: "liquidGlassBlur",
          min: 0,
          max: 4,
          interval: 0.1,
          onChanged: _rebuildGlass,
        ).toSliver(),
        _SliderSetting(
          title: "Frost Strength".tl,
          settingsIndex: "liquidGlassFrost",
          min: 0,
          max: 30,
          interval: 1,
          onChanged: _rebuildGlass,
        ).toSliver(),
        _SliderSetting(
          title: "Tint Opacity".tl,
          settingsIndex: "liquidGlassOpacity",
          min: 0.05,
          max: 0.95,
          interval: 0.01,
          onChanged: _rebuildGlass,
        ).toSliver(),
        _SliderSetting(
          title: "Thickness / Refraction Depth".tl,
          settingsIndex: "liquidGlassThickness",
          min: 10,
          max: 60,
          interval: 1,
          onChanged: _rebuildGlass,
        ).toSliver(),
        _SliderSetting(
          title: "Refractive Index".tl,
          settingsIndex: "liquidGlassRefraction",
          min: 1.05,
          max: 1.5,
          interval: 0.01,
          onChanged: _rebuildGlass,
        ).toSliver(),
        _SliderSetting(
          title: "Specular / Highlight".tl,
          settingsIndex: "liquidGlassSpecular",
          min: 0,
          max: 2,
          interval: 0.05,
          onChanged: _rebuildGlass,
        ).toSliver(),
      ],
      _SliderSetting(
        title: "Dock Side Margin".tl,
        settingsIndex: "liquidGlassDockMargin",
        min: 4,
        max: 36,
        interval: 1,
        onChanged: _rebuildGlass,
      ).toSliver(),
      _SliderSetting(
        title: "Dock Corner Radius".tl,
        settingsIndex: "liquidGlassDockRadius",
        min: 12,
        max: 40,
        interval: 1,
        onChanged: _rebuildGlass,
      ).toSliver(),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: OutlinedButton.icon(
            onPressed: () {
              Glass.resetParams();
              _rebuildGlass();
              context.showMessage(message: "Reset to defaults".tl);
            },
            icon: const Icon(Icons.restart_alt),
            label: Text("Reset Glass Parameters".tl),
          ),
        ),
      ),
    ];
  }
}
