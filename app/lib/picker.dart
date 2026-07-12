import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'categories.dart';
import 'theme.dart';

/// Tabbed emoji picker (a modal sheet). Returns the chosen emoji, or null if
/// dismissed. Choosing a sticker plays its sound; on devices that support hover
/// (Apple Pencil), hovering a sticker previews it too — [onPreview] is the play
/// hook. Emojis whose voice isn't in the current bundle are dimmed + tagged 🔇.
Future<String?> showEmojiPicker(
  BuildContext context, {
  required Set<String> playable,
  required void Function(String emoji) onPreview,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: _brandYellow,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _PickerBody(playable: playable, onPreview: onPreview),
  );
}

// Grid geometry — must match [_Grid] so we can size the sheet to fit exactly.
const double _gridPad = 16;
const double _gridSpacing = 10;
const double _gridMaxExtent = 60;

// Brand yellow + the boot-splash's tiled emblem, so the picker reads as part of
// the toy world and the space below a short category isn't blank white.
const Color _brandYellow = Color(0xFFFFF696);

class _SplashField extends StatelessWidget {
  const _SplashField();
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, con) {
        const target = 92.0;
        final cols = (con.maxWidth / target).round().clamp(3, 40);
        final cell = con.maxWidth / cols;
        final rows = (con.maxHeight / cell).ceil() + 1;
        return Opacity(
          opacity: 0.16,
          child: GridView.count(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            crossAxisCount: cols,
            children: List.generate(cols * rows, (i) {
              final tilt = (i % 2 == 0 ? 1 : -1) * 0.06;
              return Padding(
                padding: const EdgeInsets.all(14),
                child: Transform.rotate(
                  angle: tilt,
                  child: Image.asset('assets/branding/logo.png',
                      filterQuality: FilterQuality.medium),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _PickerBody extends StatefulWidget {
  final Set<String> playable;
  final void Function(String emoji) onPreview;
  const _PickerBody({required this.playable, required this.onPreview});

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody>
    with SingleTickerProviderStateMixin {
  late final List<String> _cats = kCategories.keys.toList();
  late final TabController _tab =
      TabController(length: _cats.length, vsync: this)..addListener(_onTab);
  int _lastIndex = 0;

  // A light tick each time the selected category changes (tap or swipe).
  void _onTab() {
    if (_tab.index != _lastIndex) {
      _lastIndex = _tab.index;
      HapticFeedback.selectionClick();
    }
  }

  @override
  void dispose() {
    _tab.removeListener(_onTab);
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cats = _cats;
    // One shared height for every tab (so switching categories never makes the
    // sheet jump), sized to the largest set so it — and every smaller one — fits
    // without scrolling. The largest set fills it exactly; smaller ones sit a
    // little short, which is the cost of a stable, non-jumping height.
    final maxCount = kCategories.values.map((l) => l.length).reduce(math.max);
    return LayoutBuilder(
        builder: (context, constraints) {
          final inner = constraints.maxWidth - _gridPad * 2;
          final cols =
              math.max(1, (inner / (_gridMaxExtent + _gridSpacing)).ceil());
          final tile = (inner - _gridSpacing * (cols - 1)) / cols;
          final rows = (maxCount / cols).ceil();
          final gridH = rows * tile + _gridSpacing * (rows - 1) + _gridPad * 2;
          // Never let the sheet push past most of the screen on small devices.
          final capH = MediaQuery.of(context).size.height * 0.82;
          final bottomInset = MediaQuery.of(context).viewPadding.bottom;
          final content = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                color: Toy.highlight,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text('CHOOSE YOUR STICKER',
                    textAlign: TextAlign.center, style: Toy.label(11)),
              ),
              TabBar(
                controller: _tab,
                isScrollable: true,
                indicatorColor: Toy.accent,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final c in cats)
                    Tab(
                      child: Semantics(
                        label: c,
                        child: ExcludeSemantics(
                            child: Text(categoryIcon(c),
                                style: const TextStyle(fontSize: 22))),
                      ),
                    ),
                ],
              ),
              SizedBox(
                height: math.min(gridH, capH),
                child: TabBarView(
                  controller: _tab,
                  children: [
                    for (final c in cats)
                      _Grid(
                          emojis: kCategories[c]!,
                          playable: widget.playable,
                          onPreview: widget.onPreview),
                  ],
                ),
              ),
              SizedBox(height: bottomInset),
            ],
          );
          // Faint tiled-emblem field behind the sticker grid; the amber header
          // band sits opaque on top, so only the grid + its short-fall show it.
          return Stack(
            children: [
              Positioned.fill(child: const _SplashField()),
              content,
            ],
          );
        },
      );
  }
}

class _Grid extends StatelessWidget {
  final List<String> emojis;
  final Set<String> playable;
  final void Function(String emoji) onPreview;
  const _Grid({required this.emojis, required this.playable, required this.onPreview});

  @override
  Widget build(BuildContext context) {
    return GridView.extent(
      padding: const EdgeInsets.all(_gridPad),
      maxCrossAxisExtent: _gridMaxExtent,
      mainAxisSpacing: _gridSpacing,
      crossAxisSpacing: _gridSpacing,
      physics: const ClampingScrollPhysics(),
      children: [
        for (final e in emojis)
          _Item(emoji: e, playable: playable.contains(e), onPreview: onPreview),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  final String emoji;
  final bool playable;
  final void Function(String emoji) onPreview;
  const _Item({required this.emoji, required this.playable, required this.onPreview});

  void _preview() {
    if (playable) onPreview(emoji);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: playable ? emoji : '$emoji, no sound',
      onTap: () {
        _preview();
        Navigator.pop(context, emoji);
      },
      child: ExcludeSemantics(
        // Apple Pencil / pointer hover previews the sound (fires once on enter).
        child: MouseRegion(
          onEnter: (_) => _preview(),
          child: GestureDetector(
            onTap: () {
              _preview();
              Navigator.pop(context, emoji);
            },
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
      ),
    );
  }
}
