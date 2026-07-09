import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';

enum MidiKind { noteOn, noteOff, cc, other }

/// App controls that can be driven from MIDI (learnable + smart defaults).
enum MidiAction { playStop, clear, prevVoice, nextVoice, octaveDown, octaveUp, shuttle }

extension MidiActionLabel on MidiAction {
  String get label => switch (this) {
        MidiAction.playStop => 'Play / Stop',
        MidiAction.clear => 'Clear',
        MidiAction.prevVoice => 'Prev voice',
        MidiAction.nextVoice => 'Next voice',
        MidiAction.octaveDown => 'Octave −',
        MidiAction.octaveUp => 'Octave +',
        MidiAction.shuttle => 'Shuttle (scrub)',
      };
  bool get isRelative => this == MidiAction.shuttle;
}

/// A parsed channel-voice message (the subset Phase 1 handles).
class MidiEvent {
  final MidiKind kind;
  final int channel, data1, data2;
  const MidiEvent(this.kind, this.channel, this.data1, this.data2);
  bool get isNoteOn => kind == MidiKind.noteOn;
  bool get isPress => isNoteOn || (kind == MidiKind.cc && data2 > 0);
}

/// A learned binding: which message (note or CC, on a channel) drives an action.
class MidiBinding {
  final MidiKind kind; // noteOn or cc
  final int channel;
  final int data1;
  const MidiBinding(this.kind, this.channel, this.data1);

  bool matches(MidiEvent e) =>
      e.channel == channel &&
      e.data1 == data1 &&
      (kind == MidiKind.cc
          ? e.kind == MidiKind.cc
          : (e.kind == MidiKind.noteOn || e.kind == MidiKind.noteOff));

  String get label => kind == MidiKind.cc ? 'CC $data1·ch${channel + 1}' : 'Note $data1·ch${channel + 1}';
}

/// Note number -> name, e.g. 60 -> "C4".
String midiNoteName(int n) {
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  return '${names[n % 12]}${n ~/ 12 - 1}';
}

/// Relative-CC delta (two's-complement mode, the common jog-wheel encoding).
int relativeDelta(int value) => value == 0 ? 0 : (value < 64 ? value : value - 128);

/// Wraps flutter_midi_command: device discovery/connect (USB-first), parses
/// incoming messages, sends output, and owns the MIDI feature settings +
/// learnable action mappings. The app supplies [onEvent] for note/action work.
class MidiManager extends ChangeNotifier {
  final MidiCommand _midi = MidiCommand();
  StreamSubscription<MidiDataReceivedEvent>? _dataSub;
  StreamSubscription<dynamic>? _setupSub;

  List<MidiDevice> devices = [];
  final Set<String> _connectedIds = {};
  String status = 'Not connected';
  MidiEvent? lastEvent;

  // Input settings
  bool livePlay = true;
  bool recordArm = false;
  bool useVelocity = true;
  int channelFilter = -1; // -1 = Omni
  int octaveShift = 0; // -3..+3

  // Output settings
  bool outEnabled = false;
  int outChannel = 0; // 0..15

  // Learn (one target at a time: an action, or a palette slot index)
  MidiAction? learning;
  int? learningPaletteSlot;

  // Per-palette-slot bindings (index 0..9) — map a pad/key to "select slot N".
  final List<MidiBinding?> paletteBindings = List<MidiBinding?>.filled(10, null);

  // Smart defaults: assignable CCs (kept off the note range so playing doesn't
  // trigger controls) + Mackie jog wheel for shuttle. All relearnable.
  final Map<MidiAction, MidiBinding> mappings = {
    MidiAction.playStop: const MidiBinding(MidiKind.cc, 0, 118),
    MidiAction.clear: const MidiBinding(MidiKind.cc, 0, 119),
    MidiAction.prevVoice: const MidiBinding(MidiKind.cc, 0, 116),
    MidiAction.nextVoice: const MidiBinding(MidiKind.cc, 0, 117),
    MidiAction.octaveDown: const MidiBinding(MidiKind.cc, 0, 114),
    MidiAction.octaveUp: const MidiBinding(MidiKind.cc, 0, 115),
    MidiAction.shuttle: const MidiBinding(MidiKind.cc, 0, 60),
  };

  /// App-supplied handler for musical notes (play/record). Controls are matched
  /// here and surfaced via [onAction] / [onShuttle].
  void Function(MidiEvent)? onNote;
  void Function(MidiAction)? onAction;
  void Function(int delta)? onShuttle;
  void Function(int slot)? onPaletteSlot;

  bool isConnected(MidiDevice d) => _connectedIds.contains(d.id);

  Future<void> init() async {
    try {
      _dataSub = _midi.onMidiDataReceived?.listen(_onData);
      _setupSub = _midi.onMidiSetupChanged?.listen((_) => refresh());
      await refresh();
    } catch (e) {
      status = 'MIDI unavailable: $e';
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    devices = (await _midi.devices) ?? [];
    notifyListeners();
  }

  Future<void> connect(MidiDevice d) async {
    try {
      status = 'Connecting to ${d.name}…';
      notifyListeners();
      await _midi.connectToDevice(d);
      _connectedIds.add(d.id);
      status = 'Connected: ${d.name}';
    } catch (e) {
      status = 'Connect failed: $e';
    }
    await refresh();
  }

  void disconnect(MidiDevice d) {
    _midi.disconnectDevice(d);
    _connectedIds.remove(d.id);
    status = 'Disconnected ${d.name}';
    notifyListeners();
  }

  Future<void> scanBluetooth() async {
    try {
      await _midi.startBluetooth();
      await _midi.startScanningForBluetoothDevices();
      status = 'Scanning for Bluetooth MIDI…';
    } catch (e) {
      status = 'Bluetooth unavailable: $e';
    }
    notifyListeners();
  }

  // ---- settings setters ----
  void setLivePlay(bool v) => _set(() => livePlay = v);
  void setRecordArm(bool v) => _set(() => recordArm = v);
  void setUseVelocity(bool v) => _set(() => useVelocity = v);
  void setChannelFilter(int v) => _set(() => channelFilter = v);
  void setOctaveShift(int v) => _set(() => octaveShift = v.clamp(-3, 3));
  void setOutEnabled(bool v) => _set(() => outEnabled = v);
  void setOutChannel(int v) => _set(() => outChannel = v.clamp(0, 15));

  void _set(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  // ---- learn ----
  MidiBinding _bindingFrom(MidiEvent e) =>
      MidiBinding(e.kind == MidiKind.cc ? MidiKind.cc : MidiKind.noteOn, e.channel, e.data1);

  void startLearn(MidiAction a) => _set(() {
        learning = a;
        learningPaletteSlot = null;
        status = 'Listening… trigger a control for "${a.label}"';
      });

  void startLearnPaletteSlot(int i) => _set(() {
        learningPaletteSlot = i;
        learning = null;
        status = 'Listening… trigger a pad/key for palette slot ${i + 1}';
      });

  void cancelLearn() => _set(() {
        learning = null;
        learningPaletteSlot = null;
        status = 'Ready';
      });

  void clearPaletteSlot(int i) => _set(() => paletteBindings[i] = null);

  void _bindAction(MidiEvent e) {
    final a = learning!;
    mappings[a] = _bindingFrom(e);
    learning = null;
    status = '"${a.label}" → ${mappings[a]!.label}';
    notifyListeners();
  }

  void _bindPaletteSlot(MidiEvent e) {
    final i = learningPaletteSlot!;
    paletteBindings[i] = _bindingFrom(e);
    learningPaletteSlot = null;
    status = 'Palette slot ${i + 1} → ${paletteBindings[i]!.label}';
    notifyListeners();
  }

  // ---- output ----
  void sendNote(int note, {int velocity = 100, Duration off = const Duration(milliseconds: 160)}) {
    if (!outEnabled) return;
    final ch = outChannel & 0x0F;
    final n = note.clamp(0, 127);
    _midi.sendData(Uint8List.fromList([0x90 | ch, n, velocity.clamp(1, 127)]));
    Timer(off, () => _midi.sendData(Uint8List.fromList([0x80 | ch, n, 0])));
  }

  // ---- incoming ----
  void _onData(MidiDataReceivedEvent e) {
    final d = e.message.data;
    var i = 0;
    while (i < d.length) {
      final st = d[i];
      if (st < 0x80) {
        i++;
        continue;
      }
      final hi = st & 0xF0, ch = st & 0x0F;
      if (hi == 0x90 || hi == 0x80 || hi == 0xB0) {
        if (i + 2 >= d.length) break;
        final a = d[i + 1], b = d[i + 2];
        final kind = hi == 0xB0
            ? MidiKind.cc
            : (hi == 0x90 && b > 0 ? MidiKind.noteOn : MidiKind.noteOff);
        _dispatch(MidiEvent(kind, ch, a, b));
        i += 3;
      } else {
        break; // SysEx / system not handled in Phase 1
      }
    }
  }

  void _dispatch(MidiEvent ev) {
    lastEvent = ev;
    if (ev.isPress && learning != null) {
      _bindAction(ev);
      return;
    }
    if (ev.isPress && learningPaletteSlot != null) {
      _bindPaletteSlot(ev);
      return;
    }
    // Shuttle (relative CC) first — it streams non-press values.
    final sh = mappings[MidiAction.shuttle];
    if (sh != null && sh.matches(ev) && ev.kind == MidiKind.cc) {
      final delta = relativeDelta(ev.data2);
      if (delta != 0) onShuttle?.call(delta);
      notifyListeners();
      return;
    }
    if (ev.isPress) {
      // Press-mapped actions.
      for (final entry in mappings.entries) {
        if (entry.key.isRelative) continue;
        if (entry.value.matches(ev)) {
          onAction?.call(entry.key);
          notifyListeners();
          return;
        }
      }
      // Palette-slot pads.
      for (var i = 0; i < paletteBindings.length; i++) {
        if (paletteBindings[i]?.matches(ev) == true) {
          onPaletteSlot?.call(i);
          notifyListeners();
          return;
        }
      }
    }
    // Otherwise it's musical input.
    onNote?.call(ev);
    notifyListeners();
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _setupSub?.cancel();
    super.dispose();
  }
}
