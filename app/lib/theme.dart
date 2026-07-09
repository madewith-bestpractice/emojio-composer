import 'package:flutter/material.dart';

/// The "toy" palette + widgets, ported from the web app's CSS :root variables
/// and button styling (chunky borders + hard offset shadows + pixel font).
class Toy {
  static const bg = Color(0xFFE0F7FA); // light cyan
  static const panel = Color(0xFFFFF9C4); // pale yellow
  static const header = Color(0xFF81D4FA); // sky blue
  static const accent = Color(0xFFFF4081); // hot pink
  static const highlight = Color(0xFFFFD740); // amber
  static const text = Color(0xFF37474F); // dark blue-grey
  static const line = Color(0xFF90A4AE); // staff line
  static const green = Color(0xFF4CAF50);
  static const red = Color(0xFFF44336);
  static const purple = Color(0xFFAB47BC);

  static const font = 'PressStart2P';

  static TextStyle label(double size, [Color color = text]) =>
      TextStyle(fontFamily: font, fontSize: size, color: color, height: 1.4);
}

/// A pill button with the toy look: 3px border, hard offset shadow, pixel font,
/// and a press animation (shadow collapses + sinks, like the web buttons).
class ToyButton extends StatefulWidget {
  final String? label;
  final String? emoji; // optional leading glyph
  final Color color;
  final Color textColor;
  final VoidCallback? onPressed;
  final double fontSize;
  final EdgeInsets padding;
  final double radius; // corner radius: 30 = pill, smaller = squircle chip
  final String? tooltip; // accessible name + long-press hint (needed for icon-only chips)

  const ToyButton({
    super.key,
    this.label,
    this.emoji,
    this.color = Toy.accent,
    this.textColor = Colors.white,
    required this.onPressed,
    this.fontSize = 9,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    this.radius = 30,
    this.tooltip,
  });

  @override
  State<ToyButton> createState() => _ToyButtonState();
}

class _ToyButtonState extends State<ToyButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final offset = _down ? 1.0 : 3.0;
    Widget button = GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTap: widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        transform: Matrix4.translationValues(_down ? 2 : 0, _down ? 2 : 0, 0),
        padding: widget.padding,
        decoration: BoxDecoration(
          color: enabled ? widget.color : widget.color.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(color: Toy.text, width: 3),
          boxShadow: [BoxShadow(color: Toy.text, offset: Offset(offset, offset))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.emoji != null) ...[
              Text(widget.emoji!, style: TextStyle(fontSize: widget.fontSize + 5)),
              if (widget.label != null) const SizedBox(width: 6),
            ],
            if (widget.label != null)
              Text(widget.label!.toUpperCase(), style: Toy.label(widget.fontSize, widget.textColor)),
          ],
        ),
      ),
    );
    // Icon-only chips have no visible text, so give assistive tech (and a
    // long-press tooltip) something to read.
    if (widget.tooltip != null) {
      button = Tooltip(
        message: widget.tooltip!,
        child: Semantics(button: true, label: widget.tooltip, child: button),
      );
    }
    return button;
  }
}

/// A white, chunky-bordered rounded box (the palette "Active" slot, picker items…).
BoxDecoration toyBox({Color fill = Colors.white, double radius = 14, double border = 3, bool shadow = true}) =>
    BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Toy.text, width: border),
      boxShadow: shadow ? const [BoxShadow(color: Toy.text, offset: Offset(3, 3))] : null,
    );
