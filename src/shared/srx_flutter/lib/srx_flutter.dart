import 'dart:async';
import 'package:flutter/services.dart';

export 'src/controller/srx_local_database_controller.dart';
export 'src/controller/srx_session_controller.dart';
export 'src/models/srx_base_model.dart';
export 'src/models/srx_identity.dart';
export 'src/models/srx_session.dart';
export 'src/models/srx_twoway_synchronize.dart';
export 'src/repository/srx_base_local_repositories.dart';
export 'src/repository/srx_base_rest_repositories.dart';
export 'src/repository/srx_repositories.dart';
export 'src/service/srx_navigation_service.dart';
export 'src/service/srx_http_service.dart';
export 'src/service/srx_service_error.dart';
export 'src/service/srx_service_exception.dart';
export 'src/ui/srx_dialogs.dart';
export 'src/ui/srx_widgets.dart';
export 'src/ui/srx_datatable.dart';
export 'src/viewmodels/srx_viewmodels.dart';
export 'src/viewmodels/srx_changenotifier.dart';
export 'src/utils.dart';

class SrxFlutter {
  static const MethodChannel _channel = const MethodChannel('srx_flutter');

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }
}
