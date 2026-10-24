import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/project/project_viewmodel.dart';
import 'package:mqttstudio/mqtt/mqtt_connection_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srx_flutter/srx_flutter.dart';

Map<String, dynamic> _translations = {};

// Loads the English texts of SrxFlutter and the app like SrxAssetLoader does. Call it from setUpAll, where real I/O works.
Future loadTranslations() async {
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();
  EasyLocalization.logger.enableBuildModes = [];
  _translations = {
    ...json.decode(await rootBundle.loadString('packages/srx_flutter/assets/i18n/en.json')) as Map<String, dynamic>,
    ...json.decode(File('assets/i18n/en.json').readAsStringSync()) as Map<String, dynamic>,
  };
}

class _MemoryAssetLoader extends AssetLoader {
  const _MemoryAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) => Future.value(_translations);
}

// Hosts a widget like the app does: translations, app theme, SrxTheme, project viewmodel and the navigator of
// SrxNavigationService. Pump with pumpAndSettle so the translations are loaded.
Widget testApp(Widget child) {
  return EasyLocalization(
    supportedLocales: [Locale('en')],
    path: 'assets/i18n',
    fallbackLocale: Locale('en'),
    assetLoader: const _MemoryAssetLoader(),
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProjectViewmodel()),
        ChangeNotifierProvider(create: (_) => MqttConnectionViewmodel()),
      ],
      child: Builder(
        builder: (context) => MaterialApp(
          theme: CustomTheme.lightTheme,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          navigatorKey: GetIt.I.get<SrxNavigationService>().navigatorKey,
          home: SrxTheme(data: CustomTheme.srxTheme, child: Scaffold(body: child)),
        ),
      ),
    ),
  );
}

// The test font draws every character as a full square, so texts are much wider than in the app and rows that fit in
// the app overflow in tests. Runs body ignoring these overflow errors; every other error still fails the test.
Future<void> ignoringOverflowErrors(Future<void> Function() body) async {
  var onError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (!details.exceptionAsString().contains('A RenderFlex overflowed')) {
      onError?.call(details);
    }
  };
  try {
    await body();
  } finally {
    FlutterError.onError = onError;
  }
}

// A button that opens the dialog and keeps its result
class DialogHost extends StatefulWidget {
  final Widget dialog;
  const DialogHost(this.dialog, {super.key});

  @override
  State<DialogHost> createState() => DialogHostState();
}

class DialogHostState extends State<DialogHost> {
  dynamic result;

  @override
  Widget build(BuildContext context) => TextButton(
      onPressed: () async {
        result = await showDialog(context: context, builder: (_) => widget.dialog);
      },
      child: Text('open'));
}
