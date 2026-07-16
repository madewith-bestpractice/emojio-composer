import 'package:flutter/material.dart';
import 'theme.dart';

const double kBpmMin = 60;
const double kBpmMax = 180;

/// The handset's tempo control, shown as a modal sheet.
///
/// The header's inline slider is ~120px for the whole 60-180 range — a beat per
/// pixel, under a finger wide enough to hide the thumb — and a tap on it snaps
/// the tempo to wherever the finger landed. Here the slider gets the width of
/// the sheet, and it is at full size before the finger arrives, so grabbing the
/// thumb never moves it.
class TempoSheet extends StatelessWidget {
  final double bpm;
  final ValueChanged<double> onChanged;

  const TempoSheet({super.key, required this.bpm, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('TEMPO', style: Toy.label(11)),
            const SizedBox(height: 10),
            // The slider carries the accessible value, so this is decoration.
            ExcludeSemantics(
                child: Text('${bpm.round()} BPM', style: Toy.label(16))),
            const SizedBox(height: 6),
            Row(
              children: [
                const ExcludeSemantics(
                    child: Text('🐢', style: TextStyle(fontSize: 22))),
                Expanded(
                  child: Slider(
                    min: kBpmMin,
                    max: kBpmMax,
                    value: bpm.clamp(kBpmMin, kBpmMax),
                    divisions: (kBpmMax - kBpmMin).round(),
                    label: '${bpm.round()} BPM',
                    semanticFormatterCallback: (v) =>
                        '${v.round()} beats per minute',
                    onChanged: onChanged,
                  ),
                ),
                const ExcludeSemantics(
                    child: Text('🐇', style: TextStyle(fontSize: 22))),
              ],
            ),
          ],
        ),
      );
}
