import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:emojio/layout.dart';
import 'package:emojio/staff_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

DisplayFeature _hinge(Rect r) => DisplayFeature(
  bounds: r,
  type: DisplayFeatureType.hinge,
  state: DisplayFeatureState.postureHalfOpened,
);

const _status = EdgeInsets.only(top: 24, bottom: 20);

void main() {
  group('composer layout', () {
    test('a phone, and a closed iPhone Duo, get the phone composer', () {
      for (final size in const [
        Size(390, 844),
        Size(466, 678),
        Size(844, 390),
      ]) {
        expect(
          ComposerLayout.resolve(size, const []).pose,
          ComposerPose.compact,
          reason: '$size',
        );
      }
    });

    test('the phone header stacks upright and runs in one row on its side', () {
      expect(
        ComposerLayout.resolve(const Size(466, 678), const []).oneRowHeader,
        isFalse,
      );
      expect(
        ComposerLayout.resolve(const Size(844, 390), const []).oneRowHeader,
        isTrue,
      );
    });

    test('an iPad in landscape keeps the tablet composer, with no fold', () {
      final l = ComposerLayout.resolve(const Size(1194, 834), const []);
      expect(l.pose, ComposerPose.regular);
      expect(l.band, isNull);
      expect(l.oneRowHeader, isTrue);
    });

    test('a Duo held like a book keeps clear of its vertical fold', () {
      final l = ComposerLayout.resolve(const Size(951, 669), [
        _hinge(const Rect.fromLTWH(475.5, 0, 0, 669)),
      ]);
      expect(l.pose, ComposerPose.regular);
      expect(l.verticalBand, isNotNull);
      expect(l.verticalBand!.center.dx, 475.5);
      expect(l.verticalBand!.width, kFoldBand);
    });

    test('the same size without a reported fold is laid out like an iPad', () {
      final l = ComposerLayout.resolve(const Size(951, 669), const []);
      expect(l.pose, ComposerPose.regular);
      expect(l.band, isNull);
    });

    test('a wider hinge widens the band', () {
      final l = ComposerLayout.resolve(const Size(951, 669), [
        _hinge(const Rect.fromLTWH(455, 0, 40, 669)),
      ]);
      expect(l.verticalBand!.width, 40);
      expect(l.verticalBand!.center.dx, 475);
    });

    test('a cutout is not a fold', () {
      final l = ComposerLayout.resolve(const Size(951, 669), [
        const DisplayFeature(
          bounds: Rect.fromLTWH(475, 0, 10, 669),
          type: DisplayFeatureType.cutout,
          state: DisplayFeatureState.unknown,
        ),
      ]);
      expect(l.band, isNull);
    });

    test('a Duo on a table splits at its horizontal fold', () {
      final l = ComposerLayout.resolve(const Size(669, 951), [
        _hinge(const Rect.fromLTWH(0, 475.5, 669, 0)),
      ], padding: _status);
      expect(l.pose, ComposerPose.table);
      expect(l.band!.center.dy, 475.5);
      expect(l.band!.height, kFoldBand);
      expect(l.verticalBand, isNull);
    });

    test('a tall window splits at its middle without a reported fold', () {
      final l = ComposerLayout.resolve(
        const Size(834, 1194),
        const [],
        padding: _status,
      );
      expect(l.pose, ComposerPose.table);
      expect(l.band!.center.dy, 597);
    });

    test('a squat upright window keeps the full staff under the header', () {
      final l = ComposerLayout.resolve(const Size(700, 760), const []);
      expect(l.pose, ComposerPose.regular);
      expect(l.band, isNull);
      expect(l.oneRowHeader, isFalse);
    });

    test('a horizontal fold always splits, however short', () {
      final l = ComposerLayout.resolve(const Size(700, 760), [
        _hinge(const Rect.fromLTWH(0, 380, 700, 0)),
      ]);
      expect(l.pose, ComposerPose.table);
    });
  });

  group('orientation requests', () {
    test('phone-sized windows stand upright', () {
      expect(preferredOrientationsFor(const Size(390, 844)), [
        DeviceOrientation.portraitUp,
      ]);
      expect(preferredOrientationsFor(const Size(466, 678)), [
        DeviceOrientation.portraitUp,
      ]);
      // A phone that is on its side right now still asks to stand up.
      expect(preferredOrientationsFor(const Size(844, 390)), [
        DeviceOrientation.portraitUp,
      ]);
    });

    test('roomy windows compose in landscape', () {
      for (final size in const [
        Size(1194, 834),
        Size(834, 1194),
        Size(951, 669),
        Size(669, 951),
      ]) {
        expect(preferredOrientationsFor(size), [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    });

    testWidgets('re-asked when the window changes, as a Duo folds', (
      tester,
    ) async {
      final asked = <List<String>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            asked.add(List<String>.from(call.arguments as List));
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;

      tester.view.physicalSize = const Size(951, 669); // open
      await tester.pumpWidget(
        const MaterialApp(home: OrientationPolicy(child: SizedBox())),
      );
      await tester.pump();
      tester.view.physicalSize = const Size(466, 678); // folded shut
      await tester.pump();
      await tester.pump();
      tester.view.physicalSize = const Size(678, 466); // still the outer one
      await tester.pump();
      await tester.pump();

      expect(asked, [
        ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
        ['DeviceOrientation.portraitUp'],
      ]);
    });
  });

  group('fold bridge', () {
    test('a zero-width fold widens to the band, keeping its centre', () {
      final f = decodeFoldEvent([
        {
          'left': 475.5,
          'top': 0,
          'width': 0,
          'height': 669,
          'state': 'halfOpened',
        },
      ]).single;
      expect(f.bounds, Rect.fromLTWH(475.5 - kFoldBand / 2, 0, kFoldBand, 669));
      expect(f.type, DisplayFeatureType.hinge);
      expect(f.state, DisplayFeatureState.postureHalfOpened);
    });

    test('a horizontal fold widens down and up', () {
      final f = decodeFoldEvent([
        {'left': 0, 'top': 475.5, 'width': 669, 'height': 2, 'state': 'flat'},
      ]).single;
      expect(f.bounds.height, kFoldBand);
      expect(f.bounds.center.dy, 476.5);
      expect(f.state, DisplayFeatureState.postureFlat);
    });

    test('nothing, or garbage, bridges nothing', () {
      expect(decodeFoldEvent(null), isEmpty);
      expect(decodeFoldEvent('x'), isEmpty);
      expect(decodeFoldEvent([1, 'two']), isEmpty);
    });

    testWidgets('a sheet opens on the far side of the fold', (tester) async {
      addTearDown(tester.view.reset);
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(951, 669)
        ..displayFeatures = decodeFoldEvent([
          {'left': 475.5, 'top': 0, 'width': 0, 'height': 669},
        ]);
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      showModalBottomSheet<void>(
        context: ctx,
        anchorPoint: foldAnchor(ctx),
        builder: (_) => const SizedBox(height: 100, child: Text('sheet')),
      );
      await tester.pumpAndSettle();
      final r = tester.getRect(find.byType(BottomSheet));
      expect(r.left, greaterThanOrEqualTo(475.5 + kFoldBand / 2));
    });
  });

  group('staff over a fold', () {
    final m = StaffMetrics.of(
      const Size(951, 500),
      16,
      15,
      foldX: 475.5,
      foldGap: kStaffFoldGap,
      maxNoteToStep: 1.0,
    );

    test('steps 1-8 end and 9-16 begin either side of the gap', () {
      expect(m.colLeft(7) + m.stepX, closeTo(475.5 - kStaffFoldGap / 2, 1e-9));
      expect(m.colLeft(8), closeTo(475.5 + kStaffFoldGap / 2, 1e-9));
      // Equal columns, so the second half ends a clef's width from the edge.
      expect(m.gridRight, closeTo(951 - 88, 1e-9));
    });

    test('a tap in the gap places nothing; either side lands in 8 or 9', () {
      expect(m.hitTest(const Offset(475.5, 200)), isNull);
      expect(m.hitTest(const Offset(475.5 - 25, 200))!.$1, 7);
      expect(m.hitTest(const Offset(475.5 + 25, 200))!.$1, 8);
    });

    test(
      'notes in steps 8 and 9 stay out of the fold band, bounce included',
      () {
        final reach = m.noteSize / 2 * 1.18; // the play bounce's scale
        final band = Rect.fromLTRB(475.5 - 16, 0, 475.5 + 16, 500);
        final left = m.cellCenter(7, 7).dx + reach;
        final right = m.cellCenter(8, 7).dx - reach;
        expect(left, lessThan(band.left));
        expect(right, greaterThan(band.right));
      },
    );

    test('the playhead jumps the gap', () {
      expect(m.xAt(7.9), lessThan(475.5 - kStaffFoldGap / 2));
      expect(m.xAt(8.0), greaterThanOrEqualTo(475.5 + kStaffFoldGap / 2));
    });

    test('without a fold the staff is laid out as before', () {
      final plain = StaffMetrics.of(const Size(1194, 600), 16, 15);
      expect(plain.stepX, (1194 - 88) / 16);
      expect(plain.colLeft(8), 88 + 8 * plain.stepX);
      expect(plain.noteSize, plain.stepY * 1.9);
      expect(plain.gapRect, isNull);
    });
  });
}
