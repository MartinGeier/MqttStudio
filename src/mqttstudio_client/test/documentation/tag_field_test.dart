import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/documentation/widgets/tag_field.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';
import '../helpers/test_app.dart';

void main() {
  setUpAll(loadTranslations);

  setUp(() => GetIt.I.registerSingleton(SrxNavigationService(Container(), Container())));

  tearDown(() => GetIt.I.reset());

  testWidgets('a click anywhere in the field focuses it, Enter adds a tag', (tester) async {
    var form = FormGroup({'tags': FormControl<List<String>>(value: [])});
    await tester.pumpWidget(testApp(SizedBox(
        width: 600,
        child:
            ReactiveForm(formGroup: form, child: ReactiveTagField(formControlName: 'tags', labelText: 'Consumers')))));
    await tester.pumpAndSettle();
    var field = tester.getRect(find.byType(ReactiveTagField));
    await tester.tapAt(field.centerRight - Offset(20, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus, isTrue);
    await tester.enterText(find.byType(TextField), 'mes');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(form.control('tags').value, ['mes']);
  });
}
