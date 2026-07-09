import 'dart:typed_data';

int _i16(double s) {
  if (s > 1) s = 1;
  if (s < -1) s = -1;
  return (s * 32767).round();
}

/// Encode interleaved float samples (-1..1) to a 16-bit PCM WAV file.
Uint8List encodeWav(Float32List interleaved, {required int sampleRate, int channels = 2}) {
  final dataBytes = interleaved.length * 2;
  final out = ByteData(44 + dataBytes);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      out.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  out.setUint32(4, 36 + dataBytes, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, channels, Endian.little);
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * channels * 2, Endian.little); // byte rate
  out.setUint16(32, channels * 2, Endian.little); // block align
  out.setUint16(34, 16, Endian.little); // bits per sample
  str(36, 'data');
  out.setUint32(40, dataBytes, Endian.little);
  var o = 44;
  for (var i = 0; i < interleaved.length; i++) {
    out.setInt16(o, _i16(interleaved[i]), Endian.little);
    o += 2;
  }
  return out.buffer.asUint8List();
}

/// Interleaved float -> raw 16-bit little-endian PCM (for the video encoder).
Uint8List pcm16Bytes(Float32List interleaved) {
  final out = ByteData(interleaved.length * 2);
  var o = 0;
  for (var i = 0; i < interleaved.length; i++) {
    out.setInt16(o, _i16(interleaved[i]), Endian.little);
    o += 2;
  }
  return out.buffer.asUint8List();
}
