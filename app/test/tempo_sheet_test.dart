import 'package:emojio/tempo_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The handset hands its tempo slider to a sheet because the header's inline one is
// ~120px for the whole 60-180 range. These pin what the sheet has to be worth.
void main() {
  // Drive it the way the page does: the sheet is stateless, the page owns the BPM.
  Future<double> pumpSheet(WidgetTester tester,
      {double bpm = 110, Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var current = bpm;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (ctx, setState) => TempoSheet(
            bpm: current,
            onChanged: (v) => setState(() => current = v),
          ),
        ),
      ),
    ));
    return current;
  }

  double shownBpm(WidgetTester tester) => double.parse(
      (tester.widget<Text>(find.textContaining(' BPM')).data ?? '')
          .split(' ')
          .first);

  testWidgets('the slider is far longer than the 120px it replaces',
      (tester) async {
    await pumpSheet(tester);
    // On a 390px phone: the sheet's width less its padding and the two emoji.
    expect(tester.getSize(find.byType(Slider)).width, greaterThan(240));
  });

  testWidgets('opens reading the tempo it was given', (tester) async {
    await pumpSheet(tester, bpm: 132);
    expect(find.text('TEMPO'), findsOneWidget);
    expect(find.text('132 BPM'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 132);
  });

  testWidgets('dragging right speeds up, and the readout follows',
      (tester) async {
    await pumpSheet(tester, bpm: 110);
    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(shownBpm(tester), greaterThan(110));
  });

  testWidgets('dragging left slows down', (tester) async {
    await pumpSheet(tester, bpm: 110);
    await tester.drag(find.byType(Slider), const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(shownBpm(tester), lessThan(110));
  });

  testWidgets('never leaves the 60-180 range, however hard it is dragged',
      (tester) async {
    await pumpSheet(tester, bpm: 110);
    await tester.drag(find.byType(Slider), const Offset(4000, 0));
    await tester.pumpAndSettle();
    expect(shownBpm(tester), kBpmMax);

    await tester.drag(find.byType(Slider), const Offset(-4000, 0));
    await tester.pumpAndSettle();
    expect(shownBpm(tester), kBpmMin);
  });

  testWidgets('lands on whole beats, not fractions', (tester) async {
    await pumpSheet(tester, bpm: 110);
    await tester.drag(find.byType(Slider), const Offset(37, 0));
    await tester.pumpAndSettle();
    final v = tester.widget<Slider>(find.byType(Slider)).value;
    expect(v, v.roundToDouble());
  });

  testWidgets('a screen reader hears beats per minute, not the emoji',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSheet(tester, bpm: 128);
    expect(find.bySemanticsLabel('🐢'), findsNothing);
    expect(find.bySemanticsLabel('🐇'), findsNothing);
    expect(
        tester.widget<Slider>(find.byType(Slider)).semanticFormatterCallback!(128),
        '128 beats per minute');
    handle.dispose();
  });
}
