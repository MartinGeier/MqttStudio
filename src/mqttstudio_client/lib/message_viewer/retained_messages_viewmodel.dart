import 'package:get_it/get_it.dart';
import 'package:mqttstudio/message_viewer/retained_scanner.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/recorder/engine/recorder_rules.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

enum RetainedScanState { idle, connecting, scanning, done, failed }

// Lists the retained messages below a topic filter and clears the selected ones
class RetainedMessagesViewmodel extends SrxChangeNotifier {
  static const String filterField = 'filter';

  late final FormGroup form;
  final RetainedScanner _scanner;
  RetainedScanState _state = RetainedScanState.idle;
  List<ReceivedMqttMessage> _messages = [];
  final Set<String> _selected = {};
  int _found = 0;
  int _cleared = 0;
  String? _error;
  String _scannedFilter = '';

  RetainedMessagesViewmodel({String filter = '#', MqttAdapter Function()? connectionFactory})
      : _scanner = RetainedScanner(connectionFactory: connectionFactory) {
    form = FormGroup({
      filterField: FormControl<String>(value: filter, validators: [Validators.required, Validators.delegate(_validateFilter)]),
    });
  }

  @override
  void dispose() {
    _scanner.close();
    super.dispose();
  }

  RetainedScanState get state => _state;

  bool get isBusy => _state == RetainedScanState.connecting || _state == RetainedScanState.scanning;

  List<ReceivedMqttMessage> get messages => _messages;

  // the messages found so far while scanning
  int get found => _found;

  // the messages cleared since the last scan
  int get cleared => _cleared;

  String? get error => _error;

  String get scannedFilter => _scannedFilter;

  bool isSelected(String topic) => _selected.contains(topic);

  int get selectedCount => _selected.length;

  bool get allSelected => _messages.isNotEmpty && _selected.length == _messages.length;

  void toggle(String topic) {
    if (!_selected.remove(topic)) {
      _selected.add(topic);
    }
    notifyListeners();
  }

  void selectAll(bool selected) {
    _selected.clear();
    if (selected) {
      _selected.addAll(_messages.map((message) => message.topicName));
    }
    notifyListeners();
  }

  Future<void> scan() async {
    form.markAllAsTouched();
    if (!form.valid || isBusy) {
      return;
    }
    var filter = (form.control(filterField).value as String).trim();
    _error = null;
    _cleared = 0;
    _found = 0;
    if (!_scanner.isOpen) {
      _setState(RetainedScanState.connecting);
      try {
        await _scanner.open(GetIt.I.get<ProjectManager>().currentProject!.mqttSettings);
      } catch (exc) {
        _error = exc.toString();
        _setState(RetainedScanState.failed);
        return;
      }
    }
    _setState(RetainedScanState.scanning);
    _messages = await _scanner.scan(filter, onFound: (count) {
      _found = count;
      notifyListeners();
    });
    _scannedFilter = filter;
    _selected
      ..clear()
      ..addAll(_messages.map((message) => message.topicName));
    _setState(RetainedScanState.done);
  }

  // publishes empty retained messages on the selected topics and removes them from the list
  void clearSelected() {
    var topics = _selected.toList();
    if (topics.isEmpty) {
      return;
    }
    _scanner.clear(topics);
    _messages = _messages.where((message) => !_selected.contains(message.topicName)).toList();
    _cleared += topics.length;
    _selected.clear();
    notifyListeners();
  }

  void _setState(RetainedScanState state) {
    _state = state;
    notifyListeners();
  }

  static Map<String, dynamic>? _validateFilter(AbstractControl<dynamic> control) {
    var value = control.value as String?;
    if (value == null || value.isEmpty) {
      return null;
    }
    var issue = RecorderRules.validateFilter(value.trim());
    return issue == null ? null : {'filter.${issue.name}': true};
  }
}
