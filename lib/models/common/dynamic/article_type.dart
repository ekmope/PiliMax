enum ArticleType {
  read(12),
  opus(11);

  final int replyType;
  const ArticleType(this.replyType);

  static ArticleType fromRoute(Object? value) => switch (value) {
    ArticleType type => type,
    'read' => read,
    'opus' || 'picture' => opus,
    _ => throw FormatException('Unknown article type: $value'),
  };
}
