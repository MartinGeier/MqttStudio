// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'newsletter_signup.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NewsletterSignup _$NewsletterSignupFromJson(Map<String, dynamic> json) =>
    NewsletterSignup()
      ..id = json['id'] as String?
      ..createdOn = dateTimeFromUtcJson(json['createdOn'] as String?)
      ..lastModifiedOn = dateTimeFromUtcJson(json['lastModifiedOn'] as String?)
      ..createdBy = json['createdBy'] as String?
      ..lastModifiedBy = json['lastModifiedBy'] as String?
      ..firstname = json['firstname'] as String?
      ..lastname = json['lastname'] as String?
      ..companyName = json['companyName'] as String?
      ..emailAddress = json['emailAddress'] as String?
      ..privacyAccepted = json['privacyAccepted'] as bool;

Map<String, dynamic> _$NewsletterSignupToJson(NewsletterSignup instance) {
  final val = <String, dynamic>{
    'id': SrxBaseModel.setIdIfNull(instance.id),
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('createdOn', dateTimeToUtcJson(instance.createdOn));
  writeNotNull('lastModifiedOn', dateTimeToUtcJson(instance.lastModifiedOn));
  writeNotNull('createdBy', instance.createdBy);
  writeNotNull('lastModifiedBy', instance.lastModifiedBy);
  val['firstname'] = instance.firstname;
  val['lastname'] = instance.lastname;
  val['companyName'] = instance.companyName;
  val['emailAddress'] = instance.emailAddress;
  val['privacyAccepted'] = instance.privacyAccepted;
  return val;
}
