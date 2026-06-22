import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/login.dart';
import 'package:PiliMax/models_new/login_devices/data.dart';
import 'package:PiliMax/models_new/login_devices/device.dart';
import 'package:PiliMax/pages/common/common_list_controller.dart';

class LoginDevicesController
    extends CommonListController<LoginDevicesData, LoginDevice> {
  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  @override
  List<LoginDevice>? getDataList(LoginDevicesData response) {
    return response.devices;
  }

  @override
  Future<LoadingState<LoginDevicesData>> customGetData() =>
      LoginHttp.loginDevices();
}
