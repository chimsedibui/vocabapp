import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Device-local zoom level for the whole UI.
///
/// Stored in a small JSON file next to the database instead of SQLite so it
/// is not carried over by backup/restore to a device with a different screen.
/// Desktop shortcuts: Ctrl + `=`/`+` zooms in, Ctrl + `-` zooms out,
/// Ctrl + `0` resets.
class UiScaleController extends ValueNotifier<double> {
  UiScaleController({double initial = 1, this.file})
    : super(_nearest(initial)) {
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  static const steps = [0.8, 0.9, 1.0, 1.1, 1.25, 1.4, 1.5];
  final File? file;

  static Future<UiScaleController> load(File file) async {
    try {
      final json = jsonDecode(await file.readAsString());
      return UiScaleController(
        initial: (json['ui_scale'] as num).toDouble(),
        file: file,
      );
    } catch (_) {
      return UiScaleController(file: file);
    }
  }

  static double _nearest(double v) =>
      steps.reduce((a, b) => (a - v).abs() <= (b - v).abs() ? a : b);

  bool get canZoomIn => value < steps.last;
  bool get canZoomOut => value > steps.first;
  void zoomIn() => set(steps.firstWhere((s) => s > value, orElse: () => value));
  void zoomOut() => set(steps.lastWhere((s) => s < value, orElse: () => value));
  void reset() => set(1);

  void set(double scale) {
    final next = _nearest(scale);
    if (next == value) return;
    value = next;
    final target = file;
    if (target == null) return;
    // Serialize writes so rapid zooming cannot leave an older value on disk.
    // Best effort: losing the preference must never break the app.
    saved = saved.then(
      (_) => target
          .writeAsString(jsonEncode({'ui_scale': value}))
          .then<void>((_) {}, onError: (_) {}),
    );
  }

  /// Completes when every preference write requested so far has finished.
  Future<void> saved = Future.value();

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !HardwareKeyboard.instance.isControlPressed) {
      return false;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      zoomIn();
    } else if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      zoomOut();
    } else if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0) {
      reset();
    } else {
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }
}

/// Scales every pixel of [child] (text, spacing, icons, dialogs) by [scale].
///
/// The child is laid out in a viewport `1 / scale` the real size and painted
/// enlarged, so responsive breakpoints react to the zoom like a browser does.
class UiZoom extends StatelessWidget {
  const UiZoom({super.key, required this.scale, required this.child});
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (scale == 1) return child;
    final mq = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth / scale, box.maxHeight / scale);
        return Transform.scale(
          scale: scale,
          alignment: Alignment.topLeft,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: size.width,
            maxWidth: size.width,
            minHeight: size.height,
            maxHeight: size.height,
            child: MediaQuery(
              data: mq.copyWith(
                size: size,
                padding: mq.padding / scale,
                viewPadding: mq.viewPadding / scale,
                viewInsets: mq.viewInsets / scale,
                systemGestureInsets: mq.systemGestureInsets / scale,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Lays out [children] in equal-width columns, as many as fit [minTileWidth].
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minTileWidth = 220,
    this.spacing = 12,
    this.maxColumns = 4,
  });
  final List<Widget> children;
  final double minTileWidth, spacing;
  final int maxColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = ((box.maxWidth + spacing) / (minTileWidth + spacing))
          .floor()
          .clamp(1, maxColumns.clamp(1, children.length))
          .toInt();
      final width = (box.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final c in children) SizedBox(width: width, child: c)],
      );
    },
  );
}
