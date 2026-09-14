import 'package:PiliPlus/services/source_subscription/models.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// web-selector 通用源引擎（animeko SelectorMediaSource 的 Dart 移植）。
/// 按 searchConfig 中的 CSS 选择器与正则抓取第三方站点。
class SelectorEngine {
  SelectorEngine(this.instance) {
    final cfg = instance.arguments['searchConfig'];
    _cfg = cfg is Map ? cfg.cast<String, dynamic>() : const {};
  }

  final SourceInstance instance;
  late final Map<String, dynamic> _cfg;
  final CookieJar _cookieJar = CookieJar();

  String? _str(String key) => _cfg[key] is String ? _cfg[key] as String : null;

  Map<String, dynamic>? _map(String key) =>
      _cfg[key] is Map ? (_cfg[key] as Map).cast<String, dynamic>() : null;

  Dio _dio() {
    final dio = Dio(
      BaseOptions(
        headers: {
          'user-agent':
              'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
          if (_str('rawBaseUrl') case final base? when base.isNotEmpty)
            'referer': base,
        },
        followRedirects: true,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    // 依赖 cookie_jar 包，但 dio_cookie_manager 未在 pubspec 中；保留 jar 实例以便
    // 后续接入扩展（这里仅作占位，不实际拦截请求）。
    return dio;
  }

  /// 请求限速（毫秒间隔），对同一源的连续请求生效。
  static final Map<String, DateTime> _lastRequestAt = {};

  Future<void> _throttle() async {
    final interval = (_cfg['requestInterval'] as num?)?.toInt() ?? 0;
    if (interval <= 0) return;
    final key = instance.instanceId;
    final last = _lastRequestAt[key];
    if (last != null) {
      final wait = interval - DateTime.now().difference(last).inMilliseconds;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
    }
    _lastRequestAt[key] = DateTime.now();
  }

  Future<String?> _get(String url) async {
    await _throttle();
    try {
      final res = await _dio().get<String>(url);
      if (res.statusCode == 200) return res.data;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 拉取页面源码（供直链正则匹配）。
  Future<String?> fetchPageHtml(String url) => _get(url);

  /// 搜索关键词，返回条目列表。
  Future<List<SourceSubject>> search(String keyword) async {
    final searchUrl = _str('searchUrl');
    if (searchUrl == null) return const [];
    var kw = keyword.trim();
    if (_cfg['searchUseOnlyFirstWord'] == true) {
      kw = kw.split(RegExp(r'\s+')).first;
    }
    if (_cfg['searchRemoveSpecial'] == true) {
      kw = kw.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9]+'), ' ');
    }
    final url = searchUrl.replaceAll('{keyword}', Uri.encodeComponent(kw));
    final html = await _get(url);
    if (html == null) return const [];
    return parseSubjectList(html, _resolveBase(searchUrl));
  }

  String _resolveBase(String url) =>
      _str('rawBaseUrl')?.isNotEmpty == true
          ? _str('rawBaseUrl')!
          : Uri.parse(url).replace(path: '', query: '').toString();

  /// 解析搜索结果页的条目列表（支持 indexed / flattened 两种条目格式）。
  List<SourceSubject> parseSubjectList(String html, String base) {
    final doc = html_parser.parse(html);
    final formatId = _str('subjectFormatId') ?? 'flattened';
    final results = <SourceSubject>[];

    if (formatId == 'indexed') {
      final cfg = _map('selectorSubjectFormatIndexed');
      final selectNames = cfg?['selectNames'] as String?;
      final selectLinks = cfg?['selectLinks'] as String?;
      if (selectNames == null || selectLinks == null) return const [];
      final names = doc.querySelectorAll(selectNames);
      final links = doc.querySelectorAll(selectLinks);
      for (int i = 0; i < names.length && i < links.length; i++) {
        final name = names[i].text.trim();
        final href = links[i].attributes['href'];
        if (name.isNotEmpty && href != null) {
          results.add(SourceSubject(name: name, url: _abs(href, base)));
        }
      }
    } else {
      final cfg = _map('selectorSubjectFormatFlattened');
      final selectItems =
          cfg?['selectItems'] as String? ?? cfg?['selectNames'] as String?;
      if (selectItems == null) return const [];
      for (final el in doc.querySelectorAll(selectItems)) {
        final name = el.text.trim();
        final href =
            el.attributes['href'] ?? el.querySelector('a')?.attributes['href'];
        if (name.isNotEmpty && href != null) {
          results.add(SourceSubject(name: name, url: _abs(href, base)));
        }
      }
    }
    final seen = <String>{};
    return results.where((s) => seen.add(s.url)).toList();
  }

  String _abs(String href, String base) {
    if (href.startsWith('http://') || href.startsWith('https://')) {
      return href;
    }
    return Uri.parse(base).resolve(href).toString();
  }

  /// 拉取条目详情页，解析线路与集数。
  Future<List<SourceChannel>> fetchChannels(String subjectUrl) async {
    final html = await _get(subjectUrl);
    if (html == null) return const [];
    return parseChannels(html, subjectUrl);
  }

  List<SourceChannel> parseChannels(String html, String subjectUrl) {
    final doc = html_parser.parse(html);
    final channelFormat = _str('channelFormatId') ?? 'no-channel';
    final channelTiers = _cfg['channelTiers'] is Map
        ? (_cfg['channelTiers'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    int tierOf(String name) =>
        (channelTiers[name] as num?)?.toInt() ?? instance.tier;

    if (channelFormat == 'index-grouped') {
      final cfg = _map('selectorChannelFormatFlattened');
      return _parseGroupedChannels(doc, subjectUrl, cfg ?? const {}, tierOf);
    }
    final cfg = _map('selectorChannelFormatNoChannel');
    final episodes = _parseEpisodeList(
      doc.documentElement,
      subjectUrl,
      cfg?['selectEpisodes'] as String?,
      _str('matchEpisodeSortFromName'),
    );
    return [
      SourceChannel(
        name: instance.name,
        tier: instance.tier,
        episodes: episodes,
      ),
    ];
  }

  List<SourceChannel> _parseGroupedChannels(
    dom.Document doc,
    String subjectUrl,
    Map<String, dynamic> cfg,
    int Function(String name) tierOf,
  ) {
    final results = <SourceChannel>[];
    final selectChannelNames = cfg['selectChannelNames'] as String?;
    final selectEpisodeLists = cfg['selectEpisodeLists'] as String?;
    final selectEpisodesFromList = cfg['selectEpisodesFromList'] as String? ?? 'a';
    final matchChannelName = cfg['matchChannelName'] as String?;
    final matchEpisodeSort =
        cfg['matchEpisodeSortFromName'] as String? ??
        _str('matchEpisodeSortFromName');

    final channelEls = selectChannelNames == null
        ? const <dom.Element>[]
        : doc.querySelectorAll(selectChannelNames);
    final listEls = selectEpisodeLists == null
        ? const <dom.Element>[]
        : doc.querySelectorAll(selectEpisodeLists);
    // 线路名与集数列表按索引一一对应
    final count = channelEls.length.clamp(0, listEls.length);
    for (int i = 0; i < count; i++) {
      var name = channelEls[i].text.trim();
      if (matchChannelName case final pattern? when pattern.isNotEmpty) {
        final m = RegExp(pattern).firstMatch(name);
        if (m != null) {
          name = (m.namedGroup('name') ?? name).trim();
        }
      }
      final episodes = _parseEpisodeList(
        listEls[i],
        subjectUrl,
        selectEpisodesFromList,
        matchEpisodeSort,
      );
      if (episodes.isNotEmpty) {
        results.add(
          SourceChannel(
            name: name.isEmpty ? '线路${i + 1}' : name,
            tier: tierOf(name),
            episodes: episodes,
          ),
        );
      }
    }
    return results;
  }

  List<SourceEpisode> _parseEpisodeList(
    dom.Element rootEl,
    String subjectUrl,
    String? select,
    String? matchSort,
  ) {
    final episodes = <SourceEpisode>[];
    if (select == null || select.isEmpty) return episodes;
    // Document implements Element but Dart's covariant inheritance doesn't
    // always permit passing Document where Element is expected; the
    // caller resolves to documentElement before invoking us.
    for (final el in rootEl.querySelectorAll(select)) {
      final anchor = el.text.trim();
      final href =
          el.attributes['href'] ?? el.querySelector('a')?.attributes['href'];
      if (anchor.isEmpty || href == null || href.startsWith('javascript')) {
        continue;
      }
      var sort = anchor;
      if (matchSort case final pattern? when pattern.isNotEmpty) {
        final m = RegExp(pattern).firstMatch(anchor);
        if (m != null) {
          sort = (m.namedGroup('ep') ?? m.group(1) ?? anchor).trim();
        }
      }
      episodes.add(
        SourceEpisode(
          name: anchor,
          sort: sort,
          pageUrl: _abs(href, subjectUrl),
        ),
      );
    }
    episodes.sort((a, b) {
      final an = double.tryParse(a.sort);
      final bn = double.tryParse(b.sort);
      if (an != null && bn != null) return an.compareTo(bn);
      return a.sort.compareTo(b.sort);
    });
    return episodes;
  }

  /// 直链嗅探配置（matchVideo）。
  Map<String, dynamic> get matchVideoConfig =>
      _map('matchVideo') ?? const {};

  String? get matchVideoUrl => matchVideoConfig['matchVideoUrl'] as String?;
  String? get matchNestedUrl => matchVideoConfig['matchNestedUrl'] as String?;

  Map<String, String> get videoHeaders {
    final headers = <String, String>{};
    final add = matchVideoConfig['addHeadersToVideo'];
    if (add is Map) {
      for (final e in add.entries) {
        headers[e.key.toString()] = e.value.toString();
      }
    }
    return headers;
  }
}
