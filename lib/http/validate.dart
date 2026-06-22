import 'package:PiliMax/http/api.dart';
import 'package:PiliMax/http/init.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/utils/accounts.dart';
import 'package:dio/dio.dart';

abstract final class ValidateHttp {
  static Future<LoadingState<Map?>> gaiaVgateRegister(String vVoucher) async {
    final res = await Request().post(
      Api.gaiaVgateRegister,
      queryParameters: {
        if (Accounts.main.isLogin) 'csrf': Accounts.main.csrf,
      },
      data: {
        'v_voucher': vVoucher,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    if (res.data['code'] == 0) {
      return Success(res.data['data']);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<Map?>> gaiaVgateValidate({
    required dynamic challenge,
    required dynamic seccode,
    required dynamic token,
    required dynamic validate,
  }) async {
    final res = await Request().post(
      Api.gaiaVgateValidate,
      queryParameters: {
        if (Accounts.main.isLogin) 'csrf': Accounts.main.csrf,
      },
      data: {
        'challenge': challenge,
        'seccode': seccode,
        'token': token,
        'validate': validate,
      },
    );
    if (res.data['code'] == 0) {
      return Success(res.data['data']);
    } else {
      return Error(res.data['message']);
    }
  }
}
