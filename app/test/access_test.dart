import 'package:emojio/categories.dart';
import 'package:emojio/monetization/access.dart';
import 'package:emojio/monetization/paywall.dart';
import 'package:emojio/monetization/purchases.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const free = Access(premium: false);
  const premium = Access(premium: true);

  group('Access', () {
    test('free categories are real picker categories', () {
      for (final c in Access.freeCategories) {
        expect(kCategories, contains(c));
      }
    });

    test('free tier: starter sounds only', () {
      expect(free.canUseVoice('🐶'), isTrue); // Animals
      expect(free.canUseVoice('🥁'), isTrue); // Drum Kit
      expect(free.canUseVoice('💎'), isFalse); // Objects
      // Every non-free category holds at least one locked sound.
      for (final c in kCategories.keys) {
        if (Access.freeCategories.contains(c)) continue;
        expect(kCategories[c]!.any((e) => !free.canUseVoice(e)), isTrue,
            reason: c);
      }
    });

    test('free tier: no Premium features, a few saves', () {
      for (final f in PremiumFeature.values) {
        expect(free.allows(f), isFalse, reason: f.name);
      }
      expect(free.canSaveAnother(0), isTrue);
      expect(free.canSaveAnother(Access.freeSongLimit - 1), isTrue);
      expect(free.canSaveAnother(Access.freeSongLimit), isFalse);
      // Over the limit (saved during the trial) only blocks new saves.
      expect(free.canSaveAnother(Access.freeSongLimit + 5), isFalse);
    });

    test('Premium: everything', () {
      for (final f in PremiumFeature.values) {
        expect(premium.allows(f), isTrue, reason: f.name);
      }
      for (final e in kCategories.values.expand((l) => l)) {
        expect(premium.canUseVoice(e), isTrue, reason: e);
      }
      expect(premium.canSaveAnother(1000), isTrue);
    });

    test('lockedAmong badges only what free can\'t use', () {
      expect(free.lockedAmong(['🐶', '💎', '🚗']), {'💎', '🚗'});
      expect(premium.lockedAmong(['🐶', '💎', '🚗']), isEmpty);
    });
  });

  testWidgets('UnlockSheet names the feature that opened it', (tester) async {
    var closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UnlockSheet(
          purchases: PurchaseManager(),
          reason: PremiumFeature.midi,
          onClose: () => closed = true,
        ),
      ),
    ));
    expect(find.text('MIDI KEYBOARDS IS PREMIUM'), findsOneWidget);
    // No product loaded in a test: the sheet says so instead of rendering empty.
    expect(find.textContaining("aren't available"), findsOneWidget);
    await tester.ensureVisible(find.text('Not now')); // the sheet scrolls
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    expect(closed, isTrue);
  });
}
