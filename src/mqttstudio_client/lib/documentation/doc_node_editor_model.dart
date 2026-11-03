import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:easy_localization/easy_localization.dart';
import 'package:mqttstudio/documentation/documentation_service.dart';
import 'package:mqttstudio/documentation/engine/discovery_merger.dart';
import 'package:mqttstudio/documentation/engine/schema_paths.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';
import 'package:mqttstudio/documentation/widgets/doc_format.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:reactive_forms/reactive_forms.dart';

// Form controls of the editor of one documented node (doc/documentation-design.md §12.4). Every change is written to
// the node right away, and the name of a changed control goes into the node's editedFields (T5). A namespace that
// only exists implicitly gets its node with the first change.
class DocNodeEditorModel extends ChangeNotifier {
  static const String title = 'title';
  static const String status = 'status';
  static const String replacedBy = 'replacedBy';
  static const String owner = 'owner';
  static const String tags = 'tags';
  static const String description = 'description';
  static const String links = 'links';
  static const String linkLabel = 'label';
  static const String linkUrl = 'url';
  static const String parameters = 'parameters';
  static const String parameterPattern = 'pattern';
  static const String parameterDescription = 'description';
  static const String payloadFormat = 'payloadFormat';
  static const String unit = 'unit';
  static const String min = 'min';
  static const String max = 'max';
  static const String allowedValues = 'allowedValues';
  static const String encoding = 'encoding';
  static const String examples = 'examples';
  static const String examplePayload = 'payload';
  static const String exampleNote = 'note';
  static const String qos = 'qos';
  static const String retain = 'retain';
  static const String intervalKind = 'intervalKind';
  static const String nominalInterval = 'nominalInterval';
  static const String staleAfter = 'staleAfter';
  static const String lastWill = 'lastWill';
  static const String contentType = 'contentType';
  static const String utf8Payload = 'utf8Payload';
  static const String messageExpiry = 'messageExpiry';
  static const String responseTopic = 'responseTopic';
  static const String correlationData = 'correlationData';
  static const String userProperties = 'userProperties';
  static const String userPropertyKey = 'key';
  static const String userPropertyDescription = 'description';
  static const String userPropertyExample = 'example';
  static const String producers = 'producers';
  static const String consumers = 'consumers';
  static const String sensitivity = 'sensitivity';
  static const String accessNotes = 'accessNotes';
  static const String schemaPrefix = 'schema:';

  static const int maxText = 200;
  static const int maxLongText = 20000;

  final _service = GetIt.I.get<DocumentationService>();
  final String path;
  DocNode? _node;
  final bool isTopic;
  late final FormGroup form;
  late final Map<String, (Object? Function(DocNode node), void Function(DocNode node))> _bindings;
  StreamSubscription? _subscription;

  DocNodeEditorModel(this.path, DocNode? node)
      : _node = node,
        isTopic = node?.isTopic ?? false {
    var initial = node ?? DocNode(path: path);
    form = FormGroup({..._generalControls(initial), if (isTopic) ..._topicControls(initial.topic!)},
        validators: [if (isTopic) Validators.delegate(_validateRange)]);
    _bindings = {..._generalBindings(), if (isTopic) ..._topicBindings()};
    _subscription = form.valueChanges.listen((_) => _apply());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  DocNode? get node => _node;

  bool get isMqtt5 => GetIt.I.get<ProjectManager>().currentProject?.mqttSettings.isMqtt5 ?? false;

  bool get isDeprecated => form.control(status).value == DocStatus.deprecated;

  FormArray<Map<String, Object?>> array(String name) => form.control(name) as FormArray<Map<String, Object?>>;

  List<String> get parameterNames => _node?.parameters.map((parameter) => parameter.name).toList() ?? [];

  SchemaNode? get schema => _node?.topic?.payload.schema;

  bool get isJson => form.control(payloadFormat).value == PayloadFormat.json;

  // 'Observed: …' under a field, from the last discovery
  String? observedHint(String key) {
    var observed = _node?.observed;
    if (observed == null || observed.messages == 0) {
      return null;
    }
    var interval = observed.interval;
    var qosValue = observed.mainQos;
    var value = switch (key) {
      payloadFormat => DocFormat.format(observed.mainFormat),
      qos when qosValue != null => 'QoS $qosValue (${observed.qosCounts[qosValue]! * 100 ~/ observed.messages} %)',
      retain => DocFormat.retain(DiscoveryMerger.observedRetain(observed, isMqtt5: isMqtt5)),
      nominalInterval when interval.medianMs != null =>
        '${DocFormat.duration(interval.medianMs)} (${DocFormat.duration(interval.p10Ms)} – ${DocFormat.duration(interval.p90Ms)})',
      min when observed.numericMin != null =>
        '${DocFormat.number(observed.numericMin)} – ${DocFormat.number(observed.numericMax)}',
      _ => null,
    };
    return value == null ? null : 'doceditor.observed.hint'.tr(args: [value]);
  }

  // ---------- controls ----------

  Map<String, AbstractControl<Object?>> _generalControls(DocNode node) => {
        title: FormControl<String>(value: node.title, validators: [Validators.maxLength(maxText)]),
        status: FormControl<DocStatus>(value: node.status),
        replacedBy: FormControl<String>(value: node.replacedBy ?? '', validators: [Validators.maxLength(maxText)]),
        owner: FormControl<String>(value: node.owner, validators: [Validators.maxLength(maxText)]),
        tags: FormControl<List<String>>(value: List.of(node.tags)),
        description: FormControl<String>(value: node.description, validators: [Validators.maxLength(maxLongText)]),
        links: FormArray<Map<String, Object?>>([for (var link in node.links) _linkGroup(link)]),
        parameters: FormArray<Map<String, Object?>>([
          for (var parameter in node.parameters)
            FormGroup({
              parameterPattern: FormControl<String>(
                  value: parameter.pattern ?? '', validators: [Validators.delegate(_validatePattern)]),
              parameterDescription: FormControl<String>(value: parameter.description)
            })
        ])
      };

  Map<String, AbstractControl<Object?>> _topicControls(TopicSpec topic) => {
        payloadFormat: FormControl<PayloadFormat>(value: topic.payload.format),
        unit: FormControl<String>(value: topic.payload.unit ?? '', validators: [Validators.maxLength(maxText)]),
        min: FormControl<double>(value: topic.payload.min),
        max: FormControl<double>(value: topic.payload.max),
        allowedValues: FormControl<List<String>>(value: List.of(topic.payload.allowedValues)),
        encoding: FormControl<String>(value: topic.payload.encoding ?? '', validators: [Validators.maxLength(maxText)]),
        examples: FormArray<Map<String, Object?>>([for (var example in topic.payload.examples) _exampleGroup(example)]),
        qos: FormControl<MqttQos?>(value: topic.qos),
        retain: FormControl<RetainMode>(value: topic.retain),
        intervalKind: FormControl<IntervalKind>(value: topic.interval.kind),
        nominalInterval: FormControl<String>(
            value: DocFormat.duration(topic.interval.nominalMs), validators: [Validators.delegate(_validateDuration)]),
        staleAfter: FormControl<String>(
            value: DocFormat.duration(topic.interval.staleAfterMs),
            validators: [Validators.delegate(_validateDuration)]),
        lastWill: FormControl<bool>(value: topic.lastWill),
        contentType:
            FormControl<String>(value: topic.mqtt5.contentType ?? '', validators: [Validators.maxLength(maxText)]),
        utf8Payload: FormControl<bool>(value: topic.mqtt5.utf8Payload ?? false),
        messageExpiry: FormControl<int>(value: topic.mqtt5.messageExpirySeconds, validators: [Validators.min(0)]),
        responseTopic:
            FormControl<String>(value: topic.mqtt5.responseTopic ?? '', validators: [Validators.maxLength(maxText)]),
        correlationData:
            FormControl<String>(value: topic.mqtt5.correlationData ?? '', validators: [Validators.maxLength(maxText)]),
        userProperties: FormArray<Map<String, Object?>>(
            [for (var property in topic.mqtt5.userProperties) _userPropertyGroup(property)]),
        producers: FormControl<List<String>>(value: List.of(topic.producers)),
        consumers: FormControl<List<String>>(value: List.of(topic.consumers)),
        sensitivity: FormControl<Sensitivity>(value: topic.sensitivity),
        accessNotes: FormControl<String>(value: topic.accessNotes, validators: [Validators.maxLength(maxLongText)])
      };

  FormGroup _linkGroup(DocLink link) => FormGroup({
        linkLabel: FormControl<String>(value: link.label, validators: [Validators.maxLength(maxText)]),
        linkUrl: FormControl<String>(value: link.url, validators: [Validators.maxLength(2000)])
      });

  FormGroup _exampleGroup(DocExample example) => FormGroup({
        examplePayload: FormControl<String>(value: example.payload, validators: [Validators.maxLength(maxLongText)]),
        exampleNote: FormControl<String>(value: example.note, validators: [Validators.maxLength(maxText)])
      });

  FormGroup _userPropertyGroup(DocUserProperty property) => FormGroup({
        userPropertyKey: FormControl<String>(value: property.key, validators: [Validators.maxLength(maxText)]),
        userPropertyDescription:
            FormControl<String>(value: property.description, validators: [Validators.maxLength(maxText)]),
        userPropertyExample: FormControl<String>(value: property.example, validators: [Validators.maxLength(maxText)])
      });

  void addLink() => array(links).add(_linkGroup(DocLink()));

  void addExample() => array(examples).add(_exampleGroup(DocExample()));

  void addUserProperty() => array(userProperties).add(_userPropertyGroup(DocUserProperty()));

  void removeAt(String arrayName, int index) => array(arrayName).removeAt(index);

  // ---------- validation ----------

  static Map<String, dynamic>? _validatePattern(AbstractControl<dynamic> control) {
    var value = control.value as String?;
    if (value == null || value.isEmpty) {
      return null;
    }
    try {
      RegExp(value);
      return null;
    } on FormatException {
      return {'pattern': true};
    }
  }

  static Map<String, dynamic>? _validateDuration(AbstractControl<dynamic> control) {
    var value = (control.value as String?)?.trim() ?? '';
    return value.isEmpty || DocFormat.parseDuration(value) != null ? null : {'duration': true};
  }

  static Map<String, dynamic>? _validateRange(AbstractControl<dynamic> group) {
    var low = (group as FormGroup).control(min).value as double?;
    var high = group.control(max).value as double?;
    if (low != null && high != null && low > high) {
      group.control(max).setErrors({'range': true});
    } else {
      group.control(max).removeError('range');
    }
    return null;
  }

  // ---------- writing to the node ----------

  String _text(String name) => ((form.control(name).value as String?) ?? '').trim();

  String? _optionalText(String name) => _text(name).isEmpty ? null : _text(name);

  List<Map<String, Object?>> _rows(String name) => array(name).value?.whereType<Map<String, Object?>>().toList() ?? [];

  String _rowText(Map<String, Object?> row, String name) => ((row[name] as String?) ?? '').trim();

  Map<String, (Object? Function(DocNode node), void Function(DocNode node))> _generalBindings() => {
        title: ((node) => node.title, (node) => node.title = _text(title)),
        status: ((node) => node.status.name, (node) => node.status = form.control(status).value as DocStatus),
        replacedBy: ((node) => node.replacedBy, (node) => node.replacedBy = _optionalText(replacedBy)),
        owner: ((node) => node.owner, (node) => node.owner = _text(owner)),
        tags: ((node) => node.tags, (node) => node.tags = List.of(form.control(tags).value as List<String>)),
        description: ((node) => node.description, (node) => node.description = _text(description)),
        links: (
          (node) => node.links.map((link) => link.toJson()).toList(),
          (node) => node.links = [
                for (var row in _rows(links)) DocLink(label: _rowText(row, linkLabel), url: _rowText(row, linkUrl))
              ]
        ),
        parameters: (
          (node) => node.parameters.map((parameter) => [parameter.pattern, parameter.description]).toList(),
          (node) {
            var rows = _rows(parameters);
            for (var i = 0; i < node.parameters.length && i < rows.length; i++) {
              var pattern = _rowText(rows[i], parameterPattern);
              node.parameters[i]
                ..pattern = pattern.isEmpty ? null : pattern
                ..description = _rowText(rows[i], parameterDescription);
            }
          }
        )
      };

  Map<String, (Object? Function(DocNode node), void Function(DocNode node))> _topicBindings() => {
        payloadFormat: (
          (node) => node.topic!.payload.format.name,
          (node) => node.topic!.payload.format = form.control(payloadFormat).value as PayloadFormat
        ),
        unit: ((node) => node.topic!.payload.unit, (node) => node.topic!.payload.unit = _optionalText(unit)),
        min: (
          (node) => node.topic!.payload.min,
          (node) => node.topic!.payload.min = form.control(min).value as double?
        ),
        max: (
          (node) => node.topic!.payload.max,
          (node) => node.topic!.payload.max = form.control(max).value as double?
        ),
        allowedValues: (
          (node) => node.topic!.payload.allowedValues,
          (node) => node.topic!.payload.allowedValues = List.of(form.control(allowedValues).value as List<String>)
        ),
        encoding: (
          (node) => node.topic!.payload.encoding,
          (node) => node.topic!.payload.encoding = _optionalText(encoding)
        ),
        examples: (
          (node) => node.topic!.payload.examples.map((example) => [example.payload, example.note]).toList(),
          (node) {
            var old = node.topic!.payload.examples;
            var rows = _rows(examples);
            node.topic!.payload.examples = [
              for (var i = 0; i < rows.length; i++)
                DocExample(
                    payload: (rows[i][examplePayload] as String?) ?? '',
                    note: _rowText(rows[i], exampleNote),
                    topic: i < old.length ? old[i].topic : null,
                    capturedAt: i < old.length ? old[i].capturedAt : null)
            ];
          }
        ),
        qos: ((node) => node.topic!.qos?.name, (node) => node.topic!.qos = form.control(qos).value as MqttQos?),
        retain: (
          (node) => node.topic!.retain.name,
          (node) => node.topic!.retain = form.control(retain).value as RetainMode
        ),
        intervalKind: (
          (node) => node.topic!.interval.kind.name,
          (node) => node.topic!.interval.kind = form.control(intervalKind).value as IntervalKind
        ),
        nominalInterval: (
          (node) => node.topic!.interval.nominalMs,
          (node) => _writeDuration(nominalInterval, (ms) => node.topic!.interval.nominalMs = ms)
        ),
        staleAfter: (
          (node) => node.topic!.interval.staleAfterMs,
          (node) => _writeDuration(staleAfter, (ms) => node.topic!.interval.staleAfterMs = ms)
        ),
        lastWill: (
          (node) => node.topic!.lastWill,
          (node) => node.topic!.lastWill = form.control(lastWill).value == true
        ),
        contentType: (
          (node) => node.topic!.mqtt5.contentType,
          (node) => node.topic!.mqtt5.contentType = _optionalText(contentType)
        ),
        utf8Payload: (
          (node) => node.topic!.mqtt5.utf8Payload,
          (node) => node.topic!.mqtt5.utf8Payload = form.control(utf8Payload).value == true ? true : null
        ),
        messageExpiry: (
          (node) => node.topic!.mqtt5.messageExpirySeconds,
          (node) {
            if (form.control(messageExpiry).valid) {
              node.topic!.mqtt5.messageExpirySeconds = form.control(messageExpiry).value as int?;
            }
          }
        ),
        responseTopic: (
          (node) => node.topic!.mqtt5.responseTopic,
          (node) => node.topic!.mqtt5.responseTopic = _optionalText(responseTopic)
        ),
        correlationData: (
          (node) => node.topic!.mqtt5.correlationData,
          (node) => node.topic!.mqtt5.correlationData = _optionalText(correlationData)
        ),
        userProperties: (
          (node) => node.topic!.mqtt5.userProperties.map((property) => property.toJson()).toList(),
          (node) => node.topic!.mqtt5.userProperties = [
                for (var row in _rows(userProperties))
                  DocUserProperty(
                      key: _rowText(row, userPropertyKey),
                      description: _rowText(row, userPropertyDescription),
                      example: _rowText(row, userPropertyExample))
              ]
        ),
        producers: (
          (node) => node.topic!.producers,
          (node) => node.topic!.producers = List.of(form.control(producers).value as List<String>)
        ),
        consumers: (
          (node) => node.topic!.consumers,
          (node) => node.topic!.consumers = List.of(form.control(consumers).value as List<String>)
        ),
        sensitivity: (
          (node) => node.topic!.sensitivity.name,
          (node) => node.topic!.sensitivity = form.control(sensitivity).value as Sensitivity
        ),
        accessNotes: ((node) => node.topic!.accessNotes, (node) => node.topic!.accessNotes = _text(accessNotes))
      };

  // an invalid duration keeps the documented one until it is corrected
  void _writeDuration(String name, void Function(int? ms) write) {
    if (form.control(name).valid) {
      write(DocFormat.parseDuration(_text(name)));
    }
  }

  void _apply() {
    var node = _node;
    if (node == null) {
      if (!_bindings.entries.any((binding) => _differs(DocNode(path: path), binding.value))) {
        return;
      }
      node = _node = _service.ensureNode(path);
    }
    var changed = false;
    for (var binding in _bindings.entries) {
      if (_differs(node, binding.value)) {
        binding.value.$2(node);
        node.editedFields.add(binding.key);
        changed = true;
      }
    }
    if (changed) {
      _service.notifyChanged();
    }
  }

  bool _differs(DocNode node, (Object? Function(DocNode), void Function(DocNode)) binding) {
    var before = jsonEncode(binding.$1(node));
    var probe = node.copy();
    binding.$2(probe);
    return jsonEncode(binding.$1(probe)) != before;
  }

  // ---------- payload schema ----------

  void putSchemaField(String? oldPath, String path, SchemaNode field, {required bool required}) {
    var payload = _node!.topic!.payload;
    var schema = payload.schema ??= SchemaNode();
    if (oldPath != null && oldPath != path) {
      var old = SchemaPaths.find(schema, oldPath);
      SchemaPaths.remove(schema, oldPath);
      field.properties = old?.properties ?? {};
      field.required = old?.required ?? {};
      field.items = old?.items;
      _node!.editedFields.add('$schemaPrefix$oldPath');
    }
    SchemaPaths.put(schema, path, field, required: required);
    _node!.editedFields.add('$schemaPrefix$path');
    _schemaChanged();
  }

  // the schema edited as JSON Schema replaces the whole schema
  void replaceSchema(SchemaNode schema) {
    _node!.topic!.payload.schema = schema;
    _node!.editedFields.add('$schemaPrefix${SchemaPaths.root}');
    _schemaChanged();
  }

  void removeSchemaField(String path) {
    var schema = _node?.topic?.payload.schema;
    if (schema == null) {
      return;
    }
    SchemaPaths.remove(schema, path);
    _node!.editedFields.add('$schemaPrefix$path');
    _schemaChanged();
  }

  void _schemaChanged() {
    _service.notifyChanged();
    notifyListeners();
  }
}
