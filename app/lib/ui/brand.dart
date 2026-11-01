import 'dart:math';

import 'package:flutter/material.dart';

/// The VocabApp mark: two stacked flashcards on a teal tile, the front one
/// carrying a V that doubles as a tick ("remembered"). Painted, not an image,
/// so the window, tray and launcher icons are rendered from this same code
/// (`test/tool/brand_icons_test.dart`).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: const BrandMarkPainter());
}

class BrandMarkPainter extends CustomPainter {
  const BrandMarkPainter({this.tile = true, this.inset = 0});

  /// False paints the cards only (Android adaptive-icon foreground).
  final bool tile;

  /// Fraction of the side kept empty around the glyph.
  final double inset;

  static const teal = Color(0xff0b7469);
  static const tealDeep = Color(0xff08564f);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (tile) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.23)),
        Paint()..color = teal,
      );
    }
    final g = s * (1 - 2 * inset);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    final card = Rect.fromCenter(
      center: Offset.zero,
      width: g * 0.46,
      height: g * 0.58,
    );
    final corner = Radius.circular(g * 0.07);

    canvas.save();
    canvas.translate(-g * 0.075, -g * 0.02);
    canvas.rotate(-12 * pi / 180);
    canvas.drawRRect(
      RRect.fromRectAndRadius(card, corner),
      Paint()..color = Colors.white.withValues(alpha: 0.42),
    );
    canvas.restore();

    canvas.save();
    canvas.translate(g * 0.07, g * 0.035);
    canvas.rotate(7 * pi / 180);
    canvas.drawRRect(
      RRect.fromRectAndRadius(card.shift(Offset(0, g * 0.012)), corner),
      Paint()..color = tealDeep.withValues(alpha: 0.35),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(card, corner),
      Paint()..color = Colors.white,
    );
    final w = card.width, h = card.height;
    canvas.drawPath(
      Path()
        ..moveTo(-w * 0.27, -h * 0.08)
        ..lineTo(-w * 0.04, h * 0.2)
        ..lineTo(w * 0.3, -h * 0.24),
      Paint()
        ..color = teal
        ..style = PaintingStyle.stroke
        ..strokeWidth = g * 0.068
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(BrandMarkPainter old) =>
      old.tile != tile || old.inset != inset;
}
