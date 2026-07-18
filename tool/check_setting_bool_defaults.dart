import 'dart:io';

Never _fail(String message) {
  stderr.writeln('Setting default validation failed: $message');
  exit(1);
}

Set<String> _settingKeyNames(String source) => RegExp(
  r'setKey:\s*SettingBoxKey\.(\w+)',
).allMatches(source).map((match) => match.group(1)!).toSet();

String _normalizedDefaultFor(String source, String getter) {
  final getterMatch = RegExp(
    'static bool get $getter\\s*=>\\s*([\\s\\S]*?);',
  ).firstMatch(source);
  if (getterMatch == null) {
    _fail('Pref.$getter getter was not found');
  }
  final getterBody = getterMatch.group(1)!;
  final defaultMatch = RegExp(
    r'defaultValue:\s*([^,\n\r\)]+)',
  ).firstMatch(getterBody);
  if (defaultMatch == null) {
    _fail('Pref.$getter does not declare a defaultValue');
  }
  return defaultMatch.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
}

void main() {
  final settingDirectory = Directory('lib/pages/setting');
  if (!settingDirectory.existsSync()) {
    _fail('run this command from the repository root');
  }

  final settingSource = settingDirectory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .map((file) => file.readAsStringSync())
      .join('\n');
  if (RegExp(r'\bdefaultVal\s*:').hasMatch(settingSource)) {
    _fail('settings UI contains a separate defaultVal');
  }

  final uiKeys = _settingKeyNames(settingSource);
  final prefSource = File('lib/utils/storage_pref.dart').readAsStringSync();
  final registryStart = prefSource.indexOf('_boolSettingReaders');
  final registryEnd = prefSource.indexOf(
    'static Iterable<String> get settingBoolKeys',
  );
  if (registryStart < 0 || registryEnd <= registryStart) {
    _fail('Pref boolean setting registry was not found');
  }
  final registrySource = prefSource.substring(registryStart, registryEnd);
  final registeredKeys = RegExp(
    r'SettingBoxKey\.(\w+)\s*:',
  ).allMatches(registrySource).map((match) => match.group(1)!).toSet();

  final unregistered = uiKeys.difference(registeredKeys);
  final stale = registeredKeys.difference(uiKeys);
  if (unregistered.isNotEmpty) {
    _fail('UI keys missing Pref readers: ${unregistered.toList()..sort()}');
  }
  if (stale.isNotEmpty) {
    _fail('Pref readers without UI switches: ${stale.toList()..sort()}');
  }

  const reviewedDefaults = <String, String>{
    'enableCommAntifraud': 'false',
    'biliSendCommAntifraud': 'false',
    'enableCreateDynAntifraud': 'false',
    'enableSponsorBlock': 'false',
    'autoUpdate': 'true',
    'autoPlayEnable': 'false',
    'enableOnlineTotal': 'false',
    'enableAi': 'false',
    'antiGoodsDyn': 'false',
    'removeBlockedDyn': 'false',
    'removeOnlyFansVideoDyn': 'false',
    'antiGoodsReply': 'false',
    'enableQuickDouble': 'true',
    'autoPiP': 'false',
    'enableInAppPip': 'true',
    'enableInAppPipToSystemPip': 'true',
    'slideDismissReplyPage': 'Platform.isIOS',
    'floatingNavBar': 'false',
  };
  for (final entry in reviewedDefaults.entries) {
    final actual = _normalizedDefaultFor(prefSource, entry.key);
    if (actual != entry.value) {
      _fail(
        'Pref.${entry.key} default is $actual; expected ${entry.value}',
      );
    }
  }

  stdout.writeln(
    'Validated ${uiKeys.length} boolean settings against Pref defaults.',
  );
}
