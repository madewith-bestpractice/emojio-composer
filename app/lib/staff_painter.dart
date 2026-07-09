import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Note placed on the staff. `createdAtMs` drives the stamp-in animation.
class Note {
  final String emoji;
  final int gridX;
  final int gridY;
  final double rotation;
  int createdAtMs;
  Note(this.emoji, this.gridX, this.gridY, this.rotation, this.createdAtMs);
}

/// Geometry shared by the painter and hit-testing so taps line up with pixels.
class StaffMetrics {
  final double width, height, padLeft, marginY, stepX, stepY;
  final int cols, rows;
  StaffMetrics._(this.width, this.height, this.padLeft, this.marginY,
      this.stepX, this.stepY, this.cols, this.rows);

  factory StaffMetrics.of(Size size, int cols, int rows) {
    const padLeft = 88.0, marginY = 40.0;
    return StaffMetrics._(
      size.width, size.height, padLeft, marginY,
      (size.width - padLeft) / cols,
      (size.height - marginY * 2) / (rows - 1),
      cols, rows,
    );
  }

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

  // Rows that get a bold staff line (matches the web app's MAIN_STAFF_LINES).
  static const _mainLines = {1, 3, 5, 7, 9, 11, 13};
  static final Map<String, TextPainter> _glyphCache = {};

  StaffPainter({
    required this.notes,
    required this.cols,
    required this.rows,
    required this.isPlaying,
    required this.currentStep,
    required this.playheadFrac,
    required this.tMs,
    this.cursorStep = -1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final m = StaffMetrics.of(size, cols, rows);

    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

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
        canvas.drawLine(Offset(20, y), Offset(size.width - 20, y), p);
      }
    }

    // Treble clef
    _glyph('𝄞', m.stepY * 11, const Color(0xFF37474F))
        .paint(canvas, Offset(m.padLeft / 2 - m.stepY * 2.4, m.marginY + m.stepY * 2.5));

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
        dy = -(math.sin(tMs * 0.015).abs()) * 10;
      } else if (age < 320) {
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
      _glyph(n.emoji, fs, const Color(0x33000000)).paint(canvas, Offset(-fs / 2 + 2, -fs / 2 + 3));
      _glyph(n.emoji, fs, null).paint(canvas, Offset(-fs / 2, -fs / 2));
      canvas.restore();
    }
  }

  TextPainter _glyph(String s, double fontSize, Color? shadow) {
    final key = '$s|${fontSize.toStringAsFixed(1)}|${shadow == null ? 0 : 1}';
    return _glyphCache.putIfAbsent(key, () {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            fontSize: fontSize,
            color: shadow, // null => full-color emoji glyph
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp;
    });
  }

  @override
  bool shouldRepaint(covariant StaffPainter old) => true; // driven by a ticker
}
