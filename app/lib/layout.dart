import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Below this on its shortest side, a window gets the phone composer: the
/// staff scrolls sideways under a pinned clef. A phone, a closed iPhone Duo
/// (about 466 wide) and a narrow iPad Split View pane all land here.
const double kCompactBelow = 600;

/// The band kept clear around a fold: nothing tappable and no note inside it.
const double kFoldBand = 32;

/// The least each half of [ComposerPose.table] needs inside the safe area:
/// the staff's 15 rows at a tappable 24pt above, the palette and controls
/// below.
const double kTableHalfMin = 385;

/// The gap the staff leaves between steps 8 and 9 over a vertical fold. Wider
/// than [kFoldBand] so a bouncing or sharpened note in step 8 or 9 still
/// stays out of the band.
const double kStaffFoldGap = 48;

/// How the composer lays itself out at the window's current size. Chosen from
/// the size and the display's reported fold alone, never the orientation or
/// the device, and re-read on every build, so a fold or a resize mid-session
/// lands in the right one.
enum ComposerPose {
  /// The phone composer: header, palette, then a staff that scrolls sideways.
  compact,

  /// The tablet composer: header, palette, then a staff that shows all 16
  /// steps. An iPad in landscape, a Mac window, and an open iPhone Duo held
  /// like a book (which also has a vertical fold to keep clear).
  regular,

  /// Taller than wide with room for two halves: the staff on the top half,
  /// the palette and controls on the bottom half, a band between them. An
  /// open iPhone Duo standing on a table (a horizontal fold), or an iPad
  /// held upright.
  table,
}

/// The composer's layout for one window size.
@immutable
class ComposerLayout {
  const ComposerLayout._(this.pose, this.size, this.band);

  final ComposerPose pose;
  final Size size;

  /// The band to keep clear, in the window's coordinates. In
  /// [ComposerPose.regular] it's a vertical strip, present only when the
  /// display reports a vertical fold (an iPhone Duo in book, an Android
  /// foldable): an iPad or a Mac window has none, and keeps its layout. In
  /// [ComposerPose.table] it's a horizontal strip centred on the fold the
  /// display reports, else on the middle, so the split reads as deliberate on
  /// any tall window. Null otherwise.
  final Rect? band;

  /// Picks the layout for a window of [size], with safe-area [padding], whose
  /// display reports [features] (`MediaQuery.displayFeatures`).
  factory ComposerLayout.resolve(
    Size size,
    List<DisplayFeature> features, {
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    if (size.shortestSide < kCompactBelow) {
      return ComposerLayout._(ComposerPose.compact, size, null);
    }
    if (size.width > size.height) {
      final fold = _fold(features, size, vertical: true);
      return ComposerLayout._(
        ComposerPose.regular,
        size,
        fold == null ? null : _bandAround(fold, size, vertical: true),
      );
    }
    final fold = _fold(features, size, vertical: false);
    final half = (size.height - kFoldBand) / 2;
    final roomy = half - math.max(padding.top, padding.bottom) >= kTableHalfMin;
    // A real fold across the window always splits: a staff across it would be
    // worse than a short one. Without one, only a window tall enough for both
    // halves does; a squat one keeps the full staff under the header.
    if (fold == null && !roomy) {
      return ComposerLayout._(ComposerPose.regular, size, null);
    }
    return ComposerLayout._(
      ComposerPose.table,
      size,
      _bandAround(
        fold ?? Rect.fromLTWH(0, size.height / 2, size.width, 0),
        size,
        vertical: false,
      ),
    );
  }

  static ComposerLayout of(BuildContext context) => ComposerLayout.resolve(
    MediaQuery.sizeOf(context),
    MediaQuery.displayFeaturesOf(context),
    padding: MediaQuery.paddingOf(context),
  );

  bool get compact => pose == ComposerPose.compact;

  /// The vertical fold band in [ComposerPose.regular], if the display has one.
  Rect? get verticalBand => pose == ComposerPose.regular ? band : null;

  /// Whether the header fits on one row: a window wider than tall. A narrower
  /// one stacks the brand and tempo over a row of buttons.
  bool get oneRowHeader => size.width > size.height;

  /// A fold or hinge [DisplayFeature] that runs across the whole window the
  /// given way: top to bottom when [vertical], side to side otherwise.
  static Rect? _fold(
    List<DisplayFeature> features,
    Size size, {
    required bool vertical,
  }) {
    for (final f in features) {
      if (f.type == DisplayFeatureType.cutout) continue;
      final b = f.bounds;
      final spans = vertical
          ? b.height >= size.height - 1 && b.width < size.width / 2
          : b.width >= size.width - 1 && b.height < size.height / 2;
      if (spans) return b;
    }
    return null;
  }

  /// [fold] widened to at least [kFoldBand] about its centre line.
  static Rect _bandAround(Rect fold, Size size, {required bool vertical}) {
    if (vertical) {
      final w = fold.width < kFoldBand ? kFoldBand : fold.width;
      return Rect.fromLTWH(fold.center.dx - w / 2, 0, w, size.height);
    }
    final h = fold.height < kFoldBand ? kFoldBand : fold.height;
    return Rect.fromLTWH(0, fold.center.dy - h / 2, size.width, h);
  }

  @override
  bool operator ==(Object other) =>
      other is ComposerLayout &&
      other.pose == pose &&
      other.size == size &&
      other.band == band;

  @override
  int get hashCode => Object.hash(pose, size, band);

  @override
  String toString() => 'ComposerLayout($pose, $size, band: $band)';
}

/// The orientations to ask for at a window of [size]: a phone-sized window
/// stands upright (on its side there's no height left for 15 staff rows), a
/// roomier one composes in landscape. iPad, the Mac and an iPhone Duo's inner
/// display ignore the request, and the layout copes with any shape anyway.
List<DeviceOrientation> preferredOrientationsFor(Size size) =>
    size.shortestSide < kCompactBelow
    ? const [DeviceOrientation.portraitUp]
    : const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];

/// Re-asks for [preferredOrientationsFor] whenever the window changes size
/// enough to change the answer. An iPhone Duo moves the app between its outer
/// display (phone-sized: portrait) and its inner one (roomy) as it folds; the
/// choice made at launch would otherwise follow the app onto the wrong one.
class OrientationPolicy extends StatefulWidget {
  const OrientationPolicy({super.key, required this.child});

  final Widget child;

  @override
  State<OrientationPolicy> createState() => _OrientationPolicyState();
}

class _OrientationPolicyState extends State<OrientationPolicy> {
  List<DeviceOrientation>? _asked;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (!size.isEmpty) {
      final want = preferredOrientationsFor(size);
      if (!listEquals(want, _asked)) {
        _asked = want;
        // After the frame: never mid-build, and a burst of resizes during a
        // fold settles on the last one.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && listEquals(_asked, want)) {
            SystemChrome.setPreferredOrientations(want);
          }
        });
      }
    }
    return widget.child;
  }
}

/// Supplies the iPhone Duo's fold to `MediaQuery.displayFeatures`, in the
/// shape Flutter already reports on Android foldables, so [ComposerLayout]
/// and the modal routes (which open on one side of a fold) read one source.
///
/// Flutter doesn't report iOS folds yet (flutter/flutter#193025). The Runner's
/// FoldReporter streams the view's division regions on `emojio/fold`, from
/// the iOS 27.1 SDK; built with an older SDK, or anywhere without a fold, it
/// reports none and this passes [child] through unchanged. Remove it once
/// Flutter reports iOS folds itself.
class FoldBridge extends StatefulWidget {
  const FoldBridge({super.key, required this.child});

  final Widget child;

  static const channel = EventChannel('emojio/fold');

  @override
  State<FoldBridge> createState() => _FoldBridgeState();
}

class _FoldBridgeState extends State<FoldBridge> {
  StreamSubscription<Object?>? _sub;
  List<DisplayFeature> _bridged = const [];

  @override
  void initState() {
    super.initState();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _sub = FoldBridge.channel.receiveBroadcastStream().listen(
      (event) {
        final next = decodeFoldEvent(event);
        if (mounted && !listEquals(next, _bridged)) {
          setState(() => _bridged = next);
        }
      },
      // A build without the native half, or an older iOS: nothing to bridge.
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final own = MediaQuery.displayFeaturesOf(context);
    // Flutter reporting a fold itself means the bridge has retired.
    final hasOwnFold = own.any((f) => f.type != DisplayFeatureType.cutout);
    if (_bridged.isEmpty || hasOwnFold) return widget.child;
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(displayFeatures: [...own, ..._bridged]),
      child: widget.child,
    );
  }
}

/// The native report: a list of `{left, top, width, height, state}` maps in
/// the Flutter view's points. Each becomes a hinge at least [kFoldBand]
/// across, so modal routes (which skip only a fold with some width, or a
/// half-open one) keep clear of the band too.
@visibleForTesting
List<DisplayFeature> decodeFoldEvent(Object? event) {
  if (event is! List) return const [];
  final out = <DisplayFeature>[];
  for (final raw in event) {
    if (raw is! Map) continue;
    double n(String k) => (raw[k] as num? ?? 0).toDouble();
    var r = Rect.fromLTWH(n('left'), n('top'), n('width'), n('height'));
    // A fold runs along its long side; widen its short side to the band.
    if (r.width <= r.height && r.width < kFoldBand) {
      r = Rect.fromLTWH(
        r.center.dx - kFoldBand / 2,
        r.top,
        kFoldBand,
        r.height,
      );
    } else if (r.height < r.width && r.height < kFoldBand) {
      r = Rect.fromLTWH(
        r.left,
        r.center.dy - kFoldBand / 2,
        r.width,
        kFoldBand,
      );
    }
    out.add(
      DisplayFeature(
        bounds: r,
        type: DisplayFeatureType.hinge,
        state: raw['state'] == 'halfOpened'
            ? DisplayFeatureState.postureHalfOpened
            : DisplayFeatureState.postureFlat,
      ),
    );
  }
  return out;
}

/// Where a sheet or dialog should open: with a fold on screen, the right half
/// of a book or the bottom (flat) half of a table, under the hands and off the
/// fold. Null without one, which keeps Flutter's own placement.
Offset? foldAnchor(BuildContext context) {
  final features = MediaQuery.displayFeaturesOf(context);
  if (!features.any((f) => f.type != DisplayFeatureType.cutout)) return null;
  final size = MediaQuery.sizeOf(context);
  return Offset(size.width, size.height);
}
