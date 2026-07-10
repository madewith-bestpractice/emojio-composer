import 'package:emojio/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToyButton accessibility', () {
    testWidgets('labelled button: accessible name, no emoji noise, activatable', (tester) async {
      final handle = tester.ensureSemantics();
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: ToyButton(label: 'Play', emoji: '▶️', onPressed: () => tapped = true))),
      ));

      // VoiceOver/Switch Control announce the word, not the decorative glyph.
      expect(find.bySemanticsLabel('Play'), findsOneWidget);
      expect(find.bySemanticsLabel('▶️'), findsNothing);

      await tester.tap(find.byType(ToyButton));
      expect(tapped, isTrue);
      handle.dispose();
    });

    testWidgets('icon-only chip: tooltip is the accessible name', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: ToyButton(emoji: '📤', tooltip: 'Export', onPressed: () {}))),
      ));
      expect(find.bySemanticsLabel('Export'), findsOneWidget);
      expect(find.bySemanticsLabel('📤'), findsNothing);
      handle.dispose();
    });

    testWidgets('disabled button still exposes its name', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: ToyButton(label: 'Save', onPressed: null))),
      ));
      expect(find.bySemanticsLabel('Save'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('Increase Contrast darkens a light-text button', (tester) async {
      Color fillOf() => (tester
              .widget<AnimatedContainer>(find.descendant(
                  of: find.byType(ToyButton), matching: find.byType(AnimatedContainer)))
              .decoration! as BoxDecoration)
          .color!;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ToyButton(label: 'Play', color: const Color(0xFF4CAF50), onPressed: () {})),
      ));
      final normal = fillOf();

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(highContrast: true),
            child: Scaffold(body: ToyButton(label: 'Play', color: const Color(0xFF4CAF50), onPressed: () {})),
          ),
        ),
      ));
      expect(fillOf().computeLuminance(), lessThan(normal.computeLuminance()));
    });
  });
}
