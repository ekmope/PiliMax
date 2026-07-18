import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

const double kChatListPadding = 14;

/// Reversed separated list used by private-message conversations.
///
/// Flutter's public ListView now keeps a short reversed list anchored to the
/// trailing edge, so the old copied RenderSliverList is no longer necessary.
class ChatListView extends StatelessWidget {
  const ChatListView.separated({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.controller,
    this.primary,
    this.physics,
    this.padding,
    required this.itemBuilder,
    required this.separatorBuilder,
    required this.itemCount,
    this.dragStartBehavior = DragStartBehavior.start,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    this.hitTestBehavior = HitTestBehavior.opaque,
  });

  final Axis scrollDirection;
  final ScrollController? controller;
  final bool? primary;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;
  final NullableIndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder separatorBuilder;
  final int itemCount;
  final DragStartBehavior dragStartBehavior;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;
  final String? restorationId;
  final Clip clipBehavior;
  final HitTestBehavior hitTestBehavior;

  @override
  Widget build(BuildContext context) => ListView.separated(
    scrollDirection: scrollDirection,
    reverse: true,
    controller: controller,
    primary: primary,
    physics: physics,
    padding: padding,
    itemBuilder: itemBuilder,
    separatorBuilder: separatorBuilder,
    itemCount: itemCount,
    dragStartBehavior: dragStartBehavior,
    keyboardDismissBehavior: keyboardDismissBehavior,
    restorationId: restorationId,
    clipBehavior: clipBehavior,
    hitTestBehavior: hitTestBehavior,
  );
}
