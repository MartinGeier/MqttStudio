import 'package:easy_localization/easy_localization.dart';
import 'package:mqtt5_client/mqtt5_client.dart' show MqttQos;
import 'package:mqttstudio/documentation/engine/conformance_checker.dart';
import 'package:mqttstudio/documentation/engine/discovery_merger.dart';
import 'package:mqttstudio/documentation/engine/doc_path.dart';
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/model/topic_spec.dart';

// Texts of the documentation tab
class DocFormat {
  static final RegExp _duration = RegExp(r'^(\d+(?:[.,]\d+)?)\s*(ms|s|min|h)?$');

  // '500 ms', '10 s', '1.5 min', '2 h'; a number alone is seconds. null for an empty or invalid text.
  static int? parseDuration(String? text) {
    var match = _duration.firstMatch(text?.trim() ?? '');
    if (match == null) {
      return null;
    }
    var value = double.parse(match.group(1)!.replaceAll(',', '.'));
    var factor = switch (match.group(2)) { 'ms' => 1, 'min' => 60000, 'h' => 3600000, _ => 1000 };
    return (value * factor).round();
  }

  static String duration(int? ms) {
    if (ms == null) {
      return '';
    }
    String number(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1);
    if (ms < 1000) {
      return '$ms ms';
    }
    if (ms < 60000) {
      return '${number(ms / 1000)} s';
    }
    if (ms < 3600000) {
      return '${number(ms / 60000)} min';
    }
    return '${number(ms / 3600000)} h';
  }

  static String status(DocStatus status) => 'documentation.status.${status.name}'.tr();

  static String format(PayloadFormat format) => 'documentation.format.${format.name}'.tr();

  static String retain(RetainMode retain) => 'documentation.retain.${retain.name}'.tr();

  static String interval(IntervalKind kind) => 'documentation.interval.${kind.name}'.tr();

  static String sensitivity(Sensitivity sensitivity) => 'documentation.sensitivity.${sensitivity.name}'.tr();

  static String schemaType(SchemaType type) => type == SchemaType.nullValue ? 'null' : type.name;

  static String qos(MqttQos? qos) => qos == null ? 'documentation.notdocumented'.tr() : qos.toString().tr();

  static String pathError(DocPathError error) => 'documentation.patherror.${error.name}'.tr();

  static String number(double? value) {
    if (value == null) {
      return '';
    }
    return value == value.roundToDouble() && value.abs() < 1e15 ? value.toInt().toString() : value.toString();
  }

  // '0 – 120', 'running, idle' or '' for the schema table
  static String range(double? min, double? max, List<String> values) {
    if (values.isNotEmpty) {
      return values.join(', ');
    }
    if (min == null && max == null) {
      return '';
    }
    return '${number(min)} – ${number(max)}';
  }

  static final NumberFormat _count = NumberFormat('#,##0');

  static String count(int value) => _count.format(value);

  static String findingRule(Finding finding) => finding.protocolRule != null
      ? 'docfindings.rule.${finding.protocolRule}'.tr()
      : 'docfindings.rule.${finding.rule.name}'.tr();

  static String difference(DifferenceKind kind, String? subject) =>
      'docreview.difference.${kind.name}'.tr(args: [subject ?? '']);

  static String differenceValue(DifferenceKind kind, String value) {
    if (value.isEmpty) {
      return '–';
    }
    return switch (kind) {
      DifferenceKind.format => format(PayloadFormat.values.byName(value)),
      DifferenceKind.retain => retain(RetainMode.values.byName(value)),
      DifferenceKind.qos => 'QoS $value',
      DifferenceKind.interval => duration(int.tryParse(value)),
      _ => value,
    };
  }

  // 'Number · periodic 10 s'
  static String observedSummary(ObservedTopic observed) {
    var interval = observed.interval;
    var median =
        interval.medianMs == null || interval.kind == IntervalKind.unknown ? '' : ' ${duration(interval.medianMs)}';
    return '${format(observed.mainFormat)} · ${DocFormat.interval(interval.kind)}$median';
  }

  static String observedRetain(ObservedTopic observed) =>
      'docobserved.retained.value'.tr(args: [count(observed.retainedSnapshot), count(observed.retainedLive)]);
}
