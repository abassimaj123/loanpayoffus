// Run with: flutter test test/gen_icons_test.dart
// Skipped on CI (Windows-only absolute paths)
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _rentBuyPath = r'D:\mob\RentBuyUS\android\app\src\main\res';
const _loanPath = r'D:\mob\LoanPayoffUS\android\app\src\main\res';

const _fontPath =
    r'C:\Users\DALI\AppData\Local\Pub\Cache\hosted\pub.dev\provider-6.1.5+1\extension\devtools\build\assets\fonts\MaterialIcons-Regular.otf';

const _densities = [
  ('mipmap-mdpi', 48),
  ('mipmap-hdpi', 72),
  ('mipmap-xhdpi', 96),
  ('mipmap-xxhdpi', 144),
  ('mipmap-xxxhdpi', 192),
];

Future<void> _loadFont() async {
  final bytes = File(_fontPath).readAsBytesSync();
  final loader = FontLoader('MaterialIcons');
  loader.addFont(Future.value(bytes.buffer.asByteData()));
  await loader.load();
}

Future<Uint8List> _capture(
  WidgetTester tester,
  IconData icon,
  List<Color> colors,
  double size,
) async {
  final key = GlobalKey();
  final r = size * 0.22;

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: size,
              height: size,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(r),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Icon(icon, size: size * 0.60, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1.0));
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  return bytes!.buffer.asUint8List();
}

void _write(String resPath, String density, Uint8List bytes) {
  final dir = Directory('$resPath\\$density')..createSync(recursive: true);
  File('${dir.path}\\ic_launcher.png').writeAsBytesSync(bytes);
  File('${dir.path}\\ic_launcher_round.png').writeAsBytesSync(bytes);
  debugPrint('  ✓ $density');
}

void main() {
  // Skip entirely on non-Windows (CI uses Linux — hardcoded D:\ paths don't exist)
  if (!Platform.isWindows) return;

  setUpAll(() async => _loadFont());

  const rbColors = [Color(0xFF00897B), Color(0xFF004D40)];
  const lpColors = [Color(0xFF512DA8), Color(0xFF311B92)];

  group('RentBuyUS icons', () {
    for (final (density, size) in _densities) {
      testWidgets(density, (t) async {
        t.view.physicalSize = const Size(1024, 1024);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.resetPhysicalSize);
        final bytes = await _capture(
          t,
          Icons.home_work_rounded,
          rbColors,
          size.toDouble(),
        );
        _write(_rentBuyPath, density, bytes);
      }, timeout: const Timeout(Duration(seconds: 30)));
    }
    testWidgets('splash 512', (t) async {
      t.view.physicalSize = const Size(1024, 1024);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      final bytes = await _capture(t, Icons.home_work_rounded, rbColors, 512);
      File('$_rentBuyPath\\drawable\\ic_splash.png').writeAsBytesSync(bytes);
      debugPrint('  ✓ splash 512px');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('LoanPayoffUS icons', () {
    for (final (density, size) in _densities) {
      testWidgets(density, (t) async {
        t.view.physicalSize = const Size(1024, 1024);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.resetPhysicalSize);
        final bytes = await _capture(
          t,
          Icons.monetization_on_rounded,
          lpColors,
          size.toDouble(),
        );
        _write(_loanPath, density, bytes);
      }, timeout: const Timeout(Duration(seconds: 30)));
    }
    testWidgets('splash 512', (t) async {
      t.view.physicalSize = const Size(1024, 1024);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      final bytes = await _capture(
        t,
        Icons.monetization_on_rounded,
        lpColors,
        512,
      );
      File('$_loanPath\\drawable\\ic_splash.png').writeAsBytesSync(bytes);
      debugPrint('  ✓ splash 512px');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
