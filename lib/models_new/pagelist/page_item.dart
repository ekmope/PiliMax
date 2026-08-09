import 'package:PiliMax/models_new/video/video_detail/dimension.dart';

class PageItem {
  final int? cid;
  final String? title;
  final Dimension? dimension;

  PageItem({
    this.cid,
    this.title,
    this.dimension,
  });

  factory PageItem.fromJson(Map<String, dynamic> json) => PageItem(
    cid: json['cid'] as int?,
    title: json['part'] as String?,
    dimension: json['dimension'] == null
        ? null
        : Dimension.fromJson(json['dimension'] as Map<String, dynamic>),
  );
}
