import 'dart:async';

import 'package:PiliMax/pages/live_room/controller.dart';
import 'package:PiliMax/pages/live_room/fans_medal/view.dart';
import 'package:PiliMax/pages/member/widget/medal_widget.dart';
import 'package:PiliMax/pilimax/live/fans_medal_actions.dart';
import 'package:PiliMax/services/account_service.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:PiliMax/utils/extension/size_ext.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class LiveFansMedalButton extends StatefulWidget {
  const LiveFansMedalButton({super.key, required this.controller});

  final LiveRoomController controller;

  @override
  State<LiveFansMedalButton> createState() => _LiveFansMedalButtonState();
}

class _LiveFansMedalButtonState extends State<LiveFansMedalButton> {
  LiveRoomController get controller => widget.controller;
  late final Worker _worker;

  @override
  void initState() {
    super.initState();
    _worker = ever(FansMedalActions.revision, (_) {
      if (!controller.canManageFansMedal) return;
      controller.markFansMedalStale();
      unawaited(controller.refreshCurrentFansMedal(invalidate: true));
    });
  }

  @override
  void dispose() {
    _worker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (Get.isRegistered<AccountService>()) {
        Get.find<AccountService>().isLogin.value;
      }
      if (!controller.canManageFansMedal) return const SizedBox.shrink();
      final medal = controller.currentFansMedal.value;
      final hasMedal = controller.hasRoomFansMedal.value;
      final valid =
          medal?.name != null &&
          medal?.level != null &&
          medal?.v2MedalColorStart?.isNotEmpty == true &&
          medal?.v2MedalColorText?.isNotEmpty == true;
      return Tooltip(
        message: '粉丝勋章',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _showPanel(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120, minHeight: 34),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: valid
                    ? MedalWidget.fromMedalInfo(
                        medal: medal!,
                        padding: MedalWidget.mediumPadding,
                      )
                    : hasMedal
                    ? const Text('未佩戴', style: TextStyle(fontSize: 12))
                    : const Icon(Icons.workspace_premium_outlined, size: 22),
              ),
            ),
          ),
        ),
      );
    });
  }

  Future<void> _showPanel(BuildContext context) async {
    unawaited(controller.refreshCurrentFansMedal());
    final portrait = MediaQuery.sizeOf(context).isPortrait;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      clipBehavior: Clip.hardEdge,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 450),
      builder: (_) => FractionallySizedBox(
        widthFactor: 1,
        heightFactor: PlatformUtils.isMobile && !portrait ? 1 : 0.5,
        child: FansMedalPanel(liveRoomController: controller),
      ),
    );
    if (!controller.isClosed) {
      await controller.refreshCurrentFansMedal(invalidate: true);
    }
  }
}
