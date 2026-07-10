import 'package:flutter/material.dart';
import 'categories.dart';
import 'theme.dart';

/// Tabbed emoji picker (a modal sheet). Returns the chosen emoji, or null if
/// dismissed. Emojis whose voice isn't in the current bundle are dimmed +
/// tagged 🔇 so it's clear which will actually sound right now.
Future<String?> showEmojiPicker(BuildContext context, {required Set<String> playable}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => FractionallySizedBox(
      heightFactor: 0.7,
      child: _PickerBody(playable: playable),
    ),
  );
}

class _PickerBody extends StatelessWidget {
  final Set<String> playable;
  const _PickerBody({required this.playable});

  @override
  Widget build(BuildContext context) {
    final cats = kCategories.keys.toList();
    return DefaultTabController(
      length: cats.length,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: Toy.highlight,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('CHOOSE YOUR STICKER',
                textAlign: TextAlign.center, style: Toy.label(11)),
          ),
          TabBar(
            isScrollable: true,
            indicatorColor: Toy.accent,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final c in cats)
                Tab(
                  child: Semantics(
                    label: c,
                    child: ExcludeSemantics(child: Text(categoryIcon(c), style: const TextStyle(fontSize: 22))),
                  ),
                ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final c in cats)
                  _Grid(emojis: kCategories[c]!, playable: playable),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  final List<String> emojis;
  final Set<String> playable;
  const _Grid({required this.emojis, required this.playable});

  @override
  Widget build(BuildContext context) {
    return GridView.extent(
      padding: const EdgeInsets.all(16),
      maxCrossAxisExtent: 60,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        for (final e in emojis)
          _Item(emoji: e, playable: playable.contains(e)),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  final String emoji;
  final bool playable;
  const _Item({required this.emoji, required this.playable});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: playable ? emoji : '$emoji, no sound',
      onTap: () => Navigator.pop(context, emoji),
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () => Navigator.pop(context, emoji),
          child: Opacity(
            opacity: playable ? 1 : 0.35,
            child: Container(
              alignment: Alignment.center,
              decoration: toyBox(radius: 10, border: 2, shadow: false),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 26)),
                  if (!playable)
                    const Positioned(right: 2, bottom: 1, child: Text('🔇', style: TextStyle(fontSize: 10))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
