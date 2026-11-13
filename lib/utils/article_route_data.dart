import 'package:PiliMax/models/common/dynamic/article_type.dart';

/// Reads typed article routes while retaining older parameter-based entries.
class ArticleRouteData {
  const ArticleRouteData({
    required this.id,
    required this.type,
    this.viewComment = false,
  });

  factory ArticleRouteData.from({
    Object? arguments,
    Map<String, String?> parameters = const {},
  }) {
    final args = arguments is Map ? arguments : const {};
    final id = args['id'] ?? parameters['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Missing article id');
    }
    return ArticleRouteData(
      id: id,
      type: ArticleType.fromRoute(args['type'] ?? parameters['type']),
      viewComment:
          args['viewComment'] == true || parameters.containsKey('viewComment'),
    );
  }

  final String id;
  final ArticleType type;
  final bool viewComment;

  String get tag => type.name + id;
}
