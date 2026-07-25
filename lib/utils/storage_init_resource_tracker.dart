import 'dart:async';

import 'package:hive_ce/hive.dart';

final class StorageInitResourceTracker {
  final List<FutureOr<void> Function()> _disposers = [];
  final Map<String, Future<void> Function()> _newHiveBoxDisposers = {};
  bool _committed = false;

  T own<T>(T resource, FutureOr<void> Function(T resource) dispose) {
    if (_committed) {
      throw StateError('Storage initialization is already committed');
    }
    _disposers.add(() => dispose(resource));
    return resource;
  }

  void watchHiveBox<E>(String name) {
    if (_committed) {
      throw StateError('Storage initialization is already committed');
    }
    if (!Hive.isBoxOpen(name)) {
      final canonicalName = name.toLowerCase();
      _newHiveBoxDisposers.putIfAbsent(
        canonicalName,
        () => () async {
          if (Hive.isBoxOpen(canonicalName)) {
            await Hive.box<E>(canonicalName).close();
          }
        },
      );
    }
  }

  void commit() {
    _committed = true;
    _disposers.clear();
    _newHiveBoxDisposers.clear();
  }

  Future<void> rollback() async {
    if (_committed) return;
    for (final dispose in _disposers.reversed) {
      try {
        await dispose();
      } catch (_) {}
    }
    for (final dispose in _newHiveBoxDisposers.values.toList().reversed) {
      try {
        await dispose();
      } catch (_) {}
    }
    _disposers.clear();
    _newHiveBoxDisposers.clear();
  }
}
