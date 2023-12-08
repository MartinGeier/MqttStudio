import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/common/localstore.dart';
import 'package:mqttstudio/common/newsletter_signup_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class NewsletterSignup extends StatefulWidget {
  const NewsletterSignup({Key? key}) : super(key: key);

  @override
  State<NewsletterSignup> createState() => _NewsletterSignupState();
}

class _NewsletterSignupState extends State<NewsletterSignup> {
  bool _doNotShowAgain = false;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<NewsletterSignupViewmodel>(
        create: (_) => NewsletterSignupViewmodel(),
        builder: (context, child) {
          return Consumer<NewsletterSignupViewmodel>(builder: (context, viewmodel, child) {
            return _buildBody(viewmodel);
          });
        });
  }

  Widget _buildBody(NewsletterSignupViewmodel viewmodel) {
    return AlertDialog(
      title: Text("newsletter_signup.title".tr()),
      content: _buildContent(viewmodel),
      actions: [
        _buildActions(context),
      ],
    );
  }

  Container _buildContent(NewsletterSignupViewmodel viewmodel) {
    return Container(
      height: 480,
      width: 500,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("newsletter_signup.hintmessage".tr()),
          SizedBox(height: 16),
          Text('newsletter_signup.emailsharing.label'.tr(),
              style: Theme.of(context).textTheme.titleSmall!.copyWith(fontWeight: FontWeight.bold)),
          SizedBox(height: 16),
          ReactiveForm(formGroup: viewmodel.form, child: _buildForm(viewmodel, context)),
        ],
      ),
    );
  }

  _buildForm(NewsletterSignupViewmodel viewmodel, BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SrxFormRow(children: [Expanded(child: _buildEmailField(viewmodel))]),
      SrxFormRow(children: [
        SrxFormExpandedPadded.start(child: _buildFirstnameField(viewmodel)),
        SrxFormExpandedPadded.end(child: _buildLstnameField(viewmodel))
      ]),
      SrxFormRow(children: [Expanded(child: _buildCompanyField(viewmodel))]),
      Text.rich(TextSpan(children: [
        TextSpan(text: "newsletter_signup.privacyhint.label1".tr(), style: Theme.of(context).textTheme.bodySmall),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onTap: () => launchUrl(Uri.parse('https://www.mqttstudio.com/en/terms-of-use.html')),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Text(
                "newsletter_signup.privacyhint.label2".tr(),
                style: Theme.of(context).textTheme.bodySmall!.copyWith(decoration: TextDecoration.underline),
              ),
            ),
          ),
        ),
      ])),
      SrxFormRow(children: [Expanded(child: _buildPrivacyCheckbox(viewmodel))]),
    ]);
  }

  ReactiveTextField<String> _buildEmailField(NewsletterSignupViewmodel viewmodel) {
    return ReactiveTextField(
      autofocus: true,
      textInputAction: TextInputAction.next,
      maxLines: 1,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'newsletter_signup.email.label'.tr(), isDense: true),
      formControlName: NewsletterSignupViewmodel.firstnameField,
      validationMessages: {'required': (error) => 'srx.common.fieldrequired'.tr()},
    );
  }

  ReactiveTextField<String> _buildFirstnameField(NewsletterSignupViewmodel viewmodel) {
    return ReactiveTextField(
      autofocus: true,
      textInputAction: TextInputAction.next,
      maxLines: 1,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'newsletter_signup.firstname.label'.tr(), isDense: true),
      formControlName: NewsletterSignupViewmodel.firstnameField,
    );
  }

  ReactiveTextField<String> _buildLstnameField(NewsletterSignupViewmodel viewmodel) {
    return ReactiveTextField(
      autofocus: true,
      textInputAction: TextInputAction.next,
      maxLines: 1,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'newsletter_signup.lastname.label'.tr(), isDense: true),
      formControlName: NewsletterSignupViewmodel.lastnameField,
    );
  }

  ReactiveTextField<String> _buildCompanyField(NewsletterSignupViewmodel viewmodel) {
    return ReactiveTextField(
      autofocus: true,
      textInputAction: TextInputAction.next,
      maxLines: 1,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'newsletter_signup.companyname.label'.tr(), isDense: true),
      formControlName: NewsletterSignupViewmodel.companyNameField,
    );
  }

  Widget _buildPrivacyCheckbox(NewsletterSignupViewmodel viewmodel) {
    return SrxReactiveCheckboxField(
      formControlName: NewsletterSignupViewmodel.privacyAcceptedField,
      label: 'newsletter_signup.privacyaccepted.label'.tr(),
    );
  }

  Row _buildActions(BuildContext context) {
    return Row(
      children: [
        TextButton(
          child: Text("newsletter_signup.doNotShowAgain".tr()),
          onPressed: () async {
            if (_doNotShowAgain) {
              await LocalStore().saveBrowserPerformanceWarningDoNotShow(true);
            }
            Navigator.of(context).pop(); // Close the dialog
          },
        ),
        Spacer(),
        OutlinedButton(
          child: Text("newsletter_signup.later_button".tr()),
          onPressed: () async {
            if (_doNotShowAgain) {
              await LocalStore().saveBrowserPerformanceWarningDoNotShow(true);
            }
            Navigator.of(context).pop(); // Close the dialog
          },
        ),
        SizedBox(width: 8),
        ElevatedButton(
          child: Text("newsletter_signup.signup_button".tr()),
          onPressed: () async {
            if (_doNotShowAgain) {
              await LocalStore().saveBrowserPerformanceWarningDoNotShow(true);
            }
            Navigator.of(context).pop(); // Close the dialog
          },
        ),
      ],
    );
  }

  _onClick() {
    setState(() {
      _doNotShowAgain = !_doNotShowAgain;
    });
  }
}
