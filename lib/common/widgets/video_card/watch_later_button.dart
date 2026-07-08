import 'package:PiliMax/http/user.dart';
import 'package:flutter/material.dart';

final class WatchLaterTarget {
  const WatchLaterTarget({
    required this.identity,
    required this.bvid,
    required this.aid,
  });

  factory WatchLaterTarget.from({
    required Object fallback,
    String? bvid,
    int? aid,
  }) {
    final trimmedBvid = bvid?.trim();
    final validBvid = trimmedBvid?.isNotEmpty == true ? trimmedBvid : null;
    return WatchLaterTarget(
      identity: validBvid ?? aid ?? fallback,
      bvid: validBvid,
      aid: aid,
    );
  }

  final Object identity;
  final String? bvid;
  final int? aid;
}

class QuickWatchLaterButton extends StatefulWidget {
  const QuickWatchLaterButton({
    super.key,
    required this.target,
    this.iconSize = 18,
    this.padding = const EdgeInsets.all(4),
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
  });

  final WatchLaterTarget target;
  final double iconSize;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  @override
  State<QuickWatchLaterButton> createState() => _QuickWatchLaterButtonState();
}

class _QuickWatchLaterButtonState extends State<QuickWatchLaterButton> {
  bool _isInWatchLater = false;

  @override
  void didUpdateWidget(covariant QuickWatchLaterButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.identity != widget.target.identity) {
      _isInWatchLater = false;
    }
  }

  Future<void> _onTap() async {
    final requestIdentity = widget.target.identity;
    if (_isInWatchLater) {
      final aid = widget.target.aid;
      if (aid == null) {
        return;
      }
      final res = await UserHttp.toViewDel(aids: aid.toString());
      res.toast();
      if (!mounted ||
          widget.target.identity != requestIdentity ||
          !res.isSuccess) {
        return;
      }
      setState(() => _isInWatchLater = false);
      return;
    }

    final bvid = widget.target.bvid;
    if (bvid == null) {
      return;
    }
    final res = await UserHttp.toViewLater(bvid: bvid);
    res.toast();
    if (!mounted ||
        widget.target.identity != requestIdentity ||
        !res.isSuccess) {
      return;
    }
    setState(() => _isInWatchLater = true);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _isInWatchLater
          ? Colors.green.withValues(alpha: 0.8)
          : Colors.black54,
      borderRadius: widget.borderRadius,
      child: InkWell(
        borderRadius: widget.borderRadius,
        onTap: _onTap,
        child: Padding(
          padding: widget.padding,
          child: Icon(
            _isInWatchLater ? Icons.check : Icons.watch_later_outlined,
            size: widget.iconSize,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
