import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_web_client/services/image_decoder.dart';

void main() {
  test('decodeScrambledImage restores reversed vertical slices', () async {
    const width = 7;
    const height = 23;
    const seed = 5;

    final original = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final index = (y * width + x) * 4;
        original[index] = (y * 11 + x * 3) & 0xff;
        original[index + 1] = (y * 5 + x * 7) & 0xff;
        original[index + 2] = (y * 7 + x * 2) & 0xff;
        original[index + 3] = 0xff;
      }
    }

    final sourceImage = await _imageFromRgba(original, width, height);
    final scrambledPng = await _encodeScrambledPng(
      sourceImage,
      width: width,
      height: height,
      seed: seed,
    );
    sourceImage.dispose();

    final restored = await decodeScrambledImage(
      scrambledPng,
      photoId: 1,
      page: '00001',
      seed: seed,
    );
    final codec = await ui.instantiateImageCodec(restored);
    final frame = await codec.getNextFrame();
    try {
      final pixels = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      expect(pixels, isNotNull);
      expect(pixels!.buffer.asUint8List(), orderedEquals(original));
    } finally {
      frame.image.dispose();
      codec.dispose();
    }
  });
}

Future<ui.Image> _imageFromRgba(Uint8List rgba, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

Future<Uint8List> _encodeScrambledPng(
  ui.Image source, {
  required int width,
  required int height,
  required int seed,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

  final sliceHeight = height ~/ seed;
  final remainder = height % seed;
  for (var i = 0; i < seed; i++) {
    var slice = sliceHeight;
    var sourceY = sliceHeight * i;
    final destinationY = height - sliceHeight * (i + 1) - remainder;
    if (i == 0) {
      slice += remainder;
    } else {
      sourceY += remainder;
    }
    if (slice <= 0) continue;
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(
        0,
        sourceY.toDouble(),
        width.toDouble(),
        slice.toDouble(),
      ),
      ui.Rect.fromLTWH(
        0,
        destinationY.toDouble(),
        width.toDouble(),
        slice.toDouble(),
      ),
      paint,
    );
  }

  final picture = recorder.endRecording();
  final encoded = await picture.toImage(width, height);
  try {
    final png = await encoded.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  } finally {
    encoded.dispose();
    picture.dispose();
  }
}
