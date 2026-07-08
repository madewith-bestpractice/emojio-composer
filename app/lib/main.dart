import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'manifest.dart';
import 'staff_painter.dart';
import 'voice_engine.dart';

void main() => runApp(const EmojioApp());

class EmojioApp extends StatelessWidget {
  const EmojioApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Emojio (Phase-0 harness)',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF81D4FA)),
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
  final _rng = math.Random();
  final _sw = Stopwatch();
  late final Ticker _ticker;

  VoiceManifest? _manifest;
  String? _bootError;
  List<String> _palette = [];
  String _selected = '🐶';

  final List<Note> _notes = [];
  double _bpm = 110;
  bool _playing = false;
  int _currentStep = -1;
  double _playheadFrac = 0;
  int _lastStep = -1;

  int get _rows => _manifest?.scale.length ?? 15;
  int get _nowMs => _sw.elapsedMilliseconds;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _sw.start(); // free-running clock for stamp animations + transport
    _boot();
  }

  Future<void> _boot() async {
    try {
      final m = await VoiceManifest.load();
      await _engine.init(m);
      final playable = m.playableEmojis();
      setState(() {
        _manifest = m;
        _palette = playable.take(12).toList();
        if (_palette.isNotEmpty) _selected = _palette.first;
      });
      _ticker.start(); // keep animating; transport gates on _playing
    } catch (e, st) {
      debugPrint('boot failed: $e\n$st');
      setState(() => _bootError = '$e');
    }
  }

  void _onTick(Duration _) {
    if (_playing) {
      final stepMs = 60000 / _bpm / 4; // 16th notes
      final pos = _sw.elapsedMilliseconds / stepMs;
      final step = pos.floor() % kCols;
      if (step != _lastStep) {
        _lastStep = step;
        _playStep(step);
      }
      _currentStep = step;
      _playheadFrac = (pos % kCols) / kCols;
    }
    if (mounted) setState(() {}); // repaint (playhead + stamp animations)
  }

  void _playStep(int step) {
    if (_manifest == null) return;
    for (final n in _notes) {
      if (n.gridX == step) _engine.playEmoji(n.emoji, n.gridY);
    }
  }

  void _togglePlay() {
    setState(() {
      _playing = !_playing;
      _lastStep = -1;
      _currentStep = -1;
    });
  }

  void _onTapStaff(Offset localPos, Size size) {
    final hit = StaffMetrics.of(size, kCols, _rows).hitTest(localPos);
    if (hit == null) return;
    final (gx, gy) = hit;
    final idx = _notes.indexWhere((n) => n.gridX == gx && n.gridY == gy);
    setState(() {
      if (idx >= 0) {
        _notes.removeAt(idx);
      } else {
        _notes.add(Note(_selected, gx, gy, (_rng.nextDouble() - 0.5) * 0.3, _nowMs));
        _engine.playEmoji(_selected, gy); // audible preview on placement
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bootError != null) return _errorScreen(_bootError!);
    if (_manifest == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: const Color(0xFFE0F7FA),
      body: SafeArea(
        child: Column(
          children: [
            _controls(),
            _paletteBar(),
            _diagnostics(),
            Expanded(child: _staff()),
          ],
        ),
      ),
    );
  }

  Widget _controls() => Container(
        color: const Color(0xFF81D4FA),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Text('🎵 Emojio',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: _togglePlay,
              icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
              label: Text(_playing ? 'Stop' : 'Play'),
              style: FilledButton.styleFrom(
                  backgroundColor: _playing ? const Color(0xFFF44336) : const Color(0xFF4CAF50)),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => setState(_notes.clear),
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              label: const Text('Clear', style: TextStyle(color: Colors.white)),
            ),
            const Spacer(),
            const Text('🐢', style: TextStyle(fontSize: 18)),
            SizedBox(
              width: 180,
              child: Slider(
                min: 60,
                max: 180,
                value: _bpm,
                label: '${_bpm.round()} BPM',
                divisions: 120,
                onChanged: (v) => setState(() => _bpm = v),
              ),
            ),
            const Text('🐇', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text('${_bpm.round()}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      );

  Widget _paletteBar() => Container(
        color: const Color(0xFFFFF9C4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _palette.map((e) {
              final on = e == _selected;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selected = e);
                    _engine.playEmoji(e, 7); // preview around middle of the staff
                  },
                  child: Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on ? const Color(0xFFFFD740) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF37474F), width: on ? 3 : 1),
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 28)),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      );

  Widget _diagnostics() => Container(
        width: double.infinity,
        color: const Color(0xFF263238),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          'engine: ${_engine.ready ? "ready" : "…"}   '
          'samples: ${_engine.sampleCount}   buffer: ${_engine.bufferSize}   '
          'sr: ${_manifest!.sampleRate}   voices(active): ${_engine.activeVoices}   '
          'notes: ${_notes.length}   step: ${_currentStep < 0 ? "-" : _currentStep + 1}/$kCols',
          style: const TextStyle(color: Color(0xFFB2EBF2), fontSize: 11, fontFamily: 'monospace'),
        ),
      );

  Widget _staff() => LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            onTapDown: (d) => _onTapStaff(d.localPosition, size),
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
              ),
            ),
          );
        },
      );

  Widget _errorScreen(String msg) => Scaffold(
        backgroundColor: const Color(0xFFE0F7FA),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🔇', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                const Text('No baked voices found.',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'Run tools/bake-voices.html, then unzip the output into '
                  'app/assets/voices/ (must contain manifest.json).',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(msg, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ],
            ),
          ),
        ),
      );
}
