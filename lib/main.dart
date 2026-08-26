import 'package:dgis_mobile_sdk_full/dgis.dart' as sdk;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'controls_panel.dart';
import 'frame_hud.dart';
import 'geo.dart';
import 'repro_scene.dart';
import 'repro_settings.dart';
import 'route_data.dart';

const _keyAsset = 'assets/dgissdk.key';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final hasKey = await _hasKey();
  runApp(ReproApp(hasKey: hasKey));
}

Future<bool> _hasKey() async {
  try {
    final data = await rootBundle.load(_keyAsset);
    return data.lengthInBytes > 0;
  } catch (_) {
    return false;
  }
}

class ReproApp extends StatelessWidget {
  const ReproApp({required this.hasKey, super.key});

  final bool hasKey;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '2GIS marker flicker repro',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
    home: hasKey ? const ReproScreen() : const _MissingKeyScreen(),
  );
}

class _MissingKeyScreen extends StatelessWidget {
  const _MissingKeyScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Padding(
      padding: EdgeInsets.all(24),
      child: Center(
        child: Text(
          'Нет ключа SDK.\n\n'
          'Положите свой ключ 2GIS Mobile SDK в файл\n'
          'assets/dgissdk.key\n'
          '(рядом лежит assets/dgissdk.key.example)\n'
          'и пересоберите приложение.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}

class ReproScreen extends StatefulWidget {
  const ReproScreen({super.key});

  @override
  State<ReproScreen> createState() => _ReproScreenState();
}

class _ReproScreenState extends State<ReproScreen> {
  final _settings = ReproSettings();
  final _mapController = sdk.MapWidgetController();
  // Ключ берётся по умолчанию — из assets/dgissdk.key, как в примере SDK.
  late final sdk.Context _sdkContext = sdk.DGis.initialize();

  ReproScene? _scene;
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    _mapController.getMapAsync((map) {
      if (!mounted) return;
      final scene = ReproScene(
        context: _sdkContext,
        map: map,
        settings: _settings,
        devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
      );
      _scene = scene;
      scene.start();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _scene?.dispose();
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = _scene;
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            sdk.MapWidget(
              sdkContext: _sdkContext,
              mapOptions: sdk.MapOptions(
                position: sdk.CameraPosition(
                  point: _toSdkPoint(straightTrack.first),
                  zoom: const sdk.Zoom(16),
                ),
                // Светлая тема принудительно: на ней машина остаётся
                // единственным крупным тёмным объектом, по которому кадры
                // считает tools/darkcount.py.
                appearance: sdk.UniversalAppearance(
                  const sdk.MapTheme.defaultDayTheme(),
                ),
              ),
              controller: _mapController,
            ),
            if (scene != null && _chromeVisible)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FrameHud(stats: scene.stats),
                  WritesHud(stats: scene.stats),
                  const Spacer(),
                  ControlsPanel(settings: _settings),
                ],
              ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton.filledTonal(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  _chromeVisible ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _chromeVisible = !_chromeVisible),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static sdk.GeoPoint _toSdkPoint(LatLng point) => sdk.GeoPoint(
    latitude: sdk.Latitude(point.lat),
    longitude: sdk.Longitude(point.lon),
  );
}
