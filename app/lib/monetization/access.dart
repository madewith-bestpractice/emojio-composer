import '../categories.dart';

/// What Premium (the lifetime unlock, or the first-days reverse trial) adds on
/// top of the free app. Each value also names the paywall's headline, so the
/// sheet can say *why* it opened.
enum PremiumFeature {
  voices('🎨', 'Every sound', 'Unlock all the sticker sounds — vehicles, '
      'characters, food, sports, nature and more.'),
  videoExport('🎬', 'Video export', 'Turn a song into a video to share.'),
  midi('🎹', 'MIDI keyboards', 'Play and record with a MIDI keyboard or '
      'controller.'),
  pencil('✏️', 'Apple Pencil pressure', 'Press harder for louder notes.'),
  unlimitedSongs('💾', 'Unlimited songs',
      'Save as many songs as you like (free keeps ${Access.freeSongLimit}).');

  final String emoji;
  final String title;
  final String blurb;
  const PremiumFeature(this.emoji, this.title, this.blurb);
}

/// The single answer to "may the user do this?". Everything gated in the app
/// asks here, so the free/Premium split lives in one place.
///
/// Free: the whole composer, the [freeCategories] sounds, share links, WAV
/// export and up to [freeSongLimit] saved songs. Premium: everything.
///
/// Anything the user already *has* is never taken away: songs that are loaded
/// (shared links, saves made during the trial) play and edit with whatever
/// sounds they hold, and saves over the limit are kept — only new saves stop.
class Access {
  /// Picker categories that are free for everyone. Keys of [kCategories].
  static const freeCategories = {
    'Faces 😀',
    'Animals 🐾',
    'Music 🎵',
    'Drum Kit 🥁',
  };

  static const int freeSongLimit = 3;

  /// Every emoji in a free category.
  static final Set<String> freeVoices = {
    for (final c in freeCategories) ...kCategories[c]!,
  };

  /// True with the lifetime unlock or during the reverse trial.
  final bool premium;
  const Access({required this.premium});

  bool allows(PremiumFeature f) => premium;

  bool canUseVoice(String emoji) => premium || freeVoices.contains(emoji);

  /// Whether one more song may be saved, given how many are saved already.
  bool canSaveAnother(int savedCount) =>
      premium || savedCount < freeSongLimit;

  /// The emoji in [emojis] that are locked, for the picker's 🔒 badges.
  Set<String> lockedAmong(Iterable<String> emojis) =>
      premium ? const {} : {for (final e in emojis) if (!canUseVoice(e)) e};
}
