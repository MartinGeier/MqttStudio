// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'newsletter_signup.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NewsletterSignup _$NewsletterSignupFromJson(Map<String, dynamic> json) =>
    NewsletterSignup()
      ..firstname = json['firstname'] as String?
      ..lastname = json['lastname'] as String?
      ..companyName = json['companyName'] as String?
      ..emailAddress = json['emailAddress'] as String?
      ..privacyAccepted = json['privacyAccepted'] as bool;

Map<String, dynamic> _$NewsletterSignupToJson(NewsletterSignup instance) =>
    <String, dynamic>{
      'firstname': instance.firstname,
      'lastname': instance.lastname,
      'companyName': instance.companyName,
      'emailAddress': instance.emailAddress,
      'privacyAccepted': instance.privacyAccepted,
    };
