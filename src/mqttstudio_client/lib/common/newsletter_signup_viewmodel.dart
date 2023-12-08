import 'package:mqttstudio/model/newsletter_signup.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';

class NewsletterSignupViewmodel extends SrxChangeNotifier {
  static String firstnameField = 'firstname';
  static String lastnameField = 'lastname';
  static String companyNameField = 'companyName';
  static String emailAddressField = 'emailAddress';
  static String privacyAcceptedField = 'privacyAccepted';

  late FormGroup form;
  late NewsletterSignup newsletterSignup;

  NewsletterSignupViewmodel() {
    form = buildFormGroup();
  }

  FormGroup buildFormGroup() {
    return FormGroup({
      firstnameField: FormControl<String>(validators: [Validators.maxLength(50)]),
      lastnameField: FormControl<String>(validators: [Validators.maxLength(50)]),
      companyNameField: FormControl<String>(validators: [Validators.maxLength(50)]),
      emailAddressField: FormControl<String>(validators: [Validators.email, Validators.required]),
      privacyAcceptedField: FormControl<bool>(),
    });
  }

  void toNewsletterSignup() {
    newsletterSignup = NewsletterSignup();
    newsletterSignup.firstname = form.control(firstnameField).value ?? false;
    newsletterSignup.lastname = form.control(lastnameField).value ?? false;
    newsletterSignup.companyName = form.control(companyNameField).value ?? false;
    newsletterSignup.emailAddress = form.control(emailAddressField).value ?? false;
    newsletterSignup.privacyAccepted = form.control(privacyAcceptedField).value ?? false;
  }

  bool saveModel({bool validateForm = true}) {
    if (validateForm) {
      form.markAllAsTouched();
      if (!form.valid) {
        return false;
      }
    }

    toNewsletterSignup();
    return true;
  }
}
