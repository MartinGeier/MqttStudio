import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/documentation/documentation_service.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:reactive_forms/reactive_forms.dart';

// Form controls of the documentation's own title, owner and description, shown when the root of the tree is selected
class DocRootEditorModel {
  static const String title = 'title';
  static const String owner = 'owner';
  static const String description = 'description';

  final _service = GetIt.I.get<DocumentationService>();
  final TopicDocumentation documentation;
  late final FormGroup form;
  StreamSubscription? _subscription;

  DocRootEditorModel(this.documentation) {
    form = FormGroup({
      title: FormControl<String>(value: documentation.title, validators: [Validators.maxLength(200)]),
      owner: FormControl<String>(value: documentation.owner, validators: [Validators.maxLength(200)]),
      description: FormControl<String>(value: documentation.description, validators: [Validators.maxLength(20000)])
    });
    _subscription = form.valueChanges.listen((_) => _apply());
  }

  void dispose() => _subscription?.cancel();

  String _text(String name) => ((form.control(name).value as String?) ?? '').trim();

  void _apply() {
    if (documentation.title == _text(title) &&
        documentation.owner == _text(owner) &&
        documentation.description == _text(description)) {
      return;
    }
    documentation
      ..title = _text(title)
      ..owner = _text(owner)
      ..description = _text(description);
    _service.notifyChanged();
  }
}
