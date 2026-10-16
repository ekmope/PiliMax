import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/models_new/later/list.dart';
import 'package:PiliMax/pages/later/on_push_later.dart';
import 'package:material_ui/material_ui.dart';

class MineLaterItem extends StatelessWidget {
  const MineLaterItem({
    super.key,
    required this.item,
    required this.onPop,
  });

  final LaterItemModel item;
  final VoidCallback onPop;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onPushLater(item).whenComplete(onPop),
      behavior: .opaque,
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Stack(
            clipBehavior: .none,
            children: [
              NetworkImgLayer(
                src: item.pic,
                width: 180,
                height: 110,
              ),
              ?item.label,
              ...item.progressIndicator(ColorScheme.of(context)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ' ${item.title}',
            maxLines: 2,
            overflow: .ellipsis,
            style: const TextStyle(height: 1.42, letterSpacing: 0.3),
          ),
        ],
      ),
    );
  }
}
