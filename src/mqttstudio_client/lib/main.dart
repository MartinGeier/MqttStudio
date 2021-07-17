import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/contoller/mqtt_controller.dart';
import 'package:mqttstudio/theme.dart';
import 'package:provider/provider.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'model/project.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'repository/local/local_project_repository.dart';
import 'viewmodel/mqtt_global_viewmodel.dart';
import 'viewmodel/project_global_viewmodel.dart';

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
    EasyLocalization(supportedLocales: [Locale('en')], path: 'assets/i18n', fallbackLocale: Locale('en'), child: MyApp()),
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
  GetIt.I.registerSingleton(SrxSessionController(true));
  //GetIt.I.registerSingleton(SrxHttpService(baseUrlRelease, baseUrlDebug, versionPath, GetIt.I.get<SessionController>()));
  GetIt.I.registerSingleton(SrxNavigationService(LoginPage(), HomePage()));
  GetIt.I.registerSingleton(MqttController());

  // global viewmodels
  GetIt.I.registerSingleton(MqttGlobalViewmodel());
  GetIt.I.registerSingleton(ProjectGlobalViewmodel());
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
              theme: AppColorScheme.lightTheme.copyWith(appBarTheme: Theme.of(context).appBarTheme.copyWith(brightness: Brightness.dark)),
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              navigatorKey: GetIt.instance.get<SrxNavigationService>().navigatorKey,
              home: /*GetIt.instance.get<SSessionController>().isLoggedIn ? */ HomePage())) /*: LoginPage() */,
    );
  }
}
