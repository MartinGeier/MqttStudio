import 'dart:math';

import 'package:community_charts_flutter/community_charts_flutter.dart' as chart;
import 'package:darq/darq.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/model/received_mqtt_message.dart';
import 'package:mqttstudio/project/project_global_viewmodel.dart';
// ignore: implementation_imports
import 'package:community_charts_flutter/src/text_element.dart' as te;
// ignore: implementation_imports
import 'package:community_charts_flutter/src/text_style.dart' as style;

class TopicChart extends StatefulWidget {
  const TopicChart({
    Key? key,
    required this.values,
    required this.topic,
  }) : super(key: key);

  final List<Tuple2<DateTime, double>> values;
  final ReceivedMqttMessage topic;

  @override
  State<TopicChart> createState() => _TopicChartState();
}

class _TopicChartState extends State<TopicChart> {
  ChartValues _chartToolTipValues = ChartValues();

  @override
  Widget build(BuildContext context) {
    var seriesColor = GetIt.I.get<ProjectGlobalViewmodel>().getTopicColor(widget.topic.topicName);
    return chart.TimeSeriesChart(
      [
        chart.Series<Tuple2<DateTime, double>, DateTime>(
          id: "1",
          data: widget.values,
          domainFn: (x, _) => x.item0,
          measureFn: (x, _) => x.item1,
          strokeWidthPxFn: (_, __) => 2,
          seriesColor: chart.Color.fromHex(code: "#" + seriesColor.color.value.toRadixString(16).substring(2, 8)),
        )
      ],
      selectionModels: [
        chart.SelectionModelConfig(
            type: chart.SelectionModelType.info,
            changedListener: (chart.SelectionModel model) {
              if (model.hasDatumSelection) {
                _chartToolTipValues.values.clear();
                model.selectedDatum.forEach((chart.SeriesDatum datumPair) {
                  _chartToolTipValues.values.add(datumPair.datum);
                });
              }
            })
      ],
      animate: false,
      domainAxis: chart.DateTimeAxisSpec(
        tickProviderSpec: widget.values.isNotEmpty
            ? chart.StaticDateTimeTickProviderSpec([
                chart.TickSpec(widget.values.first.item0),
                chart.TickSpec(widget.values.first.item0
                    .add(Duration(milliseconds: widget.values.last.item0.difference(widget.values.first.item0).inMilliseconds ~/ 2))),
                chart.TickSpec(widget.values.last.item0)
              ])
            : null,
        tickFormatterSpec: chart.AutoDateTimeTickFormatterSpec(
            day: chart.TimeFormatterSpec(format: 'dd.MM.', transitionFormat: 'dd.MM.'),
            hour: chart.TimeFormatterSpec(format: 'HH:mm', transitionFormat: 'HH:mm'),
            minute: chart.TimeFormatterSpec(format: 'HH:mm:ss', transitionFormat: 'HH:mm:ss')),
        renderSpec: chart.SmallTickRendererSpec(
            tickLengthPx: 6, labelOffsetFromAxisPx: 12, labelStyle: chart.TextStyleSpec(fontSize: 12), minimumPaddingBetweenLabelsPx: 20),
      ),
      primaryMeasureAxis: const chart.NumericAxisSpec(tickProviderSpec: chart.BasicNumericTickProviderSpec(zeroBound: false)),
      behaviors: [
        chart.LinePointHighlighter(
            symbolRenderer: CustomCircleSymbolRenderer(_chartToolTipValues),
            showHorizontalFollowLine: chart.LinePointHighlighterFollowLineType.none,
            showVerticalFollowLine: chart.LinePointHighlighterFollowLineType.nearest),
        chart.SelectNearest(eventTrigger: chart.SelectionTrigger.tapAndDrag),
      ],
    );
  }
}

class CustomCircleSymbolRenderer extends chart.CircleSymbolRenderer {
  ChartValues _value;
  int _i = 0;
  NumberFormat nf = NumberFormat("0.0");

  CustomCircleSymbolRenderer(this._value);

  @override
  void paint(chart.ChartCanvas canvas, Rectangle<num> bounds,
      {List<int>? dashPattern,
      chart.Color? fillColor,
      chart.FillPatternType? fillPattern,
      chart.Color? strokeColor,
      double? strokeWidthPx}) {
    super.paint(canvas, bounds,
        dashPattern: dashPattern, fillColor: fillColor, fillPattern: fillPattern, strokeColor: strokeColor, strokeWidthPx: strokeWidthPx);
    // canvas.drawRect(Rectangle(bounds.left - 5, bounds.top - 30, bounds.width + 10, bounds.height + 10), fill: charts.Color.white);
    var textStyle = style.TextStyle();
    textStyle.color = chart.Color.black;
    textStyle.fontSize = 12;
    canvas.drawText(
        te.TextElement(nf.format(_value.values[_i].item1) + ' | ' + DateFormat('HH:mm:ss').format(_value.values[_i].item0),
            style: textStyle),
        (bounds.left).round(),
        (bounds.top - 20).round());
    _i++;
    if (_i >= _value.values.length) {
      _i = 0;
    }
  }
}

class ChartValues {
  List<Tuple2<DateTime, double>> values = [];
}
