import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Note placed on the staff. `createdAtMs` drives the stamp-in animation.
class Note {
  final String emoji;
  int gridX; // mutable so a placed note can be dragged to a new cell
  int gridY;
  final double rotation;
  int createdAtMs;
  final double velocity; // 0..1, from Apple Pencil pressure (1.0 = full)
  Note(this.emoji, this.gridX, this.gridY, this.rotation, this.createdAtMs, {this.velocity = 1.0});
}

/// Geometry shared by the painter and hit-testing so taps line up with pixels.
class StaffMetrics {
  final double width, height, padLeft, marginY, stepX, stepY;
  final int cols, rows;
  StaffMetrics._(this.width, this.height, this.padLeft, this.marginY,
      this.stepX, this.stepY, this.cols, this.rows);

  /// [padLeft] is the frozen clef/label gutter (0 for the handset scrolling
  /// grid, which pins that gutter as a separate widget). [fixedStepX] pins a
  /// column width (handset horizontal scroll) instead of dividing the width.
  factory StaffMetrics.of(Size size, int cols, int rows,
      {double padLeft = 88.0, double? fixedStepX}) {
    const marginY = 40.0;
    return StaffMetrics._(
      size.width, size.height, padLeft, marginY,
      fixedStepX ?? (size.width - padLeft) / cols,
      (size.height - marginY * 2) / (rows - 1),
      cols, rows,
    );
  }

  /// The pinned clef/label gutter is 88pt wide.
  static const double gutter = 88.0;

  Offset cellCenter(int gx, int gy) =>
      Offset(padLeft + gx * stepX + stepX / 2, marginY + gy * stepY);

  /// Pixel -> (gridX, gridY), or null if outside the staff area.
  (int, int)? hitTest(Offset p) {
    if (p.dx < padLeft) return null;
    final gx = ((p.dx - padLeft) / stepX).floor();
    final gy = ((p.dy - marginY) / stepY).round();
    if (gx < 0 || gx >= cols || gy < 0 || gy >= rows) return null;
    return (gx, gy);
  }
}

class StaffPainter extends CustomPainter {
  final List<Note> notes;
  final int cols;
  final int rows;
  final bool isPlaying;
  final int currentStep;
  final double playheadFrac; // 0..1 across all columns
  final int tMs; // for animations
  final int cursorStep; // MIDI shuttle scrub column when stopped; -1 = none
  final List<String>? rowLabels; // per-row pitch names (scale mode); null = free
  final bool showClef;
  final Color bgColor;
  final bool reduceMotion; // iOS "Reduce Motion": drop the bounce + stamp-in
  final double padLeft; // frozen clef/label gutter; 0 for the handset scroll grid
  final bool drawGutter; // false = grid only (clef/labels live in a pinned gutter)
  final double? fixedStepX; // pin a column width (handset horizontal scroll)

  // Rows that get a bold staff line (matches the web app's MAIN_STAFF_LINES).
  static const _mainLines = {1, 3, 5, 7, 9, 11, 13};

  StaffPainter({
    required this.notes,
    required this.cols,
    required this.rows,
    required this.isPlaying,
    required this.currentStep,
    required this.playheadFrac,
    required this.tMs,
    this.cursorStep = -1,
    this.rowLabels,
    this.showClef = true,
    this.bgColor = Colors.white,
    this.reduceMotion = false,
    this.padLeft = 88.0,
    this.drawGutter = true,
    this.fixedStepX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final m = StaffMetrics.of(size, cols, rows,
        padLeft: padLeft, fixedStepX: fixedStepX);
    // The scrolling grid (no gutter) runs its staff lines edge-to-edge so they
    // meet the pinned gutter flush; the full staff insets them.
    final lineL = drawGutter ? 20.0 : 0.0;
    final lineR = size.width - (drawGutter ? 20.0 : 0.0);

    canvas.drawRect(Offset.zero & size, Paint()..color = bgColor);

    // Vertical grid lines
    final grid = Paint()
      ..color = const Color(0xFFE0F7FA)
      ..strokeWidth = 1;
    for (var i = 0; i <= cols; i++) {
      final x = m.padLeft + i * m.stepX;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }

    // Horizontal staff lines (only odd rows, per the app)
    for (var i = 0; i < rows; i++) {
      if (i.isOdd) {
        final y = m.marginY + i * m.stepY;
        final main = _mainLines.contains(i);
        final p = Paint()
          ..color = main ? const Color(0xFF90A4AE) : const Color(0xFFECEFF1)
          ..strokeWidth = main ? 4 : 2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(lineL, y), Offset(lineR, y), p);
      }
    }

    // Treble clef (Free mode) or per-row pitch labels (scale mode).
    if (showClef) {
      _paintClef(canvas, m.stepY * 11,
          Offset(m.padLeft / 2 - m.stepY * 2.4, m.marginY + m.stepY * 2.5),
          playing: isPlaying, tMs: tMs);
    }
    final labels = rowLabels;
    if (labels != null) {
      final fs = (m.stepY * 0.6).clamp(10.0, 22.0).toDouble();
      for (var i = 0; i < rows && i < labels.length; i++) {
        final tp = _staffGlyph(labels[i], fs, const Color(0xFF78909C));
        tp.paint(canvas, Offset((m.padLeft - tp.width) / 2, m.marginY + i * m.stepY - tp.height / 2));
      }
    }

    // Shuttle cursor (when stopped) — a soft amber column marker
    if (!isPlaying && cursorStep >= 0 && cursorStep < cols) {
      final x = m.padLeft + cursorStep * m.stepX;
      canvas.drawRect(Rect.fromLTWH(x, 0, m.stepX, size.height),
          Paint()..color = const Color(0x33FFD740));
      canvas.drawLine(Offset(x + m.stepX / 2, 0), Offset(x + m.stepX / 2, size.height),
          Paint()
            ..color = const Color(0xFFFFD740)
            ..strokeWidth = 3);
    }

    // Playhead
    if (isPlaying) {
      final x = m.padLeft + (playheadFrac * cols) * m.stepX;
      canvas.drawRect(Rect.fromLTWH(x, 0, m.stepX, size.height),
          Paint()..color = const Color(0x1AFF4081));
      canvas.drawLine(Offset(x + m.stepX / 2, 0), Offset(x + m.stepX / 2, size.height),
          Paint()
            ..color = const Color(0xFFFF4081)
            ..strokeWidth = 4);
    }

    // Notes
    final size0 = m.stepY * 1.9;
    for (final n in notes) {
      final c = m.cellCenter(n.gridX, n.gridY);
      final active = isPlaying && n.gridX == currentStep;

      double scale = 1;
      double dy = 0;
      final age = tMs - n.createdAtMs;
      if (active) {
        scale = 1.18;
        dy = reduceMotion ? 0 : -(math.sin(tMs * 0.015).abs()) * 10;
      } else if (!reduceMotion && age < 320) {
        final t = age / 320.0;
        scale = t < 0.5 ? 0.6 + t * 2 * 0.6 : 1.2 - (t - 0.5) * 2 * 0.2;
      }

      // Rasterize the glyph at its FINAL pixel size (rounded, so the cache
      // stays bounded) rather than scaling the canvas — scaling a raster glyph
      // up is what made animated notes look fuzzy.
      final fs = (size0 * scale).roundToDouble();
      canvas.save();
      canvas.translate(c.dx, c.dy + dy);
      canvas.rotate(n.rotation);
      _staffGlyph(n.emoji, fs, const Color(0x33000000)).paint(canvas, Offset(-fs / 2 + 2, -fs / 2 + 3));
      _staffGlyph(n.emoji, fs, null).paint(canvas, Offset(-fs / 2, -fs / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant StaffPainter old) => true; // driven by a ticker
}

/// The frozen clef + pitch-label gutter, drawn as its own widget on handsets so
/// it stays pinned while the note grid scrolls horizontally beside it. Shares
/// [StaffPainter]'s row geometry so the staff lines line up exactly.
class StaffGutterPainter extends CustomPainter {
  final int rows;
  final List<String>? rowLabels;
  final bool showClef;
  final bool isPlaying;
  final int tMs;
  StaffGutterPainter(
      {required this.rows,
      this.rowLabels,
      this.showClef = true,
      this.isPlaying = false,
      this.tMs = 0});

  static const _mainLines = {1, 3, 5, 7, 9, 11, 13};

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || rows < 2) return;
    const marginY = 40.0;
    final stepY = (size.height - marginY * 2) / (rows - 1);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    // Line stubs (odd rows) that meet the scrolling grid flush at the right edge.
    for (var i = 0; i < rows; i++) {
      if (i.isOdd) {
        final y = marginY + i * stepY;
        final main = _mainLines.contains(i);
        canvas.drawLine(
          Offset(20, y),
          Offset(size.width, y),
          Paint()
            ..color = main ? const Color(0xFF90A4AE) : const Color(0xFFECEFF1)
            ..strokeWidth = main ? 4 : 2
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    if (showClef) {
      _paintClef(canvas, stepY * 11,
          Offset(size.width / 2 - stepY * 2.4, marginY + stepY * 2.5),
          playing: isPlaying, tMs: tMs);
    }
    final labels = rowLabels;
    if (labels != null) {
      final fs = (stepY * 0.6).clamp(10.0, 22.0).toDouble();
      for (var i = 0; i < rows && i < labels.length; i++) {
        final tp = _staffGlyph(labels[i], fs, const Color(0xFF78909C));
        tp.paint(canvas, Offset((size.width - tp.width) / 2, marginY + i * stepY - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant StaffGutterPainter old) =>
      isPlaying ||
      old.isPlaying ||
      old.rows != rows ||
      old.showClef != showClef ||
      old.rowLabels != rowLabels;
}

/// A torn-paper right edge for the pinned clef gutter, so the notes read as
/// scrolling *under* the ripped edge of the staff paper. The paper fills the
/// left; the right edge is a ragged tear that casts a soft shadow onto the
/// notes sliding beneath it.
class TornEdgePainter extends CustomPainter {
  final Color paper;
  const TornEdgePainter({this.paper = Colors.white});

  // Deterministic ragged silhouette (0 = tear pulled in, 1 = paper reaches far).
  static const _jag = <double>[
    0.32, 0.86, 0.5, 1.0, 0.4, 0.72, 0.58, 0.94, 0.44, 0.8, 0.52, 0.9, 0.6, 1.0, 0.38, 0.7,
  ];

  Path _tear(Size size) {
    final w = size.width, h = size.height;
    double x(int i) => w * (0.4 + 0.6 * _jag[i % _jag.length]);
    const seg = 15.0;
    final path = Path()
      ..moveTo(0, -2)
      ..lineTo(x(0), -2);
    var i = 1;
    for (var y = seg; y < h; y += seg, i++) {
      path.lineTo(x(i), y);
    }
    path
      ..lineTo(x(i), h + 2)
      ..lineTo(0, h + 2)
      ..close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _tear(size);
    // Shadow the torn paper casts onto the notes scrolling under it.
    canvas.drawPath(
      path.shift(const Offset(3, 0)),
      Paint()
        ..color = const Color(0x38000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(path, Paint()..color = paper);
  }

  @override
  bool shouldRepaint(covariant TornEdgePainter old) => old.paper != paper;
}

// Soft rainbow that slowly rotates over the treble clef while a song plays.
// Alpha < 1 (srcATOP over the dark ink) keeps it colourful but not neon; the
// first and last colours match so the sweep loops seamlessly.
const List<Color> _clefRainbow = [
  Color(0xD9FF5E7E), // pink-red
  Color(0xD9FFA24B), // orange
  Color(0xD9FFD54A), // yellow
  Color(0xD955C97A), // green
  Color(0xD94FB0F0), // blue
  Color(0xD99B7BF0), // violet
  Color(0xD9FF5E7E), // back to pink-red
];

/// Paints the treble clef. While [playing], tints it with a gentle, slowly
/// rotating rainbow (a full turn every ~5s); otherwise draws it in solid ink.
void _paintClef(Canvas canvas, double fontSize, Offset offset,
    {required bool playing, required int tMs}) {
  final tp = _staffGlyph('𝄞', fontSize, const Color(0xFF37474F));
  if (!playing) {
    tp.paint(canvas, offset);
    return;
  }
  final rect = offset & Size(tp.width, tp.height);
  canvas.saveLayer(rect, Paint());
  tp.paint(canvas, offset); // dark clef = alpha mask (+ a touch of ink shows)
  final phase = (tMs / 5000.0) * 2 * math.pi;
  final shader = SweepGradient(
    colors: _clefRainbow,
    transform: GradientRotation(phase),
  ).createShader(rect);
  canvas.drawRect(
      rect,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.srcATop);
  canvas.restore();
}

final Map<String, TextPainter> _glyphCache = {};
TextPainter _staffGlyph(String s, double fontSize, Color? shadow) {
  final key = '$s|${fontSize.toStringAsFixed(1)}|${shadow == null ? 0 : 1}';
  return _glyphCache.putIfAbsent(key, () {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: fontSize, color: shadow), // null => full-color emoji
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp;
  });
}
