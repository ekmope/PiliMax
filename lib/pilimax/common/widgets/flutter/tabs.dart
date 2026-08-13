import 'dart:async' show unawaited;
import 'dart:ui' show SemanticsRole, clampDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TabBarView;

/// Tab-controlled page view that also supports a vertical page axis.
class CustomTabBarView extends StatefulWidget {
  const CustomTabBarView({
    super.key,
    required this.children,
    this.controller,
    this.physics,
    this.dragStartBehavior = DragStartBehavior.start,
    this.viewportFraction = 1,
    this.clipBehavior = Clip.hardEdge,
    this.scrollDirection = Axis.horizontal,
  });

  final List<Widget> children;
  final TabController? controller;
  final ScrollPhysics? physics;
  final DragStartBehavior dragStartBehavior;
  final double viewportFraction;
  final Clip clipBehavior;
  final Axis scrollDirection;

  @override
  State<CustomTabBarView> createState() => _CustomTabBarViewState();
}

class _CustomTabBarViewState extends State<CustomTabBarView> {
  TabController? _controller;
  Animation<double>? _controllerAnimation;
  PageController? _pageController;
  List<Widget>? _childrenWithKey;
  late int _currentIndex;
  int _warpUnderwayCount = 0;
  int _warpGeneration = 0;
  int _scrollUnderwayCount = 0;
  bool _hasScheduledChildrenUpdate = false;

  bool _updateController() {
    final next = widget.controller ?? DefaultTabController.maybeOf(context);
    if (next == null) {
      throw FlutterError('CustomTabBarView requires a TabController.');
    }
    if (next == _controller) {
      return false;
    }

    _controllerAnimation?.removeListener(_handleControllerChanged);
    _controller = next;
    _controllerAnimation = next.animation;
    _controllerAnimation?.addListener(_handleControllerChanged);
    _currentIndex = next.index;
    return true;
  }

  void _initPageController() {
    _pageController?.dispose();
    _pageController = PageController(
      initialPage: _currentIndex,
      viewportFraction: widget.viewportFraction,
    );
  }

  void _syncPageToController() {
    if (_pageController?.hasClients ?? false) {
      _jumpToPage(_currentIndex);
    } else {
      _initPageController();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controllerChanged = _updateController();
    if (controllerChanged) {
      _warpGeneration += 1;
    }
    if (_pageController == null) {
      _initPageController();
    } else if (controllerChanged) {
      _syncPageToController();
    }
    if (_childrenWithKey == null || controllerChanged) {
      _updateChildren();
    }
  }

  @override
  void didUpdateWidget(CustomTabBarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged =
        oldWidget.controller != widget.controller && _updateController();
    final viewportChanged =
        oldWidget.viewportFraction != widget.viewportFraction;
    final childrenChanged = oldWidget.children != widget.children;
    if (controllerChanged || viewportChanged || childrenChanged) {
      _warpGeneration += 1;
    }
    if (viewportChanged) {
      _initPageController();
    } else if (controllerChanged) {
      _syncPageToController();
    }
    if (controllerChanged || viewportChanged || childrenChanged) {
      _updateChildren();
    }
  }

  void _handleControllerChanged() {
    final controller = _controller;
    if (_scrollUnderwayCount > 0 || controller == null) {
      return;
    }

    final index = controller.index;
    if (index == _currentIndex) {
      return;
    }
    _currentIndex = index;
    if (!_pageController!.hasClients) {
      _warpGeneration += 1;
      _initPageController();
      setState(_updateChildren);
      return;
    }

    final generation = ++_warpGeneration;
    if (_pageController!.page == index.toDouble()) {
      setState(_updateChildren);
    } else if (!controller.indexIsChanging ||
        controller.animationDuration == Duration.zero) {
      _jumpToPage(index);
      setState(_updateChildren);
    } else if ((index - controller.previousIndex).abs() == 1) {
      setState(_updateChildren);
      unawaited(
        _warpToAdjacentPage(
          index,
          controller.animationDuration,
          generation,
        ),
      );
    } else {
      _warpToNonAdjacentPage(
        index,
        controller.previousIndex,
        controller.animationDuration,
        generation,
      );
    }
  }

  Future<void> _warpToAdjacentPage(
    int index,
    Duration duration,
    int generation,
  ) async {
    await _animateToPage(index, duration);
    if (mounted && generation == _warpGeneration) {
      setState(_updateChildren);
    }
  }

  void _warpToNonAdjacentPage(
    int index,
    int previousIndex,
    Duration duration,
    int generation,
  ) {
    final initialPage = index > previousIndex ? index - 1 : index + 1;
    setState(() {
      _updateChildren();
      _childrenWithKey = List<Widget>.of(
        _childrenWithKey!,
        growable: false,
      );
      final previousChild = _childrenWithKey![previousIndex];
      _childrenWithKey![previousIndex] = _childrenWithKey![initialPage];
      _childrenWithKey![initialPage] = previousChild;
    });
    _jumpToPage(initialPage);
    unawaited(_finishNonAdjacentWarp(index, duration, generation));
  }

  Future<void> _finishNonAdjacentWarp(
    int index,
    Duration duration,
    int generation,
  ) async {
    await _animateToPage(index, duration);
    if (mounted && generation == _warpGeneration) {
      setState(_updateChildren);
    }
  }

  void _jumpToPage(int index) {
    _warpUnderwayCount += 1;
    try {
      _pageController!.jumpToPage(index);
    } finally {
      _warpUnderwayCount -= 1;
    }
  }

  Future<void> _animateToPage(int index, Duration duration) async {
    _warpUnderwayCount += 1;
    try {
      await _pageController!.animateToPage(
        index,
        duration: duration,
        curve: Curves.ease,
      );
    } finally {
      _warpUnderwayCount -= 1;
    }
  }

  void _scheduleChildrenUpdate() {
    if (_hasScheduledChildrenUpdate || !mounted) {
      return;
    }
    _hasScheduledChildrenUpdate = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hasScheduledChildrenUpdate = false;
      if (mounted) {
        setState(_updateChildren);
      }
    }, debugLabel: 'CustomTabBarView.updateChildren');
  }

  void _updateChildren() {
    _childrenWithKey = KeyedSubtree.ensureUniqueKeysForList(
      widget.children.indexed.map((entry) {
        return HeroMode(
          enabled: entry.$1 == _currentIndex,
          child: Semantics(role: SemanticsRole.tabPanel, child: entry.$2),
        );
      }).toList(),
    );
  }

  void _syncControllerOffset(double page) {
    final controller = _controller!;
    controller.offset = clampDouble(page - controller.index, -1, 1);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (_warpUnderwayCount > 0 ||
        _scrollUnderwayCount > 0 ||
        notification.depth != 0 ||
        _controllerAnimation == null ||
        !(_pageController?.hasClients ?? false)) {
      return false;
    }

    final page = _pageController!.page;
    if (page == null) {
      return false;
    }

    _scrollUnderwayCount += 1;
    try {
      final controller = _controller!;
      if (notification is ScrollUpdateNotification &&
          !controller.indexIsChanging) {
        if ((page - controller.index).abs() > 1) {
          controller.index = page.round();
          _currentIndex = controller.index;
          _scheduleChildrenUpdate();
        }
        _syncControllerOffset(page);
      } else if (notification is ScrollEndNotification) {
        final index = page.round();
        if (controller.index != index) {
          controller.index = index;
        }
        if (_currentIndex != index) {
          _currentIndex = index;
          _scheduleChildrenUpdate();
        }
        if (!controller.indexIsChanging) {
          _syncControllerOffset(page);
        }
      }
    } finally {
      _scrollUnderwayCount -= 1;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    assert(_controller!.length == widget.children.length);
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: PageView(
        scrollDirection: widget.scrollDirection,
        controller: _pageController,
        physics: widget.physics,
        dragStartBehavior: widget.dragStartBehavior,
        clipBehavior: widget.clipBehavior,
        children: _childrenWithKey!,
      ),
    );
  }

  @override
  void dispose() {
    _warpGeneration += 1;
    _controllerAnimation?.removeListener(_handleControllerChanged);
    _controllerAnimation = null;
    _controller = null;
    _pageController?.dispose();
    super.dispose();
  }
}
