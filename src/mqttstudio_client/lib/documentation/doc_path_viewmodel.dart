import 'package:get_it/get_it.dart';
import 'package:mqttstudio/documentation/documentation_service.dart';
import 'package:mqttstudio/documentation/engine/doc_path.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

enum DocPathDialogMode { addTopic, addNamespace, move }

// Viewmodel of the dialog that adds a topic or a namespace, or moves a node with everything below it
class DocPathViewmodel extends SrxChangeNotifier {
  static const String pathField = 'path';
  static const String titleField = 'title';
  static const String copyFromField = 'copyFrom';

  final _service = GetIt.I.get<DocumentationService>();
  final DocPathDialogMode mode;
  // move: the path that moves; add: the namespace the new node goes into
  final String? basePath;
  late final FormGroup form;

  DocPathViewmodel(this.mode, {this.basePath}) {
    form = FormGroup({
      pathField: FormControl<String>(
          value: _initialPath, validators: [Validators.required, Validators.delegate(_validatePath)]),
      titleField: FormControl<String>(value: '', validators: [Validators.maxLength(200)]),
      copyFromField: FormControl<String>()
    });
  }

  String get _initialPath => switch (mode) {
        DocPathDialogMode.move => basePath!,
        _ => basePath == null || basePath!.isEmpty ? '' : '$basePath/'
      };

  bool get isMove => mode == DocPathDialogMode.move;

  // the nodes that move with the path
  int get movedCount => isMove ? _service.nodesAtOrBelow(basePath!).length : 0;

  List<String> get copySources => _service.nodes.where((node) => node.isTopic).map((node) => node.path).toList();

  String get path => ((form.control(pathField).value as String?) ?? '').trim();

  Map<String, dynamic>? _validatePath(AbstractControl<dynamic> control) {
    var path = ((control.value as String?) ?? '').trim();
    if (path.isEmpty) {
      return null;
    }
    var error = DocPath.validate(path);
    if (error != null) {
      return {'path': error};
    }
    if (isMove) {
      if (path == basePath) {
        return null;
      }
      var moved = _service.nodesAtOrBelow(basePath!).map((node) => node.path).toSet();
      for (var old in moved) {
        var target = path + old.substring(basePath!.length);
        if (DocPath.validate(target) != null || _service.conflictOf(target, ignore: moved) != null) {
          return {'taken': true};
        }
      }
      return null;
    }
    return switch (_service.conflictOf(path)) {
      DocPathConflict.exists => {'taken': true},
      DocPathConflict.sameShape => {'sameShape': true},
      null => null
    };
  }

  // the new node, or null while the form is invalid
  DocNode? createNode() {
    if (!form.valid) {
      form.markAllAsTouched();
      return null;
    }
    var title = ((form.control(titleField).value as String?) ?? '').trim();
    var source = form.control(copyFromField).value as String?;
    var copied = source == null ? null : _service.nodeAt(source);
    if (copied != null) {
      return copied.copy()
        ..path = path
        ..title = title.isEmpty ? copied.title : title
        ..editedFields = {};
    }
    return DocNode(path: path, title: title, topic: mode == DocPathDialogMode.addTopic ? TopicSpec() : null);
  }

  // after ADD & NEW: the next path starts in the same namespace
  void reset() {
    var parent = DocPath.parentOf(path);
    form.control(pathField).value = parent.isEmpty ? '' : '$parent/';
    form.control(titleField).value = '';
    form.control(pathField).markAsUntouched();
    notifyListeners();
  }
}
