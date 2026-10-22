// Renders the composer in every iPhone Duo pose, plus an iPad and a phone for
// comparison, and checks nothing tappable sits on the fold.
//
// The PNGs are review images. They're written only when EMOJIO_RENDERS names
// a folder:
//   EMOJIO_RENDERS=../store/duo-renders flutter test test/visual
import 'dart:io';
import 'dart:ui' as ui;

import 'package:emojio/layout.dart';
import 'package:emojio/main.dart';
import 'package:emojio/song.dart';
import 'package:emojio/splash.dart';
import 'package:emojio/staff_painter.dart';
import 'package:emojio/store_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_services.dart';

const _emojiFont = 'Apple Color Emoji';

class _Pose {
  const _Pose(this.name, this.size, this.padding, {this.dpr = 3, this.fold});

  final String name;
  final Size size;
  final EdgeInsets padding;
  final double dpr;

  /// What the Runner's FoldReporter would send for this pose.
  final Map<String, Object>? fold;

  List<ui.DisplayFeature> get features =>
      fold == null ? const [] : decodeFoldEvent([fold]);
}

const _closed = _Pose(
  'closed',
  Size(466, 678),
  EdgeInsets.only(right: 56, bottom: 21),
);
const _book = _Pose(
  'book',
  Size(951, 669),
  EdgeInsets.only(top: 24, bottom: 20),
  fold: {
    'left': 475.5,
    'top': 0.0,
    'width': 0.0,
    'height': 669.0,
    'state': 'halfOpened',
  },
);
const _table = _Pose(
  'table',
  Size(669, 951),
  EdgeInsets.only(top: 24, bottom: 20),
  fold: {
    'left': 0.0,
    'top': 475.5,
    'width': 669.0,
    'height': 0.0,
    'state': 'halfOpened',
  },
);
const _ipad = _Pose(
  'ipad-landscape',
  Size(1194, 834),
  EdgeInsets.only(top: 24, bottom: 20),
  dpr: 2,
);
const _ipadPortrait = _Pose(
  'ipad-portrait',
  Size(834, 1194),
  EdgeInsets.only(top: 24, bottom: 20),
  dpr: 2,
);
const _phone = _Pose(
  'phone',
  Size(390, 844),
  EdgeInsets.only(top: 47, bottom: 34),
);

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  await (FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync()))))
      .load();
}

Future<void> _loadFonts() async {
  await _loadFont('PressStart2P', 'assets/fonts/PressStart2P-Regular.ttf');
  await _loadFont('EmojioClef', 'assets/fonts/EmojioClef.otf');
  await _loadFont(_emojiFont, '/System/Library/Fonts/Apple Color Emoji.ttc');
  // Material icons (the library's delete button), from the SDK under test.
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  await _loadFont(
    'MaterialIcons',
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
}

List<Song> _library() => [
  for (final (name, song) in demoLibrary())
    Song.fresh(
      name: name,
      bpm: song.bpm,
      palette: song.palette,
      selectedEmoji: song.palette.first,
    )..notes = song.notes,
];

/// Boots the composer at [pose] with the demo song open.
Future<void> _boot(
  WidgetTester tester,
  _Pose pose, {
  bool trialRunning = false,
}) async {
  tester.view
    ..physicalSize = pose.size * pose.dpr
    ..devicePixelRatio = pose.dpr
    ..padding = FakeViewPadding(
      left: pose.padding.left * pose.dpr,
      top: pose.padding.top * pose.dpr,
      right: pose.padding.right * pose.dpr,
      bottom: pose.padding.bottom * pose.dpr,
    )
    ..viewPadding = FakeViewPadding(
      left: pose.padding.left * pose.dpr,
      top: pose.padding.top * pose.dpr,
      right: pose.padding.right * pose.dpr,
      bottom: pose.padding.bottom * pose.dpr,
    )
    ..displayFeatures = pose.features;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: emojioTheme(fontFamilyFallback: const [_emojiFont]),
      builder: (context, child) => FoldBridge(child: child!),
      home: HarnessPage(
        key: UniqueKey(),
        services: fakeServices(
          song: demoSong(),
          library: _library(),
          trialRunning: trialRunning,
        ),
      ),
    ),
  );
  // Boot reads the voice manifest from the asset bundle: real I/O, so let real
  // time pass between frames until the splash gives way.
  for (
    var i = 0;
    i < 100 && find.byType(SplashScreen).evaluate().isNotEmpty;
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byType(SplashScreen), findsNothing);
  await _settle(tester);
}

/// Lets boot, sheets and the notes' stamp-in finish. The composer's clock is
/// a real stopwatch, so real time has to pass too.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
    await Future<void>.delayed(const Duration(milliseconds: 450));
  });
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _save(WidgetTester tester, String name) async {
  final dir = Platform.environment['EMOJIO_RENDERS'];
  if (dir == null || dir.isEmpty) return;
  Directory(dir).createSync(recursive: true);
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(view.paintBounds);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

/// Every visible node a user can tap or long-press, with its rect in the
/// window's logical pixels.
List<(String, Rect)> _tappables(WidgetTester tester, double dpr) {
  final out = <(String, Rect)>[];
  void visit(SemanticsNode node, Matrix4 parent) {
    final transform = node.transform == null
        ? parent
        : (parent.clone()..multiply(node.transform!));
    final data = node.getSemanticsData();
    final tappable =
        data.hasAction(SemanticsAction.tap) ||
        data.hasAction(SemanticsAction.longPress);
    // A modal's barrier dismisses it from anywhere around the sheet: not a
    // control on the fold.
    final barrier = data.label == 'Scrim' || data.label == 'Dismiss';
    if (tappable &&
        !barrier &&
        !node.isInvisible &&
        !data.flagsCollection.isHidden) {
      final r = MatrixUtils.transformRect(transform, node.rect);
      final rect = Rect.fromLTRB(
        r.left / dpr,
        r.top / dpr,
        r.right / dpr,
        r.bottom / dpr,
      );
      final label = data.label.isNotEmpty ? data.label : data.tooltip;
      out.add((label, rect));
    }
    node.visitChildren((child) {
      visit(child, transform);
      return true;
    });
  }

  final root =
      tester.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
  if (root != null) visit(root, Matrix4.identity());
  return out;
}

/// Asserts nothing tappable crosses the middle ±16pt of [pose]'s long axis.
void _expectClearOfFold(WidgetTester tester, _Pose pose) {
  final vertical = pose.size.width > pose.size.height;
  final mid = (vertical ? pose.size.width : pose.size.height) / 2;
  final band = vertical
      ? Rect.fromLTRB(mid - 16, 0, mid + 16, pose.size.height)
      : Rect.fromLTRB(0, mid - 16, pose.size.width, mid + 16);
  final nodes = _tappables(tester, pose.dpr);
  expect(nodes, isNotEmpty);
  final onFold = [
    for (final (label, rect) in nodes)
      if (rect.overlaps(band) && !rect.intersect(band).isEmpty) '$label $rect',
  ];
  expect(onFold, isEmpty, reason: '${pose.name}: tappable on the fold');
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    debugStaffFontFallback = const [_emojiFont];
  });
  // The bundle caches the manifest's future, made in the last test's fake-async
  // zone, where it would never complete again.
  setUp(rootBundle.clear);

  for (final pose in [_closed, _book, _table, _ipad, _ipadPortrait, _phone]) {
    testWidgets('${pose.name}: composer', (tester) async {
      final semantics = tester.ensureSemantics();
      await _boot(tester, pose);
      expect(tester.takeException(), isNull);
      await _save(tester, '${pose.name}-composer');
      if (pose.fold != null) _expectClearOfFold(tester, pose);
      semantics.dispose();
    });
  }

  for (final pose in [_closed, _book, _table]) {
    testWidgets('${pose.name}: trial ribbon', (tester) async {
      final semantics = tester.ensureSemantics();
      await _boot(tester, pose, trialRunning: true);
      expect(find.textContaining('Premium free for'), findsOneWidget);
      await _save(tester, '${pose.name}-trial');
      if (pose.fold != null) _expectClearOfFold(tester, pose);
      semantics.dispose();
    });
  }

  for (final pose in [_book, _table]) {
    testWidgets('${pose.name}: song library', (tester) async {
      final semantics = tester.ensureSemantics();
      await _boot(tester, pose);
      await tester.tap(find.text('SONGS'));
      await _settle(tester);
      expect(find.text('Frog Jam'), findsOneWidget);
      await _save(tester, '${pose.name}-library');
      _expectClearOfFold(tester, pose);
      semantics.dispose();
    });

    testWidgets('${pose.name}: sticker picker', (tester) async {
      final semantics = tester.ensureSemantics();
      await _boot(tester, pose);
      await tester.tap(find.bySemanticsLabel('Add a sound'));
      await _settle(tester);
      expect(find.text('CHOOSE YOUR STICKER'), findsOneWidget);
      await _save(tester, '${pose.name}-picker');
      _expectClearOfFold(tester, pose);
      semantics.dispose();
    });

    testWidgets('${pose.name}: paywall', (tester) async {
      final semantics = tester.ensureSemantics();
      await _boot(tester, pose);
      await tester.tap(find.text('PREMIUM'));
      await _settle(tester);
      expect(find.text('EMOJIO PREMIUM'), findsOneWidget);
      await _save(tester, '${pose.name}-paywall');
      _expectClearOfFold(tester, pose);
      semantics.dispose();
    });
  }
}
