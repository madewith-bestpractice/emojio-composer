import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import '../theme.dart';
import 'midi_manager.dart';

/// Toy-styled MIDI settings sheet: device connect (USB-first), input channel +
/// octave + velocity, MIDI output on an export channel, and a MIDI-learn table
/// for app controls (transport, voice cycling, shuttle) with smart defaults.
class MidiPanel extends StatelessWidget {
  final MidiManager midi;
  final List<String> palette; // current top-row voices, for slot-learn
  const MidiPanel({super.key, required this.midi, required this.palette});

  static String _typeLabel(MidiDeviceType t) => switch (t) {
        MidiDeviceType.serial => 'USB',
        MidiDeviceType.ble => 'Bluetooth',
        MidiDeviceType.network => 'Network',
        MidiDeviceType.virtual || MidiDeviceType.ownVirtual => 'Virtual',
        _ => 'MIDI',
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: midi,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            color: Toy.header,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('🎹 MIDI',
                textAlign: TextAlign.center,
                style: Toy.label(13, Colors.white).copyWith(
                    shadows: const [Shadow(color: Toy.text, offset: Offset(2, 2))])),
          ),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                _statusRow(),
                const SizedBox(height: 14),
                _devices(),
                const SizedBox(height: 18),
                _input(),
                const SizedBox(height: 18),
                _output(),
                const SizedBox(height: 18),
                _controls(),
                const SizedBox(height: 18),
                _paletteSlots(),
                const SizedBox(height: 18),
                _activity(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusRow() => Row(
        children: [
          Expanded(child: Text(midi.status, style: const TextStyle(fontSize: 11, color: Colors.black54))),
          _MiniBtn(label: 'Refresh', emoji: '🔄', onTap: midi.refresh),
        ],
      );

  Widget _section(String title, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Toy.label(8, Colors.black54)),
          const SizedBox(height: 8),
          child,
        ],
      );

  Widget _devices() => _section(
        'DEVICES',
        Column(
          children: [
            if (midi.devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Plug in a USB-C controller, or scan Bluetooth.',
                    style: TextStyle(fontSize: 12, color: Colors.black45)),
              ),
            for (final d in midi.devices)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: toyBox(radius: 12, border: 2, shadow: false),
                child: Row(
                  children: [
                    const Text('🎛️', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          Text(_typeLabel(d.type), style: const TextStyle(fontSize: 11, color: Colors.black45)),
                        ],
                      ),
                    ),
                    _MiniBtn(
                      label: midi.isConnected(d) ? 'Disconnect' : 'Connect',
                      color: midi.isConnected(d) ? Toy.red : Toy.green,
                      onTap: () => midi.isConnected(d) ? midi.disconnect(d) : midi.connect(d),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: _MiniBtn(label: 'Scan Bluetooth', emoji: '📡', color: Toy.purple, onTap: midi.scanBluetooth),
            ),
          ],
        ),
      );

  Widget _input() => _section(
        'INPUT',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Listen on channel', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _Chip(label: 'OMNI', on: midi.channelFilter == -1, onTap: () => midi.setChannelFilter(-1)),
                  for (var c = 0; c < 16; c++)
                    _Chip(label: '${c + 1}', on: midi.channelFilter == c, onTap: () => midi.setChannelFilter(c)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Octave', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 12),
                _Stepper(
                  value: midi.octaveShift,
                  onDown: () => midi.setOctaveShift(midi.octaveShift - 1),
                  onUp: () => midi.setOctaveShift(midi.octaveShift + 1),
                ),
              ],
            ),
            _ToyToggle(label: 'Live play (hear the active voice)', value: midi.livePlay, onChanged: midi.setLivePlay),
            _ToyToggle(label: 'Use velocity for loudness', value: midi.useVelocity, onChanged: midi.setUseVelocity),
            _ToyToggle(label: 'Record into grid while playing', value: midi.recordArm, onChanged: midi.setRecordArm),
          ],
        ),
      );

  Widget _output() => _section(
        'OUTPUT',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ToyToggle(label: 'Send notes out (drive external gear)', value: midi.outEnabled, onChanged: midi.setOutEnabled),
            const SizedBox(height: 6),
            const Text('Export channel', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var c = 0; c < 16; c++)
                    _Chip(label: '${c + 1}', on: midi.outChannel == c, onTap: () => midi.setOutChannel(c)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _controls() => _section(
        'CONTROLS · MIDI LEARN',
        Column(
          children: [
            for (final a in MidiAction.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(width: 108, child: Text(a.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                    Expanded(
                      child: Text(
                        midi.learning == a ? 'press a control…' : (midi.mappings[a]?.label ?? '—'),
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: midi.learning == a ? Toy.accent : Colors.black54,
                        ),
                      ),
                    ),
                    _MiniBtn(
                      label: midi.learning == a ? 'Cancel' : 'Learn',
                      color: midi.learning == a ? Toy.red : Toy.accent,
                      onTap: () => midi.learning == a ? midi.cancelLearn() : midi.startLearn(a),
                    ),
                  ],
                ),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Smart defaults are assignable CCs; Shuttle = jog wheel (CC60). Relearn any to fit your controller.',
                  style: TextStyle(fontSize: 10, color: Colors.black38)),
            ),
          ],
        ),
      );

  Widget _paletteSlots() => _section(
        'PALETTE PADS · MIDI LEARN',
        Column(
          children: [
            if (palette.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Add voices to the palette first.', style: TextStyle(fontSize: 12, color: Colors.black45)),
              ),
            for (var i = 0; i < palette.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(width: 22, child: Text('${i + 1}', style: Toy.label(8, Colors.black45))),
                    Text(palette[i], style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        midi.learningPaletteSlot == i ? 'press a pad/key…' : (midi.paletteBindings[i]?.label ?? '—'),
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: midi.learningPaletteSlot == i ? Toy.accent : Colors.black54,
                        ),
                      ),
                    ),
                    if (midi.paletteBindings[i] != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Clear',
                        onPressed: () => midi.clearPaletteSlot(i),
                      ),
                    _MiniBtn(
                      label: midi.learningPaletteSlot == i ? 'Cancel' : 'Learn',
                      color: midi.learningPaletteSlot == i ? Toy.red : Toy.accent,
                      onTap: () =>
                          midi.learningPaletteSlot == i ? midi.cancelLearn() : midi.startLearnPaletteSlot(i),
                    ),
                  ],
                ),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Map drum pads / keys to the top-row voices. Learns the SLOT — whatever emoji is in it plays.',
                  style: TextStyle(fontSize: 10, color: Colors.black38)),
            ),
          ],
        ),
      );

  Widget _activity() {
    final e = midi.lastEvent;
    final label = e == null
        ? 'waiting for MIDI…'
        : (e.kind == MidiKind.cc
            ? 'CC ${e.data1} = ${e.data2} · ch${e.channel + 1}'
            : '${midiNoteName(e.data1)} (${e.data1}) vel ${e.data2} · ch${e.channel + 1}');
    final vel = (e != null && e.isNoteOn) ? e.data2 / 127.0 : 0.0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: toyBox(fill: const Color(0xFF263238), border: 2, shadow: false),
      child: Row(
        children: [
          const Text('🎵', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFFB2EBF2))),
          ),
          SizedBox(
            width: 60,
            child: LinearProgressIndicator(
              value: vel,
              minHeight: 6,
              backgroundColor: Colors.white24,
              color: Toy.highlight,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  final String label;
  final String? emoji;
  final Color color;
  final VoidCallback onTap;
  const _MiniBtn({required this.label, this.emoji, this.color = Toy.accent, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Toy.text, width: 2),
            boxShadow: const [BoxShadow(color: Toy.text, offset: Offset(2, 2))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (emoji != null) ...[Text(emoji!, style: const TextStyle(fontSize: 12)), const SizedBox(width: 5)],
            Text(label.toUpperCase(), style: Toy.label(7, Colors.white)),
          ]),
        ),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: on ? Toy.highlight : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? Toy.text : const Color(0xFFCFD8DC), width: 2),
          ),
          child: Text(label, style: Toy.label(7, Toy.text)),
        ),
      );
}

class _Stepper extends StatelessWidget {
  final int value;
  final VoidCallback onDown, onUp;
  const _Stepper({required this.value, required this.onDown, required this.onUp});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          _MiniBtn(label: '−', onTap: onDown),
          Container(
            width: 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(value > 0 ? '+$value' : '$value', style: Toy.label(9)),
          ),
          _MiniBtn(label: '+', onTap: onUp),
        ],
      );
}

class _ToyToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToyToggle({required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontSize: 12)),
        value: value,
        onChanged: onChanged,
      );
}
