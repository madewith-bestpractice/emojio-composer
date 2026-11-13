import 'dart:convert';
import 'dart:io';

import 'package:in_app_review/in_app_review.dart';
import 'package:path_provider/path_provider.dart';

import 'app_version.dart';

/// Asks for a store rating at a genuine success moment: the first song saved,
/// exported or shared, or a song the player listened to all the way through
/// (see [playedThrough]). It asks at most once per app version and
/// [minGap] apart, and not right after a paywall. The OS has the final say
/// (iOS and macOS show the sheet at most 3 times a year; Play has its own
/// quota) and never says whether the sheet appeared, so this only records
/// that we asked.
///
/// State lives in a small JSON file in the app-support directory rather than
/// the Keychain, so a keychain that can't be written (macOS without an access
/// group, say) can't silently turn the prompt off.
class ReviewPrompt {
  static const minGap = Duration(days: 30);
  static const paywallQuiet = Duration(minutes: 2);

  /// A listen counts once the song has this many notes on the staff...
  static const minNotes = 8;

  /// ...and has looped all the way through this many times before Stop.
  static const minLoops = 2;

  final Future<File> Function() _file;
  final InAppReview _review;
  final String _version;

  /// Set once this session has asked, so a burst of wins asks once.
  bool _askedThisSession = false;

  ReviewPrompt({
    Future<File> Function()? file,
    InAppReview? review,
    String version = kAppVersion,
  }) : _file = file ?? _defaultFile,
       _review = review ?? InAppReview.instance,
       _version = version;

  static Future<File> _defaultFile() async => File(
    '${(await getApplicationSupportDirectory()).path}/review_prompt.json',
  );

  /// Whether a stop after [stepsPlayed] steps of a [noteCount]-note song is a
  /// finished listen, worth treating like a save.
  static bool playedThrough({
    required int noteCount,
    required int stepsPlayed,
    required int stepsPerLoop,
  }) => noteCount >= minNotes && stepsPlayed >= minLoops * stepsPerLoop;

  /// Whether a win right now should ask. Pure, so the rules are testable.
  static bool shouldAsk({
    required String version,
    required String? askedVersion,
    required DateTime? lastAsked,
    required DateTime now,
    DateTime? paywallAt,
  }) {
    if (askedVersion == version) return false;
    if (paywallAt != null && now.difference(paywallAt) < paywallQuiet) {
      return false;
    }
    return lastAsked == null || now.difference(lastAsked) >= minGap;
  }

  /// Records a win and asks for a rating if [shouldAsk] says it's time.
  /// [paywallAt] is when this session last showed the paywall, if it did.
  Future<void> noteSuccess({DateTime? paywallAt}) async {
    if (_askedThisSession) return;
    try {
      final file = await _file();
      var state = <String, dynamic>{};
      if (await file.exists()) {
        try {
          state = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        } catch (_) {
          // Unreadable: start over rather than never asking again.
        }
      }
      final askedMs = state['asked_ms'];
      final now = DateTime.now();
      if (!shouldAsk(
        version: _version,
        askedVersion: state['asked_version'] as String?,
        lastAsked: askedMs is int
            ? DateTime.fromMillisecondsSinceEpoch(askedMs)
            : null,
        now: now,
        paywallAt: paywallAt,
      )) {
        return;
      }
      if (!await _review.isAvailable()) return;
      _askedThisSession = true;
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'asked_version': _version,
          'asked_ms': now.millisecondsSinceEpoch,
        }),
      );
      await _review.requestReview();
    } catch (_) {
      // A rating prompt is never worth an error in front of the player.
    }
  }
}
