import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:path_provider/path_provider.dart';
import 'host_time.dart';

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

  Map<String, dynamic> toJson() => {'k': kind.index, 'ch': channel, 'd': data1};
  factory MidiBinding.fromJson(Map<String, dynamic> j) =>
      MidiBinding(MidiKind.values[j['k'] as int], j['ch'] as int, j['d'] as int);
}

/// Note number -> name, e.g. 60 -> "C4".
String midiNoteName(int n) {
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  return '${names[n % 12]}${n ~/ 12 - 1}';
}

/// Relative-CC encodings for jog/shuttle wheels (vendor-dependent, so the user
/// picks). twosComplement: +1..+63=0x01..0x3F, −=0x7F..0x41. signedBit: bit6 is
/// the sign, low 6 bits the magnitude. binOffset: 0x40=no change, offset from 64.
enum RelMode { twosComplement, signedBit, binOffset }

extension RelModeLabel on RelMode {
  String get label => switch (this) {
        RelMode.twosComplement => "2's comp",
        RelMode.signedBit => 'Signed',
        RelMode.binOffset => 'Offset',
      };
}

int decodeRelative(int value, RelMode mode) {
  switch (mode) {
    case RelMode.twosComplement:
      return (value == 0 || value == 64) ? 0 : (value < 64 ? value : value - 128);
    case RelMode.signedBit:
      final mag = value & 0x3F;
      return (value & 0x40) != 0 ? -mag : mag;
    case RelMode.binOffset:
      return value - 64;
  }
}

/// Wraps flutter_midi_command: device discovery/connect (USB-first), parses
/// incoming messages, sends output, and owns the MIDI feature settings +
/// learnable action mappings. The app supplies [onEvent] for note/action work.
class MidiManager extends ChangeNotifier {
  final MidiCommand _midi = MidiCommand();
  StreamSubscription<MidiDataReceivedEvent>? _dataSub;
  StreamSubscription<dynamic>? _setupSub;
  File? _cfgFile;
  Timer? _saveTimer;

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
  RelMode shuttleMode = RelMode.twosComplement;

  // Output settings
  bool outEnabled = false;
  int outChannel = 0; // 0..15
  bool sendClock = false; // emit 24-PPQN clock + transport as master

  // External sync (MIDI clock / Song Position) — external device drives transport
  bool externalSync = false;
  double? syncedBpm; // estimated from incoming clock
  DateTime? _lastClock;
  int _clockNotify = 0;

  // Hardware-timestamped clock-interval jitter (µs), from received packet
  // timestamps — the measurement for the loopback clock-out test, and a live
  // quality readout when following an external clock.
  HostClock? _hostClock;
  int? _lastClockTicks;
  double _clockIntervalAvgTicks = 0;
  double clockJitterUs = 0;

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
  // Transport sync (only meaningful when externalSync is on)
  void Function()? onClock; // 24 PPQN pulse
  void Function()? onStart;
  void Function()? onStop;
  void Function()? onContinue;
  void Function(int beats)? onSongPosition; // 1 beat = one 16th step

  bool isConnected(MidiDevice d) => _connectedIds.contains(d.id);

  Future<void> init() async {
    await _load(); // restore saved mappings + settings first
    try {
      _hostClock = MachHostClock();
    } catch (_) {
      // non-Apple platform — jitter readout stays 0, everything else works
    }
    try {
      _dataSub = _midi.onMidiDataReceived?.listen(_onData);
      _setupSub = _midi.onMidiSetupChanged?.listen((_) => refresh());
      await refresh();
    } catch (e) {
      status = 'MIDI unavailable: $e';
      notifyListeners();
    }
  }

  // ---- persistence (mappings + settings survive restarts) ----
  Future<File> _configFile() async {
    if (_cfgFile != null) return _cfgFile!;
    final dir = await getApplicationDocumentsDirectory();
    return _cfgFile = File('${dir.path}/midi_config.json');
  }

  Map<String, dynamic> _toJson() => {
        'channelFilter': channelFilter,
        'octaveShift': octaveShift,
        'useVelocity': useVelocity,
        'livePlay': livePlay,
        'recordArm': recordArm,
        'outEnabled': outEnabled,
        'outChannel': outChannel,
        'sendClock': sendClock,
        'externalSync': externalSync,
        'shuttleMode': shuttleMode.index,
        'mappings': {for (final e in mappings.entries) e.key.name: e.value.toJson()},
        'paletteBindings': [for (final b in paletteBindings) b?.toJson()],
      };

  Future<void> _load() async {
    try {
      final f = await _configFile();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      channelFilter = j['channelFilter'] as int? ?? channelFilter;
      octaveShift = j['octaveShift'] as int? ?? octaveShift;
      useVelocity = j['useVelocity'] as bool? ?? useVelocity;
      livePlay = j['livePlay'] as bool? ?? livePlay;
      recordArm = j['recordArm'] as bool? ?? recordArm;
      outEnabled = j['outEnabled'] as bool? ?? outEnabled;
      outChannel = j['outChannel'] as int? ?? outChannel;
      sendClock = j['sendClock'] as bool? ?? sendClock;
      externalSync = j['externalSync'] as bool? ?? externalSync;
      final sm = j['shuttleMode'] as int?;
      if (sm != null && sm >= 0 && sm < RelMode.values.length) shuttleMode = RelMode.values[sm];
      final mp = j['mappings'] as Map<String, dynamic>?;
      if (mp != null) {
        for (final a in MidiAction.values) {
          final b = mp[a.name];
          if (b != null) mappings[a] = MidiBinding.fromJson(b as Map<String, dynamic>);
        }
      }
      final pb = j['paletteBindings'] as List?;
      if (pb != null) {
        for (var i = 0; i < paletteBindings.length && i < pb.length; i++) {
          paletteBindings[i] = pb[i] == null ? null : MidiBinding.fromJson(pb[i] as Map<String, dynamic>);
        }
      }
    } catch (_) {
      // ignore corrupt config
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        await (await _configFile()).writeAsString(jsonEncode(_toJson()));
      } catch (_) {}
    });
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
  void setShuttleMode(RelMode m) => _set(() => shuttleMode = m);
  void setOutEnabled(bool v) => _set(() => outEnabled = v);
  void setOutChannel(int v) => _set(() => outChannel = v.clamp(0, 15));
  void setSendClock(bool v) => _set(() {
        sendClock = v;
        if (v) externalSync = false; // master and follower are mutually exclusive
      });
  void setExternalSync(bool v) => _set(() {
        externalSync = v;
        if (!v) syncedBpm = null;
        if (v) sendClock = false; // master and follower are mutually exclusive
      });

  void _set(VoidCallback fn) {
    fn();
    notifyListeners();
    _scheduleSave();
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
    _scheduleSave();
  }

  void _bindPaletteSlot(MidiEvent e) {
    final i = learningPaletteSlot!;
    paletteBindings[i] = _bindingFrom(e);
    learningPaletteSlot = null;
    status = 'Palette slot ${i + 1} → ${paletteBindings[i]!.label}';
    notifyListeners();
    _scheduleSave();
  }

  // ---- output ----
  void sendNote(int note, {int velocity = 100, Duration off = const Duration(milliseconds: 160)}) {
    if (!outEnabled) return;
    final ch = outChannel & 0x0F;
    final n = note.clamp(0, 127);
    _midi.sendData(Uint8List.fromList([0x90 | ch, n, velocity.clamp(1, 127)]));
    Timer(off, () => _midi.sendData(Uint8List.fromList([0x80 | ch, n, 0])));
  }

  /// Send a System Real-Time / Common message (no channel) to connected outputs,
  /// optionally stamped at a future host-time [timestamp] (Mach ticks) for precise
  /// delivery. Used by the clock-out master; independent of [outEnabled].
  void sendRealtime(List<int> bytes, {int? timestamp}) {
    _midi.sendData(Uint8List.fromList(bytes), timestamp: timestamp);
  }

  void _onClockPulse(int tsTicks) {
    onClock?.call();
    final now = DateTime.now();
    if (_lastClock != null) {
      final us = now.difference(_lastClock!).inMicroseconds;
      if (us > 0) {
        final bpm = 60000000.0 / (us * 24); // 24 PPQN
        syncedBpm = syncedBpm == null ? bpm : syncedBpm! * 0.8 + bpm * 0.2;
      }
    }
    _lastClock = now;
    _measureClockJitter(tsTicks);
    if (++_clockNotify >= 24) {
      _clockNotify = 0;
      notifyListeners(); // ~once per quarter, for the BPM + jitter readout
    }
  }

  // Rolling deviation of the received clock interval from its own running mean,
  // measured from hardware packet timestamps (µs). Resets across a stop/start
  // gap (an interval far larger than the running mean).
  void _measureClockJitter(int tsTicks) {
    final hc = _hostClock;
    final last = _lastClockTicks;
    if (hc != null && last != null) {
      final dt = tsTicks - last;
      if (dt > 0) {
        if (_clockIntervalAvgTicks != 0 && dt > _clockIntervalAvgTicks * 3) {
          _clockIntervalAvgTicks = 0; // gap → restart the average
          clockJitterUs = 0;
        } else {
          _clockIntervalAvgTicks =
              _clockIntervalAvgTicks == 0 ? dt.toDouble() : _clockIntervalAvgTicks * 0.9 + dt * 0.1;
          final devUs = hc.ticksToNanos((dt - _clockIntervalAvgTicks).abs().round()) / 1000.0;
          clockJitterUs = clockJitterUs * 0.8 + devUs * 0.2;
        }
      }
    }
    _lastClockTicks = tsTicks;
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
      // System real-time (single byte) — can interleave anywhere.
      if (st >= 0xF8) {
        switch (st) {
          case 0xF8:
            _onClockPulse(e.timestamp);
          case 0xFA:
            onStart?.call();
            notifyListeners();
          case 0xFB:
            onContinue?.call();
            notifyListeners();
          case 0xFC:
            onStop?.call();
            notifyListeners();
        }
        i++;
        continue;
      }
      // System common.
      if (st == 0xF2) {
        // Song Position Pointer: 14-bit, LSB then MSB, in 16th-note beats.
        if (i + 2 >= d.length) break;
        onSongPosition?.call(d[i + 1] | (d[i + 2] << 7));
        notifyListeners();
        i += 3;
        continue;
      }
      if (st == 0xF0) {
        // SysEx: skip to end (0xF7).
        var j = i + 1;
        while (j < d.length && d[j] != 0xF7) {
          j++;
        }
        i = j + 1;
        continue;
      }
      if (st == 0xF1 || st == 0xF3) {
        i += 2; // MTC quarter-frame / song select
        continue;
      }
      // Channel-voice.
      final hi = st & 0xF0, ch = st & 0x0F;
      if (hi == 0x90 || hi == 0x80 || hi == 0xB0) {
        if (i + 2 >= d.length) break;
        final a = d[i + 1], b = d[i + 2];
        final kind = hi == 0xB0
            ? MidiKind.cc
            : (hi == 0x90 && b > 0 ? MidiKind.noteOn : MidiKind.noteOff);
        _dispatch(MidiEvent(kind, ch, a, b));
        i += 3;
        continue;
      }
      if (hi == 0xC0 || hi == 0xD0) {
        i += 2; // program change / channel pressure
        continue;
      }
      if (hi == 0xA0 || hi == 0xE0) {
        i += 3; // poly aftertouch / pitch bend
        continue;
      }
      i++; // unknown
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
      final delta = decodeRelative(ev.data2, shuttleMode);
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
    _saveTimer?.cancel();
    super.dispose();
  }
}
