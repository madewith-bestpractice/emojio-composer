import 'package:emojio/monetization/access.dart';
import 'package:emojio/monetization/paywall.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_purchases.dart';

void main() {
  late int closes;

  Future<void> open(
    WidgetTester tester,
    FakePurchaseManager p, {
    PremiumFeature? reason,
    Size size = const Size(820, 1180), // iPad portrait
  }) async {
    closes = 0;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnlockSheet(
            purchases: p,
            reason: reason,
            onClose: () => closes++,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // ToyButton upper-cases its label, so match without case.
  Finder text(String s) => find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').toLowerCase().contains(s.toLowerCase()),
    description: 'text containing "$s"',
  );

  testWidgets(
    'shows the real store price, one-time wording and every benefit',
    (tester) async {
      await open(tester, FakePurchaseManager(price: '4,99 €'));
      expect(text('Get Premium — 4,99 €'), findsOneWidget);
      expect(text('one-time purchase'), findsOneWidget);
      expect(text('No subscription'), findsOneWidget);
      for (final f in PremiumFeature.values) {
        expect(text(f.title), findsWidgets);
      }
      expect(text('Restore Purchase'), findsOneWidget);
      expect(text('Terms of Use'), findsOneWidget);
      expect(text('Privacy Policy'), findsOneWidget);
    },
  );

  testWidgets('names the feature that opened it', (tester) async {
    await open(tester, FakePurchaseManager(), reason: PremiumFeature.midi);
    expect(text('MIDI KEYBOARDS IS PREMIUM'), findsOneWidget);
  });

  testWidgets('a successful purchase closes the sheet', (tester) async {
    final p = FakePurchaseManager();
    await open(tester, p);
    await tester.tap(text('Get Premium'));
    await tester.pump();
    expect(p.buys, 1);
    expect(p.unlocked, isTrue);
    expect(closes, 1);
  });

  testWidgets('shows a spinner while the store sheet is up', (tester) async {
    final p = FakePurchaseManager(buyOutcome: BuyOutcome.hang);
    await open(tester, p);
    await tester.tap(text('Get Premium'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(text('Get Premium'), findsNothing);
    p.hang!.complete();
    await tester.pump();
    expect(text('Get Premium'), findsOneWidget);
  });

  testWidgets('cancelling is quiet: no error, sheet stays', (tester) async {
    final p = FakePurchaseManager(buyOutcome: BuyOutcome.cancel);
    await open(tester, p);
    await tester.tap(text('Get Premium'));
    await tester.pump();
    expect(text("didn't go through"), findsNothing);
    expect(closes, 0);
    expect(text('Get Premium'), findsOneWidget);
  });

  testWidgets('a failed purchase says so in plain words', (tester) async {
    await open(tester, FakePurchaseManager(buyOutcome: BuyOutcome.fail));
    await tester.tap(text('Get Premium'));
    await tester.pump();
    expect(text("That didn't go through"), findsOneWidget);
    expect(text('store said no'), findsOneWidget, reason: 'debug-only detail');
  });

  testWidgets('pending (Ask to Buy) waits, then closes on approval', (
    tester,
  ) async {
    final p = FakePurchaseManager(buyOutcome: BuyOutcome.pending);
    await open(tester, p);
    await tester.tap(text('Get Premium'));
    await tester.pump();
    expect(text('Waiting for approval'), findsOneWidget);
    expect(closes, 0);
    p.grant();
    await tester.pump();
    expect(closes, 1);
  });

  testWidgets('store unavailable: retries on open, then offers Try Again', (
    tester,
  ) async {
    final p = FakePurchaseManager(sellable: false);
    await open(tester, p);
    expect(p.reloads, 1, reason: 'the sheet retries a failed boot load');
    expect(text("Purchases aren't available"), findsOneWidget);
    expect(text('Get Premium'), findsNothing);
    p.reloadMakesSellable = true;
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pump();
    expect(text(r'Get Premium — $4.99'), findsOneWidget);
  });

  testWidgets('restore with nothing to restore says so', (tester) async {
    final p = FakePurchaseManager();
    await open(tester, p);
    await tester.tap(text('Restore Purchase'));
    await tester.pump();
    expect(p.restores, 1);
    expect(text('No earlier purchase was found'), findsOneWidget);
    expect(closes, 0);
  });

  testWidgets('restore that finds Premium closes the sheet', (tester) async {
    final p = FakePurchaseManager(ownedOnStore: true);
    await open(tester, p);
    await tester.tap(text('Restore Purchase'));
    await tester.pump();
    expect(closes, 1);
  });

  testWidgets('an owner sees thanks and Restore, not a buy button', (
    tester,
  ) async {
    final p = FakePurchaseManager()..unlocked = true;
    await open(tester, p);
    expect(text('YOU HAVE PREMIUM'), findsOneWidget);
    expect(text('Restore Purchase'), findsOneWidget);
    expect(text('Get Premium'), findsNothing);
    await tester.tap(text('Done'));
    expect(closes, 1);
  });

  testWidgets('fits a phone and a Mac window without overflow', (tester) async {
    for (final size in const [Size(390, 844), Size(1280, 800)]) {
      await open(tester, FakePurchaseManager(sellable: false), size: size);
      expect(tester.takeException(), isNull);
    }
  });
}
