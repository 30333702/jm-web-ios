import 'package:flutter_test/flutter_test.dart';
import 'package:jm_web_client/services/scramble.dart';

void main() {
  group('calcSeed', () {
    test('returns a supported slice count', () {
      for (final page in ['00001', '00012', '00033', '00100']) {
        final seed = calcSeed(1081229, page);
        expect(seedMap, contains(seed));
      }
    });

    test('old photos always fall back to ten slices', () {
      final seed = calcSeed(120, '00007');
      expect(seed, 10);
    });
  });

  group('needsScramble', () {
    test('gif images are kept original', () {
      expect(
        needsScramble(
          photoId: 1081229,
          scrambleStart: 220980,
          speed: '',
          name: '00001.gif',
        ),
        isFalse,
      );
    });

    test('images before scramble id stay original', () {
      expect(
        needsScramble(
          photoId: 100000,
          scrambleStart: 220980,
          speed: '',
          name: '00001.webp',
        ),
        isFalse,
      );
    });

    test('speed equal to one stays original', () {
      expect(
        needsScramble(
          photoId: 1081229,
          scrambleStart: 220980,
          speed: '1',
          name: '00001.webp',
        ),
        isFalse,
      );
    });

    test('normal chapter image needs scramble', () {
      expect(
        needsScramble(
          photoId: 1081229,
          scrambleStart: 220980,
          speed: '',
          name: '00001.webp',
        ),
        isTrue,
      );
    });
  });
}
