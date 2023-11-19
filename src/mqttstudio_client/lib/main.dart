import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/mqtt/mqtt_controller.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:provider/provider.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'model/project.dart';
import 'topic_viewer/topic_detailviewer_page.dart';
import 'common/login_page.dart';
import 'repository/local/local_project_repository.dart';
import 'mqtt/mqtt_global_viewmodel.dart';
import 'project/project_global_viewmodel.dart';

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

  runApp(
    EasyLocalization(
        supportedLocales: [Locale('en')], path: 'assets/i18n', fallbackLocale: Locale('en'), assetLoader: SrxAssetLoader(), child: MyApp()),
  );
}

Future openLocalDatabase() async {
  GetIt.I.registerSingleton(SrxLocalDatabaseController());
  await GetIt.instance.get<SrxLocalDatabaseController>().openDatabase(); // TODO: eventually do during splash screen
}

void setupServiceLocator() {
  // repositories
  GetIt.I.registerSingleton<SrxCrudRepository<Project, Project>>(LocalProjectRepository());

  // common
  GetIt.I.registerSingleton(SrxSessionController(true, '', ''));
  //GetIt.I.registerSingleton(SrxHttpService(baseUrlRelease, baseUrlDebug, versionPath, GetIt.I.get<SessionController>()));
  GetIt.I.registerSingleton(SrxNavigationService(LoginPage(), TopicDetailViewerPage()));
  GetIt.I.registerSingleton(MqttController());

  // global viewmodels
  GetIt.I.registerSingleton(MqttGlobalViewmodel());
  GetIt.I.registerSingleton(ProjectGlobalViewmodel(onClosingNotSaved));
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: GetIt.I.get<MqttGlobalViewmodel>(),
      child: ChangeNotifierProvider.value(
          value: GetIt.I.get<ProjectGlobalViewmodel>(),
          child: MaterialApp(
              title: 'MQTT Studio',
              theme: CustomTheme.lightTheme,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              navigatorKey: GetIt.instance.get<SrxNavigationService>().navigatorKey,
              home: /*GetIt.instance.get<SSessionController>().isLoggedIn ? */ TopicDetailViewerPage())) /*: LoginPage() */,
    );
  }
}

Future<bool?> onClosingNotSaved() async {
  return await showDialog<bool>(
      context: GetIt.instance.get<SrxNavigationService>().navigatorKey.currentContext!,
      builder: (context) => SrxDialogs.srxYesNoDialog('navigator.confirmsaving_message'.tr(), context, showCancel: true));
}
