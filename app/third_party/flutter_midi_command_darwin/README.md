# flutter_midi_command_darwin (Emojio patch)

Vendored copy of `flutter_midi_command_darwin` **1.0.2** from pub.dev, with one fix.
Emojio points at it with `dependency_overrides` in `app/pubspec.yaml`.

## The bug

A virtual CoreMIDI source with no destination of the same name (a send-only controller, a DAW's
virtual output) is listed with the id `":<sourceRef>"`. `ConnectedVirtualDevice` split that id with
`id.split(separator: ":")`, and Swift's default drops the empty leading half. So `":456"` became
`["456"]`: the source was taken for a destination, `inSource` stayed nil, and
`MIDIPortConnectSource` was never called. The device listed and "connected" but never delivered a
note. Devices that have both ports get the id `"<dest>:<source>"`, which split correctly, so they
were never affected. Physical (USB, network, Bluetooth) devices take a different path and were
never affected either.

## The change

- New `darwin/flutter_midi_command_darwin/Sources/flutter_midi_command_darwin/VirtualDeviceId.swift`:
  `parseVirtualDeviceId(_:)` splits with `omittingEmptySubsequences: false`.
- `SwiftFlutterMidiCommandPlugin.swift`: `ConnectedVirtualDevice.init` uses it instead of the inline split.
- New `Tests/.../VirtualDeviceIdTests.swift`.
- `pubspec.yaml`: version `1.0.2+emojio.1`. Nothing else differs from 1.0.2.

Emojio's check is `app/integration_test/midi_source_only_test.dart` (run with
`app/tool/midi_source_only/run.sh`), which uses a source-only virtual device.

## Dropping this

Remove the `dependency_overrides` entry and this folder once an upstream release ships the same
split fix (report it at https://github.com/InvisibleWrench/FlutterMidiCommand).
