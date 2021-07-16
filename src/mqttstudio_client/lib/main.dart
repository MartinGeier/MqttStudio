import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio_client/contoller/mqtt_controller.dart';
import 'package:mqttstudio_client/contoller/project_controller.dart';
import 'package:mqttstudio_client/theme.dart';
import 'package:mqttstudio_client/viewmodel/mqtt_master_viewmodel.dart';
import 'package:srx_flutter/srx_flutter.dart';

import 'pages/home_page.dart';
import 'pages/login_page.dart';

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

  // global viewmodels
  GetIt.I.registerLazySingleton(() => MqttMasterViewmodel());

  // common
  GetIt.I.registerSingleton(SrxSessionController(true));
  //GetIt.I.registerSingleton(SrxHttpService(baseUrlRelease, baseUrlDebug, versionPath, GetIt.I.get<SessionController>()));
  GetIt.I.registerSingleton(SrxNavigationService(LoginPage(), HomePage()));
  GetIt.I.registerSingleton(MqttController());
  GetIt.I.registerSingleton(ProjectController());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Enerdesk',
      theme: AppColorScheme.lightTheme.copyWith(appBarTheme: Theme.of(context).appBarTheme.copyWith(brightness: Brightness.dark)),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      navigatorKey: GetIt.instance.get<SrxNavigationService>().navigatorKey,
      home: /*GetIt.instance.get<SSessionController>().isLoggedIn ? */ HomePage() /*: LoginPage() */,
    );
  }
}
