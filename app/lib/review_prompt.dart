import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:in_app_review/in_app_review.dart';

/// Asks for a store rating after the player has had a few wins — a song saved,
/// exported or shared — and never on first launch, never in a session that
/// showed the paywall, and at most once every [cooldown]. The OS has the final
/// say (iOS shows the sheet at most 3 times a year), and it never says whether
/// the sheet appeared, so this only counts that we asked.
class ReviewPrompt {
  static const successesNeeded = 3;
  static const minAge = Duration(days: 1);
  static const cooldown = Duration(days: 120);
  static const _countKey = 'emojio.review.successes';
  static const _askedKey = 'emojio.review.asked_ms';

  final FlutterSecureStorage _store;
  final InAppReview _review;

  ReviewPrompt({FlutterSecureStorage? store, InAppReview? review})
    : _store = store ?? const FlutterSecureStorage(),
      _review = review ?? InAppReview.instance;

  /// Whether a win right now should ask. Pure, so the rules are testable.
  static bool shouldAsk({
    required int successes,
    required DateTime? installed,
    required DateTime? lastAsked,
    required DateTime now,
    required bool paywallSeen,
  }) {
    if (paywallSeen || installed == null) return false;
    if (successes < successesNeeded) return false;
    if (now.difference(installed) < minAge) return false;
    return lastAsked == null || now.difference(lastAsked) >= cooldown;
  }

  /// Records a win and asks for a rating if [shouldAsk] says it's time.
  Future<void> noteSuccess({
    required DateTime? installed,
    required bool paywallSeen,
  }) async {
    try {
      final successes =
          (int.tryParse(await _store.read(key: _countKey) ?? '') ?? 0) + 1;
      await _store.write(key: _countKey, value: '$successes');
      final askedMs = int.tryParse(await _store.read(key: _askedKey) ?? '');
      final now = DateTime.now();
      if (!shouldAsk(
        successes: successes,
        installed: installed,
        lastAsked: askedMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(askedMs),
        now: now,
        paywallSeen: paywallSeen,
      )) {
        return;
      }
      if (!await _review.isAvailable()) return;
      await _store.write(
        key: _askedKey,
        value: '${now.millisecondsSinceEpoch}',
      );
      await _review.requestReview();
    } catch (_) {
      // A rating prompt is never worth an error in front of the player.
    }
  }
}
