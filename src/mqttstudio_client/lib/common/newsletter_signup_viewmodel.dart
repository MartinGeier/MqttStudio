import 'package:mqttstudio/model/newsletter_signup.dart';
import 'package:mqttstudio/service/newsletter_signup_service.dart';
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
    newsletterSignup.firstname = form.control(firstnameField).value ?? '';
    newsletterSignup.lastname = form.control(lastnameField).value ?? '';
    newsletterSignup.companyName = form.control(companyNameField).value ?? '';
    newsletterSignup.emailAddress = form.control(emailAddressField).value ?? '';
    newsletterSignup.privacyAccepted = form.control(privacyAcceptedField).value ?? false;
  }

  Future<bool> saveModel({bool validateForm = true}) async {
    if (validateForm) {
      form.markAllAsTouched();
      if (!form.valid) {
        return false;
      }
    }

    toNewsletterSignup();
    await NewsletterSignupService().signup(newsletterSignup);
    return true;
  }
}
