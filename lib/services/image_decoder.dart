import 'dart:typed_data';
import 'dart:ui' as ui;

/// 按 jm 客户端算法把原图纵向分片并从底部反向重排为正常图片。
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
    if (height <= 0 || width <= 0) return raw;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint();

    final remainder = height % seed;
    for (var i = 0; i < seed; i++) {
      var sliceHeight = height ~/ seed;
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
      if (byteData == null) return raw;
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
