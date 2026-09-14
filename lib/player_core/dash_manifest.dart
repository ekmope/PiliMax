import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/player_core/core_player.dart';

/// 把 B 站 DASH（音视频分离 + segmentBase 字节区间）合成为
/// on-demand profile 的静态 MPD 清单，并经本地 HTTP 服务提供给
/// media3 / VLC 内核播放（bv VlcDashManifest 的 Dart 移植）。
class DashManifestServer {
  DashManifestServer._();

  static DashManifestServer? _instance;
  static DashManifestServer get instance => _instance ??= DashManifestServer._();

  HttpServer? _server;
  final Map<String, String> _manifests = {};

  Future<String> ensureUrl(CoreMediaSource source) async {
    final mpd = buildMpd(source);
    final id = mpd.hashCode.toRadixString(16);
    _manifests[id] = mpd;
    final server = await _ensureServer();
    return 'http://127.0.0.1:${server.port}/manifest/$id.mpd';
  }

  Future<HttpServer> _ensureServer() async {
    final s = _server;
    if (s != null) return s;
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: true,
    );
    _server!.listen((request) {
      final path = request.uri.pathSegments;
      final id = path.length == 2 && path[0] == 'manifest'
          ? path[1].replaceAll('.mpd', '')
          : null;
      final body = id != null ? _manifests[id] : null;
      if (body == null) {
        request.response.statusCode = 404;
        request.response.close();
        return;
      }
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType(
        'application',
        'dash+xml',
      );
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      request.response.add(body.codeUnits);
      request.response.close();
    });
    return _server!;
  }

  void clear() => _manifests.clear();
}

/// 合成 on-demand profile MPD（SegmentBase + indexRange）。
/// media3 的 DashMediaSource 原生解析 sidx；VLC 内核若解析异常则
/// 降级为仅视频流。
String buildMpd(CoreMediaSource source) {
  final videoUrl = source.videoUrl ?? '';
  final audioUrl = source.audioUrl;
  final durationSec = ((source.durationMs ?? 0) / 1000.0).toStringAsFixed(3);
  final vCodecs = _safeCodecs(source.videoCodecs) ?? 'avc1.640028';
  final aCodecs = _safeCodecs(source.audioCodecs) ?? 'mp4a.40.2';

  final buffer = StringBuffer();
  buffer.write('<?xml version="1.0" encoding="UTF-8"?>\n');
  buffer.write(
    '<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" '
    'profiles="urn:mpeg:dash:profile:isoff-on-demand:2011" '
    'type="static" mediaPresentationDuration="PT${durationSec}S" '
    'minBufferTime="PT1.5S">\n',
  );
  buffer.write('  <Period id="0" start="PT0S">\n');
  buffer.write(
    '    <AdaptationSet contentType="video" segmentAlignment="true" '
    'startWithSAP="1">\n',
  );
  buffer.write(
    '      <Representation id="video" mimeType="video/mp4" codecs="$vCodecs"'
    '${source.bandwidth != null ? ' bandwidth="${source.bandwidth}"' : ''}>\n',
  );
  buffer.write(
    '        <BaseURL>${_escape(videoUrl)}</BaseURL>\n'
    '        <SegmentBase indexRange="${source.videoIndexRange ?? '0-1'}" '
    'indexRangeExact="true">\n'
    '          <Initialization range="${source.videoInitRange ?? '0-1'}"/>\n'
    '        </SegmentBase>\n',
  );
  buffer.write('      </Representation>\n    </AdaptationSet>\n');
  if (audioUrl != null && audioUrl.isNotEmpty) {
    buffer.write(
      '    <AdaptationSet contentType="audio" segmentAlignment="true" '
      'startWithSAP="1">\n',
    );
    buffer.write(
      '      <Representation id="audio" mimeType="audio/mp4" codecs="$aCodecs">\n',
    );
    buffer.write(
      '        <BaseURL>${_escape(audioUrl)}</BaseURL>\n'
      '        <SegmentBase indexRange="${source.audioIndexRange ?? '0-1'}" '
      'indexRangeExact="true">\n'
      '          <Initialization range="${source.audioInitRange ?? '0-1'}"/>\n'
      '        </SegmentBase>\n',
    );
    buffer.write('      </Representation>\n    </AdaptationSet>\n');
  }
  buffer.write('  </Period>\n</MPD>\n');
  return buffer.toString();
}

String? _safeCodecs(String? codecs) =>
    codecs == null || codecs.isEmpty ? null : codecs;

String _escape(String url) => url
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
