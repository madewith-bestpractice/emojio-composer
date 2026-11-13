// Needs a virtual MIDI device running beside it: tool/midi_source_only/run.sh starts one.
//
// A send-only virtual CoreMIDI source (no destination of its own) must list, connect and deliver
// notes through MidiManager. flutter_midi_command_darwin 1.0.2 listed it but never connected its
// input; see third_party/flutter_midi_command_darwin/README.md.
import 'package:emojio/midi/midi_manager.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _name = String.fromEnvironment('MIDI_TEST_DEVICE', defaultValue: 'Emojio Test Source');
// 'in' = a source only (inputs, no outputs); 'both' = a source plus a destination of the same name.
const _shape = String.fromEnvironment('MIDI_TEST_SHAPE', defaultValue: 'in');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a virtual MIDI device lists, connects and delivers notes ($_shape)', (tester) async {
    final midi = MidiManager();
    final notes = <MidiEvent>[];
    midi.onNote = notes.add;
    // Loads any saved midi_config.json; the test only the test from a user's saved midi_config.json.
    await midi.init();
    addTearDown(midi.dispose);

    MidiDevice? device;
    for (var i = 0; i < 50 && device == null; i++) {
      await midi.refresh();
      for (final d in midi.devices) {
        if (d.name == _name) device = d;
      }
      if (device == null) await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(device, isNotNull, reason: 'the device "$_name" should be listed; got ${midi.devices.map((d) => d.name)}');
    expect(device!.inputPorts, isNotEmpty);
    expect(device.outputPorts.isEmpty, _shape == 'in');

    await midi.connect(device);
    expect(midi.isConnected(device), isTrue, reason: midi.status);

    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (notes.where((e) => e.isNoteOn).length < 3 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final ons = notes.where((e) => e.isNoteOn).map((e) => e.data1).toList();
    expect(ons.length, greaterThanOrEqualTo(3), reason: 'no notes arrived from "$_name"');
    expect(ons.toSet(), containsAll(<int>[60, 64, 67]));
    expect(notes.any((e) => e.kind == MidiKind.noteOff), isTrue);

    midi.disconnect(device);
    // Let the setup-changed refresh that a disconnect triggers finish before dispose.
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
}
