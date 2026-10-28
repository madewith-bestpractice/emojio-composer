// A virtual CoreMIDI device for testing Emojio's MIDI input, on macOS. Sends MIDI bytes only, so it
// makes no sound. Build: swiftc -O source_only.swift -o source_only
//     source_only <name> [--with-destination]
// Creates a virtual SOURCE called <name> and, with --with-destination, a destination of the same
// name too (a keyboard that exposes both ports). Then sends C4, E4, G4 (note on, note off) every
// 120 ms until killed or 180 s have passed.
import CoreMIDI
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: source_only <name> [--with-destination]"); exit(2) }
let name = args[1]

var client = MIDIClientRef()
var status = MIDIClientCreate(name as CFString, nil, nil, &client)
guard status == noErr else { print("client error \(status)"); exit(1) }
var source = MIDIEndpointRef()
status = MIDISourceCreate(client, name as CFString, &source)
guard status == noErr else { print("source error \(status)"); exit(1) }
if args.contains("--with-destination") {
    var destination = MIDIEndpointRef()
    status = MIDIDestinationCreateWithBlock(client, name as CFString, &destination) { _, _ in }
    guard status == noErr else { print("destination error \(status)"); exit(1) }
}
print("ready \(name)"); fflush(stdout)

func send(_ bytes: [UInt8]) {
    var list = MIDIPacketList()
    let packet = MIDIPacketListInit(&list)
    _ = MIDIPacketListAdd(&list, MemoryLayout<MIDIPacketList>.size, packet, 0, bytes.count, bytes)
    MIDIReceived(source, &list)
}

let start = Date()
let notes: [UInt8] = [60, 64, 67]
var i = 0
while Date().timeIntervalSince(start) < 180 {
    let n = notes[i % notes.count]
    send([0x90, n, 100])
    usleep(60_000)
    send([0x80, n, 0])
    usleep(60_000)
    i += 1
}
