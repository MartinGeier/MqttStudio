import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class PiwikTrackingService {
  static const String _baseUrl = 'https://redpin.piwik.pro/ppms.php';
  static const String _idSite = '3c17e157-36c1-46bb-9477-da848745ceab';

  Future trackAction(String action) async {
    // do not track in debug mode
    // if (kDebugMode) {
    //   return;
    // }

    try {
      final url = Uri.parse('$_baseUrl');
      // add URL parameters
      var uri = url.replace(queryParameters: <String, String>{
        'idsite': _idSite,
        'rec': '1',
        'action_name': Uri.encodeQueryComponent(action),
        'r': Random().nextInt(9999999).toString(),
        'h': DateTime.now().hour.toString(),
        'm': DateTime.now().minute.toString(),
        's': DateTime.now().second.toString(),
        'ua': kIsWeb ? 'browser' : Platform.operatingSystem,
      });

      http.get(uri).then((response) {
        if (kDebugMode) {
          if (response.statusCode == 202) {
            print('PiwikTrackingService: Tracked action: $action');
          } else {
            print('PiwikTrackingService: Failed to track action: $action');
          }
        }
      });
    } catch (e) {
      print('PiwikTrackingService: Error tracking action=$action: $e');
    }
  }
}
