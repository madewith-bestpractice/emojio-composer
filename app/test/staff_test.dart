import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:emojio/staff_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('treble staff', () {
    final scale =
        (jsonDecode(File('assets/voices/manifest.json').readAsStringSync())
                as Map)['scale']
            as List;

    test('the five lines are F5 D5 B4 G4 E4', () {
      expect([for (final r in kStaffLineRows) scale[r]], [
        'F5',
        'D5',
        'B4',
        'G4',
        'E4',
      ]);
    });

    test('the clef curls round G4', () {
      expect(scale[kGLineRow], 'G4');
    });

    test('ledger lines only below the staff, one per line passed', () {
      for (var r = 0; r <= 10; r++) {
        expect(ledgerRowsFor(r), isEmpty, reason: '${scale[r]}');
      }
      expect(ledgerRowsFor(11), [11]); // C4 sits on one
      expect(ledgerRowsFor(12), [11]); // B3 hangs under it
      expect(ledgerRowsFor(13), [11, 13]); // A3
      expect(ledgerRowsFor(14), [11, 13]); // G3
    });
  });

  group('staff margins', () {
    test('a tablet keeps 40pt', () {
      expect(staffMarginY(1000), 40);
    });

    test('height for a row step inverts the row spacing', () {
      for (final step in [10.0, 24.0, 40.0, 80.0]) {
        final h = staffHeightForStep(step, 15);
        expect((h - 2 * staffMarginY(h)) / 14, closeTo(step, 1e-9));
      }
    });

    test('a short phone staff gives its rows the room', () {
      expect(staffMarginY(400), lessThan(40));
      expect(staffMarginY(100), 16);
    });

    test('a phone staff keeps tappable rows', () {
      final m = StaffMetrics.of(
        Size(1024, staffHeightForStep(24, 15)),
        16,
        15,
        padLeft: 0,
        fixedStepX: 64,
      );
      expect(m.stepY, closeTo(24, 1e-9));
      expect(m.hitTest(m.cellCenter(3, 14)), (3, 14));
    });
  });

  test('paints low notes with ledger lines without throwing', () {
    final recorder = ui.PictureRecorder();
    StaffPainter(
      notes: [Note('🐶', 0, 14, 0, 0), Note('🐱', 15, 11, 0, 0)],
      cols: 16,
      rows: 15,
      isPlaying: true,
      currentStep: 0,
      playheadFrac: 0,
      tMs: 0,
      ledgers: true,
    ).paint(Canvas(recorder), const Size(390, 420));
    recorder.endRecording().dispose();
  });
}
