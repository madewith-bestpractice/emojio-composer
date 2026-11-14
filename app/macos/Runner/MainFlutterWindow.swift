import Cocoa
import CoreAudioKit
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var bluetoothMidiWindow: CABTLEMIDIWindowController?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Scan Bluetooth in the 🎹 sheet opens Apple's Bluetooth MIDI window (the
    // one Audio MIDI Setup shows). A device connected there is an ordinary
    // CoreMIDI device, which the MIDI plugin lists and connects like USB.
    let bluetoothMidi = FlutterMethodChannel(
      name: "emojio/bluetooth_midi",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    bluetoothMidi.setMethodCallHandler { [weak self] call, result in
      guard call.method == "show" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let controller = self?.bluetoothMidiWindow ?? CABTLEMIDIWindowController()
      self?.bluetoothMidiWindow = controller
      controller.showWindow(nil)
      controller.window?.makeKeyAndOrderFront(nil)
      result(true)
    }

    super.awakeFromNib()
  }
}
