import 'package:PiliMax/utils/parse_int.dart';
import 'package:PiliMax/utils/parse_string.dart';

class SearchEsports {
  SearchEsports({required this.configInfo, required this.contest});

  final EsportsConfigInfo configInfo;
  final List<EsportsContest> contest;

  factory SearchEsports.fromJson(Map<String, dynamic> json) {
    final rawContest = json['contest'];
    return SearchEsports(
      configInfo: EsportsConfigInfo.fromJson(
        (json['config_info'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      contest: rawContest is List
          ? rawContest
                .whereType<Map>()
                .map((e) => EsportsContest.fromJson(e.cast<String, dynamic>()))
                .toList()
          : const [],
    );
  }
}

class EsportsContest {
  EsportsContest({
    required this.id,
    this.gameStage,
    this.homeScore,
    this.awayScore,
    required this.homeTeam,
    required this.awayTeam,
    required this.liveRoom,
    this.playback,
    this.contestStatus,
    this.stime,
    this.title,
  });

  final int id;
  final String? gameStage;
  final int? homeScore;
  final int? awayScore;
  final EsportsTeam homeTeam;
  final EsportsTeam awayTeam;
  final int liveRoom;
  final String? playback;
  final int? contestStatus;
  final int? stime;
  final String? title;

  factory EsportsContest.fromJson(Map<String, dynamic> json) => EsportsContest(
    id: safeToInt(json['ID']) ?? 0,
    gameStage: nonNullOrEmptyString(json['gameStage'] as String?),
    homeScore: safeToInt(json['homeScore']),
    awayScore: safeToInt(json['awayScore']),
    homeTeam: EsportsTeam.fromJson(
      (json['homeTeam'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    awayTeam: EsportsTeam.fromJson(
      (json['awayTeam'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    liveRoom: safeToInt(json['liveRoom']) ?? 0,
    playback: json['playback'] as String?,
    contestStatus: safeToInt(json['contestStatus']),
    stime: safeToInt(json['stime']),
    title: (json['season'] as Map?)?['title'] as String?,
  );
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

class EsportsTeam {
  EsportsTeam({required this.title, required this.logoFull});

  final String title;
  final String logoFull;

  factory EsportsTeam.fromJson(Map<String, dynamic> json) => EsportsTeam(
    title: (json['title'] as String?) ?? '',
    logoFull: (json['logoFull'] as String?) ?? '',
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
