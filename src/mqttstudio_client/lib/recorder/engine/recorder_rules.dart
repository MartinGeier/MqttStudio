import 'package:mqttstudio/model/topic_subscription.dart';
import 'package:mqttstudio/recorder/model/recording_header.dart';

enum FilterIssue { empty, shared, wildcardPosition, hasNull }

// A filter dropped because another include filter already receives all its messages (R22)
class CoveredFilter {
  final RecorderFilter filter;
  final RecorderFilter coveredBy;

  CoveredFilter(this.filter, this.coveredBy);
}

// Rules for recorder topic filters
class RecorderRules {
  static FilterIssue? validateFilter(String filter) {
    if (filter.trim().isEmpty) {
      return FilterIssue.empty;
    }
    // R21: a shared subscription would record only this client's share
    if (filter.startsWith(TopicSubscription.sharePrefix)) {
      return FilterIssue.shared;
    }
    if (filter.contains('\u0000')) {
      return FilterIssue.hasNull;
    }
    var levels = filter.split('/');
    for (var i = 0; i < levels.length; i++) {
      var level = levels[i];
      if (level.contains('#') && (level != '#' || i != levels.length - 1)) {
        return FilterIssue.wildcardPosition;
      }
      if (level.contains('+') && level != '+') {
        return FilterIssue.wildcardPosition;
      }
    }
    return null;
  }

  // true when every topic that matches [filter] also matches [by]
  static bool covers(String by, String filter) {
    if (filter.startsWith(r'$') && (by.startsWith('+') || by.startsWith('#'))) {
      return false;
    }
    var byLevels = by.split('/');
    var levels = filter.split('/');
    for (var i = 0; i < levels.length; i++) {
      if (i >= byLevels.length) {
        return false;
      }
      var byLevel = byLevels[i];
      var level = levels[i];
      if (byLevel == '#') {
        return true;
      }
      if (level == '#') {
        return false;
      }
      if (byLevel == '+') {
        continue;
      }
      if (byLevel != level || level == '+') {
        return false;
      }
    }
    // a/# also matches a
    return byLevels.length == levels.length || (byLevels.length == levels.length + 1 && byLevels.last == '#');
  }

  // the include filters to subscribe to, without those another include already covers
  static ({List<RecorderFilter> filters, List<CoveredFilter> covered}) normalize(List<RecorderFilter> filters) {
    var includes = filters.where((filter) => !filter.exclude).toList();
    var kept = <RecorderFilter>[];
    var covered = <CoveredFilter>[];
    for (var i = 0; i < includes.length; i++) {
      var filter = includes[i];
      RecorderFilter? coveredBy;
      for (var j = 0; j < includes.length; j++) {
        var other = includes[j];
        if (i == j || !covers(other.filter, filter.filter)) {
          continue;
        }
        // of two equal filters the first one is kept
        if (covers(filter.filter, other.filter) && j > i) {
          continue;
        }
        coveredBy = other;
        break;
      }
      if (coveredBy == null) {
        kept.add(filter);
      } else {
        covered.add(CoveredFilter(filter, coveredBy));
      }
    }
    return (filters: [...kept, ...filters.where((filter) => filter.exclude)], covered: covered);
  }

  // true when the topic matches an include filter and no exclude filter
  static bool isRecorded(String topic, List<RecorderFilter> filters) {
    var included = false;
    for (var filter in filters) {
      if (matches(topic, filter.filter)) {
        if (filter.exclude) {
          return false;
        }
        included = true;
      }
    }
    return included;
  }

  // MQTT matching: + one level, # the rest including the parent level; wildcards at the start skip $ topics
  static bool matches(String topic, String filter) {
    if (topic.startsWith(r'$') && (filter.startsWith('+') || filter.startsWith('#'))) {
      return false;
    }
    var levels = topic.split('/');
    var filterLevels = filter.split('/');
    for (var i = 0; i < filterLevels.length; i++) {
      var level = filterLevels[i];
      if (level == '#') {
        return true;
      }
      if (i >= levels.length) {
        return false;
      }
      if (level != '+' && level != levels[i]) {
        return false;
      }
    }
    return levels.length == filterLevels.length;
  }

  // the filter that colors a recorded topic: the most specific matching include
  static RecorderFilter? colorFilterOf(String topic, List<RecorderFilter> filters) {
    RecorderFilter? best;
    for (var filter in filters) {
      if (filter.exclude || !matches(topic, filter.filter)) {
        continue;
      }
      if (best == null || covers(best.filter, filter.filter)) {
        best = filter;
      }
    }
    return best;
  }
}
