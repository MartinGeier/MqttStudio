import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../helpers/test_app.dart';

void main() {
  // easy_localization looks plural forms up as the flat keys "key.one" and "key.other"; a nested object under a
  // dotted key is not found and shows the raw key
  test('every plural text has flat plural keys', () {
    var translations = json.decode(File('assets/i18n/en.json').readAsStringSync()) as Map<String, dynamic>;
    expect(translations.values.whereType<Map<String, dynamic>>(), isEmpty);
    var plural = RegExp(r"'([a-z0-9_.]+)'\s*\.plural\(");
    var missing = <String>[];
    for (var file
        in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (var match in plural.allMatches(file.readAsStringSync())) {
        if (!translations.containsKey('${match.group(1)}.other')) {
          missing.add('${file.path}: ${match.group(1)}');
        }
      }
    }
    expect(missing, isEmpty);
  });

  testWidgets('plural texts resolve with their count and named arguments', (tester) async {
    GetIt.I.registerSingleton(SrxNavigationService(Container(), Container()));
    addTearDown(GetIt.I.reset);
    await loadTranslations();
    await tester.pumpWidget(testApp(Builder(
        builder: (context) => Column(children: [
              Text('documentation.delete.confirm'.plural(1, namedArgs: {'path': 'a/b'})),
              Text('documentation.delete.confirm'.plural(3, namedArgs: {'path': 'a'})),
              Text('docreview.template.meta'.plural(24)),
            ]))));
    await tester.pumpAndSettle();
    expect(find.text('Delete the documentation of a/b?'), findsOneWidget);
    expect(find.text('Delete a and everything below it (3 documented entries)?'), findsOneWidget);
    expect(find.text('Template · 24 topics'), findsOneWidget);
  });
}
