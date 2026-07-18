import 'package:PiliMax/utils/custom_font_manager.dart';
import 'package:PiliMax/utils/storage.dart';

final class GStorageCustomFontSettingsStore implements CustomFontSettingsStore {
  const GStorageCustomFontSettingsStore();

  @override
  bool containsKey(String key) => GStorage.setting.containsKey(key);

  @override
  Object? read(String key) => GStorage.setting.get(key);

  @override
  Future<void> putAll(Map<String, Object?> values) =>
      GStorage.setting.putAll(values);

  @override
  Future<void> deleteAll(Iterable<String> keys) =>
      GStorage.setting.deleteAll(keys);
}
