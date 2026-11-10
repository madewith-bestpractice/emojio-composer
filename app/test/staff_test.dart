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
      expect(
        [for (final r in kStaffLineRows) scale[r]],
        ['F5', 'D5', 'B4', 'G4', 'E4'],
      );
    });

    test('the clef curls round G4', () {
      expect(scale[kGLineRow], 'G4');
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

  test('paints notes below the staff without throwing', () {
    final recorder = ui.PictureRecorder();
    StaffPainter(
      notes: [Note('🐶', 0, 14, 0, 0), Note('🐱', 15, 11, 0, 0)],
      cols: 16,
      rows: 15,
      isPlaying: true,
      currentStep: 0,
      playheadFrac: 0,
      tMs: 0,
    ).paint(Canvas(recorder), const Size(390, 420));
    recorder.endRecording().dispose();
  });
}
