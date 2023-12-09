import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mqttstudio/model/newsletter_signup.dart';

class NewsletterSignupService {
  static const String _baseUrl = 'https://5e2jnxq4vyvggikrhi3cigzgku0wnlux.lambda-url.eu-south-1.on.aws/';

  Future signup(NewsletterSignup signup) async {
    try {
      final url = Uri.parse('$_baseUrl');
      http.post(url, headers: {"Content-Type": "application/json"}, body: jsonEncode(signup.toJson())).then((response) {
        if (response.statusCode == 200) {
          print('NewsletterSignupService: Sign up successful!');
        } else {
          print('NewsletterSignupService: Sign up failed: ${response.statusCode}');
        }
      });
    } catch (e) {
      print('NewsletterSignupService: Error signing up!');
    }
  }
}
