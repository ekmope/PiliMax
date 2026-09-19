import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/models/search/search_esports.dart';
import 'package:PiliMax/utils/app_scheme.dart';
import 'package:PiliMax/utils/date_utils.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:material_ui/material_ui.dart';

class SearchEsportsItem extends StatelessWidget {
  const SearchEsportsItem({super.key, required this.item});

  final SearchEsports item;

  @override
  Widget build(BuildContext context) {
    if (item.contest.isEmpty) return const SizedBox.shrink();
    final colorScheme = ColorScheme.of(context);
    final contest = item.contest.first;

    Widget team(EsportsTeam value) => Column(
      spacing: 6,
      mainAxisSize: .min,
      children: [
        if (value.logoFull.isNotEmpty)
          NetworkImgLayer(
            src: value.logoFull,
            width: 50,
            height: 50,
            type: .emote,
            fit: .contain,
          )
        else
          const SizedBox(width: 50, height: 50),
        Text(value.title, style: const TextStyle(fontSize: 13)),
      ],
    );

    final buttonStyle = ButtonStyle(
      visualDensity: .compact,
      tapTargetSize: .shrinkWrap,
      padding: const WidgetStatePropertyAll(.symmetric(horizontal: 16)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: const .all(.circular(6)),
          side: BorderSide(color: colorScheme.outline),
        ),
      ),
      foregroundColor: WidgetStatePropertyAll(colorScheme.onSurfaceVariant),
    );
    Widget actions;
    if (contest.contestStatus == 2) {
      actions = FilledButton.tonal(
        style: const ButtonStyle(
          visualDensity: .compact,
          tapTargetSize: .shrinkWrap,
          padding: WidgetStatePropertyAll(.symmetric(horizontal: 16)),
        ),
        onPressed: contest.liveRoom == 0
            ? null
            : () => PageUtils.toLiveRoom(contest.liveRoom),
        child: const Text('观看直播'),
      );
    } else {
      final live = OutlinedButton(
        style: buttonStyle,
        onPressed: contest.liveRoom == 0
            ? null
            : () => PageUtils.toLiveRoom(contest.liveRoom),
        child: const Text('直播间'),
      );
      actions = contest.playback?.isNotEmpty == true
          ? Row(
              spacing: 12,
              mainAxisSize: .min,
              children: [
                OutlinedButton(
                  style: buttonStyle,
                  onPressed: () =>
                      PiliScheme.routePushFromUrl(contest.playback!),
                  child: const Text('回放'),
                ),
                live,
              ],
            )
          : live;
    }

    final statusText = [
      if (contest.gameStage != null) contest.gameStage!,
      if (contest.contestStatus == 3)
        '已结束'
      else if (contest.contestStatus == 1 && contest.stime != null)
        DateFormatUtils.format(contest.stime),
    ].join('  ');

    return Padding(
      padding: const .symmetric(vertical: 5),
      child: Center(
        child: GestureDetector(
          behavior: .opaque,
          onTap: contest.id == 0
              ? null
              : () => Get.toNamed(
                  '/matchInfo',
                  parameters: {'cid': contest.id.toString()},
                ),
          child: Column(
            mainAxisSize: .min,
            children: [
              Text(
                contest.title ?? item.configInfo.esportTitle,
                style: const TextStyle(fontWeight: .bold, fontSize: 16),
              ),
              if (statusText.isNotEmpty)
                Padding(
                  padding: const .only(top: 4),
                  child: Text(
                    statusText,
                    style: TextStyle(fontSize: 13, color: colorScheme.outline),
                  ),
                ),
              Row(
                spacing: 20,
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: [
                  team(contest.homeTeam),
                  Text(
                    contest.contestStatus == 1
                        ? 'VS'
                        : '${contest.homeScore ?? '-'} : ${contest.awayScore ?? '-'}',
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: .bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  team(contest.awayTeam),
                ],
              ),
              const SizedBox(height: 10),
              actions,
            ],
          ),
        ),
      ),
    );
  }
}
