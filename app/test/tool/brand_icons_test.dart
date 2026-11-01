// Renders the launcher, window and tray icons from BrandMarkPainter.
// Skipped unless BRAND_OUT names an output folder:
//   BRAND_OUT=/tmp/icons flutter test test/tool/brand_icons_test.dart
// then scripts/pack-icons.py places them in android/ and windows/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabapp/ui/brand.dart';

Future<void> _render(String path, int size, BrandMarkPainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), Size.square(size.toDouble()));
  final image = await recorder.endRecording().toImage(size, size);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(path).writeAsBytes(png!.buffer.asUint8List());
}

void main() {
  final out = Platform.environment['BRAND_OUT'];
  testWidgets('render brand icons', skip: out == null, (tester) async {
    await tester.runAsync(() async {
      await Directory(out!).create(recursive: true);
      for (final size in [
        16,
        20,
        24,
        32,
        40,
        48,
        64,
        72,
        96,
        128,
        144,
        192,
        256,
        512,
      ]) {
        await _render('$out/mark-$size.png', size, const BrandMarkPainter());
      }
      // Adaptive icon foreground: 108dp canvas, glyph inside the 66dp safe zone.
      for (final size in [108, 162, 216, 324, 432]) {
        await _render(
          '$out/foreground-$size.png',
          size,
          const BrandMarkPainter(tile: false, inset: 0.17),
        );
      }
    });
  });
}
