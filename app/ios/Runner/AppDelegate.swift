import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var foldReporter: FoldReporter?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "EmojioFoldReporter") {
      foldReporter = FoldReporter(registrar: registrar)
    }
  }
}

/// Streams the iPhone Duo's fold to Flutter, which doesn't report iOS folds
/// itself yet (flutter/flutter#193025), on the `emojio/fold` event channel: a
/// list of `{left, top, width, height, state}` maps in the Flutter view's
/// points, which lib/layout.dart's FoldBridge merges into
/// MediaQuery.displayFeatures. Empty without a fold (iPad, any iPhone, the
/// closed Duo).
///
/// The fold is the view's division reserved region; whether it's half or
/// fully open comes from UIHingeInteraction. Both exist only in the iOS 27.1
/// SDK, so that code compiles only when EMOJIO_SDK_27_1 is set (per SDK, in
/// Flutter/Debug.xcconfig and Release.xcconfig). Built with an earlier SDK it
/// reports nothing, and such a build runs letterboxed on the Duo anyway.
/// Adapted from volca_fold's FoldWatcher.
final class FoldReporter: NSObject, FlutterStreamHandler {
  private let watcher: FoldWatcher

  @MainActor init(registrar: FlutterPluginRegistrar) {
    watcher = FoldWatcher(registrar: registrar)
    super.init()
    FlutterEventChannel(name: "emojio/fold", binaryMessenger: registrar.messenger())
      .setStreamHandler(self)
  }

  // Flutter calls stream handlers on the main thread.
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    let watcher = self.watcher
    MainActor.assumeIsolated { watcher.sink = events }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    let watcher = self.watcher
    MainActor.assumeIsolated { watcher.sink = nil }
    return nil
  }
}

/// Watches the Flutter view: its size (the fold moves in view points as the
/// device turns) and the hinge. Sends the fold whenever it changes, and once
/// when Flutter starts listening.
@MainActor
private final class FoldWatcher {
  private weak var registrar: FlutterPluginRegistrar?
  private weak var view: UIView?
  private var boundsObservation: NSKeyValueObservation?
  private var attachTries = 0
  /// UIHinge.Status's raw value as last reported; 0 (unknown) until then.
  private var hingeStatus = 0
  private var last: [[String: Any]]?

  var sink: FlutterEventSink? {
    didSet {
      last = nil
      attach()
      emit()
    }
  }

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  /// Finds the Flutter view once there is one; a listen can come before the
  /// view controller is on screen, so it retries for a few seconds.
  private func attach() {
    guard view == nil else { return }
    guard let controller = registrar?.viewController, let view = controller.viewIfLoaded else {
      guard attachTries < 50 else { return }
      attachTries += 1
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
        self?.attach()
        self?.emit()
      }
      return
    }
    self.view = view
    boundsObservation = view.layer.observe(\.bounds, options: [.new]) { [weak self] _, _ in
      DispatchQueue.main.async { MainActor.assumeIsolated { self?.emit() } }
    }
    #if EMOJIO_SDK_27_1
      if #available(iOS 27.1, *) {
        view.addInteraction(
          UIHingeInteraction { [weak self] _, update in
            self?.hingeStatus = update.hinge?.status.rawValue ?? 0
            self?.emit()
          })
      }
    #endif
  }

  private func emit() {
    guard let sink = sink else { return }
    let features = currentFeatures()
    if let last = last, NSArray(array: last).isEqual(to: features) { return }
    last = features
    sink(features)
  }

  /// The fold while the device is open, half or fully; nothing when closed or
  /// on a device without one. Before the hinge has reported, an active
  /// division region still counts.
  private func currentFeatures() -> [[String: Any]] {
    #if EMOJIO_SDK_27_1
      if #available(iOS 27.1, *), let view = view {
        let state: String
        switch UIHinge.Status(rawValue: hingeStatus) {
        case .partiallyOpen?: state = "halfOpened"
        case .fullyOpen?: state = "flat"
        case .closed?: return []
        default: state = "unknown"
        }
        // Fully open, the fold's region is inactive, but the crease is there.
        let regions = view.reservedRegions(kind: .division, options: .includeInactive)
        return regions.filter { state != "unknown" || $0.isActive }.map { region in
          [
            "left": region.frame.minX, "top": region.frame.minY,
            "width": region.frame.width, "height": region.frame.height,
            "state": state,
          ]
        }
      }
    #endif
    return []
  }
}
