import 'package:PiliMax/utils/app_scheme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invalid external routes fail closed without async errors', () async {
    for (final url in [
      '%',
      'bilibili://comment/detail/17/832703053858603029',
      'bilibili://comment/detail/17/-1/238686570016',
      'bilibili://comment/detail/17/9223372036854775808/1',
      'bilibili://video/123?cid=-1',
      'https://www.bilibili.com/video/av123?comment_root_id=-1',
    ]) {
      expect(
        await PiliScheme.routePushFromUrl(url),
        isFalse,
        reason: url,
      );
    }
  });

  test(
    'invalid vote id is rejected without opening a fallback route',
    () async {
      for (final voteId in ['-1', '0', '9223372036854775808']) {
        expect(
          await PiliScheme.routePushFromUrl(
            'https://t.bilibili.com/vote/h5/index?vote_id=$voteId',
            selfHandle: true,
          ),
          isFalse,
          reason: voteId,
        );
      }
    },
  );

  test('clipboard video rejects a malformed authority', () async {
    var navigationChecked = false;

    expect(
      await PiliScheme.openClipboardVideo(
        'https://[invalid]/video/av1',
        off: false,
        canNavigate: () {
          navigationChecked = true;
          return true;
        },
      ),
      isFalse,
    );
    expect(navigationChecked, isFalse);
  });
}
