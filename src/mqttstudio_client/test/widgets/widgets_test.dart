import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/widgets/checkbox_field.dart';
import 'package:mqttstudio/common/widgets/topic_chip.dart';
import 'package:mqttstudio/custom_theme.dart';
import 'package:mqttstudio/message_viewer/add_topic_dialog.dart';
import 'package:mqttstudio/model/project.dart';
import 'package:mqttstudio/model/topic_color.dart';
import 'package:mqttstudio/project/project_edit_dialog.dart';
import 'package:mqttstudio/project/project_edit_viewmodel.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../helpers/test_app.dart';
import '../helpers/test_setup.dart';

Finder textField(String formControlName) =>
    find.byWidgetPredicate((w) => w is ReactiveTextField && w.formControlName == formControlName);

void main() {
  setUpAll(loadTranslations);

  setUp(() {
    setUpServices();
    GetIt.I.registerSingleton(SrxNavigationService(Container(), Container()));
  });

  tearDown(tearDownServices);

  group('CheckboxField', () {
    testWidgets('tapping the label toggles the value', (tester) async {
      var form = FormGroup({'flag': FormControl<bool>(value: false)});
      var changes = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ReactiveForm(
                  formGroup: form,
                  child:
                      CheckboxField(formControlName: 'flag', form: form, label: 'Flag', onChanged: () => changes++)))));

      await tester.tap(find.text('Flag'));
      await tester.pump();

      expect(form.control('flag').value, isTrue);
      expect(changes, 1);
    });

    testWidgets('does not toggle a disabled control', (tester) async {
      var form = FormGroup({'flag': FormControl<bool>(value: false, disabled: true)});
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ReactiveForm(
                  formGroup: form, child: CheckboxField(formControlName: 'flag', form: form, label: 'Flag')))));

      await tester.tap(find.text('Flag'));
      await tester.pump();

      expect(form.control('flag').value, isFalse);
    });
  });

  group('TopicChip', () {
    testWidgets('shows topic and count and reports presses', (tester) async {
      var pressed = 0;
      String? deleted;
      await tester.pumpWidget(MaterialApp(
          theme: CustomTheme.lightTheme,
          home: Scaffold(
              body: TopicChip(
                  topic: 'home/temp',
                  topicColor: TopicColor(Colors.teal),
                  countLabel: '3',
                  onPressed: () => pressed++,
                  onDeletePressed: (topic) => deleted = topic))));

      expect(find.text('home/temp'), findsOneWidget);
      expect(find.text('# 3'), findsOneWidget);

      await tester.tap(find.text('home/temp'));
      await tester.tap(find.byIcon(Icons.cancel_rounded));

      expect(pressed, 1);
      expect(deleted, 'home/temp');
    });
  });

  // opens the dialog through a button, like the app does
  Future openDialog(WidgetTester tester, Widget dialog) async {
    await tester.pumpWidget(testApp(DialogHost(dialog)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('ProjectEditDialog', () {
    testWidgets('does not close while the form is invalid', (tester) async {
      await ignoringOverflowErrors(() async {
        await openDialog(tester, ProjectEditDialog());

        await tester.tap(find.text('Ok'));
        await tester.pumpAndSettle();

        expect(find.byType(ProjectEditDialog), findsOneWidget);
        expect(find.text('Value required'), findsWidgets);
      });
    });

    testWidgets('returns a new project', (tester) async {
      await ignoringOverflowErrors(() async {
        await openDialog(tester, ProjectEditDialog());

        await tester.enterText(textField(ProjectEditViewmodel.projectNameField), 'Widget project');
        await tester.enterText(textField(ProjectEditViewmodel.mqttHostnameField), 'broker.local');
        await tester.tap(find.text('Ok'));
        await tester.pumpAndSettle();

        expect(find.byType(ProjectEditDialog), findsNothing);
        Project project = tester.state<DialogHostState>(find.byType(DialogHost)).result;
        expect(project.name, 'Widget project');
        expect(project.mqttSettings.hostname, 'broker.local');
      });
    });

    testWidgets('cancel returns nothing', (tester) async {
      await ignoringOverflowErrors(() async {
        await openDialog(tester, ProjectEditDialog());

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.byType(ProjectEditDialog), findsNothing);
        expect(tester.state<DialogHostState>(find.byType(DialogHost)).result, isNull);
      });
    });
  });

  group('AddTopicDialog', () {
    testWidgets('subscribes a topic and closes', (tester) async {
      await ignoringOverflowErrors(() async {
        await GetIt.I.get<ProjectManager>().openProject(createProject());
        await openDialog(tester, AddTopicDialog());

        await tester.enterText(find.byType(TextField).first, 'home/#');
        await tester.tap(find.text('SUBSCRIBE'));
        await tester.pumpAndSettle();

        expect(find.byType(AddTopicDialog), findsNothing);
        expect(GetIt.I.get<ProjectManager>().currentProject!.topicSubscriptions.single.topic, 'home/#');
      });
    });

    testWidgets('shows an error for a duplicate topic', (tester) async {
      await ignoringOverflowErrors(() async {
        var project = createProject();
        await GetIt.I.get<ProjectManager>().openProject(project);
        await openDialog(tester, AddTopicDialog());

        await tester.enterText(find.byType(TextField).first, 'home/#');
        await tester.tap(find.text('SUBSCRIBE & NEW'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'home/#');
        await tester.tap(find.text('SUBSCRIBE & NEW'));
        await tester.pumpAndSettle();

        expect(find.byType(SrxDialog), findsOneWidget);
        expect(project.topicSubscriptions, hasLength(1));
      });
    });
  });
}
