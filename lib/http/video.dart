import 'dart:convert';

import 'package:PiliMax/common/constants.dart';
import 'package:PiliMax/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliMax/http/api.dart';
import 'package:PiliMax/http/browser_ua.dart';
import 'package:PiliMax/pilimax/forks/http/init.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/pilimax/http/web_request_headers.dart';
import 'package:PiliMax/http/login.dart';
import 'package:PiliMax/models/common/account_type.dart';
import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/models/home/rcmd/result.dart';
import 'package:PiliMax/models/model_hot_video_item.dart';
import 'package:PiliMax/models/model_rec_video_item.dart';
import 'package:PiliMax/models/pgc_lcf.dart';
import 'package:PiliMax/models/video/play/url.dart';
import 'package:PiliMax/models_new/pgc/pgc_rank/pgc_rank_item_model.dart';
import 'package:PiliMax/models_new/popular/popular_precious/data.dart';
import 'package:PiliMax/models_new/popular/popular_series_list/list.dart';
import 'package:PiliMax/models_new/popular/popular_series_one/data.dart';
import 'package:PiliMax/models_new/triple/pgc_triple.dart';
import 'package:PiliMax/models_new/triple/ugc_triple.dart';
import 'package:PiliMax/models_new/video/video_ai_conclusion/data.dart';
import 'package:PiliMax/models_new/video/video_detail/data.dart';
import 'package:PiliMax/models_new/video/video_detail/video_detail_response.dart';
import 'package:PiliMax/models_new/video/video_note_list/data.dart';
import 'package:PiliMax/models_new/video/video_play_info/data.dart';
import 'package:PiliMax/models_new/video/video_relation/data.dart';
import 'package:PiliMax/models_new/video/video_shot/data.dart';
import 'package:PiliMax/pilimax/forks/utils/accounts.dart';
import 'package:PiliMax/utils/app_sign.dart';
import 'package:PiliMax/utils/extension/string_ext.dart';
import 'package:PiliMax/pilimax/utils/filter_pattern_compiler.dart';
import 'package:PiliMax/utils/global_data.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/parse_int.dart';
import 'package:PiliMax/utils/recommend_filter.dart';
import 'package:PiliMax/utils/request_utils.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/subtitle_utils.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:PiliMax/pilimax/forks/utils/wbi_sign.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:protobuf/protobuf.dart';

/// view灞傛牴鎹?status 鍒ゆ柇娓叉煋閫昏緫
abstract final class VideoHttp {
  static final _initialZoneFilter = FilterPatternCompiler.compileStoredSafely(
    Pref.banWordForZone,
    onError: (error, stackTrace) => Utils.reportError(
      error,
      stackTrace,
      'VideoHttp.invalidStoredZonePattern',
    ),
  );
  static RegExp zoneRegExp = _initialZoneFilter.regExp;
  static bool enableFilter = _initialZoneFilter.isEnabled;
  static Future<Response> _getWbiFeed(
    String url,
    Map<String, Object> queryParameters,
  ) async {
    Future<Response> send({required bool forceRefresh}) async {
      return Request().get(
        url,
        queryParameters: await WbiSign.makSign(
          Map<String, Object>.of(queryParameters),
          forceRefresh: forceRefresh,
        ),
        options: WebRequestHeaders.browser,
      );
    }

    var response = await send(forceRefresh: false);
    if (_responseCode(response.data) == -403) {
      response = await send(forceRefresh: true);
    }
    return response;
  }

  static int? _responseCode(Object? body) {
    if (body is! Map) return null;
    return switch (body['code']) {
      int code => code,
      num code when code.isFinite && code == code.truncate() => code.toInt(),
      String code => int.tryParse(code.trim()),
      _ => null,
    };
  }

  // 棣栭〉鎺ㄨ崘瑙嗛
  static Future<LoadingState<List<RcmdVideoItemModel>>> rcmdVideoList({
    required int ps,
    required int freshIdx,
  }) async {
    final res = await Request().get(
      Api.recommendListWeb,
      queryParameters: await WbiSign.makSign({
        'version': 1,
        'feed_version': 'V8',
        'homepage_ver': 1,
        'ps': ps,
        'fresh_idx': freshIdx,
        'brush': freshIdx,
        'fresh_type': 4,
      }),
    );
    if (res.data['code'] == 0) {
      List<RcmdVideoItemModel> list = <RcmdVideoItemModel>[];
      for (final i in res.data['data']['item']) {
        final mid = safeToInt(i['owner']?['mid']);
        //杩囨护鎺塴ive涓巃d锛屼互鍙婃媺榛戠敤鎴?
        if (i['goto'] == 'av' &&
            (i['owner'] != null &&
                (!GlobalData().blackMids.contains(i['owner']['mid']) ||
                    RecommendFilter.isWhitelisted(mid)))) {
          RcmdVideoItemModel videoItem = RcmdVideoItemModel.fromJson(i);
          if (!RecommendFilter.filter(videoItem)) {
            list.add(videoItem);
          }
        }
      }
      return Success(list);
    } else {
      return Error(res.data['message']);
    }
  }

  // 娣诲姞棰濆鐨刲oginState鍙橀噺妯℃嫙鏈櫥褰曠姸鎬?
  static Future<LoadingState<List<RcmdVideoItemAppModel>>> rcmdVideoListApp({
    required int freshIdx,
  }) async {
    final params = {
      'build': 2001100,
      'c_locale': 'zh_CN',
      'channel': 'master',
      'column': 4,
      'device': 'pad',
      'device_name': 'android',
      'device_type': 0,
      'disable_rcmd': 0,
      'flush': 5,
      'fnval': 976,
      'fnver': 0,
      'force_host': 2, //浣跨敤https
      'fourk': 1,
      'guidance': 0,
      'https_url_req': 0,
      'idx': freshIdx,
      'mobi_app': 'android_hd',
      'network': 'wifi',
      'platform': 'android',
      'player_net': 1,
      'pull': freshIdx == 0 ? 'true' : 'false',
      'qn': 32,
      'recsys_mode': 0,
      's_locale': 'zh_CN',
      'splash_id': '',
      'statistics': Constants.statistics,
      'voice_balance': 0,
    };
    final res = await Request().get(
      Api.recommendListApp,
      queryParameters: params,
      options: Options(
        headers: {
          'buvid': LoginHttp.buvid,
          'fp_local':
              '1111111111111111111111111111111111111111111111111111111111111111',
          'fp_remote':
              '1111111111111111111111111111111111111111111111111111111111111111',
          'session_id': '11111111',
          'env': 'prod',
          'app-key': 'android_hd',
          'User-Agent': Constants.userAgent,
          'x-bili-trace-id': IdUtils.genTraceId(),
          'x-bili-aurora-eid': '',
          'x-bili-aurora-zone': '',
          'bili-http-engine': 'cronet',
        },
      ),
    );

    if (res.data['code'] == 0) {
      List<RcmdVideoItemAppModel> list = <RcmdVideoItemAppModel>[];
      final bool removeBlockedRcmd = Pref.removeBlockedRcmd;
      for (final i in res.data['data']['items']) {
        final upMid = safeToInt(i['args']?['up_id']);
        final isWhitelisted = RecommendFilter.isWhitelisted(upMid);
        // 灞忚斀鎺ㄥ箍鍜屾媺榛戠敤鎴?
        if (i['card_goto'] != 'ad_av' &&
            i['card_goto'] != 'ad_web_s' &&
            i['ad_info'] == null &&
            (i['args'] != null &&
                (!GlobalData().blackMids.contains(i['args']['up_id']) ||
                    isWhitelisted))) {
          if (enableFilter &&
              !isWhitelisted &&
              i['args']?['tname'] != null &&
              zoneRegExp.hasMatch(i['args']['tname'])) {
            continue;
          }
          if (removeBlockedRcmd && !isWhitelisted && i['can_play'] != 1) {
            continue;
          }
          RcmdVideoItemAppModel videoItem = RcmdVideoItemAppModel.fromJson(i);
          if (!RecommendFilter.filter(videoItem)) {
            list.add(videoItem);
          }
        }
      }
      return Success(list);
    } else {
      return Error(res.data['message']);
    }
  }

  // 鏈€鐑棰?
  static Future<LoadingState<List<HotVideoItemModel>>> hotVideoList({
    required int pn,
    required int ps,
  }) async {
    final res = await Request().get(
      Api.hotList,
      queryParameters: {'pn': pn, 'ps': ps},
    );
    if (res.data['code'] == 0) {
      List<HotVideoItemModel> list = <HotVideoItemModel>[];
      final applyFullFilter = RecommendFilter.applyFilterToHotVideos;
      for (final i in res.data['data']['list']) {
        final mid = safeToInt(i['owner']?['mid']);
        final isWhitelisted = RecommendFilter.isWhitelisted(mid);
        // 鍒嗗尯鍏抽敭璇嶈繃婊わ紙濮嬬粓鐢熸晥锛屼笂娓稿師濮嬭涓猴級
        if (enableFilter &&
            !isWhitelisted &&
            i['tname'] != null &&
            zoneRegExp.hasMatch(i['tname'])) {
          continue;
        }
        if (applyFullFilter) {
          // 寮€鍏冲紑鍚細鍏ㄥ眬榛戝悕鍗?+ 瀹屾暣杩囨护锛堟椂闀裤€佹挱鏀鹃噺銆佺偣璧炵巼銆佹爣棰樺叧閿瘝銆佹帹鑽愬睆钄界敤鎴凤級
          if (!isWhitelisted &&
              GlobalData().blackMids.contains(i['owner']['mid'])) {
            continue;
          }
          final item = HotVideoItemModel.fromJson(i);
          if (!RecommendFilter.filterAll(item)) list.add(item);
        } else {
          list.add(HotVideoItemModel.fromJson(i));
        }
      }
      return Success(list);
    } else {
      return Error(res.data['message']);
    }
  }

  // 瑙嗛娴?
  @pragma('vm:notify-debugger-on-exception')
  static Future<LoadingState<PlayUrlModel>> videoUrl({
    int? avid,
    String? bvid,
    required int cid,
    int? qn,
    dynamic epid,
    dynamic seasonId,
    required bool tryLook,
    required VideoType videoType,
    String? language,
    bool voiceBalance = false,
  }) async {
    final dmImgStr = Utils.base64EncodeRandomString(16, 64);
    final dmCoverImgStr = Utils.base64EncodeRandomString(32, 128);
    final params = await WbiSign.makSign({
      'avid': ?avid,
      'bvid': ?bvid,
      'ep_id': ?epid,
      'season_id': ?seasonId,
      'cid': cid,
      'qn': qn ?? 80,
      // 鑾峰彇鎵€鏈夋牸寮忕殑瑙嗛
      'fnval': 4048,
      'fourk': 1,
      'fnver': 0,
      'voice_balance': voiceBalance ? 1 : 0,
      'gaia_source': 'pre-load',
      'isGaiaAvoided': true,
      'web_location': 1315873,
      // 鍏嶇櫥褰曟煡鐪?080p
      if (tryLook) 'try_look': 1,
      'dm_img_list': '[]',
      'dm_img_str': dmImgStr,
      'dm_cover_img_str': dmCoverImgStr,
      'dm_img_inter': '{"ds":[],"wh":[0,0,0],"of":[0,0,0]}',
      'cur_language': ?language,
    });

    try {
      final res = await Request().get(videoType.api, queryParameters: params);

      if (res.data['code'] == 0) {
        late PlayUrlModel data;
        switch (videoType) {
          case .ugc:
            data = PlayUrlModel.fromJson(res.data['data']);

          case .pgc:
            final result = res.data['result'];
            data = PlayUrlModel.fromJson(result['video_info'])
              ..lastPlayTime =
                  result['play_view_business_info']?['user_status']?['watch_progress']?['current_watch_progress'];

          case .pugv:
            final result = res.data['data'];
            data = PlayUrlModel.fromJson(result)
              ..lastPlayTime =
                  result['play_view_business_info']?['user_status']?['watch_progress']?['current_watch_progress'];
        }
        return Success(data);
      } else if (epid != null && videoType == .ugc) {
        return await videoUrl(
          avid: avid,
          bvid: bvid,
          cid: cid,
          qn: qn,
          epid: epid,
          seasonId: seasonId,
          tryLook: tryLook,
          videoType: .pgc,
        );
      }
      return Error(_parseVideoErr(res.data['code'], res.data['message']));
    } catch (e, s) {
      return Error('$e\n\n$s');
    }
  }

  static String _parseVideoErr(int? code, String? msg) {
    return switch (code) {
      -404 => '瑙嗛涓嶅瓨鍦ㄦ垨宸茶鍒犻櫎',
      87008 => '褰撳墠瑙嗛鍙兘鏄笓灞炶棰戯紝鍙兘闇€鍖呮湀鍏呯數瑙傜湅($msg})',
      _ => '閿欒($code): $msg',
    };
  }

  // 瑙嗛淇℃伅 鏍囬銆佺畝浠?
  static Future<LoadingState<VideoDetailData>> videoIntro({
    required String bvid,
  }) async {
    final res = await Request().get(
      Api.videoIntro,
      queryParameters: {'bvid': bvid},
    );
    VideoDetailResponse data = VideoDetailResponse.fromJson(res.data);
    if (data.code == 0) {
      return Success(data.data!);
    } else {
      return Error(data.message);
    }
  }

  static Future<LoadingState<VideoRelation>> videoRelation({
    required String bvid,
  }) async {
    final res = await Request().get(
      Api.videoRelation,
      queryParameters: {'aid': IdUtils.bv2av(bvid), 'bvid': bvid},
    );
    if (res.data['code'] == 0) {
      return Success(VideoRelation.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }

  // 鐩稿叧瑙嗛
  static Future<LoadingState<List<HotVideoItemModel>?>> relatedVideoList({
    required String bvid,
  }) async {
    final res = await Request().get(
      Api.relatedList,
      queryParameters: {'bvid': bvid},
    );
    if (res.data['code'] == 0) {
      final items = (res.data['data'] as List?)?.map(
        (i) => HotVideoItemModel.fromJson(i),
      );
      final list = RecommendFilter.applyFilterToRelatedVideos
          ? items?.where((i) => !RecommendFilter.filterAll(i)).toList()
          : items?.toList();
      return Success(list);
    } else {
      return Error(res.data['message']);
    }
  }

  // 鑾峰彇鐐硅禐/鎶曞竵/鏀惰棌鐘舵€?pgc
  static Future<LoadingState<PgcLCF>> pgcLikeCoinFav({
    required Object epId,
  }) async {
    final res = await Request().get(
      Api.pgcLikeCoinFav,
      queryParameters: {'ep_id': epId},
    );
    if (res.data['code'] == 0) {
      return Success(PgcLCF.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }

  // 鎶曞竵
  static Future<LoadingState<void>> coinVideo({
    required String bvid,
    required int multiply,
    int selectLike = 0,
  }) async {
    final hasAccessKey = !Accounts.main.accessKey.isNullOrEmpty;
    final options = Options(
      contentType: Headers.formUrlEncodedContentType,
      headers: hasAccessKey
          ? null
          : {
              'origin': 'https://www.bilibili.com',
              'referer': 'https://www.bilibili.com/video/$bvid',
              'user-agent': BrowserUa.pc,
            },
    );
    final res = await Request().post(
      hasAccessKey ? Api.coinVideo : Api.coinVideoWeb,
      data: {
        'aid': IdUtils.bv2av(bvid).toString(),
        // 'bvid': bvid,
        'multiply': multiply.toString(),
        'select_like': selectLike.toString(),
        if (!hasAccessKey) 'csrf': Accounts.main.csrf,
      },
      options: options,
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  // 涓€閿笁杩?pgc
  static Future<LoadingState<PgcTriple>> pgcTriple({
    required Object epId,
    Object? seasonId,
  }) async {
    final res = await Request().post(
      Api.pgcTriple,
      data: {'ep_id': epId, 'csrf': Accounts.main.csrf},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'origin': 'https://www.bilibili.com',
          'referer':
              'https://www.bilibili.com/bangumi/play/${seasonId == null ? "ep$epId" : "ss$seasonId"}',
          'user-agent': BrowserUa.pc,
        },
      ),
    );
    if (res.data['code'] == 0) {
      return Success(PgcTriple.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }

  // 涓€閿笁杩?
  static Future<LoadingState<UgcTriple>> ugcTriple({
    required String bvid,
  }) async {
    final res = await Request().post(
      Api.ugcTriple,
      data: {
        'aid': IdUtils.bv2av(bvid),
        'eab_x': 2,
        'ramval': 0,
        'source': 'web_normal',
        'ga': 1,
        'csrf': Accounts.main.csrf,
        'spmid': '333.788.0.0',
        'statistics': '{"appId":100,"platform":5}',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'origin': 'https://www.bilibili.com',
          'referer': 'https://www.bilibili.com/video/$bvid',
          'user-agent': BrowserUa.pc,
        },
      ),
    );
    if (res.data['code'] == 0) {
      return Success(UgcTriple.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }

  // 锛堝彇娑堬級鐐硅禐
  static Future<LoadingState<String>> likeVideo({
    required String bvid,
    required bool type,
  }) async {
    final hasAccessKey = !Accounts.main.accessKey.isNullOrEmpty;
    final options = Options(
      contentType: Headers.formUrlEncodedContentType,
      headers: hasAccessKey
          ? null
          : {
              'origin': 'https://www.bilibili.com',
              'referer': 'https://www.bilibili.com/video/$bvid',
              'user-agent': BrowserUa.pc,
            },
    );
    final res = await Request().post(
      hasAccessKey ? Api.likeVideo : Api.likeVideoWeb,
      data: hasAccessKey
          ? {'aid': IdUtils.bv2av(bvid).toString(), 'like': type ? '0' : '1'}
          : {
              'aid': IdUtils.bv2av(bvid).toString(),
              'like': type ? '1' : '2',
              'csrf': Accounts.main.csrf,
            },
      options: options,
    );
    if (res.data['code'] == 0) {
      return Success(res.data['data']?['toast'] as String? ?? '鐐硅禐鎴愬姛');
    } else {
      return Error(res.data['message']);
    }
  }

  // 锛堝彇娑堬級鐐硅俯
  static Future<LoadingState<void>> dislikeVideo({
    required String bvid,
    required bool type,
  }) async {
    if (Accounts.main.accessKey.isNullOrEmpty) {
      return const Error('璇烽€€鍑鸿处鍙峰悗閲嶆柊鐧诲綍');
    }
    final res = await Request().post(
      Api.dislikeVideo,
      data: {
        'aid': IdUtils.bv2av(bvid).toString(),
        'dislike': type ? '0' : '1',
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data is! String && res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data is String ? res.data : res.data['message']);
    }
  }

  // 鎺ㄩ€佷笉鎰熷叴瓒ｅ弽棣?
  static Future<LoadingState<void>> feedDislike({
    required String goto,
    required int id,
    int? reasonId,
    int? feedbackId,
  }) async {
    if (Accounts.get(AccountType.recommend).accessKey.isNullOrEmpty) {
      return const Error('璇烽€€鍑鸿处鍙峰悗閲嶆柊鐧诲綍');
    }
    assert((reasonId != null) ^ (feedbackId != null));
    final res = await Request().get(
      Api.feedDislike,
      queryParameters: {
        'goto': goto,
        'id': id,
        'reason_id': ?reasonId,
        'feedback_id': ?feedbackId,
        'build': 1,
        'mobi_app': 'android',
      },
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  // 鎺ㄩ€佷笉鎰熷叴瓒ｅ彇娑?
  static Future<LoadingState<void>> feedDislikeCancel({
    required String goto,
    required int id,
    int? reasonId,
    int? feedbackId,
  }) async {
    if (Accounts.get(AccountType.recommend).accessKey.isNullOrEmpty) {
      return const Error('璇烽€€鍑鸿处鍙峰悗閲嶆柊鐧诲綍');
    }
    final res = await Request().get(
      Api.feedDislikeCancel,
      queryParameters: {
        'goto': goto,
        'id': id,
        'reason_id': ?reasonId,
        'feedback_id': ?feedbackId,
        'build': 1,
        'mobi_app': 'android',
      },
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  // 鍙戣〃璇勮 replyAdd

  // type	num	璇勮鍖虹被鍨嬩唬鐮?蹇呰	绫诲瀷浠ｇ爜瑙佽〃
  // oid	num	鐩爣璇勮鍖篿d	蹇呰
  // root	num	鏍硅瘎璁簉pid	闈炲繀瑕?浜岀骇璇勮浠ヤ笂浣跨敤
  // parent	num	鐖惰瘎璁簉pid	闈炲繀瑕?浜岀骇璇勮鍚屾牴璇勮id 澶т簬浜岀骇璇勮涓鸿鍥炲鐨勮瘎璁篿d
  // message	str	鍙戦€佽瘎璁哄唴瀹?蹇呰	鏈€澶?000瀛楃
  // plat	num	鍙戦€佸钩鍙版爣璇?闈炲繀瑕?1锛歸eb绔?2锛氬畨鍗撳鎴风  3锛歩os瀹㈡埛绔? 4锛歸p瀹㈡埛绔?
  static Future<LoadingState<ReplyInfo?>> replyAdd({
    required int type,
    required int oid,
    required String message,
    int? root,
    int? parent,
    List? pictures,
    bool syncToDynamic = false,
    Map<String, int>? atNameToMid,
  }) async {
    final data = {
      'type': type,
      'oid': oid,
      if (root != null && root != 0) 'root': root,
      if (parent != null && parent != 0) 'parent': parent,
      'message': message,
      if (atNameToMid?.isNotEmpty == true)
        'at_name_to_mid': jsonEncode(atNameToMid), // {"name":uid}
      if (pictures != null) 'pictures': jsonEncode(pictures),
      if (syncToDynamic) 'sync_to_dynamic': 1,
      'csrf': Accounts.main.csrf,
    };
    final res = await Request().post(
      Api.replyAdd,
      data: data,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      try {
        final replyInfo = RequestUtils.replyCast(res.data['data']['reply']);
        GStorage.replyCacheStore.put(
          replyInfo.id.toString(),
          (replyInfo.deepCopy()
                ..unknownFields.clear()
                ..clearTrackInfo())
              .writeToBuffer(),
        );
        return Success(replyInfo);
      } catch (e, s) {
        Utils.reportError(e, s);
        return const Success(null);
      }
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<void>> replyDel({
    required int type, //replyType
    required int oid,
    required int rpid,
  }) async {
    final res = await Request().post(
      Api.replyDel,
      data: {
        'type': type, //type.index
        'oid': oid,
        'rpid': rpid,
        'csrf': Accounts.main.csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      GStorage.replyCacheStore.delete(rpid.toString());
      return const Success(null);
    } else {
      return const Error('璇烽€€鍑鸿处鍙峰悗閲嶆柊鐧诲綍');
    }
  }

  // 鎿嶄綔鐢ㄦ埛鍏崇郴
  static Future<LoadingState<void>> relationMod({
    required int mid,
    required int act,
    required int reSrc,
  }) async {
    final res = await Request().post(
      Api.relationMod,
      queryParameters: {
        'statistics': '{"appId":100,"platform":5}',
        'x-bili-device-req-json':
            '{"platform":"web","device":"pc","spmid":"333.1387"}',
      },
      data: {
        'fid': mid,
        'act': act,
        're_src': reSrc,
        'gaia_source': 'web_main',
        'spmid': '333.1387',
        'extend_content': jsonEncode({
          "entity": "user",
          "entity_id": mid,
          'fp': BrowserUa.pc,
        }),
        'csrf': Accounts.main.csrf,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'origin': 'https://space.bilibili.com',
          'referer': 'https://space.bilibili.com/$mid/dynamic',
          'user-agent': BrowserUa.pc,
        },
      ),
    );
    if (res.data['code'] == 0) {
      if (act == 5) {
        // block
        Pref.setBlackMid(mid);
      } else if (act == 6) {
        // unblock
        Pref.removeBlackMid(mid);
      }
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<void> roomEntryAction({required Object roomId}) {
    return Request().post(
      Api.roomEntryAction,
      queryParameters: {'csrf': Accounts.heartbeat.csrf},
      data: {'room_id': roomId, 'platform': 'pc'},
    );
  }

  static Future<void> historyReport({
    required Object aid,
    required Object type,
  }) {
    return Request().post(
      Api.historyReport,
      data: {'aid': aid, 'type': type, 'csrf': Accounts.heartbeat.csrf},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
  }

  // 瑙嗛鎾斁杩涘害
  static Future<void> heartBeat({
    Object? aid,
    Object? bvid,
    required Object cid,
    required Object progress,
    Object? epid,
    Object? seasonId,
    Object? subType,
    required VideoType videoType,
  }) {
    final isPugv = videoType == VideoType.pugv;
    return Request().post(
      Api.heartBeat,
      data: {
        if (isPugv) 'aid': ?aid else 'bvid': ?bvid,
        'cid': cid,
        'epid': ?epid,
        'sid': ?seasonId,
        'type': videoType.type,
        'sub_type': ?subType,
        'played_time': progress,
        'csrf': Accounts.heartbeat.csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
  }

  static Future<void> medialistHistory({
    required int desc,
    required Object oid,
    required Object upperMid,
  }) {
    return Request().post(
      Api.mediaListHistory,
      data: {
        'desc': desc,
        'oid': oid,
        'upper_mid': upperMid,
        'csrf': Accounts.heartbeat.csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
  }

  // 娣诲姞杩界暘
  static Future<LoadingState<String>> pgcAdd({int? seasonId}) async {
    final res = await Request().post(
      Api.pgcAdd,
      data: {'season_id': seasonId, 'csrf': Accounts.main.csrf},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return Success(res.data['result']['toast']);
    } else {
      return Error(res.data['message']);
    }
  }

  // 鍙栨秷杩界暘
  static Future<LoadingState<String>> pgcDel({int? seasonId}) async {
    final res = await Request().post(
      Api.pgcDel,
      data: {'season_id': seasonId, 'csrf': Accounts.main.csrf},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return Success(res.data['result']['toast']);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<String>> pgcUpdate({
    required String seasonId,
    required int status,
  }) async {
    final res = await Request().post(
      Api.pgcUpdate,
      data: {
        'season_id': seasonId,
        'status': status,
        'csrf': Accounts.main.csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return Success(res.data['result']['toast']);
    } else {
      return Error(res.data['message']);
    }
  }

  // 鏌ョ湅瑙嗛鍚屾椂鍦ㄧ湅浜烘暟
  static Future<LoadingState<String>> onlineTotal({
    int? aid,
    String? bvid,
    required int cid,
  }) async {
    assert(aid != null || bvid != null);
    final res = await Request().get(
      Api.onlineTotal,
      queryParameters: {'aid': aid, 'bvid': bvid, 'cid': cid},
    );
    if (res.data['code'] == 0) {
      return Success(res.data['data']['total']);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<AiConclusionData>> aiConclusion({
    required String bvid,
    required int cid,
    int? upMid,
  }) async {
    final params = await WbiSign.makSign({
      'bvid': bvid,
      'cid': cid,
      'up_mid': ?upMid,
    });
    final res = await Request().get(Api.aiConclusion, queryParameters: params);
    final int? code = res.data['code'];
    if (code == 0) {
      final int? dataCode = res.data['data']?['code'];
      if (dataCode == 0) {
        return Success(AiConclusionData.fromJson(res.data['data']));
      } else {
        return Error(null, code: dataCode);
      }
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<PlayInfoData>> playInfo({
    String? aid,
    String? bvid,
    required int cid,
    dynamic seasonId,
    dynamic epId,
  }) async {
    assert(aid != null || bvid != null);
    final res = await Request().get(
      Api.playInfo,
      queryParameters: await WbiSign.makSign({
        'aid': ?aid,
        'bvid': ?bvid,
        'cid': cid,
        'season_id': ?seasonId,
        'ep_id': ?epId,
      }),
    );
    if (res.data['code'] == 0) {
      return Success(PlayInfoData.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<String?> getSubtitles(
    String subtitleUrl, {
    SubtitleFormat format = .vtt,
  }) async {
    final res = await Request().get("https:$subtitleUrl");
    if (res.data?['body'] case List list) {
      switch (format) {
        case .json:
          throw UnimplementedError();
        case .vtt:
          return compute<List, String>(SubtitleUtils.json2Vtt, list);
        case .srt:
          return compute<List, String>(SubtitleUtils.json2Srt, list);
      }
    }
    return null;
  }

  static final _fillerWords = RegExp(
    [
      r'(鍡?|鍟?|棰?|鍛?|閭ｄ釜|灏辨槸璇磡鐒跺悗鍛瀵瑰惂|鏄惂|瀵逛笉瀵箌浣犵煡閬撳悧|鍙嶆灏辨槸|鍩烘湰涓妡璇村疄璇?',
      ')',
    ].join(),
  );

  /// Fetch raw subtitle body JSON list from URL.
  static Future<List?> fetchSubtitleBody(String subtitleUrl) async {
    final res = await Request().get("https:$subtitleUrl");
    return res.data?['body'] as List?;
  }

  /// Preprocess subtitle body JSON for AI analysis.
  /// Returns (compressed text, isTooLong).
  static ({String text, bool isTooLong}) preprocessSubtitlesForAi(
    List body,
  ) {
    final sb = StringBuffer();
    // Check if any subtitle exceeds 1 hour to determine format
    final hasHour = body.isNotEmpty && (body.last['from'] as num) >= 3600;
    for (final item in body) {
      final from = item['from'] as num;
      final content = (item['content'] as String?)?.trim() ?? '';
      if (content.isEmpty) continue;
      final h = from ~/ 3600;
      final m = (from % 3600) ~/ 60;
      final s = (from % 60).toInt();
      final ts = hasHour
          ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
          : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      sb.writeln('[$ts] $content');
    }

    // Second level: remove filler words
    var text = sb.toString().replaceAll(_fillerWords, '');
    // Collapse multiple blank lines
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    return (text: text, isTooLong: text.length > 20000);
  }

  static bool _canAddRank(Map i) {
    final isWhitelisted = RecommendFilter.isWhitelisted(
      safeToInt(i['owner']?['mid']),
    );
    if (isWhitelisted) {
      return true;
    }
    // 鍒嗗尯鍏抽敭璇嶈繃婊わ紙濮嬬粓鐢熸晥锛屼笂娓稿師濮嬭涓猴級
    return !(enableFilter &&
        i['tname'] != null &&
        zoneRegExp.hasMatch(i['tname']));
  }

  // 瑙嗛鎺掕
  static Future<LoadingState<List<HotVideoItemModel>>> getRankVideoList(
    int rid,
  ) async {
    try {
      final res = await _getWbiFeed(
        Api.getRankApi,
        {'rid': rid, 'type': 'all'},
      );
      if (res.data['code'] == 0) {
        List<HotVideoItemModel> list = <HotVideoItemModel>[];
        final applyFullFilter = RecommendFilter.applyFilterToRankVideos;
        for (final i in res.data['data']['list']) {
          if (!_canAddRank(i)) continue;
          final isWhitelisted = RecommendFilter.isWhitelisted(
            safeToInt(i['owner']?['mid']),
          );
          if (applyFullFilter) {
            // 寮€鍏冲紑鍚細鍏ㄥ眬榛戝悕鍗?+ 瀹屾暣杩囨护锛堟椂闀裤€佹挱鏀鹃噺銆佺偣璧炵巼銆佹爣棰樺叧閿瘝銆佹帹鑽愬睆钄界敤鎴凤級
            if (!isWhitelisted &&
                GlobalData().blackMids.contains(i['owner']['mid'])) {
              continue;
            }
            final item = HotVideoItemModel.fromJson(i);
            if (!RecommendFilter.filterAll(item)) list.add(item);
          } else {
            list.add(HotVideoItemModel.fromJson(i));
            // final List? others = i['others'];
            // if (others != null && others.isNotEmpty) {
            //   for (final j in others) {
            //     if (_canAddRank(j)) {
            //       list.add(HotVideoItemModel.fromJson(j));
            //     }
            //   }
            // }
          }
        }
        return Success(list);
      } else {
        return Error(res.data['message']);
      }
    } catch (e) {
      return Error(e.toString());
    }
  }

  // pgc 鎺掕
  static Future<LoadingState<List<PgcRankItemModel>?>> pgcRankList({
    int day = 3,
    required int seasonType,
  }) async {
    try {
      final res = await _getWbiFeed(
        Api.pgcRank,
        {
          'day': day,
          'season_type': seasonType,
        },
      );
      if (res.data['code'] == 0) {
        final items = res.data['result']?['list'] as List?;
        if (items == null) return const Success(null);
        final applyFilter = RecommendFilter.applyFilterToRankVideos;
        return Success(
          items
              .where(
                (e) =>
                    !applyFilter ||
                    !RecommendFilter.filterTitle(e['title'] ?? ''),
              )
              .map((e) => PgcRankItemModel.fromJson(e))
              .toList(),
        );
      } else {
        return Error(res.data['message']);
      }
    } catch (e) {
      return Error(e.toString());
    }
  }

  // pgc season 鎺掕
  static Future<LoadingState<List<PgcRankItemModel>?>> pgcSeasonRankList({
    int day = 3,
    required int seasonType,
  }) async {
    try {
      final res = await _getWbiFeed(
        Api.pgcSeasonRank,
        {
          'day': day,
          'season_type': seasonType,
        },
      );
      if (res.data['code'] == 0) {
        final items = res.data['data']?['list'] as List?;
        if (items == null) return const Success(null);
        final applyFilter = RecommendFilter.applyFilterToRankVideos;
        return Success(
          items
              .where(
                (e) =>
                    !applyFilter ||
                    !RecommendFilter.filterTitle(e['title'] ?? ''),
              )
              .map((e) => PgcRankItemModel.fromJson(e))
              .toList(),
        );
      } else {
        return Error(res.data['message']);
      }
    } catch (e) {
      return Error(e.toString());
    }
  }

  static Future<LoadingState<VideoNoteData>> getVideoNoteList({
    dynamic oid,
    dynamic uperMid,
    required int page,
  }) async {
    final res = await Request().get(
      Api.archiveNoteList,
      queryParameters: {
        'csrf': Accounts.main.csrf,
        'oid': oid,
        'oid_type': 0,
        'pn': page,
        'ps': 10,
        'uper_mid': ?uperMid,
      },
    );
    if (res.data['code'] == 0) {
      return Success(VideoNoteData.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<List<PopularSeriesListItem>?>>
  popularSeriesList() async {
    final res = await Request().get(
      Api.popularSeriesList,
      queryParameters: await WbiSign.makSign({'web_location': 333.934}),
    );
    if (res.data['code'] == 0) {
      return Success(
        (res.data['data']?['list'] as List<dynamic>?)
            ?.map(
              (e) => PopularSeriesListItem.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      );
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<PopularSeriesOneData>> popularSeriesOne({
    required int number,
  }) async {
    final res = await Request().get(
      Api.popularSeriesOne,
      queryParameters: await WbiSign.makSign({
        'number': number,
        'web_location': 333.934,
      }),
    );
    if (res.data['code'] == 0) {
      return Success(PopularSeriesOneData.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<PopularPreciousData>> popularPrecious({
    required int page,
  }) async {
    final res = await Request().get(
      Api.popularPrecious,
      queryParameters: await WbiSign.makSign({
        'page_size': 100,
        'page': page,
        'web_location': 333.934,
      }),
    );
    if (res.data['code'] == 0) {
      return Success(PopularPreciousData.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<PlayUrlModel>> tvPlayUrl({
    required int cid,
    required int objectId, // aid, epid
    required int playurlType, // ugc 1, pgc 2
    int? qn,
  }) async {
    final accessKey = Accounts.get(AccountType.video).accessKey;
    final params = {
      'access_key': ?accessKey,
      'actionKey': 'appkey',
      'cid': cid,
      'fourk': 1,
      'is_proj': 1,
      'mobile_access_key': ?accessKey,
      'object_id': objectId,
      'mobi_app': 'android',
      'platform': 'android',
      'playurl_type': playurlType,
      'protocol': 0,
      'qn': qn ?? 80,
    };
    AppSign.appSign(params);
    final res = await Request().get(Api.tvPlayUrl, queryParameters: params);
    if (res.data['code'] == 0) {
      return Success(PlayUrlModel.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<VideoShotData>> videoshot({
    required String bvid,
    required int cid,
  }) async {
    final res = await Request().get(
      Api.videoshot,
      queryParameters: {
        // 'aid': IdUtils.bv2av(_bvid),
        'bvid': bvid,
        'cid': cid,
        'index': 1,
      },
      options: Options(
        headers: {
          'user-agent': BrowserUa.pc,
          'referer': 'https://www.bilibili.com/video/$bvid',
        },
      ),
    );
    if (res.data['code'] == 0) {
      final data = VideoShotData.fromJson(res.data['data']);
      if (data.index.isNotEmpty) {
        return Success(data);
      } else {
        return const Error(null);
      }
    }
    return Error(res.data['message']);
  }
}
