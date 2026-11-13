import 'package:PiliMax/models/common/dynamic/article_type.dart';
import 'package:PiliMax/utils/article_route_data.dart';
import 'package:PiliMax/utils/reply_scheme_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('typed arguments take precedence without consuming reply targets', () {
    final args = <String, Object>{
      'id': '42',
      'type': ArticleType.opus,
      'rpid': 101,
      rootRpIdKey: 100,
      secondRpIdKey: 101,
      'viewComment': true,
    };
    final route = ArticleRouteData.from(
      arguments: args,
      parameters: {'id': '7', 'type': 'read'},
    );
    expect(route.id, '42');
    expect(route.type, ArticleType.opus);
    expect(route.tag, 'opus42');
    expect(route.viewComment, isTrue);
    expect(args['rpid'], 101);
    expect(args[rootRpIdKey], 100);
    expect(args[secondRpIdKey], 101);
  });

  test(
    'old picture parameters retain opus comment type and route identity',
    () {
      final route = ArticleRouteData.from(
        parameters: {'id': '42', 'type': 'picture', 'viewComment': ''},
      );
      expect(route.type, ArticleType.opus);
      expect(route.type.replyType, 11);
      expect(route.tag, 'opus42');
      expect(route.viewComment, isTrue);
    },
  );

  test('legacy read entry and empty arguments remain compatible', () {
    final route = ArticleRouteData.from(
      arguments: {},
      parameters: {'id': '7', 'type': 'read'},
    );
    expect(route.type, ArticleType.read);
    expect(route.viewComment, isFalse);
    expect(route.type.replyType, 12);
  });
}
