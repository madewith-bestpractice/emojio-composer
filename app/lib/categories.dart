/// Emoji categories, ported verbatim from the web app's CATEGORIES map
/// (index.html). Each key is `Name <tabIcon>`; the icon drives the picker tab.
const Map<String, List<String>> kCategories = {
  'Faces 😀': ['😀', '😂', '😍', '😎', '😢', '😱', '😴', '😡', '🤔', '😘', '🤯', '😈', '🤗', '🥺', '🥳', '😇'],
  'Animals 🐾': [
    '🐶', '🐱', '🐷', '🐸', '🐔', '🦆', '🦁', '🐮', '🐦', '🐺', '🐗', '🦄', '🐰', '🐭', '🐻', '🐨',
    '🐯', '🐵', '🐢', '🐍', '🐝', '🐠', '🐬', '🐳', '🦋', '🦊', '🐴', '🐘', '🦉', '🐧', '🦅', '🦈'
  ],
  'Music 🎵': ['🎹', '🥁', '🎸', '🎺', '🎻', '🎷', '🔔', '🎼', '🎤', '🎧', '🎵', '🎶', '📻'],
  'Vehicles 🚗': [
    '🚗', '✈️', '🚢', '🚓', '🚒', '🚑', '🚜', '🚁', '🚀', '🛸', '🤖', '👾', '🚂', '🚕', '🚌', '🏎️', '🏍️', '🚲', '⛵', '🚤'
  ],
  'Characters 🧙': ['👶', '👻', '👽', '💩', '💀', '🤡', '👺', '👼', '🧛', '🧚', '🧜', '🧞', '🧟', '🦸', '🥷', '🎅', '👹'],
  'Food 🍕': ['🍕', '🍔', '🍎', '🍌', '🍓', '🍦', '🍩', '🍰', '🍪', '🍿', '🍉', '🍇', '☕', '🍣'],
  'Sports 🏀': ['⚽', '🏀', '🏈', '⚾', '🎾', '🏐', '⛳', '🏓', '🎳', '🏆', '🎯', '🎲'],
  'Nature 🌸': ['🌸', '❤️', '🌊', '⭐', '🔥', '🌈', '🍄', '🌵', '💡', '🌳', '☀️', '🌙', '⛄', '❄️', '⚡', '☁️'],
  'Objects 💎': ['💎', '🎁', '🎈', '📱', '🔑', '⏰', '⚙️'],
};

final List<String> kAllEmojis =
    kCategories.values.expand((e) => e).toList(growable: false);

/// The trailing emoji of a category key ("Faces 😀" -> "😀"), used as its tab icon.
String categoryIcon(String key) => key.split(' ').last;

/// The category name without its trailing emoji ("Faces 😀" -> "Faces").
String categoryName(String key) {
  final parts = key.split(' ');
  return parts.length > 1 ? parts.sublist(0, parts.length - 1).join(' ') : key;
}
