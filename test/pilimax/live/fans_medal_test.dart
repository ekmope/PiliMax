import 'dart:async';

import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models_new/live/live_fans_medal/config.dart';
import 'package:PiliMax/models_new/live/live_fans_medal/user_medal.dart';
import 'package:PiliMax/models_new/live/live_medal_wall/uinfo_medal.dart';
import 'package:PiliMax/pilimax/live/fans_medal_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps unavailable display settings unknown', () {
    final missing = FansMedalConfig.fromJson({});
    expect(missing.closeSpaceMedal, isNull);
    expect(missing.onlyShowWearing, isNull);
    final partial = FansMedalConfig.fromJson({
      'configs': {
        'close_space_medal': {'status': '1'},
        'only_show_wearing': {},
      },
    });
    expect(partial.closeSpaceMedal, isTrue);
    expect(partial.onlyShowWearing, isNull);
    final disabled = FansMedalConfig.fromJson({
      'configs': {
        'only_show_wearing': {'status': false},
      },
    });
    expect(disabled.onlyShowWearing, isFalse);
  });

  test('distinguishes selected, room and server displayed medals', () {
    final info = UserMedalInfo.fromJson({
      'up_medal': {},
      'curr_show': {'id': '10', 'ruid': '100', 'level': '4', 'name': '房间牌'},
      'curr_weared_v2': {'id': 20, 'ruid': 200, 'name': '佩戴牌'},
      'lookup_v2': {'id': '30', 'ruid': '300', 'name': '主播牌'},
    });
    expect(info.hasMedal, isTrue);
    expect(info.current?.id, 10);
    expect(info.current?.level, 4);
    expect(info.wearing?.id, 20);
    expect(info.roomMedal?.ruid, 300);
    expect(UserMedalInfo.fromJson({'curr_show': []}).current, isNull);
  });

  test('retains the lit-only chat medal rule', () {
    expect(UinfoMedal.lightMedal({'id': 1, 'is_light': 0}), isNull);
    expect(UinfoMedal.lightMedal({'id': 1, 'is_light': 1})?.id, 1);
  });

  test(
    'serializes cross-page actions and notifies only successful mutations',
    () async {
      final completion = Completer<LoadingState<void>>();
      final revision = FansMedalActions.revision.value;
      final first = FansMedalActions.run(() => completion.future);
      var secondCalled = false;
      final second = await FansMedalActions.run(() async {
        secondCalled = true;
        return const Success(null);
      });
      expect(second.isSuccess, isFalse);
      expect(secondCalled, isFalse);
      completion.complete(const Success(null));
      expect((await first).isSuccess, isTrue);
      expect(FansMedalActions.revision.value, revision + 1);
      final failed = await FansMedalActions.run(
        () async => const Error('failure'),
      );
      expect(failed.isSuccess, isFalse);
      expect(FansMedalActions.revision.value, revision + 1);
      expect(FansMedalActions.isBusy, isFalse);
    },
  );

  test('releases the action lane after an unexpected failure', () async {
    await expectLater(
      FansMedalActions.run(() async => throw StateError('network failure')),
      throwsStateError,
    );
    expect(FansMedalActions.isBusy, isFalse);
    expect(
      (await FansMedalActions.run(() async => const Success(null))).isSuccess,
      isTrue,
    );
  });
}
