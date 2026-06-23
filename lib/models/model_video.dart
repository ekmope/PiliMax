abstract class BaseSimpleVideoItemModel {
  late String title;
  String? bvid;
  int? cid;
  String? cover;
  int duration = -1;
  late BaseOwner owner;
  late BaseStat stat;
}

abstract class BaseVideoItemModel extends BaseSimpleVideoItemModel {
  int? aid;
  String? desc;
  int? pubdate;
  bool isFollowed = false;
}

abstract class BaseOwner {
  int? mid;
  String? name;
}

abstract class BaseStat {
  int? view;
  int? like;
  int? favorite;
  int? danmu;
}

class Stat extends BaseStat {
  Stat.fromJson(Map<String, dynamic> json) {
    view = json["view"];
    like = json["like"];
    favorite = json["favorite"];
    danmu = json['danmaku'];
  }
}

class PlayStat extends BaseStat {
  PlayStat.fromJson(Map<String, dynamic> json) {
    view = json['play'];
    danmu = json['danmaku'];
  }
}
