import 'package:flutter/material.dart';
import 'theme.dart';

/// Boot splash: the Emojio emblem tiled across the brand-yellow field with a
/// gentle breathing animation. Shown while voices load. (The native launch
/// screen — solid yellow + centered logo — sits behind this for the instant
/// before Flutter's first frame.)
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  static const _brandYellow = Color(0xFFFFF696);
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _brandYellow,
      body: LayoutBuilder(
        builder: (context, con) {
          const target = 104.0;
          final cols = (con.maxWidth / target).round().clamp(3, 40);
          final cell = con.maxWidth / cols;
          final rows = (con.maxHeight / cell).ceil() + 1;
          return Stack(
            children: [
              // Tiled emblem field, breathing subtly.
              AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = Curves.easeInOut.transform(_c.value);
                  return Transform.scale(
                    scale: 1.0 + 0.04 * t,
                    child: GridView.count(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      crossAxisCount: cols,
                      children: List.generate(cols * rows, (i) {
                        // Alternate a gentle tilt for a hand-stamped feel.
                        final tilt = (i % 2 == 0 ? 1 : -1) * 0.06;
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Transform.rotate(
                            angle: tilt,
                            child: Image.asset('assets/branding/logo.png', filterQuality: FilterQuality.medium),
                          ),
                        );
                      }),
                    ),
                  );
                },
              ),
              // Hanging Bob — dangles from a string off the top-center, swinging.
              Align(
                alignment: Alignment.topCenter,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) {
                    final swing = (Curves.easeInOut.transform(_c.value) - 0.5) * 0.16; // ~±4.5°
                    return Transform.rotate(
                      alignment: Alignment.topCenter, // pivot at the top of the string
                      angle: swing,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 3, height: 150, color: Toy.text), // string off the top edge
                          Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 4))],
                            ),
                            child: ClipOval(
                              child: Image.asset('assets/branding/bob.png', width: 104, height: 104, fit: BoxFit.cover),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // Loading cue.
              const Align(
                alignment: Alignment(0, 0.86),
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 3, color: Toy.text),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
