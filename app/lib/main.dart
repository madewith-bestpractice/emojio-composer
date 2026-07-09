import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'manifest.dart';
import 'midi/midi_manager.dart';
import 'midi/midi_panel.dart';
import 'monetization/paywall.dart';
import 'monetization/purchases.dart';
import 'monetization/trial.dart';
import 'picker.dart';
import 'song.dart';
import 'song_library.dart';
import 'staff_painter.dart';
import 'theme.dart';
import 'voice_engine.dart';

void main() => runApp(const EmojioApp());

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
  final _rng = math.Random();
  final _sw = Stopwatch();
  late final Ticker _ticker;
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
  int _lastStep = -1;
  (int, int)? _lastPainted;

  String? _currentId;
  String _currentName = 'Untitled';

  int get _rows => _manifest?.scale.length ?? 15;
  int get _nowMs => _sw.elapsedMilliseconds;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _sw.start();
    _boot();
  }

  Future<void> _boot() async {
    try {
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
    } catch (e, st) {
      debugPrint('boot failed: $e\n$st');
      setState(() => _bootError = '$e');
    }
  }

  void _onMonetizationChange() {
    if (mounted) setState(() {});
  }

  // ---- transport ----
  void _onTick(Duration _) {
    // Internal clock. When synced to external MIDI clock, the clock handlers
    // drive the step instead (see _extClockStep).
    if (_playing && !_midi.externalSync) {
      final stepMs = 60000 / _bpm / 4;
      final pos = _sw.elapsedMilliseconds / stepMs;
      final step = pos.floor() % kCols;
      if (step != _lastStep) {
        _lastStep = step;
        _playStep(step);
      }
      _currentStep = step;
      _playheadFrac = (pos % kCols) / kCols;
    }
    if (mounted) setState(() {});
  }

  void _playStep(int step) {
    final scale = _manifest?.scale;
    for (final n in _notes) {
      if (n.gridX != step) continue;
      _engine.playEmoji(n.emoji, n.gridY);
      if (_midi.outEnabled && scale != null) {
        final ev = _manifest!.emojiVoices[n.emoji];
        _midi.sendNote(noteToMidi(scale[n.gridY]) + (ev?.semi ?? 0));
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
    if (_midi.livePlay) _engine.playSynth(ev.synth, note, velocity: vel);
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

  int _rowForMidi(int note, int semi) {
    final scale = _manifest!.scale;
    final target = note - semi;
    var best = 0, bestD = 1 << 30;
    for (var i = 0; i < scale.length; i++) {
      final dd = (noteToMidi(scale[i]) - target).abs();
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

  void _togglePlay() => setState(() {
        _playing = !_playing;
        _lastStep = -1;
        _currentStep = -1;
      });

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
    _notes.add(Note(_selected, gx, gy, (_rng.nextDouble() - 0.5) * 0.3, _nowMs));
    _engine.playEmoji(_selected, gy);
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
    var name = _currentName;
    if (_currentId == null) {
      final entered = await _promptName(initial: name == 'Untitled' ? 'My Song' : name);
      if (entered == null) return;
      name = entered;
    }
    final notes = _notes.map((n) => SongNote(n.emoji, n.gridX, n.gridY)).toList();
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

  Future<String?> _promptName({required String initial}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
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
  }

  void _loadSong(Song s) => setState(() {
        _currentId = s.id;
        _currentName = s.name;
        _bpm = s.bpm.clamp(60, 180);
        if (s.palette.isNotEmpty) _palette = s.palette;
        _selected = s.selectedEmoji ?? (_palette.isNotEmpty ? _palette.first : _selected);
        _notes
          ..clear()
          ..addAll(s.notes.map((n) => Note(n.emoji, n.gridX, n.gridY, (_rng.nextDouble() - 0.5) * 0.3, _nowMs)));
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
    _ticker.dispose();
    _engine.dispose();
    _purchases.removeListener(_onMonetizationChange);
    _purchases.dispose();
    _midi.dispose();
    super.dispose();
  }

  void _openPaywall() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => Paywall(purchases: _purchases, dismissible: true)),
      );

  @override
  Widget build(BuildContext context) {
    if (_bootError != null) return _errorScreen(_bootError!);
    if (_manifest == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
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
            _diagnostics(),
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
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text('🎵 $_currentName',
                  style: Toy.label(12, Colors.white).copyWith(
                    shadows: const [Shadow(color: Toy.text, offset: Offset(2, 2))],
                  )),
            ),
            ToyButton(
              label: _playing ? 'Stop' : 'Play',
              emoji: _playing ? '⏹️' : '▶️',
              color: _playing ? Toy.red : Toy.green,
              onPressed: _togglePlay,
            ),
            ToyButton(label: 'New', emoji: '✨', color: Colors.white, textColor: Toy.text, onPressed: _newSong),
            ToyButton(label: 'Save', emoji: '💾', onPressed: _saveFlow),
            ToyButton(label: 'Songs', emoji: '📂', color: Toy.purple, onPressed: _openLibrary),
            // Only surfaced once a MIDI controller is plugged in.
            if (_midi.devices.isNotEmpty)
              ToyButton(label: 'MIDI', emoji: '🎹', color: Toy.purple, onPressed: _openMidi),
            ToyButton(label: 'Clear', emoji: '🗑️', color: Colors.white, textColor: Toy.text, onPressed: () => setState(_notes.clear)),
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
            const Text('🐢', style: TextStyle(fontSize: 16)),
            SizedBox(
              width: 130,
              child: Slider(
                min: 60,
                max: 180,
                value: _bpm,
                divisions: 120,
                label: '${_bpm.round()} BPM',
                onChanged: (v) => setState(() => _bpm = v),
              ),
            ),
            const Text('🐇', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text('${_bpm.round()}', style: Toy.label(9)),
          ],
        ),
      );

  Widget _paletteBar() => Container(
        color: Toy.panel,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Row(
          children: [
            // Active swatch
            Column(
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
            const SizedBox(width: 18),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: GestureDetector(
        onTap: () => _select(e),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 52,
          height: 52,
          transform: Matrix4.translationValues(0, on ? -6 : 0, 0),
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
    );
  }

  Widget _addButton() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
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
      );

  Widget _diagnostics() => Container(
        width: double.infinity,
        color: const Color(0xFF263238),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(
          'engine ${_engine.ready ? "ready" : "…"} · samples ${_engine.sampleCount} · '
          'buffer ${_engine.bufferSize} · active ${_engine.activeVoices} · '
          'notes ${_notes.length} · step ${_currentStep < 0 ? "-" : _currentStep + 1}/$kCols',
          style: const TextStyle(color: Color(0xFFB2EBF2), fontSize: 9, fontFamily: 'monospace'),
        ),
      );

  Widget _staff() => LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            onTapUp: (d) => _toggleAt(d.localPosition, size),
            onPanStart: (d) {
              _lastPainted = null;
              _paintAt(d.localPosition, size);
            },
            onPanUpdate: (d) => _paintAt(d.localPosition, size),
            onPanEnd: (_) => _lastPainted = null,
            child: CustomPaint(
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
