import 'package:easy_localization/easy_localization.dart';

String formatDuration(Duration? duration) {
  if (duration == null) {
    return '';
  }

  int totalSeconds = duration.inSeconds;
  int hours = (totalSeconds / 3600).floor();
  totalSeconds -= hours * 3600;
  int minutes = (totalSeconds / 60).floor();
  totalSeconds -= minutes * 60;
  return '${NumberFormat('00').format(hours)}:${NumberFormat('00').format(minutes)}:${NumberFormat('00').format(totalSeconds)}';
}
