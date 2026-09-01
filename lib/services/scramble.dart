import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 图片分片加扰参数，与后端 jm-mobile 客户端保持一致。
const seedMap = [2, 4, 6, 8, 10, 12, 14, 16, 18, 20];
const scrambleLeft = 268850;
const scrambleRight = 421925;

int calcSeed(int photoId, String page) {
  final hex = md5.convert(utf8.encode('$photoId$page')).toString();
  var code = hex.codeUnitAt(hex.length - 1);
  if (photoId >= scrambleLeft && photoId <= scrambleRight) {
    code %= 10;
  } else if (photoId > scrambleRight) {
    code %= 8;
  }
  return code >= 0 && code < seedMap.length ? seedMap[code] : 10;
}

bool needsScramble({
  required int photoId,
  required int? scrambleStart,
  required String? speed,
  required String name,
}) {
  if (name.toLowerCase().endsWith('.gif')) return false;
  if (scrambleStart != null && photoId <= scrambleStart) return false;
  if (speed == '1' || speed?.trim() == '1') return false;
  return true;
}
