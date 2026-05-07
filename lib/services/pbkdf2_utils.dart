import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

Uint8List derivePbkdf2Sha256Key(
  String password,
  List<int> salt,
  int iterations,
  int length,
) {
  final passwordBytes = utf8.encode(password);
  final blocks = <int>[];
  var blockIndex = 1;

  while (blocks.length < length) {
    blocks.addAll(
      _pbkdf2Block(passwordBytes, salt, iterations, blockIndex),
    );
    blockIndex += 1;
  }

  return Uint8List.fromList(blocks.take(length).toList());
}

List<int> _pbkdf2Block(
  List<int> passwordBytes,
  List<int> salt,
  int iterations,
  int blockIndex,
) {
  final hmac = Hmac(sha256, passwordBytes);
  final indexBytes = ByteData(4)..setUint32(0, blockIndex);
  var u = hmac.convert([...salt, ...indexBytes.buffer.asUint8List()]).bytes;
  final output = List<int>.from(u);

  for (var i = 1; i < iterations; i += 1) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < output.length; j += 1) {
      output[j] ^= u[j];
    }
  }

  return output;
}

bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;

  var difference = 0;
  for (var i = 0; i < a.length; i += 1) {
    difference |= a[i] ^ b[i];
  }

  return difference == 0;
}
