import 'package:emojio/review_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final installed = DateTime(2026, 10, 1);
  final later = installed.add(const Duration(days: 3));

  bool ask({
    int successes = 3,
    DateTime? installedAt,
    DateTime? lastAsked,
    DateTime? now,
    bool paywallSeen = false,
  }) => ReviewPrompt.shouldAsk(
    successes: successes,
    installed: installedAt ?? installed,
    lastAsked: lastAsked,
    now: now ?? later,
    paywallSeen: paywallSeen,
  );

  test('asks on the third win, not before', () {
    expect(ask(successes: 2), isFalse);
    expect(ask(successes: 3), isTrue);
  });

  test('never on the first day', () {
    expect(ask(now: installed.add(const Duration(hours: 5))), isFalse);
  });

  test('never in a session that showed the paywall', () {
    expect(ask(paywallSeen: true), isFalse);
  });

  test('not again until the cooldown has passed', () {
    expect(ask(lastAsked: later.subtract(const Duration(days: 30))), isFalse);
    expect(ask(lastAsked: later.subtract(ReviewPrompt.cooldown)), isTrue);
  });

  test('never without a known install date', () {
    expect(
      ReviewPrompt.shouldAsk(
        successes: 9,
        installed: null,
        lastAsked: null,
        now: later,
        paywallSeen: false,
      ),
      isFalse,
    );
  });
}
