// Schermate PNG della Dashboard e del login a varie dimensioni, per GUARDARE
// il layout adattivo. Fuori da test/ apposta: la CI non lo esegue, e i PNG
// non si confrontano con nulla. Si lancia a mano:
//
//   flutter test tool/screenshots/layout_screenshots_test.dart --update-goldens
//
// e le immagini finiscono in tool/screenshots/out/ (da non committare).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:astroarch_interface/screens/login_screen.dart';
import 'package:astroarch_interface/screens/shell_screen.dart';
import 'package:astroarch_interface/state/app_state.dart';

Future<void> _font(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return;
  final bytes = f.readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
}

Future<void> _loadFonts() async {
  // Roboto, il font predefinito, non e' nell'app: lo sostituisco con Exo2,
  // che c'e', solo perche' nelle immagini si legga il testo.
  await _font('Roboto', 'assets/fonts/exo2/Exo2.ttf');
  await _font('Exo2', 'assets/fonts/exo2/Exo2.ttf');
  await _font('Antonio', 'assets/fonts/antonio/Antonio.ttf');
  await _font('Misa13', 'assets/fonts/13misa/13_Misa.ttf');
  for (final root in [
    Platform.environment['FLUTTER_ROOT'] ?? '',
    r'C:\src\flutter\flutter',
  ]) {
    final p = '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
    if (File(p).existsSync()) {
      await _font('MaterialIcons', p);
      break;
    }
  }
}

Future<void> _shot(WidgetTester tester, Size size, Widget home, String name) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
    value: AppState(),
    child: MaterialApp(debugShowCheckedModeBanner: false, home: home),
  ));
  await tester.pump(const Duration(milliseconds: 500));
  await expectLater(find.byType(MaterialApp),
      matchesGoldenFile('out/${name}_${size.width.toInt()}x${size.height.toInt()}.png'));
}

void main() {
  setUpAll(_loadFonts);
  const sizes = [
    Size(390, 844),   // telefono
    Size(800, 360),   // telefono in orizzontale
    Size(820, 1180),  // tablet verticale
    Size(1440, 900),  // Mac
    Size(1920, 1080), // monitor
    Size(2560, 1440), // monitor grande
  ];
  for (final s in sizes) {
    testWidgets('dashboard ${s.width.toInt()}x${s.height.toInt()}', (t) => _shot(t, s, const ShellScreen(), 'dashboard'));
  }
  for (final s in const [Size(390, 844), Size(1920, 1080)]) {
    testWidgets('login ${s.width.toInt()}x${s.height.toInt()}', (t) => _shot(t, s, const LoginScreen(), 'login'));
  }
}
