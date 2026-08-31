import 'package:PiliMax/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliMax/pages/setting/models/model.dart';
import 'package:PiliMax/pages/setting/models/setting_section.dart';
import 'package:material_ui/material_ui.dart';

class CommonSetting extends StatefulWidget {
  const CommonSetting({
    super.key,
    required this.section,
    this.showAppBar = true,
    this.autoOpenKeywordFilter = false,
  });

  final SettingSection section;
  final bool showAppBar;
  final bool autoOpenKeywordFilter;

  @override
  State<CommonSetting> createState() => _CommonSettingState();
}

class _CommonSettingState extends State<CommonSetting> {
  late EdgeInsets padding;
  late List<SettingsModel> settings;

  void _initSettings() {
    settings = widget.section.createSettings();
  }

  void _scheduleKeywordFilter() {
    if (!widget.autoOpenKeywordFilter) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = widget.section.keywordFilterIndex;
      if (index == null || index < 0 || index >= settings.length) return;
      if (settings[index] case NormalModel(:final onTap)) {
        onTap?.call(context, () {
          if (mounted) setState(() {});
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _initSettings();
    _scheduleKeywordFilter();
  }

  @override
  void didUpdateWidget(CommonSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sectionChanged = widget.section.type != oldWidget.section.type;
    if (sectionChanged) {
      _initSettings();
    }
    if ((sectionChanged && widget.autoOpenKeywordFilter) ||
        (!oldWidget.autoOpenKeywordFilter && widget.autoOpenKeywordFilter)) {
      _scheduleKeywordFilter();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    padding = MediaQuery.viewPaddingOf(context);
  }

  @override
  Widget build(BuildContext context) {
    final showAppBar = widget.showAppBar;
    final dividerBeforeIndex = widget.section.dividerBeforeIndex;
    final validDividerIndex =
        dividerBeforeIndex != null &&
            dividerBeforeIndex >= 0 &&
            dividerBeforeIndex <= settings.length
        ? dividerBeforeIndex
        : null;
    return SimpleScaffold(
      appBar: showAppBar
          ? AppBar(title: Text(widget.section.type.title))
          : null,
      body: ListView.builder(
        key: ValueKey(widget.section.type),
        padding: EdgeInsets.only(
          left: showAppBar ? padding.left : 0,
          right: showAppBar ? padding.right : 0,
          bottom: padding.bottom + 100,
        ),
        itemCount: settings.length + (validDividerIndex == null ? 0 : 1),
        itemBuilder: (context, index) {
          if (index == validDividerIndex) {
            return const Divider(height: 1);
          }
          final settingIndex =
              validDividerIndex != null && index > validDividerIndex
              ? index - 1
              : index;
          return settings[settingIndex].widget;
        },
      ),
    );
  }
}
