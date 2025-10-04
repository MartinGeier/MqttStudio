import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/mqtt/mqtt_connection_viewmodel.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/service/piwik_tracking_service.dart';
import 'package:provider/provider.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'model/project.dart';
import 'message_viewer/message_viewer_page.dart';
import 'common/login_page.dart';
import 'repository/local/local_project_repository.dart';
import 'message_viewer/message_viewer.dart';
import 'project/project_viewmodel.dart';

//final String baseUrlRelease = 'to be defined';
//final String baseUrlDebug = 'http://192.168.10.100:5001';
//final String baseUrlDebug = 'http://192.168.5.118:5001';
//final String versionPath = 'v1';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  await openLocalDatabase();

  setupServiceLocator();
  await GetIt.instance.get<SrxSessionController>().restoreSession(); // TODO: eventually do during splash screen

  PiwikTrackingService().trackAction('App started');

  runApp(
    EasyLocalization(
        supportedLocales: [Locale('en')],
        path: 'assets/i18n',
        fallbackLocale: Locale('en'),
        assetLoader: SrxAssetLoader(),
        child: MyApp()),
  );
}

Future openLocalDatabase() async {
  GetIt.I.registerSingleton(SrxLocalDatabaseController());
  await GetIt.instance.get<SrxLocalDatabaseController>().openDatabase(); // TODO: eventually do during splash screen
}

void setupServiceLocator() {
  // repositories
  GetIt.I.registerSingleton<SrxCrudRepository<Project>>(LocalProjectRepository());

  // common
  GetIt.I.registerSingleton(SrxSessionController(true, '', ''));
  //GetIt.I.registerSingleton(SrxHttpService(baseUrlRelease, baseUrlDebug, versionPath, GetIt.I.get<SessionController>()));
  GetIt.I.registerSingleton(SrxNavigationService(LoginPage(), MessageViewerPage()));
  GetIt.I.registerSingleton(MqttAdapter());

  // features
  GetIt.I.registerSingleton(ProjectManager(onClosingNotSaved));
  GetIt.I.registerSingleton(MessageViewer());
  GetIt.I.registerSingleton(MqttConnectionViewmodel());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: GetIt.I.get<MqttConnectionViewmodel>(),
      child: ChangeNotifierProvider(
          create: (_) => ProjectViewmodel(),
          child: MaterialApp(
              title: 'MQTT Studio',
              theme: CustomTheme.lightTheme,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              navigatorKey: GetIt.instance.get<SrxNavigationService>().navigatorKey,
              home: /*GetIt.instance.get<SSessionController>().isLoggedIn ? */
                  SrxTheme(data: CustomTheme.srxTheme, child: MessageViewerPage()))) /*: LoginPage() */,
    );
  }
}

Future<bool?> onClosingNotSaved() async {
  return await showDialog<bool>(
      context: GetIt.instance.get<SrxNavigationService>().navigatorKey.currentContext!,
      builder: (context) =>
          SrxDialogs.srxYesNoDialog('navigator.confirmsaving_message'.tr(), context, showCancel: true));
}
