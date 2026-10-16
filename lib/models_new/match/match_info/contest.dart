import 'package:PiliMax/models_new/match/match_info/season.dart';
import 'package:PiliMax/models_new/match/match_info/team.dart';
import 'package:PiliMax/utils/parse_int.dart';
import 'package:PiliMax/utils/parse_string.dart';

class MatchContest {
  int? id;
  String? gameStage;
  int? stime;
  int? homeId;
  int? awayId;
  int? homeScore;
  int? awayScore;
  int? liveRoom;
  MatchSeason? season;
  MatchTeam? homeTeam;
  MatchTeam? awayTeam;
  int? contestStatus;
  String? playback;
  String? title;

  MatchContest({
    this.id,
    this.gameStage,
    this.stime,
    this.homeId,
    this.awayId,
    this.homeScore,
    this.awayScore,
    this.liveRoom,
    this.season,
    this.homeTeam,
    this.awayTeam,
    this.contestStatus,
    this.playback,
    this.title,
  });

  factory MatchContest.fromJson(Map<String, dynamic> json) => MatchContest(
    id: json['id'] as int?,
    gameStage: json['game_stage'] as String?,
    stime: json['stime'] as int?,
    homeId: json['home_id'] as int?,
    awayId: json['away_id'] as int?,
    homeScore: json['home_score'] as int?,
    awayScore: json['away_score'] as int?,
    liveRoom: json['live_room'] as int?,
    season: json['season'] == null
        ? null
        : MatchSeason.fromJson(json['season'] as Map<String, dynamic>),
    homeTeam: json['home_team'] == null
        ? null
        : MatchTeam.fromJson(json['home_team'] as Map<String, dynamic>),
    awayTeam: json['away_team'] == null
        ? null
        : MatchTeam.fromJson(json['away_team'] as Map<String, dynamic>),
    contestStatus: json['contest_status'] as int?,
    playback: json['playback'] as String?,
  );

  factory MatchContest.fromSearch(Map<String, dynamic> json) {
    final home = (json['homeTeam'] as Map?)?.cast<String, dynamic>();
    final away = (json['awayTeam'] as Map?)?.cast<String, dynamic>();
    final season = (json['season'] as Map?)?.cast<String, dynamic>();
    return MatchContest(
      id: safeToInt(json['ID']),
      gameStage: nonNullOrEmptyString(json['gameStage'] as String?),
      stime: safeToInt(json['stime']),
      homeId: home == null ? 0 : 1,
      awayId: away == null ? 0 : 1,
      homeScore: safeToInt(json['homeScore']),
      awayScore: safeToInt(json['awayScore']),
      liveRoom: safeToInt(json['liveRoom']),
      season: season == null ? null : MatchSeason.fromJson(season),
      homeTeam: home == null ? null : MatchTeam.fromJson(home),
      awayTeam: away == null ? null : MatchTeam.fromJson(away),
      contestStatus: safeToInt(json['contestStatus']),
      playback: json['playback'] as String?,
      title: (season?['title'] as String?),
    );
  }
}
