import 'dart:io';

import 'package:emojio/app_version.dart';
import 'package:emojio/review_prompt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_review/in_app_review.dart';

class _FakeReview implements InAppReview {
  bool available = true;
  int requests = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> requestReview() async => requests++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime(2026, 10, 12, 12);

  group('shouldAsk', () {
    bool ask({
      String version = '1.1.2',
      String? askedVersion,
      DateTime? lastAsked,
      DateTime? paywallAt,
    }) => ReviewPrompt.shouldAsk(
      version: version,
      askedVersion: askedVersion,
      lastAsked: lastAsked,
      now: now,
      paywallAt: paywallAt,
    );

    test('asks on the very first win of a fresh install', () {
      expect(ask(), isTrue);
    });

    test('once per version', () {
      expect(
        ask(
          askedVersion: '1.1.2',
          lastAsked: now.subtract(const Duration(days: 90)),
        ),
        isFalse,
      );
    });

    test('a new version may ask again once the gap has passed', () {
      expect(
        ask(
          askedVersion: '1.1.1',
          lastAsked: now.subtract(const Duration(days: 5)),
        ),
        isFalse,
      );
      expect(
        ask(
          askedVersion: '1.1.1',
          lastAsked: now.subtract(ReviewPrompt.minGap),
        ),
        isTrue,
      );
    });

    test('not right after a paywall, but fine later in the session', () {
      expect(
        ask(paywallAt: now.subtract(const Duration(seconds: 20))),
        isFalse,
      );
      expect(ask(paywallAt: now.subtract(const Duration(minutes: 10))), isTrue);
    });
  });

  group('playedThrough', () {
    test('needs a real song and two full loops', () {
      bool p(int notes, int steps) => ReviewPrompt.playedThrough(
        noteCount: notes,
        stepsPlayed: steps,
        stepsPerLoop: 16,
      );
      expect(p(8, 32), isTrue);
      expect(p(7, 64), isFalse, reason: 'too few notes');
      expect(
        p(12, 31),
        isFalse,
        reason: 'stopped before the second loop ended',
      );
    });
  });

  group('noteSuccess', () {
    late Directory dir;
    late File file;
    late _FakeReview review;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('review_prompt_test');
      file = File('${dir.path}/sub/review_prompt.json');
      review = _FakeReview();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    ReviewPrompt prompt({String version = '1.1.2'}) =>
        ReviewPrompt(file: () async => file, review: review, version: version);

    test('first save asks, and only once for this version', () async {
      await prompt().noteSuccess();
      expect(review.requests, 1);
      expect(file.readAsStringSync(), contains('"asked_version":"1.1.2"'));
      final again = prompt();
      await again.noteSuccess();
      await again.noteSuccess();
      expect(review.requests, 1);
    });

    test('the next version waits out the gap', () async {
      await prompt(version: '1.1.2').noteSuccess();
      await prompt(version: '1.1.3').noteSuccess();
      expect(review.requests, 1);
    });

    test(
      'a win just after the paywall neither asks nor uses up the version',
      () async {
        await prompt().noteSuccess(paywallAt: DateTime.now());
        expect(review.requests, 0);
        expect(file.existsSync(), isFalse);
        await prompt().noteSuccess();
        expect(review.requests, 1);
      },
    );

    test('no store sheet available: does not record an ask', () async {
      review.available = false;
      await prompt().noteSuccess();
      expect(file.existsSync(), isFalse);
    });

    test('a corrupt state file is treated as never asked', () async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('{not json');
      await prompt().noteSuccess();
      expect(review.requests, 1);
    });
  });

  test('kAppVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(
      r'^version:\s*([0-9.]+)\+',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(m?.group(1), kAppVersion);
  });
}
