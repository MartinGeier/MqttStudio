import 'package:community_charts_flutter/community_charts_flutter.dart' as chart;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:mqttstudio/common/utils/json_path.dart';
import 'package:mqttstudio/recorder/analysis/recording_values.dart';
import 'package:mqttstudio/recorder/model/recording_summary.dart';
import 'package:mqttstudio/recorder/recording_charts_viewmodel.dart';
import 'package:mqttstudio/recorder/widgets/recorder_format.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:url_launcher/url_launcher.dart';

// The CHARTS tab (doc/recorder-design.md §7.4): a value of a topic over the selected range with min, max and average,
// the topic's interval histogram, and positions as a track on the map
class RecordingChartsView extends StatelessWidget {
  static const double histogramWidth = 360;

  const RecordingChartsView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var vm = context.watch<RecordingChartsViewmodel>();
    if (vm.info == null || vm.topic == null) {
      return Container();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _buildToolbar(context, vm),
      Divider(height: 1),
      if (vm.isLoading) LinearProgressIndicator(),
      Expanded(child: vm.mode == ChartMode.numbers ? _buildNumbers(context, vm) : _buildPositions(context, vm)),
    ]);
  }

  Widget _buildToolbar(BuildContext context, RecordingChartsViewmodel vm) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        Tooltip(
          message: 'recordingcharts.topic.tooltip'.tr(),
          child: DropdownButton<String>(
            value: vm.topic,
            onChanged: (topic) => vm.setTopic(topic!),
            items: [for (var topic in vm.topics) DropdownMenuItem(value: topic, child: Text(topic))],
          ),
        ),
        SizedBox(width: 16),
        ToggleButtons(
          renderBorder: false,
          isSelected: [vm.mode == ChartMode.numbers, vm.mode == ChartMode.positions],
          onPressed: (index) => vm.setMode(ChartMode.values[index]),
          children: [
            Tooltip(message: 'recordingcharts.numbers.tooltip'.tr(), child: Icon(Icons.show_chart)),
            Tooltip(message: 'recordingcharts.positions.tooltip'.tr(), child: Icon(Icons.map)),
          ],
        ),
        SizedBox(height: 40, child: VerticalDivider()),
        SizedBox(width: 8),
        if (vm.mode == ChartMode.numbers) ..._buildValueChoice(context, vm),
        if (vm.mode == ChartMode.positions && !vm.topicHasCoordinates) ..._buildPositionChoice(context, vm),
      ]),
    );
  }

  List<Widget> _buildValueChoice(BuildContext context, RecordingChartsViewmodel vm) {
    return [
      Tooltip(
        message: 'recordingcharts.value.tooltip'.tr(),
        child: DropdownButton<ValueSelector>(
          value: vm.selector,
          onChanged: (selector) => vm.setSelector(selector!),
          items: [
            for (var selector in vm.selectors)
              DropdownMenuItem(
                  value: selector,
                  child: Text(selector.path == null ? 'recordingcharts.payload.label'.tr() : selector.path.toString())),
          ],
        ),
      ),
      SizedBox(width: 16),
      SizedBox(
        width: 240,
        child: ReactiveForm(
          formGroup: vm.form,
          child: ReactiveTextField<String>(
            formControlName: RecordingChartsViewmodel.pathField,
            decoration: InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                labelText: 'recordingcharts.path.label'.tr(),
                hintText: r'$.sensor.value'),
            validationMessages: {'jsonpath': (_) => 'recordingcharts.path.error'.tr()},
            onSubmitted: (_) => vm.applyPath(),
          ),
        ),
      ),
      IconButton(onPressed: vm.applyPath, icon: Icon(Icons.check), tooltip: 'recordingcharts.path.tooltip'.tr()),
    ];
  }

  List<Widget> _buildPositionChoice(BuildContext context, RecordingChartsViewmodel vm) {
    Widget choice(String label, JsonPath? value, void Function(JsonPath?) onChanged) => Row(children: [
          Text(label),
          SizedBox(width: 8),
          DropdownButton<JsonPath?>(
            value: value,
            onChanged: onChanged,
            items: [
              DropdownMenuItem(value: null, child: Text('–')),
              for (var path in vm.jsonPaths) DropdownMenuItem(value: path, child: Text(path.toString())),
            ],
          ),
        ]);
    return [
      choice('recordingcharts.latitude.label'.tr(), vm.latitude, vm.setLatitude),
      SizedBox(width: 16),
      choice('recordingcharts.longitude.label'.tr(), vm.longitude, vm.setLongitude),
    ];
  }

  Widget _buildNumbers(BuildContext context, RecordingChartsViewmodel vm) {
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _buildStats(context, vm),
            SizedBox(height: 8),
            Expanded(child: _buildValueChart(context, vm)),
          ]),
        ),
      ),
      Container(
        width: histogramWidth,
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border(left: BorderSide(color: Theme.of(context).dividerColor))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('recordingcharts.intervals.title'.tr(), style: Theme.of(context).textTheme.titleSmall),
          SizedBox(height: 8),
          Expanded(child: _buildHistogram(context, vm)),
        ]),
      ),
    ]);
  }

  Widget _buildStats(BuildContext context, RecordingChartsViewmodel vm) {
    var series = vm.series;
    var theme = Theme.of(context);
    var bold = theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w500);
    if (series == null) {
      return SizedBox(height: 20);
    }
    String number(double? value) => value == null ? '–' : NumberFormat('#,##0.###', 'en').format(value);
    Widget fact(String label, String value) =>
        Text.rich(TextSpan(children: [TextSpan(text: '$label ', style: bold), TextSpan(text: value)]));
    return Wrap(spacing: 24, runSpacing: 4, children: [
      fact('recordingcharts.count.label'.tr(), RecorderFormat.count(series.count)),
      fact('recordingcharts.min.label'.tr(), number(series.min)),
      fact('recordingcharts.max.label'.tr(), number(series.max)),
      fact('recordingcharts.avg.label'.tr(), number(series.average)),
      if (series.skipped > 0)
        Text('recordingcharts.skipped.label'.tr(args: [RecorderFormat.count(series.skipped)]),
            style: TextStyle(color: theme.hintColor)),
    ]);
  }

  Widget _buildValueChart(BuildContext context, RecordingChartsViewmodel vm) {
    var series = vm.series;
    if (series == null || series.points.isEmpty) {
      return _hint(context, vm.isLoading ? '' : 'recordingcharts.novalues.label'.tr());
    }
    var color = vm.colorOf(vm.topic!).color;
    var lineColor = chart.Color(r: (color.r * 255).round(), g: (color.g * 255).round(), b: (color.b * 255).round());
    var hint = Theme.of(context).hintColor;
    var annotationColor = chart.Color(r: (hint.r * 255).round(), g: (hint.g * 255).round(), b: (hint.b * 255).round());
    chart.LineAnnotationSegment<Object> line(double? value, String label) => chart.LineAnnotationSegment(
        value ?? 0, chart.RangeAnnotationAxisType.measure,
        endLabel: label, color: annotationColor, dashPattern: [4, 4]);
    return chart.TimeSeriesChart(
      [
        chart.Series<ValuePoint, DateTime>(
          id: 'values',
          data: series.points,
          domainFn: (point, _) => vm.timeAt(point.offsetMicros),
          measureFn: (point, _) => point.value,
          colorFn: (_, __) => lineColor,
          strokeWidthPxFn: (_, __) => 2,
        ),
      ],
      animate: false,
      primaryMeasureAxis: const chart.NumericAxisSpec(tickProviderSpec: chart.BasicNumericTickProviderSpec(zeroBound: false)),
      domainAxis: chart.DateTimeAxisSpec(
        tickFormatterSpec: chart.AutoDateTimeTickFormatterSpec(
            day: chart.TimeFormatterSpec(format: 'dd.MM.', transitionFormat: 'dd.MM.'),
            hour: chart.TimeFormatterSpec(format: 'HH:mm', transitionFormat: 'HH:mm'),
            minute: chart.TimeFormatterSpec(format: 'HH:mm:ss', transitionFormat: 'HH:mm:ss')),
      ),
      behaviors: [
        chart.RangeAnnotation([
          line(series.min, 'recordingcharts.min.label'.tr()),
          line(series.max, 'recordingcharts.max.label'.tr()),
          line(series.average, 'recordingcharts.avg.label'.tr()),
        ]),
      ],
    );
  }

  // from the first to the last bucket that has intervals
  Widget _buildHistogram(BuildContext context, RecordingChartsViewmodel vm) {
    var histogram = vm.histogram;
    var first = histogram.indexWhere((count) => count > 0);
    if (first < 0) {
      return _hint(context, 'recordingcharts.nointervals.label'.tr());
    }
    var last = histogram.lastIndexWhere((count) => count > 0);
    var bars = [
      for (var bucket = first; bucket <= last; bucket++)
        (RecorderFormat.duration(Duration(microseconds: (IntervalHistogram.upperBoundMs(bucket) * 1000).round())), histogram[bucket])
    ];
    var color = Theme.of(context).colorScheme.primary;
    return chart.BarChart(
      [
        chart.Series<(String, int), String>(
          id: 'intervals',
          data: bars,
          domainFn: (bar, _) => bar.$1,
          measureFn: (bar, _) => bar.$2,
          colorFn: (_, __) =>
              chart.Color(r: (color.r * 255).round(), g: (color.g * 255).round(), b: (color.b * 255).round()),
        ),
      ],
      animate: false,
      vertical: false,
      domainAxis: chart.OrdinalAxisSpec(renderSpec: chart.SmallTickRendererSpec(labelStyle: chart.TextStyleSpec(fontSize: 11))),
    );
  }

  Widget _buildPositions(BuildContext context, RecordingChartsViewmodel vm) {
    if (!vm.canShowTrack) {
      return _hint(context, 'recordingcharts.nopositions.label'.tr());
    }
    var track = vm.track;
    if (track == null || track.isEmpty) {
      return _hint(context, vm.isLoading ? '' : 'recordingcharts.notrack.label'.tr());
    }
    var theme = Theme.of(context);
    return FlutterMap(
      key: ValueKey('${vm.topic}|${track.length}|${track.first}'),
      options: MapOptions(
        initialCameraFit: track.length > 1
            ? CameraFit.coordinates(coordinates: track, padding: EdgeInsets.all(48), maxZoom: 18)
            : null,
        initialCenter: track.first,
        initialZoom: 16,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          // OpenStreetMap blocks requests without a user agent identifying the app
          userAgentPackageName: 'eu.redpin.mqttstudio',
        ),
        PolylineLayer(polylines: [
          Polyline(points: track, strokeWidth: 3, color: vm.colorOf(vm.topic!).color),
        ]),
        MarkerLayer(markers: [
          Marker(point: track.first, child: Icon(Icons.trip_origin, size: 20, color: theme.colorScheme.primary)),
          Marker(point: track.last, child: Icon(Icons.location_on, size: 32, color: theme.colorScheme.secondary)),
        ]),
        // attribution required by the OpenStreetMap tile usage policy
        SimpleAttributionWidget(
          source: Text('OpenStreetMap contributors'),
          onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
        ),
      ],
    );
  }

  Widget _hint(BuildContext context, String text) {
    var theme = Theme.of(context);
    return Center(
        child: Text(text,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium!.copyWith(color: theme.hintColor),
            maxLines: 3,
            overflow: TextOverflow.ellipsis));
  }
}

