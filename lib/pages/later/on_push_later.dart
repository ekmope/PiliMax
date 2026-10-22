import 'package:PiliMax/http/search.dart';
import 'package:PiliMax/models_new/later/list.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:flutter/foundation.dart' show ValueChanged;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

Future<void> onPushLater(
  LaterItemModel item, {
  ValueChanged<int>? onViewLater,
}) async {
  if (item.isPugv ?? false) {
    PageUtils.viewPugv(seasonId: item.aid, viewLater: true);
    return;
  }
  if (item.isPgc ?? false) {
    if (item.bangumi?.epId != null) {
      PageUtils.viewPgc(epId: item.bangumi!.epId, viewLater: true);
    } else if (item.redirectUrl?.isNotEmpty == true) {
      PageUtils.viewPgcFromUri(item.redirectUrl!, viewLater: true);
    }
    return;
  }
  try {
    final cid =
        item.cid ??
        await SearchHttp.ab2c(
          aid: item.aid,
          bvid: item.bvid,
        );
    if (cid != null) {
      if (onViewLater != null) {
        onViewLater(cid);
      } else {
        await PageUtils.toVideoPage(
          bvid: item.bvid,
          cid: cid,
          cover: item.pic,
          title: item.title,
          dimension: item.dimension,
          extraArguments: const {'viewLater': true},
        );
      }
    }
  } catch (err) {
    SmartDialog.showToast(err.toString());
  }
}
