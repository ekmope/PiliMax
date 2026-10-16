const rootRpIdKey = 'comment_root_id';
const secondRpIdKey = 'comment_secondary_id';

(int? rootRpId, int? secondRpId) parseCommentId(
  Map<String, String> queryParameters,
) {
  final root = queryParameters[rootRpIdKey];
  final secondary = queryParameters[secondRpIdKey];
  final parsedRoot = root == null ? null : int.tryParse(root);
  final parsedSecondary = secondary == null ? null : int.tryParse(secondary);
  return (
    parsedRoot != null && parsedRoot > 0 ? parsedRoot : null,
    parsedSecondary != null && parsedSecondary > 0 ? parsedSecondary : null,
  );
}

Map<String, int> replyRouteArguments({
  int? rpid,
  int? rootRpId,
  int? secondRpId,
}) => {
  if (rpid != null) 'rpid': rpid,
  if (rootRpId != null) rootRpIdKey: rootRpId,
  if (secondRpId != null) secondRpIdKey: secondRpId,
};
