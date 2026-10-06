import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Note placed on the staff. `createdAtMs` drives the stamp-in animation.
class Note {
  final String emoji;
  int gridX; // mutable so a placed note can be dragged to a new cell
  int gridY;
  int pitchOffset; // -1 flat, 0 natural, +1 sharp
  bool pitchEdited; // true once the pitch was explicitly chosen
  final double rotation;
  int createdAtMs;
  final double velocity; // 0..1, from Apple Pencil pressure (1.0 = full)
  Note(
    this.emoji,
    this.gridX,
    this.gridY,
    this.rotation,
    this.createdAtMs, {
    this.velocity = 1.0,
    this.pitchOffset = 0,
    this.pitchEdited = false,
  });
}

/// Space above the top row and below the bottom one. 40pt on a tablet; a short
/// phone staff gets less so its rows aren't squeezed to nothing.
double staffMarginY(double height) => (height * 0.06).clamp(16.0, 40.0);

/// The staff height whose rows come out exactly [stepY] apart, margins
/// included (the inverse of [StaffMetrics]'s row spacing).
double staffHeightForStep(double stepY, int rows) {
  final inner = (rows - 1) * stepY;
  // The margin is 16 on a short staff, 6% of the height mid-range, 40 when tall.
  for (final h in [inner + 32, inner / 0.88, inner + 80]) {
    if ((staffMarginY(h) * 2 - (h - inner)).abs() < 1e-6) return h;
  }
  return inner + 80;
}

/// Rows (indices into the manifest scale, G5 at the top) that carry the five
/// treble-staff lines, F5 D5 B4 G4 E4. The other odd rows (C4, A3) sit on
/// ledger lines.
const kStaffLineRows = {1, 3, 5, 7, 9};

/// The treble clef's curl wraps the G4 line.
const kGLineRow = 7;

/// Ledger lines a note on [row] needs: every odd row between the staff and it.
List<int> ledgerRowsFor(int row) => [for (var r = 11; r <= row; r += 2) r];

/// Geometry shared by the painter and hit-testing so taps line up with pixels.
class StaffMetrics {
  final double width, height, padLeft, marginY, stepX, stepY;
  final int cols, rows;
  StaffMetrics._(
    this.width,
    this.height,
    this.padLeft,
    this.marginY,
    this.stepX,
    this.stepY,
    this.cols,
    this.rows,
  );

  /// [padLeft] is the frozen clef/label gutter (0 for the handset scrolling
  /// grid, which pins that gutter as a separate widget). [fixedStepX] pins a
  /// column width (handset horizontal scroll) instead of dividing the width.
  factory StaffMetrics.of(
    Size size,
    int cols,
    int rows, {
    double padLeft = 88.0,
    double? fixedStepX,
  }) {
    final marginY = staffMarginY(size.height);
    return StaffMetrics._(
      size.width,
      size.height,
      padLeft,
      marginY,
      fixedStepX ?? (size.width - padLeft) / cols,
      (size.height - marginY * 2) / (rows - 1),
      cols,
      rows,
    );
  }

  /// The pinned handset clef/label gutter: wide enough for a treble clef that
  /// spans the staff.
  static const double gutter = 112.0;

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
  final List<String>?
  rowLabels; // per-row pitch names (scale mode); null = free
  final bool showClef;
  final Color bgColor;
  final bool reduceMotion; // iOS "Reduce Motion": drop the bounce + stamp-in
  final double
  padLeft; // frozen clef/label gutter; 0 for the handset scroll grid
  final bool
  drawGutter; // false = grid only (clef/labels live in a pinned gutter)
  final double? fixedStepX; // pin a column width (handset horizontal scroll)
  final bool ledgers; // free (treble) mode: ledger lines under low notes

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
    this.ledgers = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final m = StaffMetrics.of(
      size,
      cols,
      rows,
      padLeft: padLeft,
      fixedStepX: fixedStepX,
    );
    // The scrolling grid (no gutter) runs its staff lines edge-to-edge so they
    // meet the pinned gutter flush; the full staff insets them.
    final lineL = drawGutter ? 20.0 : 0.0;
    final lineR = size.width - (drawGutter ? 20.0 : 0.0);

    canvas.drawRect(Offset.zero & size, Paint()..color = bgColor);

    // Vertical grid lines
    final grid = Paint()
      ..color = const Color(0xFFE0F7FA)
      ..strokeWidth = 1;
    // Every 4th line is a beat (16 steps = one bar of 4/4).
    final beat = Paint()
      ..color = const Color(0xFFB2EBF2)
      ..strokeWidth = 2;
    for (var i = 0; i <= cols; i++) {
      final x = m.padLeft + i * m.stepX;
      final onBeat = i % 4 == 0 && i > 0 && i < cols;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), onBeat ? beat : grid);
    }

    paintStaffLines(canvas, lineL, lineR, m.stepY, rows, m.marginY);
    _paintEndRepeat(canvas, lineR, m);

    // Treble clef (Free mode) or per-row pitch labels (scale mode).
    if (showClef) {
      paintClef(
        canvas,
        stepY: m.stepY,
        marginY: m.marginY,
        gutter: m.padLeft,
        maxWidth: m.padLeft * 1.25,
        playing: isPlaying,
        tMs: tMs,
      );
    }
    final labels = rowLabels;
    if (labels != null) {
      final fs = (m.stepY * 0.6).clamp(10.0, 22.0).toDouble();
      for (var i = 0; i < rows && i < labels.length; i++) {
        final tp = _staffGlyph(labels[i], fs, const Color(0xFF78909C));
        tp.paint(
          canvas,
          Offset(
            (m.padLeft - tp.width) / 2,
            m.marginY + i * m.stepY - tp.height / 2,
          ),
        );
      }
    }

    // Shuttle cursor (when stopped) — a soft amber column marker
    if (!isPlaying && cursorStep >= 0 && cursorStep < cols) {
      final x = m.padLeft + cursorStep * m.stepX;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, m.stepX, size.height),
        Paint()..color = const Color(0x33FFD740),
      );
      canvas.drawLine(
        Offset(x + m.stepX / 2, 0),
        Offset(x + m.stepX / 2, size.height),
        Paint()
          ..color = const Color(0xFFFFD740)
          ..strokeWidth = 3,
      );
    }

    // Playhead
    if (isPlaying) {
      final x = m.padLeft + (playheadFrac * cols) * m.stepX;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, m.stepX, size.height),
        Paint()..color = const Color(0x1AFF4081),
      );
      canvas.drawLine(
        Offset(x + m.stepX / 2, 0),
        Offset(x + m.stepX / 2, size.height),
        Paint()
          ..color = const Color(0xFFFF4081)
          ..strokeWidth = 4,
      );
    }

    // Notes. Ledger lines go down first so every note sits on top of them.
    final size0 = m.stepY * 1.9;
    if (ledgers) {
      final ledger = Paint()
        ..color = const Color(0xFF90A4AE)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (final n in notes) {
        final cx = m.cellCenter(n.gridX, n.gridY).dx;
        for (final r in ledgerRowsFor(n.gridY)) {
          final y = m.marginY + r * m.stepY;
          canvas.drawLine(
            Offset(cx - size0 * 0.65, y),
            Offset(cx + size0 * 0.65, y),
            ledger,
          );
        }
      }
    }
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
      _staffGlyph(
        n.emoji,
        fs,
        const Color(0x33000000),
      ).paint(canvas, Offset(-fs / 2 + 2, -fs / 2 + 3));
      _staffGlyph(n.emoji, fs, null).paint(canvas, Offset(-fs / 2, -fs / 2));
      canvas.restore();
      if (n.pitchEdited) {
        _paintAccidental(canvas, n.pitchOffset, Offset(c.dx, c.dy + dy), size0);
      }
    }
  }

  @override
  bool shouldRepaint(covariant StaffPainter old) => true; // driven by a ticker
}

void _paintAccidental(
  Canvas canvas,
  int pitchOffset,
  Offset center,
  double noteSize,
) {
  final label = pitchOffset < 0
      ? 'b'
      : pitchOffset > 0
      ? '#'
      : '♮';
  final badgeR = (noteSize * 0.23).clamp(8.0, 15.0).toDouble();
  final badgeC = center + Offset(noteSize * 0.45, -noteSize * 0.45);
  canvas.drawCircle(
    badgeC + const Offset(2, 2),
    badgeR,
    Paint()..color = const Color(0x33000000),
  );
  canvas.drawCircle(badgeC, badgeR, Paint()..color = const Color(0xFFFFD740));
  canvas.drawCircle(
    badgeC,
    badgeR,
    Paint()
      ..color = const Color(0xFF37474F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
  final tp = _staffGlyph(label, badgeR * 1.35, const Color(0xFF37474F));
  tp.paint(canvas, badgeC - Offset(tp.width / 2, tp.height / 2));
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
  StaffGutterPainter({
    required this.rows,
    this.rowLabels,
    this.showClef = true,
    this.isPlaying = false,
    this.tMs = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || rows < 2) return;
    final marginY = staffMarginY(size.height);
    final stepY = (size.height - marginY * 2) / (rows - 1);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    // Line stubs that meet the scrolling grid flush at the right edge.
    paintStaffLines(canvas, 20, size.width, stepY, rows, marginY);
    if (showClef) {
      paintClef(
        canvas,
        stepY: stepY,
        marginY: marginY,
        gutter: size.width,
        maxWidth: size.width - 8,
        playing: isPlaying,
        tMs: tMs,
      );
    }
    final labels = rowLabels;
    if (labels != null) {
      final fs = (stepY * 0.6).clamp(10.0, 22.0).toDouble();
      for (var i = 0; i < rows && i < labels.length; i++) {
        final tp = _staffGlyph(labels[i], fs, const Color(0xFF78909C));
        tp.paint(
          canvas,
          Offset(
            (size.width - tp.width) / 2,
            marginY + i * stepY - tp.height / 2,
          ),
        );
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

/// The staff's ruled lines: the five treble-staff lines solid, and the ledger
/// rows below (C4, A3) as faint dashed guides so those rows are still easy to
/// aim at. Shared so the grid, the pinned gutter and the torn edge that
/// continues it can't drift apart.
void paintStaffLines(
  Canvas canvas,
  double x0,
  double x1,
  double stepY,
  int rows,
  double marginY,
) {
  final line = Paint()
    ..color = const Color(0xFF90A4AE)
    ..strokeWidth = 4
    ..strokeCap = StrokeCap.round;
  final guide = Paint()
    ..color = const Color(0xFFCFD8DC)
    ..strokeWidth = 2;
  for (var i = 1; i < rows; i += 2) {
    final y = marginY + i * stepY;
    if (kStaffLineRows.contains(i)) {
      canvas.drawLine(Offset(x0, y), Offset(x1, y), line);
    } else {
      for (var x = x0; x < x1; x += 14) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 7, x1), y), guide);
      }
    }
  }
}

/// End-repeat barline at [x]: dots, a thin line and a thick one across the
/// five staff lines, since the 16 steps loop.
void _paintEndRepeat(Canvas canvas, double x, StaffMetrics m) {
  final ink = Paint()..color = const Color(0xFF90A4AE);
  final top = m.marginY + kStaffLineRows.first * m.stepY;
  final bottom = m.marginY + kStaffLineRows.last * m.stepY;
  canvas.drawRect(Rect.fromLTRB(x - 6, top, x, bottom), ink);
  canvas.drawRect(Rect.fromLTRB(x - 12, top, x - 10, bottom), ink);
  final r = (m.stepY * 0.22).clamp(2.5, 6.0).toDouble();
  for (final row in const [4, 6]) {
    canvas.drawCircle(Offset(x - 20, m.marginY + row * m.stepY), r, ink);
  }
}

/// A torn-paper right edge for the pinned clef gutter, so the notes read as
/// scrolling *under* the ripped edge of the staff paper. The paper fills the
/// left; the right edge is a ragged tear that casts a soft shadow onto the
/// notes sliding beneath it.
class TornEdgePainter extends CustomPainter {
  final Color paper;

  /// Row count, so the staff lines can be carried across the torn paper and
  /// cut off by the rip itself.
  final int rows;
  const TornEdgePainter({required this.rows, this.paper = Colors.white});

  // Deterministic ragged silhouette (0 = tear pulled in, 1 = paper reaches far).
  static const _jag = <double>[
    0.32,
    0.86,
    0.5,
    1.0,
    0.4,
    0.72,
    0.58,
    0.94,
    0.44,
    0.8,
    0.52,
    0.9,
    0.6,
    1.0,
    0.38,
    0.7,
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

    // The staff lines are printed on the paper, so carry them across the torn
    // strip and let the rip cut them off. Without this the tear reads as a blank
    // white margin tacked onto the end of the staff. Shares the gutter's row
    // geometry (same height, same marginY) so the lines meet it exactly.
    if (rows < 2 || size.height <= 0) return;
    canvas.save();
    canvas.clipPath(path);
    final marginY = staffMarginY(size.height);
    paintStaffLines(
      canvas,
      0,
      size.width,
      (size.height - marginY * 2) / (rows - 1),
      rows,
      marginY,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TornEdgePainter old) =>
      old.paper != paper || old.rows != rows;
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

/// Paints the treble clef with its curl on the G line, as in real notation.
/// The glyph is Bravura's (bundled as EmojioClef): SMuFL puts the G line on the
/// baseline and the outline spans 2.684 x 7.024 staff spaces. Where the staff
/// is tall it's drawn under true size, no wider than [maxWidth], so it doesn't
/// cover the first columns. While [playing], tints it
/// with a gentle, slowly rotating rainbow (a full turn every ~5s); otherwise
/// draws it in solid ink.
void paintClef(
  Canvas canvas, {
  required double stepY,
  required double marginY,
  required double gutter,
  required double maxWidth,
  required bool playing,
  required int tMs,
}) {
  // One clef staff space: 1.5 rows (a touch under the true two, so the clef
  // stays inside the margins), capped at [maxWidth].
  final space = math.min(stepY * 1.5, maxWidth / 2.684);
  final tp = _clefGlyph(space * 4); // SMuFL: 1 em = 4 staff spaces
  final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  final offset = Offset(
    math.max(4.0, (gutter - tp.width) / 2),
    marginY + kGLineRow * stepY - baseline,
  );
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
      ..blendMode = BlendMode.srcATop,
  );
  canvas.restore();
}

final Map<double, TextPainter> _clefCache = {};
TextPainter _clefGlyph(double fontSize) {
  final fs = fontSize.roundToDouble();
  return _clefCache.putIfAbsent(
    fs,
    () => TextPainter(
      text: TextSpan(
        text: '\uE050', // SMuFL gClef
        style: TextStyle(
          fontFamily: 'EmojioClef',
          fontSize: fs,
          color: const Color(0xFF37474F),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(),
  );
}

final Map<String, TextPainter> _glyphCache = {};
TextPainter _staffGlyph(String s, double fontSize, Color? shadow) {
  final key = '$s|${fontSize.toStringAsFixed(1)}|${shadow == null ? 0 : 1}';
  return _glyphCache.putIfAbsent(key, () {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: fontSize,
          color: shadow,
        ), // null => full-color emoji
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp;
  });
}
