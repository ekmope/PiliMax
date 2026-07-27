import 'dart:convert';

import 'package:PiliMax/common/constants.dart';
import 'package:PiliMax/grpc/bilibili/metadata.pb.dart';
import 'package:PiliMax/grpc/bilibili/metadata/device.pb.dart';
import 'package:PiliMax/grpc/bilibili/metadata/fawkes.pb.dart';
import 'package:PiliMax/grpc/bilibili/metadata/locale.pb.dart';
import 'package:PiliMax/grpc/bilibili/metadata/network.pb.dart' as network;
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/login_utils.dart';
import 'package:PiliMax/utils/utils.dart';

abstract final class GrpcHeaders {
  static const _build = 2001100;
  static const _versionName = '2.0.1';
  static const _biliChannel = 'master';
  static const _mobiApp = 'android_hd';
  static const _device = 'android';

  static const _appBuild = 8430300;
  static const _appVersionName = '8.43.0';
  static const _appMobiApp = 'android';

  static String get _buvid => LoginUtils.buvid;
  static String get _sessionId => Utils.generateSecureRandomString(8);

  static Map<String, String> _baseHeaders({
    required int appId,
    required int build,
    required String versionName,
    required String mobiApp,
    required String userAgent,
    required String buvid,
  }) => {
    'grpc-encoding': 'gzip',
    'gzip-accept-encoding': 'gzip,identity',
    'user-agent': userAgent,
    'x-bili-gaia-vtoken': '',
    'x-bili-aurora-zone': '',
    'x-bili-trace-id': IdUtils.genTraceId(),
    'buvid': buvid,
    'bili-http-engine': 'cronet',
    // 'te': 'trailers', // dio not supported
    'x-bili-device-bin': base64Encode(
      Device(
        appId: appId,
        build: build,
        buvid: buvid,
        mobiApp: mobiApp,
        platform: _device,
        channel: _biliChannel,
        brand: _device,
        model: _device,
        osver: '15',
        versionName: versionName,
      ).writeToBuffer(),
    ),
    'x-bili-network-bin': base64Encode(
      network.Network(type: network.NetworkType.WIFI).writeToBuffer(),
    ),
    'x-bili-locale-bin': base64Encode(
      Locale(
        cLocale: LocaleIds(language: 'zh', region: 'CN', script: 'Hans'),
        sLocale: LocaleIds(language: 'zh', region: 'CN', script: 'Hans'),
        timezone: 'Asia/Shanghai',
      ).writeToBuffer(),
    ),
    'x-bili-exps-bin': '',
  };

  static final Map<String, String> _base = _baseHeaders(
    appId: 5,
    build: _build,
    versionName: _versionName,
    mobiApp: _mobiApp,
    userAgent: Constants.userAgent,
    buvid: _buvid,
  );

  static String _fawkes(String mobiApp) => base64Encode(
    FawkesReq(
      appkey: mobiApp,
      env: 'prod',
      sessionId: _sessionId,
    ).writeToBuffer(),
  );

  static String get fawkes => _fawkes(_mobiApp);

  static Map<String, String> newHeaders([String? accessKey]) {
    return {
      ..._base,
      if (accessKey != null) 'authorization': 'identify_v1 $accessKey',
      'x-bili-fawkes-req-bin': fawkes,
      'x-bili-metadata-bin': base64Encode(
        Metadata(
          accessKey: accessKey,
          mobiApp: _mobiApp,
          device: _device,
          build: _build,
          channel: _biliChannel,
          buvid: _buvid,
          platform: _device,
        ).writeToBuffer(),
      ),
    };
  }

  static Map<String, String> newAppHeaders(String? accessKey, int mid) {
    final buvid = _buvid;
    return {
      ..._baseHeaders(
        appId: 1,
        build: _appBuild,
        versionName: _appVersionName,
        mobiApp: _appMobiApp,
        userAgent: Constants.userAgentApp,
        buvid: buvid,
      ),
      'x-bili-mid': mid.toString(),
      'x-bili-aurora-eid': IdUtils.genAuroraEid(mid),
      if (accessKey != null) 'authorization': 'identify_v1 $accessKey',
      'x-bili-fawkes-req-bin': _fawkes(_appMobiApp),
      'x-bili-metadata-bin': base64Encode(
        Metadata(
          accessKey: accessKey,
          mobiApp: _appMobiApp,
          device: _device,
          build: _appBuild,
          channel: _biliChannel,
          buvid: buvid,
          platform: _device,
        ).writeToBuffer(),
      ),
    };
  }
}
