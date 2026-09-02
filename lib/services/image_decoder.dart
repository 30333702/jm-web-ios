import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

class _DescrambleRequest {
  const _DescrambleRequest({
    required this.rgba,
    required this.width,
    required this.height,
    required this.seed,
  });

  final Uint8List rgba;
  final int width;
  final int height;
  final int seed;
}

/// Reorders the vertical slices of a JM image back to normal order.
///
/// `dart:ui` image decoding must run on the root isolate, then the pure Dart
/// slice reorder and PNG encoding run in a background isolate.
Future<Uint8List> decodeScrambledImage(
  Uint8List raw, {
  required int photoId,
  required String page,
  required int seed,
}) async {
  final codec = await ui.instantiateImageCodec(raw);
  final frame = await codec.getNextFrame();
  final source = frame.image;
  try {
    final width = source.width;
    final height = source.height;
    if (width <= 0 || height <= 0) return raw;
    final pixels = await source.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (pixels == null) return raw;
    return compute(
      _computeDescramble,
      _DescrambleRequest(
        rgba: pixels.buffer.asUint8List(),
        width: width,
        height: height,
        seed: seed,
      ),
    );
  } finally {
    source.dispose();
    codec.dispose();
  }
}

@pragma('vm:entry-point')
Uint8List _computeDescramble(_DescrambleRequest request) {
  final rowBytes = request.width * 4;
  final output = Uint8List(request.rgba.length);
  final sliceHeight = request.height ~/ request.seed;
  final remainder = request.height % request.seed;

  for (var i = 0; i < request.seed; i++) {
    var slice = sliceHeight;
    var destY = sliceHeight * i;
    final sourceY = request.height - sliceHeight * (i + 1) - remainder;
    if (i == 0) {
      slice += remainder;
    } else {
      destY += remainder;
    }
    if (slice <= 0) continue;
    final sourceStart = sourceY * rowBytes;
    final destStart = destY * rowBytes;
    output.setRange(
      destStart,
      destStart + slice * rowBytes,
      request.rgba,
      sourceStart,
    );
  }

  return _encodePng(request.width, request.height, output);
}

Uint8List _encodePng(int width, int height, Uint8List rgba) {
  final image = BytesBuilder();
  image.add(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

  final header = ByteData(13);
  header.setUint32(0, width);
  header.setUint32(4, height);
  header.setUint8(8, 8); // bit depth
  header.setUint8(9, 6); // color type: truecolor with alpha
  _addPngChunk(image, 'IHDR', header.buffer.asUint8List());

  final stride = width * 4;
  final filtered = Uint8List(height * (stride + 1));
  for (var y = 0; y < height; y++) {
    final rowStart = y * (stride + 1);
    filtered[rowStart] = 0; // no per-row PNG filter
    filtered.setRange(rowStart + 1, rowStart + stride + 1, rgba, y * stride);
  }
  final compressed = ZLibEncoder(level: 6).convert(filtered);
  _addPngChunk(image, 'IDAT', compressed);
  _addPngChunk(image, 'IEND', Uint8List(0));
  return image.toBytes();
}

void _addPngChunk(BytesBuilder output, String type, List<int> data) {
  final length = ByteData(4)..setUint32(0, data.length);
  output.add(length.buffer.asUint8List());

  final typeBytes = utf8.encode(type);
  final crcInput = BytesBuilder()
    ..add(typeBytes)
    ..add(data);
  final crc = ByteData(4)..setUint32(0, _crc32(crcInput.toBytes()));
  output
    ..add(typeBytes)
    ..add(data)
    ..add(crc.buffer.asUint8List());
}

int _crc32(List<int> data) {
  var crc = 0xffffffff;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (0xedb88320 ^ (crc >> 1)) : (crc >> 1);
    }
  }
  return crc ^ 0xffffffff;
}
