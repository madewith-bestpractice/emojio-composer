// Emojio patch (flutter_midi_command_darwin 1.0.2): see third_party/flutter_midi_command_darwin/README.md.
import Foundation

/// A virtual device's id is "<destination>:<source>". Either half is empty when
/// the device has only the other: ":<source>" for a source with no destination
/// of the same name (a send-only controller), "<destination>" for the reverse.
///
/// The endpoint refs are the plain decimal CoreMIDI refs.
func parseVirtualDeviceId(_ id: String) -> (destination: UInt32?, source: UInt32?) {
    // omittingEmptySubsequences must be false: the default drops the empty
    // leading half of ":<source>", which then reads as a destination and the
    // source is never connected.
    let parts = id.split(separator: ":", omittingEmptySubsequences: false)
    let destination = parts.count > 0 ? UInt32(parts[0]) : nil
    let source = parts.count > 1 ? UInt32(parts[1]) : nil
    return (destination, source)
}
