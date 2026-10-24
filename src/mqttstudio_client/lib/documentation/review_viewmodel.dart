import 'dart:async';
import 'package:mqttstudio/documentation/engine/discovery_merger.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

enum ReviewTab { templates, added, changed, notSeen }

// Viewmodel of the review dialog after a discovery (doc/documentation-design.md §5.6, §12.5). The choices are kept in
// the result's items; APPLY hands the result to the discovery service.
class ReviewViewmodel extends SrxChangeNotifier {
  static final RegExp _parameterName = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$');

  final DiscoveryResult result;
  ReviewTab _tab;
  Object? _selected;
  FormGroup? namesForm;
  StreamSubscription? _namesSubscription;

  ReviewViewmodel(this.result) : _tab = _firstTab(result) {
    _selected = items.firstOrNull;
    _buildNamesForm();
  }

  static ReviewTab _firstTab(DiscoveryResult result) {
    if (result.templates.isNotEmpty) {
      return ReviewTab.templates;
    }
    if (result.added.isNotEmpty) {
      return ReviewTab.added;
    }
    return result.changed.isNotEmpty ? ReviewTab.changed : ReviewTab.notSeen;
  }

  @override
  void dispose() {
    _namesSubscription?.cancel();
    super.dispose();
  }

  ReviewTab get tab => _tab;

  Object? get selected => _selected;

  int countOf(ReviewTab tab) => switch (tab) {
        ReviewTab.templates => result.templates.length,
        ReviewTab.added => result.added.length,
        ReviewTab.changed => result.changed.length,
        ReviewTab.notSeen => result.notSeen.length,
      };

  // NewItem, ChangedItem or DocNode
  List<Object> get items => switch (_tab) {
        ReviewTab.templates => result.templates,
        ReviewTab.added => result.added,
        ReviewTab.changed => result.changed,
        ReviewTab.notSeen => result.notSeen,
      };

  bool get hasChoices => result.added.isNotEmpty || result.changed.isNotEmpty || result.notSeen.isNotEmpty;

  void selectTab(ReviewTab tab) {
    _tab = tab;
    _selected = items.firstOrNull;
    _buildNamesForm();
    notifyListeners();
  }

  void select(Object item) {
    _selected = item;
    _buildNamesForm();
    notifyListeners();
  }

  // ---------- choices ----------

  void setAccept(NewItem item, bool accept) {
    item.accept = accept;
    if (accept) {
      item.ignore = false;
    }
    notifyListeners();
  }

  void setAsTemplate(NewItem item, bool asTemplate) {
    item.asTemplate = asTemplate;
    notifyListeners();
  }

  void setIgnore(NewItem item, bool ignore) {
    item.ignore = ignore;
    notifyListeners();
  }

  void setAdopt(DocDifference difference, bool adopt) {
    difference.adopt = adopt;
    notifyListeners();
  }

  void acceptAll(bool accept) {
    for (var item in result.added) {
      item.accept = accept;
    }
    notifyListeners();
  }

  // ---------- parameter names of the selected template ----------

  void _buildNamesForm() {
    _namesSubscription?.cancel();
    namesForm = null;
    var item = _selected;
    if (item is! NewItem || !item.isTemplate) {
      return;
    }
    namesForm = FormGroup({
      for (var name in item.parameterNames)
        name: FormControl<String>(value: item.names[name] ?? name, validators: [
          Validators.required,
          Validators.pattern(_parameterName),
          Validators.delegate((control) => _validateUnique(item, name, control)),
        ]),
    });
    _namesSubscription = namesForm!.valueChanges.listen((_) => _applyNames(item));
  }

  Map<String, dynamic>? _validateUnique(NewItem item, String name, AbstractControl<dynamic> control) {
    var form = namesForm;
    if (form == null) {
      return null;
    }
    var value = (control.value as String?)?.trim();
    var duplicate = item.parameterNames.any((other) => other != name && form.control(other).value == value);
    return duplicate ? {'unique': true} : null;
  }

  void _applyNames(NewItem item) {
    var form = namesForm!;
    for (var name in item.parameterNames) {
      form.control(name).updateValueAndValidity(emitEvent: false);
    }
    if (!form.valid) {
      return;
    }
    item.names.clear();
    for (var name in item.parameterNames) {
      var value = (form.control(name).value as String).trim();
      if (value != name) {
        item.names[name] = value;
      }
    }
    notifyListeners();
  }

  bool get canApply => namesForm?.valid ?? true;

  // the documented topics a change or a not seen mark is about
  DocNode? nodeOf(Object item) => switch (item) {
        ChangedItem changed => changed.node,
        DocNode node => node,
        _ => null,
      };
}
