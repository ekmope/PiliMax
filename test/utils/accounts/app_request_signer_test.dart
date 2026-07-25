import 'dart:convert';

import 'package:PiliMax/common/constants.dart';
import 'package:PiliMax/utils/accounts/account_manager/app_request_signer.dart';
import 'package:PiliMax/utils/app_sign.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppRequestSigner', () {
    test('signs query parameters when there is no body', () {
      final options = RequestOptions(
        path: 'https://app.bilibili.com/x/test',
        queryParameters: {'foo': 'bar'},
      );

      final target = AppRequestSigner.sign(options, accessKey: 'access');

      expect(target, AppRequestSignTarget.query);
      expect(options.queryParameters['access_key'], 'access');
      _expectValidSignature(options.queryParameters);
    });

    test('signs query and scalar Map fields into the body', () {
      final body = <String, dynamic>{'body': 2, 'enabled': true};
      final options = RequestOptions(
        path: 'https://app.bilibili.com/x/test',
        method: 'POST',
        queryParameters: {'query': 'one'},
        data: body,
      );

      final target = AppRequestSigner.sign(options, accessKey: 'access');

      expect(target, AppRequestSignTarget.map);
      expect(options.queryParameters, {'query': 'one'});
      expect(body['access_key'], 'access');
      _expectValidSignature({...options.queryParameters, ...body});
    });

    test('signs FormData scalar fields without signing or removing files', () {
      final form = FormData.fromMap({
        'title': 'test',
        'file': MultipartFile.fromBytes([1, 2, 3], filename: 'private.bin'),
      });
      final options = RequestOptions(
        path: 'https://app.bilibili.com/x/test',
        method: 'POST',
        queryParameters: {'query': 'one'},
        data: form,
      );

      final target = AppRequestSigner.sign(options, accessKey: 'access');
      final fields = <String, dynamic>{
        for (final field in form.fields) field.key: field.value,
      };

      expect(target, AppRequestSignTarget.formData);
      expect(form.files, hasLength(1));
      expect(form.files.single.key, 'file');
      expect(fields, isNot(contains('file')));
      _expectValidSignature({...options.queryParameters, ...fields});
    });

    test('keeps raw Map file values out of the signature', () {
      final file = MultipartFile.fromBytes([1], filename: 'private.bin');
      final body = <String, dynamic>{'title': 'test', 'file': file};
      final options = RequestOptions(
        path: 'https://app.bilibili.com/x/test',
        method: 'POST',
        data: body,
      );

      AppRequestSigner.sign(options);

      expect(body['file'], same(file));
      _expectValidSignature({...body}..remove('file'));
    });

    test('supports all documented scalar and repeated string values', () {
      final body = <String, dynamic>{
        'nullable': null,
        'count': 2,
        'enabled': true,
        'tags': <String>['one', 'two'],
      };
      final options = RequestOptions(
        path: 'https://app.bilibili.com/x/test',
        method: 'POST',
        data: body,
      );

      AppRequestSigner.sign(options);

      _expectValidSignature({...body, 'nullable': ''});
    });

    test('rejects malformed Map fields without leaking their values', () {
      expect(
        () => AppRequestSigner.sign(
          RequestOptions(
            path: 'https://app.bilibili.com/x/test',
            data: <Object, Object>{1: 'private-value'},
          ),
        ),
        throwsA(
          isA<AppRequestSigningException>().having(
            (error) => error.issue,
            'issue',
            AppRequestSigningIssue.nonStringMapKey,
          ),
        ),
      );

      expect(
        () => AppRequestSigner.sign(
          RequestOptions(
            path: 'https://app.bilibili.com/x/test',
            data: <String, dynamic>{'field': DateTime.utc(2026)},
          ),
        ),
        throwsA(
          isA<AppRequestSigningException>().having(
            (error) => error.issue,
            'issue',
            AppRequestSigningIssue.unsupportedFieldValue,
          ),
        ),
      );
    });

    test('rejects FormData that has already been finalized', () {
      final form = FormData.fromMap({'field': 'value'})..finalize();

      expect(
        () => AppRequestSigner.sign(
          RequestOptions(
            path: 'https://app.bilibili.com/x/test',
            method: 'POST',
            data: form,
          ),
        ),
        throwsA(
          isA<AppRequestSigningException>().having(
            (error) => error.issue,
            'issue',
            AppRequestSigningIssue.finalizedFormData,
          ),
        ),
      );
    });

    test('rejects unsupported bodies and ambiguous duplicate fields', () {
      expect(
        () => AppRequestSigner.sign(
          RequestOptions(
            path: 'https://app.bilibili.com/x/test',
            method: 'POST',
            data: 'raw-body',
          ),
        ),
        throwsA(
          isA<AppRequestSigningException>().having(
            (e) => e.issue,
            'issue',
            AppRequestSigningIssue.unsupportedBody,
          ),
        ),
      );

      expect(
        () => AppRequestSigner.sign(
          RequestOptions(
            path: 'https://app.bilibili.com/x/test',
            queryParameters: {'same': 'query'},
            data: <String, dynamic>{'same': 'body'},
          ),
        ),
        throwsA(
          isA<AppRequestSigningException>().having(
            (e) => e.issue,
            'issue',
            AppRequestSigningIssue.duplicateField,
          ),
        ),
      );
    });
  });
}

void _expectValidSignature(Map<String, dynamic> signed) {
  final actual = signed['sign'];
  final unsigned = Map<String, dynamic>.from(signed)..remove('sign');
  final expected = md5
      .convert(utf8.encode(AppSign.makeQuery(unsigned) + Constants.appSec))
      .toString();
  expect(actual, expected);
}
