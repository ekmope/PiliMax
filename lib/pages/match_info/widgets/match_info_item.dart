import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/models_new/match/match_info/contest.dart';
import 'package:PiliMax/models_new/match/match_info/team.dart';
import 'package:PiliMax/pages/match_info/widgets/team_info_layout.dart';
import 'package:PiliMax/utils/app_scheme.dart';
import 'package:PiliMax/utils/date_utils.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

class MatchInfoItem extends StatelessWidget {
  const MatchInfoItem({super.key, required this.contest});

  final MatchContest contest;

  @override
  Widget build(BuildContext context) =>
      buildContestItem(ColorScheme.of(context), contest);
}

Widget _buildTeamInfo(MatchTeam team) {
  final logo = team.logoFull?.isNotEmpty == true
      ? team.logoFull
      : team.logo?.isNotEmpty == true
      ? 'https://i1.hdslb.com${team.logo}'
      : null;
  return Column(
    spacing: 6,
    mainAxisSize: .min,
    children: [
      if (logo != null)
        NetworkImgLayer(
          src: logo,
          width: 50,
          height: 50,
          type: .emote,
          fit: .contain,
        )
      else
        const SizedBox(width: 50, height: 50),
      if (team.title?.isNotEmpty == true)
        Text(team.title!, style: const TextStyle(fontSize: 13)),
    ],
  );
}

Widget? _buildMatchActions(ColorScheme colorScheme, MatchContest contest) {
  if (contest.contestStatus == 2) {
    return FilledButton.tonal(
      style: const ButtonStyle(
        visualDensity: .compact,
        tapTargetSize: .shrinkWrap,
        padding: WidgetStatePropertyAll(.symmetric(horizontal: 16)),
      ),
      onPressed: contest.liveRoom == null || contest.liveRoom == 0
          ? null
          : () => PageUtils.toLiveRoom(contest.liveRoom!),
      child: const Text('观看直播'),
    );
  }

  final style = ButtonStyle(
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
  final buttons = <Widget>[];
  if (contest.playback?.isNotEmpty == true) {
    buttons.add(
      OutlinedButton(
        style: style,
        onPressed: () => PiliScheme.routePushFromUrl(contest.playback!),
        child: const Text('回放'),
      ),
    );
  }
  if (contest.liveRoom != null && contest.liveRoom != 0) {
    buttons.add(
      OutlinedButton(
        style: style,
        onPressed: () => PageUtils.toLiveRoom(contest.liveRoom!),
        child: const Text('直播间'),
      ),
    );
  }
  if (buttons.isEmpty) return null;
  if (buttons.length == 1) return buttons.single;
  return Row(spacing: 12, mainAxisSize: .min, children: buttons);
}

Widget buildContestItem(
  ColorScheme colorScheme,
  MatchContest contest, {
  String? fallbackTitle,
}) {
  final home = contest.homeTeam;
  final away = contest.awayTeam;
  final hasTeams =
      contest.homeId != 0 &&
      contest.awayId != 0 &&
      home != null &&
      away != null;
  final status = contest.contestStatus == 1
      ? 'VS'
      : '${contest.homeScore ?? '-'} : ${contest.awayScore ?? '-'}';
  final date = contest.contestStatus == 3
      ? '${DateFormatUtils.dateFormat(contest.stime)} 已结束'
      : contest.contestStatus == 1 && contest.stime != null
      ? DateFormatUtils.format(
          contest.stime,
          format: DateFormat('yy-MM-dd HH:mm'),
        )
      : null;
  final title = contest.title ?? contest.season?.title ?? fallbackTitle;

  return Column(
    mainAxisSize: .min,
    children: [
      if (title != null)
        Text(title, style: const TextStyle(fontWeight: .bold, fontSize: 16)),
      if (contest.gameStage != null || date != null)
        Padding(
          padding: const .only(top: 4),
          child: Text(
            [
              if (contest.gameStage != null) contest.gameStage!,
              ?date,
            ].join('    '),
            style: TextStyle(fontSize: 13, color: colorScheme.outline),
          ),
        ),
      const SizedBox(height: 5),
      if (hasTeams)
        TeamInfoLayout(
          homeTeam: _buildTeamInfo(home),
          status: Text(
            status,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: .bold,
              letterSpacing: 1.5,
            ),
          ),
          awayTeam: _buildTeamInfo(away),
        )
      else if (contest.season?.logo != null)
        NetworkImgLayer(
          width: 50,
          height: 50,
          src: 'https://i1.hdslb.com${contest.season!.logo}',
          type: .emote,
        ),
      const SizedBox(height: 10),
      ?_buildMatchActions(colorScheme, contest),
    ],
  );
}
