import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

class _ScrambleRequest {
  const _ScrambleRequest({
    required this.raw,
    required this.photoId,
    required this.page,
    required this.seed,
  });

  final Uint8List raw;
  final int photoId;
  final String page;
  final int seed;
}

/// Reorders the vertical slices of a JM image back to normal order.
///
/// The work happens in a background isolate so the reader UI stays responsive.
Future<Uint8List> decodeScrambledImage(
  Uint8List raw, {
  required int photoId,
  required String page,
  required int seed,
}) {
  return compute(
    _decodeScrambledIsolate,
    _ScrambleRequest(raw: raw, photoId: photoId, page: page, seed: seed),
  );
}

@pragma('vm:entry-point')
Future<Uint8List> _decodeScrambledIsolate(_ScrambleRequest request) async {
  final codec = await ui.instantiateImageCodec(request.raw);
  final frame = await codec.getNextFrame();
  final source = frame.image;
  try {
    final width = source.width;
    final height = source.height;
    if (height <= 0 || width <= 0) return request.raw;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint();

    final remainder = height % request.seed;
    for (var i = 0; i < request.seed; i++) {
      var sliceHeight = height ~/ request.seed;
      var destY = sliceHeight * i;
      final sourceY = height - sliceHeight * (i + 1) - remainder;
      if (i == 0) {
        sliceHeight += remainder;
      } else {
        destY += remainder;
      }
      if (sliceHeight <= 0) continue;
      canvas.drawImageRect(
        source,
        ui.Rect.fromLTWH(
          0,
          sourceY.toDouble(),
          width.toDouble(),
          sliceHeight.toDouble(),
        ),
        ui.Rect.fromLTWH(
          0,
          destY.toDouble(),
          width.toDouble(),
          sliceHeight.toDouble(),
        ),
        paint,
      );
    }

    final picture = recorder.endRecording();
    final output = await picture.toImage(width, height);
    try {
      final byteData = await output.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return request.raw;
      return byteData.buffer.asUint8List();
    } finally {
      output.dispose();
      picture.dispose();
    }
  } finally {
    source.dispose();
    codec.dispose();
  }
}
