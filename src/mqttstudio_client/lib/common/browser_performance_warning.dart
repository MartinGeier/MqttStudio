import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/common/localstore.dart';
import 'package:url_launcher/url_launcher.dart';

class BrowserPerformanceWarning extends StatefulWidget {
  const BrowserPerformanceWarning({Key? key}) : super(key: key);

  @override
  State<BrowserPerformanceWarning> createState() => _BrowserPerformanceWarningState();
}

class _BrowserPerformanceWarningState extends State<BrowserPerformanceWarning> {
  bool _doNotShowAgain = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("browserperformancewarning.title".tr()),
      content: Container(
        height: 196,
        child: Column(
          children: [
            SizedBox(width: 420, child: Text("browserperformancewarning.hintmessage".tr())),
            SizedBox(height: 32),
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.secondary),
                onPressed: () => _openDownloadPage(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.download),
                    SizedBox(width: 12),
                    Text("browserperformancewarning.downloadDesktopClient".tr()),
                  ],
                )),
            SizedBox(height: 24),
            Row(
              children: [
                Row(
                  children: [
                    Checkbox(value: _doNotShowAgain, onChanged: (_) => _onClick()),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(child: Text("browserperformancewarning.doNotShowAgain".tr()), onTap: () => _onClick()),
                    )
                  ],
                ),
              ],
            )
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: Text("commmon.okButtonCaption".tr()),
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

  _openDownloadPage() async {
    final Uri url = Uri.parse('https://www.mqttstudio.com/downloads');
    await launchUrl(url);
  }
}
