import 'dart:convert';

/// 源订阅：一个 URL 指向 animeko 兼容的 JSON 清单，
/// 清单内每条记录由对应工厂实例化为可查询的数据源。
class SourceSubscription {
  final String subscriptionId;
  final String url;
  final Duration updatePeriod;
  DateTime? lastUpdateAt;
  int? mediaSourceCount;
  String? lastError;

  SourceSubscription({
    required this.subscriptionId,
    required this.url,
    this.updatePeriod = const Duration(hours: 1),
    this.lastUpdateAt,
    this.mediaSourceCount,
    this.lastError,
  });

  bool get isOutdated =>
      lastUpdateAt == null ||
      DateTime.now().difference(lastUpdateAt!) > updatePeriod;

  Map<String, dynamic> toJson() => {
    'subscriptionId': subscriptionId,
    'url': url,
    'updatePeriodSec': updatePeriod.inSeconds,
    'lastUpdateAt': lastUpdateAt?.millisecondsSinceEpoch,
    'mediaSourceCount': mediaSourceCount,
    'lastError': lastError,
  };

  factory SourceSubscription.fromJson(Map<String, dynamic> json) =>
      SourceSubscription(
        subscriptionId: json['subscriptionId'] as String,
        url: json['url'] as String,
        updatePeriod: Duration(
          seconds: (json['updatePeriodSec'] as num?)?.toInt() ?? 3600,
        ),
        lastUpdateAt: json['lastUpdateAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(json['lastUpdateAt'] as int)
            : null,
        mediaSourceCount: (json['mediaSourceCount'] as num?)?.toInt(),
        lastError: json['lastError'] as String?,
      );
}

/// 订阅清单中的单个数据源导出数据（animeko ExportedMediaSourceData）。
class ExportedMediaSourceData {
  final String factoryId;
  final int version;
  final Map<String, dynamic> arguments;

  const ExportedMediaSourceData({
    required this.factoryId,
    required this.version,
    required this.arguments,
  });

  factory ExportedMediaSourceData.fromJson(Map<String, dynamic> json) =>
      ExportedMediaSourceData(
        factoryId: json['factoryId'] as String,
        version: (json['version'] as num?)?.toInt() ?? 1,
        arguments: (json['arguments'] as Map?)?.cast<String, dynamic>() ?? {},
      );

  Map<String, dynamic> toJson() => {
    'factoryId': factoryId,
    'version': version,
    'arguments': arguments,
  };
}

/// 订阅 URL 返回的顶层 JSON。
class SubscriptionManifest {
  final List<ExportedMediaSourceData> mediaSources;

  const SubscriptionManifest(this.mediaSources);

  static SubscriptionManifest? parse(String body) {
    try {
      final decoded = jsonDecode(body);
      Map root;
      if (decoded is Map && decoded['exportedMediaSourceDataList'] is Map) {
        root = decoded['exportedMediaSourceDataList'] as Map;
      } else if (decoded is Map && decoded['mediaSources'] is List) {
        root = decoded;
      } else {
        return null;
      }
      final list = (root['mediaSources'] as List)
          .whereType<Map>()
          .map(
            (e) => ExportedMediaSourceData.fromJson(
              e.map((k, v) => MapEntry(k.toString(), v)),
            ),
          )
          .toList();
      return SubscriptionManifest(list);
    } catch (_) {
      return null;
    }
  }
}

/// 数据源实例：由订阅或用户手动创建，持久化并可在运行期实例化。
class SourceInstance {
  final String instanceId;
  final String factoryId;
  bool isEnabled;
  int sortOrder;
  String? subscriptionId;
  Map<String, dynamic> arguments;

  SourceInstance({
    required this.instanceId,
    required this.factoryId,
    this.isEnabled = true,
    this.sortOrder = 0,
    this.subscriptionId,
    required this.arguments,
  });

  String get name => (arguments['name'] as String?) ?? instanceId;
  String? get description => arguments['description'] as String?;
  String? get iconUrl => arguments['iconUrl'] as String?;
  int get tier => (arguments['tier'] as num?)?.toInt() ?? 0;

  Map<String, dynamic> toJson() => {
    'instanceId': instanceId,
    'factoryId': factoryId,
    'isEnabled': isEnabled,
    'sortOrder': sortOrder,
    'subscriptionId': subscriptionId,
    'arguments': arguments,
  };

  factory SourceInstance.fromExported(
    ExportedMediaSourceData data, {
    required String instanceId,
    int sortOrder = 0,
    String? subscriptionId,
  }) => SourceInstance(
    instanceId: instanceId,
    factoryId: data.factoryId,
    sortOrder: sortOrder,
    subscriptionId: subscriptionId,
    arguments: data.arguments,
  );

  factory SourceInstance.fromJson(Map<String, dynamic> json) =>
      SourceInstance(
        instanceId: json['instanceId'] as String,
        factoryId: json['factoryId'] as String,
        isEnabled: json['isEnabled'] as bool? ?? true,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        subscriptionId: json['subscriptionId'] as String?,
        arguments:
            (json['arguments'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

/// 一次源查询得到的条目（番剧/影视等聚合条目）。
class SourceSubject {
  final String name;
  final String url;

  const SourceSubject({required this.name, required this.url});
}

/// 条目下的一条线路（如"新番主线①"）。
class SourceChannel {
  final String name;
  final int tier;
  final List<SourceEpisode> episodes;

  const SourceChannel({required this.name, required this.tier, required this.episodes});
}

/// 线路内的一集。
class SourceEpisode {
  final String name;
  final String sort;
  final String pageUrl;

  const SourceEpisode({
    required this.name,
    required this.sort,
    required this.pageUrl,
  });
}

/// 播放资源位置：订阅源产出的资源形态。
sealed class ResourceLocation {
  const ResourceLocation();
}

/// 网页播放页，需要进一步嗅探出直链。
class WebVideoLocation extends ResourceLocation {
  final String uri;
  const WebVideoLocation(this.uri);
}

/// 可直接播放的流媒体直链（m3u8/mp4/mkv）。
class HttpStreamingLocation extends ResourceLocation {
  final String uri;
  const HttpStreamingLocation(this.uri);
}
