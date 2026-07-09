import 'package:PiliMax/models/dynamics/result.dart';

DynamicArchiveModel? dynamicVideoHeroArchive(DynamicItemModel item) {
  return switch (item.type) {
    'DYNAMIC_TYPE_AV' => item.modules.moduleDynamic?.major?.archive,
    'DYNAMIC_TYPE_UGC_SEASON' =>
      item.modules.moduleDynamic?.major?.ugcSeason,
    'DYNAMIC_TYPE_PGC_UNION' => item.modules.moduleDynamic?.major?.pgc,
    'DYNAMIC_TYPE_COURSES_SEASON' =>
      item.modules.moduleDynamic?.major?.courses,
    _ => null,
  };
}

String? makeDynamicVideoHeroTag(DynamicItemModel item, int ownerHash) {
  final key = dynamicVideoHeroKey(item);
  if (key == null) {
    return null;
  }
  return 'dynamic-video-$key-$ownerHash';
}

Object? dynamicVideoHeroKey(DynamicItemModel item) {
  final video = dynamicVideoHeroArchive(item);
  final cover = video?.cover;
  if (video == null || cover == null || cover.isEmpty) {
    return null;
  }
  return item.idStr ?? video.bvid ?? video.aid ?? cover;
}
