import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/download_source.dart';
import 'package:PiliMax/http/video.dart';
import 'package:PiliMax/models/common/account_type.dart';
import 'package:PiliMax/models/common/video/video_quality.dart';
import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/models/video/play/url.dart';
import 'package:PiliMax/models_new/download/bili_download_entry_info.dart';
import 'package:PiliMax/models_new/download/bili_download_media_file_info.dart';
import 'package:PiliMax/models_new/sponsor_block/segment_item.dart';
import 'package:PiliMax/utils/accounts.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/video_utils.dart';
import 'package:collection/collection.dart';

abstract final class DownloadHttp {
  static const String referer = "https://www.bilibili.com/";
  static const String userAgent = "Bilibili Freedoooooom/MarkII";

  static Future<DownloadVideoUrlResult> getVideoUrl({
    required BiliDownloadEntryInfo entry,
    SourceInfo? source,
    PageInfo? pageData,
    EpInfo? ep,
  }) async {
    final isLogin = Accounts.get(AccountType.video).isLogin;
    final res = await VideoHttp.videoUrl(
      avid: entry.avid,
      bvid: entry.bvid,
      cid: entry.cid,
      seasonId: entry.seasonId,
      epid: ep?.episodeId,
      qn: entry.preferedVideoQuality,
      tryLook: !isLogin && Pref.p1080,
      videoType: switch (ep?.from) {
        'pugv' => VideoType.pugv,
        != null when isLogin => VideoType.pgc,
        _ => VideoType.ugc,
      },
    );
    if (res case Success(:final response)) {
      final dash = response.dash;
      if (dash != null) {
        final selection = DownloadSourceSelector.selectDashVideo(
          videos: dash.video,
          supportFormats: response.supportFormats,
          preferredQuality: entry.preferedVideoQuality,
          preferredCodecs: Pref.preferCodecs,
        );
        final videoDash = selection.video;
        final targetVideoQa = selection.quality;
        final targetSupportFormat = selection.format;
        final duration = DownloadSourceSelector.requirePositiveDuration(
          dash.duration,
        );

        entry
          ..typeTag = targetVideoQa.toString()
          ..videoQuality = targetVideoQa
          ..preferedVideoQuality = targetVideoQa
          ..qualityPithyDescription =
              targetSupportFormat.newDesc ??
              VideoQuality.fromCode(targetVideoQa).desc;

        final videoUrl = VideoUtils.getCdnUrl(
          DownloadSourceSelector.playableUrls(videoDash.playUrls),
        );

        final Type2File videoFile = Type2File(
          id: videoDash.id!,
          baseUrl: videoUrl,
          bandwidth: videoDash.bandWidth!,
          codecid: videoDash.codecid!,
          size: 0,
          md5: '',
          noRexcode: false,
          frameRate: videoDash.frameRate ?? '',
          width: videoDash.width!,
          height: videoDash.height!,
          dashDrmType: 0,
        );
        List<Type2File>? audioFileList;
        final audioDash = DownloadSourceSelector.selectDashAudio(
          audios: dash.audio,
          preferredQuality: Pref.defaultAudioQa,
        );
        if (audioDash != null) {
          final audioUrl = VideoUtils.getCdnUrl(
            DownloadSourceSelector.playableUrls(audioDash.playUrls),
            isAudio: true,
          );
          audioFileList = [
            Type2File(
              id: audioDash.id!,
              baseUrl: audioUrl,
              bandwidth: audioDash.bandWidth!,
              codecid: audioDash.codecid!,
              size: 0,
              md5: '',
              noRexcode: false,
              frameRate: audioDash.frameRate ?? '',
              width: audioDash.width ?? 0,
              height: audioDash.height ?? 0,
              dashDrmType: 0,
            ),
          ];
          entry.hasDashAudio = true;
        }
        return DownloadVideoUrlResult(
          mediaFileInfo: Type2(
            duration: duration,
            video: [videoFile],
            audio: audioFileList,
            referer: referer,
            userAgent: userAgent,
          ),
          clipInfoList: response.clipInfoList,
        );
      } else {
        final first = DownloadSourceSelector.selectDurl(response.durl);
        final List<Type1Segment> segmentList = [
          Type1Segment(
            backupUrls: [],
            bytes: first.size!,
            duration: first.length!,
            md5: '',
            metaUrl: '',
            order: first.order!,
            url: VideoUtils.getCdnUrl(
              DownloadSourceSelector.playableUrls(first.playUrls),
            ),
          ),
        ];
        final FormatItem? formatItem = response.supportFormats
            ?.firstWhereOrNull((e) => e.quality == response.quality);
        final String description =
            formatItem?.newDesc ?? VideoQuality.clear480.desc;
        final int targetVideoQa =
            formatItem?.quality ?? VideoQuality.clear480.code;

        entry
          ..mediaType = 1
          ..typeTag = targetVideoQa.toString()
          ..videoQuality = targetVideoQa
          ..preferedVideoQuality = targetVideoQa
          ..qualityPithyDescription = description;

        final List<Type1PlayerCodecConfig> playerCodecConfigList = [
          Type1PlayerCodecConfig(
            player: "IJK_PLAYER",
            useIjkMediaCodec: false,
          ),
          Type1PlayerCodecConfig(
            player: "ANDROID_PLAYER",
            useIjkMediaCodec: false,
          ),
        ];

        return DownloadVideoUrlResult(
          mediaFileInfo: Type1(
            from: pageData?.from ?? ep?.from,
            quality: entry.preferedVideoQuality,
            typeTag: entry.typeTag,
            description: description,
            playerCodecConfigList: playerCodecConfigList,
            segmentList: segmentList,
            parseTimestampMilli: 0,
            availablePeriodMilli: 0,
            isDownloaded: false,
            isResolved: true,
            timeLength: 0,
            marlinToken: '',
            videoCodecId: 0,
            videoProject: true,
            format: DownloadSourceSelector.requireFormat(
              response.format ?? formatItem?.format,
            ),
            playerError: 0,
            needVip: false,
            needLogin: false,
            intact: false,
            referer: referer,
            userAgent: userAgent,
          ),
          clipInfoList: response.clipInfoList,
        );
      }
    } else {
      throw DownloadSourceException('Play URL request failed: $res');
    }
  }
}

class DownloadVideoUrlResult {
  final BiliDownloadMediaInfo mediaFileInfo;
  final List<SegmentItemModel>? clipInfoList;

  const DownloadVideoUrlResult({
    required this.mediaFileInfo,
    this.clipInfoList,
  });
}
