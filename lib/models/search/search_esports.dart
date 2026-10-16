import 'package:PiliMax/models_new/match/match_info/contest.dart';

class SearchEsports {
  SearchEsports({required this.configInfo, required this.contest});

  final EsportsConfigInfo configInfo;
  final List<MatchContest> contest;

  factory SearchEsports.fromJson(Map<String, dynamic> json) {
    final rawContest = json['contest'];
    return SearchEsports(
      configInfo: EsportsConfigInfo.fromJson(
        (json['config_info'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      contest: rawContest is List
          ? rawContest
                .whereType<Map>()
                .map((e) => MatchContest.fromSearch(e.cast<String, dynamic>()))
                .toList()
          : const [],
    );
  }
}

class EsportsConfigInfo {
  EsportsConfigInfo({required this.esportTitle, this.btnList});

  final String esportTitle;
  final List<EsportsBtnList>? btnList;

  factory EsportsConfigInfo.fromJson(Map<String, dynamic> json) =>
      EsportsConfigInfo(
        esportTitle: (json['esport_title'] as String?) ?? '电竞赛事',
        btnList: (json['btn_list'] as List?)
            ?.whereType<Map>()
            .map((e) => EsportsBtnList.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

class EsportsBtnList {
  EsportsBtnList({required this.text, required this.link});

  final String text;
  final String link;

  factory EsportsBtnList.fromJson(Map<String, dynamic> json) => EsportsBtnList(
    text: (json['text'] as String?) ?? '',
    link: (json['link'] as String?) ?? '',
  );
}
