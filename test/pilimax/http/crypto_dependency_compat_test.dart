import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AES CBC matches the NIST SP 800-38A vector', () {
    final cipher = encrypt.Encrypter(
      encrypt.AES(
        encrypt.Key.fromBase16('2b7e151628aed2a6abf7158809cf4f3c'),
        mode: encrypt.AESMode.cbc,
        padding: null,
      ),
    );
    final iv = encrypt.IV.fromBase16('000102030405060708090a0b0c0d0e0f');
    final plain = encrypt.Encrypted.fromBase16(
      '6bc1bee22e409f96e93d7e117393172a',
    ).bytes;
    final encrypted = cipher.encryptBytes(plain, iv: iv);
    expect(encrypted.base16, '7649abac8119b246cee98e9b12e9197d');
    expect(cipher.decryptBytes(encrypted, iv: iv), plain);
  });

  test('login RSA parser and PKCS1 encoding preserve Unicode payloads', () {
    // Fixed mathematical test values, unrelated to application signing keys.
    final p = (BigInt.one << 521) - BigInt.one;
    final q = (BigInt.one << 607) - BigInt.one;
    final n = p * q;
    final e = BigInt.from(65537);
    final d = e.modInverse((p - BigInt.one) * (q - BigInt.one));
    final parser = encrypt.RSAKeyParser();
    final dynamic publicKey = parser.parse(_pem('RSA PUBLIC KEY', [n, e]));
    final dynamic privateKey = parser.parse(
      _pem('RSA PRIVATE KEY', [
        BigInt.zero,
        n,
        e,
        d,
        p,
        q,
        d % (p - BigInt.one),
        d % (q - BigInt.one),
        q.modInverse(p),
      ]),
    );
    final cipher = encrypt.Encrypter(
      encrypt.RSA(
        publicKey: publicKey,
        privateKey: privateKey,
      ),
    );
    const payload = 'synthetic-login-hash:测试-password';
    final encrypted = cipher.encrypt(payload);
    expect(encrypted.bytes.length, (n.bitLength + 7) ~/ 8);
    expect(cipher.decrypt(encrypted), payload);
  });
}

String _pem(String label, List<BigInt> values) {
  final body = values.expand((value) {
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    final bytes = <int>[
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
    if (bytes.first >= 128) bytes.insert(0, 0);
    return _der(2, bytes);
  }).toList();
  final encoded = base64Encode(Uint8List.fromList(_der(48, body)));
  return '-----BEGIN $label-----\n$encoded\n-----END $label-----';
}

List<int> _der(int tag, List<int> body) {
  if (body.length < 128) return [tag, body.length, ...body];
  final length = <int>[];
  for (var size = body.length; size > 0; size >>= 8) {
    length.insert(0, size & 255);
  }
  return [tag, 128 | length.length, ...length, ...body];
}
