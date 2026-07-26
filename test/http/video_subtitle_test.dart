import 'package:PiliMax/http/video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('subtitle preprocessing initializes the filler pattern', () {
    final result = VideoHttp.preprocessSubtitlesForAi([
      {'from': 0, 'content': 'hello'},
    ]);

    expect(result.text, '[00:00] hello');
    expect(result.isTooLong, isFalse);
  });
}
