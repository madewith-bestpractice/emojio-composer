import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:app_links/app_links.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'export/song_exporter.dart';
import 'export/wav.dart';
import 'manifest.dart';
import 'midi/clock_out.dart';
import 'midi/host_time.dart';
import 'midi/midi_manager.dart';
import 'midi/midi_panel.dart';
import 'monetization/paywall.dart';
import 'monetization/purchases.dart';
import 'monetization/trial.dart';
import 'picker.dart';
import 'song.dart';
import 'song_library.dart';
import 'splash.dart';
import 'staff_painter.dart';
import 'theme.dart';
import 'voice_engine.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const EmojioApp());
}

class EmojioApp extends StatelessWidget {
  const EmojioApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Emojio',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: Toy.font,
          colorSchemeSeed: Toy.header,
          scaffoldBackgroundColor: Toy.bg,
        ),
        home: const HarnessPage(),
      );
}

const int kCols = 16;

class HarnessPage extends StatefulWidget {
  const HarnessPage({super.key});
  @override
  State<HarnessPage> createState() => _HarnessPageState();
}

class _HarnessPageState extends State<HarnessPage> with SingleTickerProviderStateMixin {
  final _engine = VoiceEngine();
  final _library = SongLibrary();
  final _trial = TrialManager();
  final _purchases = PurchaseManager();
  final _midi = MidiManager();
  MidiClockOut? _clockOut; // MIDI clock master (null if the host clock is unavailable)
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub; // incoming universal/share links
  late final SongExporter _exporter = SongExporter(_engine);
  final GlobalKey _exportKey = GlobalKey(); // share-sheet origin anchor (iPad)
  final GlobalKey _shareKey = GlobalKey(); // share-sheet origin anchor (iPad)
  static const int _exportLoops = 4;
  // Header button size tiers: medium labelled pills vs small icon-only chips.
  static const _medPad = EdgeInsets.symmetric(horizontal: 14, vertical: 10);
  static const _chipPad = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
  final _rng = math.Random();
  final _sw = Stopwatch();
  late final Ticker _ticker;
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0); // drives only the staff CustomPaint
  int _midiDevices = 0; // tracked so device connect/disconnect rebuilds the page
  int _cursorStep = 0; // MIDI shuttle scrub position (shown when stopped)
  int _extClock = 0; // MIDI-clock pulse counter (6 per 16th step)

  bool get _hasAccess => _purchases.unlocked || _trial.active;

  VoiceManifest? _manifest;
  String? _bootError;
  List<String> _palette = [];
  Set<String> _playable = {};
  String _selected = '🐶';

  final List<Note> _notes = [];
  double _bpm = 110;
  bool _playing = false;
  int _currentStep = -1;
  double _playheadFrac = 0;
  int _globalStep = 0; // ever-increasing step counter while playing
  int _playStartMs = 0; // stopwatch ms when play began
  (int, int)? _lastPainted;
  double _lastPressure = 1.0; // latest Apple Pencil pressure (1.0 for finger/mouse)

  // Swing (delays every other 16th for a groovy feel) is fixed off — the header
  // toggle was removed. Transport and export still route through _swing.
  static const double _swing = 0.0;

  String? _currentId;
  String _currentName = 'Untitled';

  int get _rows => _manifest?.scale.length ?? 15;
  int get _nowMs => _sw.elapsedMilliseconds;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _sw.start();
    // MIDI clock master; null if the Mach host clock can't be resolved (non-Apple
    // platform) so the rest of the app is unaffected.
    try {
      _clockOut = MidiClockOut(
        clock: MachHostClock(),
        send: (bytes, ts) => _midi.sendRealtime(bytes, timestamp: ts),
      );
    } catch (e) {
      debugPrint('clock-out unavailable: $e');
    }
    _boot();
  }

  Future<void> _boot() async {
    try {
      // Music-app audio session: plays through the silent/ringer switch and at
      // screen-lock; stop cleanly on interruptions (calls/Siri) and when
      // headphones are unplugged. Guarded so unsupported platforms don't break boot.
      try {
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());
        session.interruptionEventStream.listen((e) {
          if (e.begin && _playing && mounted) _stopTransport();
        });
        session.becomingNoisyEventStream.listen((_) {
          if (_playing && mounted) _stopTransport();
        });
        await session.setActive(true);
      } catch (e) {
        debugPrint('audio session config failed: $e');
      }
      await _trial.ensureStarted();
      _purchases.addListener(_onMonetizationChange);
      await _purchases.init();
      _midi.onNote = _onMidiNote;
      _midi.onAction = _doMidiAction;
      _midi.onShuttle = _shuttle;
      _midi.onPaletteSlot = _selectSlot;
      _midi.onClock = _extClockStep;
      _midi.onStart = _extStart;
      _midi.onContinue = () {
        if (_midi.externalSync) _playing = true;
      };
      _midi.onStop = _extStop;
      _midi.onSongPosition = _extSongPos;
      await _midi.init();
      _midiDevices = _midi.devices.length;
      _midi.addListener(_onMidiDevices);
      final m = await VoiceManifest.load();
      await _engine.init(m);
      final playable = m.playableEmojis();
      final shuffled = List.of(playable)..shuffle(_rng);
      setState(() {
        _manifest = m;
        _playable = playable.toSet();
        _palette = shuffled.take(6).toList();
        if (_palette.isNotEmpty) _selected = _palette.first;
      });
      _ticker.start();
      await _initDeepLinks();
    } catch (e, st) {
      debugPrint('boot failed: $e\n$st');
      setState(() => _bootError = '$e');
    }
  }

  void _onMonetizationChange() {
    if (mounted) setState(() {});
  }

  // Rebuild the page only when the MIDI device list changes (not per note),
  // so the 🎹 button appears/disappears without per-frame page rebuilds.
  void _onMidiDevices() {
    if (mounted && _midi.devices.length != _midiDevices) {
      setState(() => _midiDevices = _midi.devices.length);
    }
    // Also picks up the clock-master / follow-clock toggles flipping mid-play.
    _syncClockOut();
  }

  bool get _clockOutShouldRun => _playing && _midi.sendClock && !_midi.externalSync;

  // Start/stop the clock master to match the transport + settings. Anchored at
  // the same play-press instant as _playStartMs, so the app's audio and the
  // emitted 24-PPQN clock share a downbeat (same host clock, same rate).
  void _syncClockOut() {
    final co = _clockOut;
    if (co == null) return;
    if (_clockOutShouldRun && !co.isRunning) {
      co.start(_bpm);
    } else if (!_clockOutShouldRun && co.isRunning) {
      co.stop();
    }
  }

  // ---- transport ----
  // Swung onset (ms from play start) of global step k: offbeats pushed later.
  double _onsetMs(int k, double stepMs) => (k + (k.isOdd ? _swing : 0.0)) * stepMs;

  void _onTick(Duration _) {
    // Internal clock. When synced to external MIDI clock, the clock handlers
    // drive the step instead (see _extClockStep).
    if (_playing && !_midi.externalSync) {
      final stepMs = 60000 / _bpm / 4;
      final elapsed = _nowMs - _playStartMs;
      // Fire every step whose (swung) onset has passed — catch-up so a laggy
      // frame never drops notes, and swing is honored.
      while (_onsetMs(_globalStep, stepMs) <= elapsed) {
        _currentStep = _globalStep % kCols;
        _playStep(_currentStep);
        _globalStep++;
      }
      // Smooth straight sweep for the playhead (swing is an audio-timing detail).
      final barMs = kCols * stepMs;
      _playheadFrac = (elapsed % barMs) / barMs;
    }
    // Repaint ONLY the staff, and only while something is animating — no
    // whole-page rebuild per frame, and fully idle (0 render CPU) when static.
    final now = _nowMs;
    final animating = _playing || _notes.any((n) => now - n.createdAtMs < 360);
    if (animating) _repaint.value++;
  }

  void _playStep(int step) {
    for (final n in _notes) {
      if (n.gridX != step) continue;
      _engine.playEmoji(n.emoji, n.gridY, velocity: n.velocity);
      if (_midi.outEnabled && _manifest != null) {
        final ev = _manifest!.emojiVoices[n.emoji];
        _midi.sendNote(_engine.midiForRow(n.gridY) + (ev?.semi ?? 0));
      }
    }
  }

  // ---- MIDI input handlers ----
  void _onMidiNote(MidiEvent e) {
    if (_manifest == null || !e.isNoteOn) return;
    if (_midi.channelFilter != -1 && e.channel != _midi.channelFilter) return;
    final ev = _manifest!.emojiVoices[_selected];
    if (ev == null) return;
    final note = (e.data1 + 12 * _midi.octaveShift).clamp(0, 127).toInt();
    final vel = _midi.useVelocity ? (e.data2 / 127).clamp(0.15, 1.0).toDouble() : 1.0;
    if (_midi.livePlay) _engine.playSynth(ev.synth, note, velocity: vel, pan: _engine.panForEmoji(_selected));
    if (_midi.recordArm && _playing && _currentStep >= 0) {
      final gy = _rowForMidi(note, ev.semi);
      if (!_notes.any((n) => n.gridX == _currentStep && n.gridY == gy)) {
        setState(() => _notes.add(Note(_selected, _currentStep, gy, (_rng.nextDouble() - 0.5) * 0.3, _nowMs)));
      }
    }
  }

  void _doMidiAction(MidiAction a) {
    switch (a) {
      case MidiAction.playStop:
        _togglePlay();
      case MidiAction.clear:
        setState(_notes.clear);
      case MidiAction.prevVoice:
        _cycleVoice(-1);
      case MidiAction.nextVoice:
        _cycleVoice(1);
      case MidiAction.octaveDown:
        _midi.setOctaveShift(_midi.octaveShift - 1);
      case MidiAction.octaveUp:
        _midi.setOctaveShift(_midi.octaveShift + 1);
      case MidiAction.shuttle:
        break; // via onShuttle
    }
  }

  void _selectSlot(int i) {
    if (i >= 0 && i < _palette.length) _select(_palette[i]);
  }

  // ---- external MIDI-clock transport (fields mutate; the ticker repaints) ----
  void _extClockStep() {
    if (!_midi.externalSync || !_playing) return;
    if (++_extClock >= 6) {
      _extClock = 0;
      final ns = (_currentStep + 1) % kCols;
      _currentStep = ns;
      _playheadFrac = ns / kCols;
      _playStep(ns);
    }
  }

  void _extStart() {
    if (!_midi.externalSync) return;
    _playing = true;
    _extClock = 0;
    _currentStep = 0;
    _playheadFrac = 0;
    _playStep(0);
  }

  void _extStop() {
    if (!_midi.externalSync) return;
    _playing = false;
    _currentStep = -1;
  }

  void _extSongPos(int beats) {
    if (!_midi.externalSync) return;
    _currentStep = beats % kCols;
    _extClock = 0;
    _playheadFrac = _currentStep / kCols;
  }

  void _cycleVoice(int dir) {
    if (_palette.isEmpty) return;
    final i = _palette.indexOf(_selected);
    final idx = (((i < 0 ? 0 : i) + dir) % _palette.length + _palette.length) % _palette.length;
    _select(_palette[idx]);
  }

  void _shuttle(int delta) {
    setState(() => _cursorStep = ((_cursorStep + delta) % kCols + kCols) % kCols);
    for (final n in _notes) {
      if (n.gridX == _cursorStep) _engine.playEmoji(n.emoji, n.gridY);
    }
  }

  static const _pcNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  String _pcName(int midi) => _pcNames[midi % 12];

  int _rowForMidi(int note, int semi) {
    final target = note - semi;
    var best = 0, bestD = 1 << 30;
    for (var i = 0; i < _rows; i++) {
      final dd = (_engine.midiForRow(i) - target).abs();
      if (dd < bestD) {
        bestD = dd;
        best = i;
      }
    }
    return best;
  }

  void _openMidi() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => FractionallySizedBox(heightFactor: 0.88, child: MidiPanel(midi: _midi, palette: _palette)),
      );

  // ---- export ----
  Future<void> _openExport() async {
    if (_playing) _togglePlay();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('EXPORT', style: Toy.label(11)),
            const SizedBox(height: 6),
            Text('~$_exportLoops loops of your song', style: const TextStyle(fontSize: 11, color: Colors.black54)),
            const SizedBox(height: 18),
            ToyButton(
              label: 'Audio (WAV)',
              emoji: '🎵',
              color: Toy.green,
              fontSize: 11,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              onPressed: () {
                Navigator.pop(ctx);
                _exportAudio();
              },
            ),
            const SizedBox(height: 12),
            ToyButton(
              label: 'Video (MP4)',
              emoji: '🎬',
              color: Toy.accent,
              fontSize: 11,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              onPressed: () {
                Navigator.pop(ctx);
                _exportVideo();
              },
            ),
            const SizedBox(height: 10),
            const Text('Video shows the staff on brand yellow — no app chrome.',
                style: TextStyle(fontSize: 10, color: Colors.black45)),
          ],
        ),
      ),
    );
  }

  String _exportName() {
    final base = _currentName == 'Untitled' ? 'emojio-song' : _currentName;
    final clean = base.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim().replaceAll(' ', '_');
    return clean.isEmpty ? 'emojio-song' : clean;
  }

  void _showProgress(String msg) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Row(children: [
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 16),
            Expanded(child: Text(msg, style: const TextStyle(fontSize: 13))),
          ]),
        ),
      );

  void _dismissProgress() {
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _shareFile(String path, String mime) async {
    final box = _exportKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : null;
    await SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType: mime)], sharePositionOrigin: origin));
  }

  // Render ~[_exportLoops] loops of the song to a shareable WAV in a temp file.
  Future<File> _renderWav() async {
    final r = await _exporter.renderAudio(notes: _notes, bpm: _bpm, swing: _swing, cols: kCols, loops: _exportLoops);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_exportName()}.wav');
    await file.writeAsBytes(encodeWav(r.stereo, sampleRate: r.sampleRate));
    return file;
  }

  Future<void> _exportAudio() async {
    if (_notes.isEmpty) {
      _snack('Add some notes first!');
      return;
    }
    _showProgress('Rendering audio…');
    try {
      final file = await _renderWav();
      _dismissProgress();
      await _shareFile(file.path, 'audio/wav');
    } catch (e, st) {
      debugPrint('audio export failed: $e\n$st');
      _dismissProgress();
      _snack('Export failed: $e');
    }
  }

  // Share the song straight to the iOS share sheet: a link that opens/plays/
  // remixes it in the web player, plus the rendered audio as an attachment.
  Future<void> _shareSong() async {
    if (_notes.isEmpty) {
      _snack('Add some notes first!');
      return;
    }
    if (_playing) _togglePlay();
    _showProgress('Getting your song ready…');
    try {
      final file = await _renderWav();
      final url = webShareUrl(
        bpm: _bpm,
        palette: _palette,
        notes: _notes.map((n) => SongNote(n.emoji, n.gridX, n.gridY, velocity: n.velocity)).toList(),
      );
      _dismissProgress();
      final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
      final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : null;
      await SharePlus.instance.share(ShareParams(
        text: '🎵 Check out my Emojio song!\n$url',
        files: [XFile(file.path, mimeType: 'audio/wav')],
        sharePositionOrigin: origin,
      ));
    } catch (e, st) {
      debugPrint('share failed: $e\n$st');
      _dismissProgress();
      _snack('Share failed: $e');
    }
  }

  Future<void> _exportVideo() async {
    if (_notes.isEmpty) {
      _snack('Add some notes first!');
      return;
    }
    _showProgress('Rendering video…');
    try {
      final r = await _exporter.renderAudio(notes: _notes, bpm: _bpm, swing: _swing, cols: kCols, loops: _exportLoops);
      const fps = 30, width = 1280, height = 720;
      final frameCount = (r.durationSec * fps).round();
      final stepMs = 60000 / _bpm / 4;
      final barMs = kCols * stepMs;
      // Static note copies (no stamp-in animation during export).
      final frameNotes =
          _notes.map((n) => Note(n.emoji, n.gridX, n.gridY, n.rotation, -1000000, velocity: n.velocity)).toList();
      final labels = _engine.scaleMode == ScaleMode.free
          ? null
          : List.generate(_rows, (i) => _pcName(_engine.midiForRow(i)));
      final showClef = _engine.scaleMode == ScaleMode.free;

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${_exportName()}.mp4';
      await FlutterQuickVideoEncoder.setup(
        width: width,
        height: height,
        fps: fps,
        videoBitrate: 4000000,
        profileLevel: ProfileLevel.highAutoLevel,
        audioChannels: 2,
        audioBitrate: 128000,
        sampleRate: r.sampleRate,
        filepath: path,
      );

      final samplesPerFrame = (r.sampleRate / fps).round() * 2; // interleaved stereo
      var audioPos = 0;
      for (var f = 0; f < frameCount; f++) {
        final elapsedMs = f / fps * 1000;
        final rgba = await _renderFrameRgba(
          width,
          height,
          currentStep: (elapsedMs / stepMs).floor() % kCols,
          playheadFrac: (elapsedMs % barMs) / barMs,
          tMs: elapsedMs.round(),
          notes: frameNotes,
          rowLabels: labels,
          showClef: showClef,
        );
        await FlutterQuickVideoEncoder.appendVideoFrame(rgba);
        final end = math.min(audioPos + samplesPerFrame, r.stereo.length);
        if (end > audioPos) {
          await FlutterQuickVideoEncoder.appendAudioFrame(pcm16Bytes(Float32List.sublistView(r.stereo, audioPos, end)));
          audioPos = end;
        }
      }
      if (audioPos < r.stereo.length) {
        await FlutterQuickVideoEncoder.appendAudioFrame(pcm16Bytes(Float32List.sublistView(r.stereo, audioPos)));
      }
      await FlutterQuickVideoEncoder.finish();
      _dismissProgress();
      await _shareFile(path, 'video/mp4');
    } catch (e, st) {
      debugPrint('video export failed: $e\n$st');
      _dismissProgress();
      _snack('Video export failed: $e');
    }
  }

  Future<Uint8List> _renderFrameRgba(
    int width,
    int height, {
    required int currentStep,
    required double playheadFrac,
    required int tMs,
    required List<Note> notes,
    List<String>? rowLabels,
    required bool showClef,
  }) async {
    final recorder = ui.PictureRecorder();
    StaffPainter(
      notes: notes,
      cols: kCols,
      rows: _rows,
      isPlaying: true,
      currentStep: currentStep,
      playheadFrac: playheadFrac,
      tMs: tMs,
      rowLabels: rowLabels,
      showClef: showClef,
      bgColor: const Color(0xFFFFF696), // brand yellow
    ).paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
    final img = await recorder.endRecording().toImage(width, height);
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    return bd!.buffer.asUint8List();
  }

  void _togglePlay() {
    setState(() {
      _playing = !_playing;
      _currentStep = -1;
      if (_playing) {
        _globalStep = 0;
        _playStartMs = _nowMs;
      }
    });
    _syncClockOut();
  }

  void _stopTransport() {
    setState(() {
      _playing = false;
      _currentStep = -1;
    });
    _syncClockOut();
  }

  // ---- editing ----
  void _toggleAt(Offset p, Size size) {
    final hit = StaffMetrics.of(size, kCols, _rows).hitTest(p);
    if (hit == null) return;
    final (gx, gy) = hit;
    final idx = _notes.indexWhere((n) => n.gridX == gx && n.gridY == gy);
    setState(() => idx >= 0 ? _notes.removeAt(idx) : _addNote(gx, gy));
  }

  void _paintAt(Offset p, Size size) {
    final hit = StaffMetrics.of(size, kCols, _rows).hitTest(p);
    if (hit == null || hit == _lastPainted) return;
    _lastPainted = hit;
    final (gx, gy) = hit;
    if (_notes.any((n) => n.gridX == gx && n.gridY == gy)) return;
    setState(() => _addNote(gx, gy));
  }

  void _addNote(int gx, int gy) {
    // Apple Pencil pressure -> velocity (kept above ~0.45 so light taps aren't silent).
    final v = (0.45 + 0.55 * _lastPressure).clamp(0.0, 1.0);
    _notes.add(Note(_selected, gx, gy, (_rng.nextDouble() - 0.5) * 0.3, _nowMs, velocity: v));
    _engine.playEmoji(_selected, gy, velocity: v);
  }

  // Generate a random song from the current palette (ported from the web app):
  // 12-19 notes, biased toward the downbeats (cols 0/4/8/12).
  void _randomize() {
    if (_palette.isEmpty) return;
    setState(() {
      _notes.clear();
      const preferred = [0, 4, 8, 12];
      final count = 12 + _rng.nextInt(8);
      for (var i = 0; i < count; i++) {
        final gx = _rng.nextDouble() < 0.6 ? preferred[_rng.nextInt(preferred.length)] : _rng.nextInt(kCols);
        final gy = _rng.nextInt(_rows);
        if (_notes.any((n) => n.gridX == gx && n.gridY == gy)) continue;
        _notes.add(Note(_palette[_rng.nextInt(_palette.length)], gx, gy, (_rng.nextDouble() - 0.5) * 0.3, _nowMs));
      }
    });
  }

  // ---- palette ----
  void _select(String e) {
    setState(() => _selected = e);
    _engine.playEmoji(e, 7);
  }

  void _addToPalette(String c) {
    setState(() {
      _palette.remove(c);
      if (_palette.length >= 10) _palette.removeAt(0);
      _palette.add(c);
      _selected = c;
    });
    _engine.playEmoji(c, 7);
  }

  Future<void> _openPicker() async {
    final picked = await showEmojiPicker(context, playable: _playable);
    if (picked != null) _addToPalette(picked);
  }

  // ---- library ----
  void _newSong() => setState(() {
        _currentId = null;
        _currentName = 'Untitled';
        _notes.clear();
      });

  Future<void> _saveFlow() async {
    // Stop the transport first (like Library/Export/MIDI do) so the naming
    // dialog + keyboard don't compete with live playback for the CPU — that
    // contention was starving the audio thread (crackle/drop-outs).
    if (_playing) _togglePlay();
    var name = _currentName;
    if (_currentId == null) {
      final entered = await _promptName(initial: name == 'Untitled' ? 'My Song' : name);
      if (entered == null) return;
      name = entered;
    }
    final notes = _notes.map((n) => SongNote(n.emoji, n.gridX, n.gridY, velocity: n.velocity)).toList();
    final Song s;
    if (_currentId == null) {
      s = Song.fresh(name: name, bpm: _bpm, palette: _palette, selectedEmoji: _selected)..notes = notes;
      _currentId = s.id;
    } else {
      s = Song(
        id: _currentId!,
        name: name,
        bpm: _bpm,
        palette: _palette,
        selectedEmoji: _selected,
        notes: notes,
        updatedAt: 0,
      );
    }
    await _library.save(s);
    if (!mounted) return;
    setState(() => _currentName = name);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved "$name"'), duration: const Duration(seconds: 1)));
  }

  Future<String?> _promptName({required String initial}) async {
    final ctrl = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false, // must use Cancel/Save — avoids stray-tap dismissal
        builder: (ctx) => AlertDialog(
          title: const Text('Name your song', style: TextStyle(fontSize: 14)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(hintText: 'e.g. Happy Robot'),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? 'Untitled' : v.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isEmpty ? 'Untitled' : ctrl.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  void _loadSong(Song s) => setState(() {
        _currentId = s.id;
        _currentName = s.name;
        _bpm = s.bpm.clamp(60, 180);
        if (s.palette.isNotEmpty) _palette = s.palette;
        _selected = s.selectedEmoji ?? (_palette.isNotEmpty ? _palette.first : _selected);
        _notes
          ..clear()
          ..addAll(s.notes.map((n) =>
              Note(n.emoji, n.gridX, n.gridY, (_rng.nextDouble() - 0.5) * 0.3, _nowMs, velocity: n.velocity)));
      });

  // ---- deep links ----
  // A shared link (universal link, or one pasted/opened) that carries a song in
  // its `#s=` payload opens it here — on cold start and while already running.
  Future<void> _initDeepLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleIncomingLink(initial);
      _linkSub = _appLinks.uriLinkStream.listen(_handleIncomingLink);
    } catch (e) {
      debugPrint('deep link init failed: $e');
    }
  }

  void _handleIncomingLink(Uri uri) {
    final shared = sharedSongFromUri(uri);
    if (shared == null || !mounted) return;
    _loadShared(shared);
    _snack('Loaded shared song!');
  }

  // Like _loadSong but for an incoming link: no id/name, so it behaves as a
  // fresh unsaved song the recipient can tweak and Save under their own name.
  void _loadShared(SharedSong s) => setState(() {
        _currentId = null;
        _currentName = 'Untitled';
        _bpm = s.bpm.clamp(60, 180);
        if (s.palette.isNotEmpty) _palette = List.of(s.palette);
        if (_palette.isNotEmpty) _selected = _palette.first;
        _notes
          ..clear()
          ..addAll(s.notes.map((n) =>
              Note(n.emoji, n.gridX, n.gridY, (_rng.nextDouble() - 0.5) * 0.3, _nowMs, velocity: n.velocity)));
      });

  Future<void> _openLibrary() async {
    if (_playing) _togglePlay();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _LibrarySheet(
        library: _library,
        rows: _rows,
        currentId: _currentId,
        onLoad: (s) {
          _loadSong(s);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _clockOut?.dispose();
    _ticker.dispose();
    _engine.dispose();
    _purchases.removeListener(_onMonetizationChange);
    _purchases.dispose();
    _midi.removeListener(_onMidiDevices);
    _midi.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _openPaywall() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => Paywall(purchases: _purchases, dismissible: true)),
      );

  @override
  Widget build(BuildContext context) {
    if (_bootError != null) return _errorScreen(_bootError!);
    if (_manifest == null) return const SplashScreen();
    // Hard wall once the 3-day trial ends and the app isn't unlocked.
    if (!_hasAccess) return Paywall(purchases: _purchases, dismissible: false);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, // bars span full width
          children: [
            if (!_purchases.unlocked) TrialBanner(trial: _trial, onTap: _openPaywall),
            _header(),
            _paletteBar(),
            Expanded(child: _staff()),
          ],
        ),
      ),
    );
  }

  Widget _header() => Container(
        decoration: const BoxDecoration(
          color: Toy.header,
          border: Border(bottom: BorderSide(color: Toy.text, width: 4)),
          boxShadow: [BoxShadow(color: Color(0x26000000), offset: Offset(0, 6))],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text('🎵 ${_currentName == 'Untitled' ? 'Emojio Paint Composer' : _currentName}',
                        style: Toy.label(12, Colors.white).copyWith(
                          shadows: const [Shadow(color: Toy.text, offset: Offset(2, 2))],
                        )),
                  ),
                  // Tier 1 — Play: the big, unmissable primary target.
                  ToyButton(
                    label: _playing ? 'Pause' : 'Play',
                    emoji: _playing ? '⏸️' : '▶️',
                    color: _playing ? Toy.red : Toy.green,
                    fontSize: 18,
                    radius: 10, // square-ish corners
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                    onPressed: _togglePlay,
                  ),
                  // Tier 2 — creative actions: medium labelled pills.
                  ToyButton(label: 'Random', emoji: '🎲', color: Colors.white, textColor: Toy.text, padding: _medPad, onPressed: _randomize),
                  ToyButton(label: 'Save', emoji: '💾', color: Toy.highlight, textColor: Toy.text, padding: _medPad, onPressed: _saveFlow),
                  ToyButton(label: 'Songs', emoji: '📂', color: Toy.purple, padding: _medPad, onPressed: _openLibrary),
                  ToyButton(key: _shareKey, label: 'Share', emoji: '🔗', color: Toy.accent, padding: _medPad, onPressed: _shareSong),
                  // Tier 3 — utilities: small icon-only chips (name lives in the tooltip).
                  ToyButton(emoji: '✨', tooltip: 'New song', color: Colors.white, textColor: Toy.text, fontSize: 13, radius: 16, padding: _chipPad, onPressed: _newSong),
                  ToyButton(key: _exportKey, emoji: '📤', tooltip: 'Export audio or video', color: Toy.purple, fontSize: 13, radius: 16, padding: _chipPad, onPressed: _openExport),
                  // Only surfaced once a MIDI controller is plugged in.
                  if (_midi.devices.isNotEmpty)
                    ToyButton(emoji: '🎹', tooltip: 'MIDI', color: Toy.purple, fontSize: 13, radius: 16, padding: _chipPad, onPressed: _openMidi),
                  ToyButton(emoji: '🗑️', tooltip: 'Clear all notes', color: Colors.white, textColor: Toy.text, fontSize: 13, radius: 16, padding: _chipPad, onPressed: () => setState(_notes.clear)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Tempo pinned to the top-right so it never pushes onto a second line.
            _tempo(),
          ],
        ),
      );

  Widget _tempo() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Toy.text, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ExcludeSemantics(child: Text('🐢', style: TextStyle(fontSize: 16))),
            SizedBox(
              width: 130,
              child: Slider(
                min: 60,
                max: 180,
                value: _bpm,
                divisions: 120,
                label: '${_bpm.round()} BPM',
                semanticFormatterCallback: (v) => '${v.round()} beats per minute',
                onChanged: (v) {
                  setState(() => _bpm = v);
                  if (_clockOut?.isRunning ?? false) _clockOut!.setBpm(v);
                },
              ),
            ),
            const ExcludeSemantics(child: Text('🐇', style: TextStyle(fontSize: 16))),
            const SizedBox(width: 6),
            ExcludeSemantics(child: Text('${_bpm.round()}', style: Toy.label(9))),
          ],
        ),
      );

  Widget _paletteBar() => Container(
        color: Toy.panel,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Row(
          children: [
            // Active swatch
            Semantics(
              label: 'Active sound',
              value: _selected,
              excludeSemantics: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('ACTIVE', style: Toy.label(6)),
                  const SizedBox(height: 4),
                  Container(
                    width: 58,
                    height: 58,
                    alignment: Alignment.center,
                    decoration: toyBox(radius: 14),
                    child: Text(_selected, style: const TextStyle(fontSize: 34)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (final e in _palette) _paletteItem(e),
                    _addButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _paletteItem(String e) {
    final on = e == _selected;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Semantics(
        button: true,
        selected: on,
        label: 'Sound $e',
        onTap: () => _select(e),
        child: ExcludeSemantics(
          child: GestureDetector(
            onTap: () => _select(e),
            child: AnimatedContainer(
              duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 100),
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? Toy.highlight : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: on ? Toy.text : Colors.transparent, width: 3),
                boxShadow: [BoxShadow(color: Toy.text.withValues(alpha: on ? 1 : 0.1), offset: const Offset(3, 3))],
              ),
              child: Text(e, style: const TextStyle(fontSize: 30)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _addButton() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Semantics(
          button: true,
          label: 'Add a sound',
          onTap: _openPicker,
          child: ExcludeSemantics(
            child: GestureDetector(
              onTap: _openPicker,
              child: Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFECEFF1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFB0BEC5), width: 3, style: BorderStyle.solid),
                ),
                child: const Text('➕', style: TextStyle(fontSize: 22)),
              ),
            ),
          ),
        ),
      );

  // Capture Apple Pencil pressure (finger/mouse report no useful pressure -> full).
  void _capturePressure(PointerEvent e) {
    _lastPressure = e.kind == PointerDeviceKind.stylus ? e.pressure.clamp(0.0, 1.0) : 1.0;
  }

  Widget _staff() => LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
          return Semantics(
            container: true,
            label: 'Music staff',
            hint: 'Tap a spot to place or remove a sound',
            value: '${_notes.length} sound${_notes.length == 1 ? '' : 's'} placed',
            child: Listener(
              onPointerDown: _capturePressure,
              onPointerMove: _capturePressure,
              child: GestureDetector(
                onTapUp: (d) => _toggleAt(d.localPosition, size),
                onPanStart: (d) {
                  _lastPainted = null;
                  _paintAt(d.localPosition, size);
                },
                onPanUpdate: (d) => _paintAt(d.localPosition, size),
                onPanEnd: (_) => _lastPainted = null,
                child: RepaintBoundary(
                  child: ListenableBuilder(
                    listenable: _repaint,
                    builder: (context, _) => CustomPaint(
                      size: size,
                      painter: StaffPainter(
                        notes: _notes,
                        cols: kCols,
                        rows: _rows,
                        isPlaying: _playing,
                        currentStep: _currentStep,
                        playheadFrac: _playheadFrac,
                        tMs: _nowMs,
                        cursorStep: _playing ? -1 : _cursorStep,
                        rowLabels: _engine.scaleMode == ScaleMode.free
                            ? null
                            : List.generate(_rows, (i) => _pcName(_engine.midiForRow(i))),
                        showClef: _engine.scaleMode == ScaleMode.free,
                        reduceMotion: reduceMotion,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );

  Widget _errorScreen(String msg) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🔇', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text('No baked voices found.', style: Toy.label(12)),
                const SizedBox(height: 10),
                Text(
                  'Run tools/bake-voices.html, then unzip the output into '
                  'app/assets/voices/ (must contain manifest.json).',
                  textAlign: TextAlign.center,
                  style: Toy.label(8).copyWith(height: 1.6),
                ),
                const SizedBox(height: 16),
                Text(msg, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ],
            ),
          ),
        ),
      );
}

/// Bottom sheet listing saved songs with a mini staff preview.
class _LibrarySheet extends StatefulWidget {
  final SongLibrary library;
  final int rows;
  final String? currentId;
  final void Function(Song) onLoad;
  const _LibrarySheet({
    required this.library,
    required this.rows,
    required this.currentId,
    required this.onLoad,
  });

  @override
  State<_LibrarySheet> createState() => _LibrarySheetState();
}

class _LibrarySheetState extends State<_LibrarySheet> {
  late Future<List<Song>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.library.list();
  }

  void _reload() => setState(() => _future = widget.library.list());

  String _ago(int ms) {
    if (ms == 0) return '';
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 420,
      child: FutureBuilder<List<Song>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final songs = snap.data!;
          if (songs.isEmpty) {
            return Center(
              child: Text('No saved songs yet.\nTap Save to keep one.',
                  textAlign: TextAlign.center, style: Toy.label(9).copyWith(height: 1.6)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: songs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = songs[i];
              return ListTile(
                leading: SizedBox(
                  width: 96,
                  height: 54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Toy.text),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CustomPaint(
                        painter: StaffPainter(
                          notes: s.notes.map((n) => Note(n.emoji, n.gridX, n.gridY, 0, -1000000)).toList(),
                          cols: kCols,
                          rows: widget.rows,
                          isPlaying: false,
                          currentStep: -1,
                          playheadFrac: 0,
                          tMs: 0,
                        ),
                      ),
                    ),
                  ),
                ),
                title: Text(s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Toy.label(10, s.id == widget.currentId ? Toy.accent : Toy.text)),
                subtitle: Text('${s.notes.length} notes · ${s.bpm.round()} BPM · ${_ago(s.updatedAt)}',
                    style: const TextStyle(fontSize: 11)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: () async {
                    await widget.library.delete(s.id);
                    _reload();
                  },
                ),
                onTap: () => widget.onLoad(s),
              );
            },
          );
        },
      ),
    );
  }
}
