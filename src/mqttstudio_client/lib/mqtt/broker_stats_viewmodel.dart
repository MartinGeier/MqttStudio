import 'dart:async';
import 'package:event/event.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/mqtt/mqtt_adapter.dart';
import 'package:mqttstudio/mqtt/sys_monitor.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:srx_flutter/srx_flutter.dart';

enum BrokerStatsState { connecting, waiting, receiving, noData, failed }

class BrokerStatsViewmodel extends SrxChangeNotifier {
  // a little more than Mosquitto's default interval of 10 s
  static const Duration noDataAfter = Duration(seconds: 12);
  static const Duration _refreshPeriod = Duration(milliseconds: 300);

  final SysMonitor _monitor;
  BrokerStatsState _state = BrokerStatsState.connecting;
  String? _error;
  String _topicFilter = '';
  Timer? _noDataTimer;
  Timer? _refreshTimer;

  BrokerStatsViewmodel({MqttAdapter Function()? connectionFactory})
      : _monitor = SysMonitor(connectionFactory: connectionFactory) {
    _monitor.changedEvent.subscribe(_onChanged);
  }

  @override
  void dispose() {
    _noDataTimer?.cancel();
    _refreshTimer?.cancel();
    _monitor.changedEvent.unsubscribe(_onChanged);
    _monitor.close();
    super.dispose();
  }

  BrokerStatsState get state => _state;

  String? get error => _error;

  String get topicFilter => _topicFilter;

  set topicFilter(String value) {
    _topicFilter = value;
    notifyListeners();
  }

  // the statistics of the summary that the broker published, as label key and value
  List<(SysSummaryItem, String)> get summary => [
        for (var item in SysMonitor.summaryItems)
          if (_monitor.valueOf(item) case var value?) (item, value)
      ];

  int get topicCount => _monitor.values.length;

  List<MapEntry<String, SysValue>> get topics {
    var filter = _topicFilter.trim().toLowerCase();
    return _monitor.values.entries.where((entry) => filter.isEmpty || entry.key.toLowerCase().contains(filter)).toList();
  }

  Future<void> start() async {
    try {
      await _monitor.open(GetIt.I.get<ProjectManager>().currentProject!.mqttSettings);
    } catch (exc) {
      _error = exc.toString();
      _setState(BrokerStatsState.failed);
      return;
    }
    if (_state == BrokerStatsState.connecting) {
      _setState(BrokerStatsState.waiting);
    }
    _noDataTimer = Timer(noDataAfter, () {
      if (_monitor.values.isEmpty) {
        _setState(BrokerStatsState.noData);
      }
    });
  }

  // the broker sends its $SYS topics in bursts, so the view is updated at most every _refreshPeriod
  void _onChanged(EventArgs? _) {
    if (_state != BrokerStatsState.receiving) {
      _setState(BrokerStatsState.receiving);
      return;
    }
    _refreshTimer ??= Timer(_refreshPeriod, () {
      _refreshTimer = null;
      notifyListeners();
    });
  }

  void _setState(BrokerStatsState state) {
    _state = state;
    notifyListeners();
  }
}
