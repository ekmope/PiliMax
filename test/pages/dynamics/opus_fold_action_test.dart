import 'package:PiliMax/models/dynamics/result.dart';
import 'package:PiliMax/pages/dynamics/widgets/rich_node_panel.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show ThemeData;

void main() {
  test('only the exact single full-text action redirects', () {
    expect(
      DynamicOpusModel.fromJson({
        'fold_action': ['全文'],
      }).redirect,
      isTrue,
    );
    for (final action in [
      null,
      [],
      ['收起'],
      ['全文', '收起'],
    ]) {
      expect(
        DynamicOpusModel.fromJson({'fold_action': action}).redirect,
        isFalse,
      );
    }
  });

  for (final scenario in ['plain description', 'title only', 'empty body']) {
    testWidgets('full-text entry survives $scenario', (tester) async {
      final opus = DynamicOpusModel(
        title: scenario == 'title only' ? '标题' : null,
        redirect: true,
      );
      final item = DynamicItemModel.fromJson({'id_str': '42'});
      item.modules.moduleDynamic = ModuleDynamicModel(
        major: DynamicMajorModel(opus: opus),
        desc: scenario == 'plain description'
            ? DynamicDescModel.fromJson({'text': '摘要'})
            : null,
      );
      TextSpan? span;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              span = richNode(
                context,
                theme: ThemeData(),
                floor: 0,
                isDetail: false,
                isSave: false,
                item: item,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      expect(span, isNotNull);
      expect(span!.toPlainText(), endsWith('\n全文'));
      expect((span!.children!.last as TextSpan).recognizer, isNotNull);
      if (scenario == 'plain description') {
        expect(span!.toPlainText(), startsWith('摘要'));
      }
      if (scenario == 'title only') {
        expect(span!.toPlainText(), startsWith('标题'));
      }
    });
  }
}
