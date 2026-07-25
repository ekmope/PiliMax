import 'package:PiliMax/utils/app_sign.dart';
import 'package:dio/dio.dart';

enum AppRequestSignTarget { query, map, formData }

enum AppRequestSigningIssue {
  unsupportedBody,
  nonStringMapKey,
  unsupportedFieldValue,
  duplicateField,
  finalizedFormData,
}

final class AppRequestSigningException implements Exception {
  const AppRequestSigningException(this.issue);

  final AppRequestSigningIssue issue;

  @override
  String toString() => 'AppRequestSigningException(${issue.name})';
}

abstract final class AppRequestSigner {
  static const _generatedKeys = {'appkey', 'ts', 'sign'};

  static AppRequestSignTarget sign(
    RequestOptions options, {
    String? accessKey,
  }) {
    final query = options.queryParameters;
    _removeGeneratedMapFields(query);

    final _SignTarget target;
    final data = options.data;
    if (data == null) {
      target = _MapSignTarget(query, AppRequestSignTarget.query);
    } else if (data is Map) {
      final body = _asStringKeyedMap(data);
      _removeGeneratedMapFields(body);
      target = _MapSignTarget(body, AppRequestSignTarget.map);
    } else if (data is FormData) {
      if (data.isFinalized) {
        throw const AppRequestSigningException(
          AppRequestSigningIssue.finalizedFormData,
        );
      }
      target = _FormDataSignTarget(data)..removeGeneratedFields();
    } else {
      throw const AppRequestSigningException(
        AppRequestSigningIssue.unsupportedBody,
      );
    }

    if (accessKey != null && accessKey.isNotEmpty) {
      if (target.kind != AppRequestSignTarget.query) {
        query.remove('access_key');
      }
      target.setField('access_key', accessKey);
    }

    final parameters = <String, dynamic>{};
    _mergeParameters(
      parameters,
      _extractScalarMap(query, allowFiles: false),
    );
    if (target.kind != AppRequestSignTarget.query) {
      _mergeParameters(parameters, target.scalarParameters());
    }

    AppSign.appSign(parameters);
    for (final key in _generatedKeys) {
      target.setField(key, parameters[key]!.toString());
    }
    return target.kind;
  }

  static Map<String, dynamic> _asStringKeyedMap(Map<dynamic, dynamic> source) {
    if (source.keys.any((key) => key is! String)) {
      throw const AppRequestSigningException(
        AppRequestSigningIssue.nonStringMapKey,
      );
    }
    return source.cast<String, dynamic>();
  }

  static void _removeGeneratedMapFields(Map<String, dynamic> target) {
    for (final key in _generatedKeys) {
      target.remove(key);
    }
  }

  static Map<String, dynamic> _extractScalarMap(
    Map<String, dynamic> source, {
    required bool allowFiles,
  }) {
    final result = <String, dynamic>{};
    for (final entry in source.entries) {
      final value = entry.value;
      if (_isFileValue(value)) {
        if (allowFiles) continue;
        throw const AppRequestSigningException(
          AppRequestSigningIssue.unsupportedFieldValue,
        );
      }
      if (value == null) {
        result[entry.key] = '';
      } else if (value is String || value is num || value is bool) {
        result[entry.key] = value;
      } else if (value is Iterable<String>) {
        result[entry.key] = value;
      } else {
        throw const AppRequestSigningException(
          AppRequestSigningIssue.unsupportedFieldValue,
        );
      }
    }
    return result;
  }

  static bool _isFileValue(Object? value) {
    if (value is MultipartFile || value is Iterable<MultipartFile>) {
      return true;
    }
    return value is Iterable &&
        value.isNotEmpty &&
        value.every((element) => element is MultipartFile);
  }

  static void _mergeParameters(
    Map<String, dynamic> destination,
    Map<String, dynamic> source,
  ) {
    for (final entry in source.entries) {
      if (destination.containsKey(entry.key)) {
        throw const AppRequestSigningException(
          AppRequestSigningIssue.duplicateField,
        );
      }
      destination[entry.key] = entry.value;
    }
  }
}

sealed class _SignTarget {
  const _SignTarget(this.kind);

  final AppRequestSignTarget kind;

  Map<String, dynamic> scalarParameters();

  void setField(String key, String value);
}

final class _MapSignTarget extends _SignTarget {
  const _MapSignTarget(this.data, super.kind);

  final Map<String, dynamic> data;

  @override
  Map<String, dynamic> scalarParameters() =>
      AppRequestSigner._extractScalarMap(data, allowFiles: true);

  @override
  void setField(String key, String value) => data[key] = value;
}

final class _FormDataSignTarget extends _SignTarget {
  const _FormDataSignTarget(this.data) : super(AppRequestSignTarget.formData);

  final FormData data;

  void removeGeneratedFields() {
    data.fields.removeWhere(
      (entry) => AppRequestSigner._generatedKeys.contains(entry.key),
    );
  }

  @override
  Map<String, dynamic> scalarParameters() {
    final result = <String, dynamic>{};
    for (final entry in data.fields) {
      final previous = result[entry.key];
      if (previous == null && !result.containsKey(entry.key)) {
        result[entry.key] = entry.value;
      } else if (previous is List<String>) {
        previous.add(entry.value);
      } else {
        result[entry.key] = <String>[previous.toString(), entry.value];
      }
    }
    return result;
  }

  @override
  void setField(String key, String value) {
    data.fields
      ..removeWhere((entry) => entry.key == key)
      ..add(MapEntry(key, value));
  }
}
