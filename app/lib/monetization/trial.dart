import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tracks the self-implemented free trial. The first-launch timestamp lives in
/// the **Keychain** (via flutter_secure_storage), which survives app deletion
/// on iOS — so deleting/reinstalling can't reset the trial, and no server is
/// needed. (Guideline 3.1.1 sanctions a developer-run trial on a non-consumable.)
///
/// Not hardened against device-clock changes; that would need server-side
/// validation, unnecessary for this app.
class TrialManager {
  static const int trialDays = 3;
  static const _key = 'emojio.trial_start_ms';

  final FlutterSecureStorage _store;
  DateTime? _start;

  TrialManager([FlutterSecureStorage? store]) : _store = store ?? const FlutterSecureStorage();

  /// Reads the stored start, or stamps "now" on the very first launch.
  Future<void> ensureStarted() async {
    final v = await _store.read(key: _key);
    if (v == null) {
      _start = DateTime.now();
      await _store.write(key: _key, value: _start!.millisecondsSinceEpoch.toString());
    } else {
      final ms = int.tryParse(v);
      _start = ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : DateTime.now();
    }
  }

  DateTime get _end => (_start ?? DateTime.now()).add(const Duration(days: trialDays));

  Duration get remaining {
    final r = _end.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  bool get active => remaining > Duration.zero;

  /// Whole days left, rounded up (so ">0" reads as "1 day left", not "0").
  int get daysLeft => (remaining.inHours / 24).ceil();
}
