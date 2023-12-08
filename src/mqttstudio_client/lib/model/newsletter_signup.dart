import 'package:json_annotation/json_annotation.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'dart:convert';

// use 'flutter pub run build_runner build' to run the code generator
part 'newsletter_signup.g.dart';

@JsonSerializable(explicitToJson: true)
class NewsletterSignup extends SrxBaseModel {
  String? firstname;
  String? lastname;
  String? companyName;
  String? emailAddress;
  bool privacyAccepted = false;

  NewsletterSignup();

  int getHash() {
    return json.encode(_$NewsletterSignupToJson(this)).hashCode;
  }

  factory NewsletterSignup.fromJson(Map<String, dynamic> json) => _$NewsletterSignupFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$NewsletterSignupToJson(this);
}
