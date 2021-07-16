import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class SrxDialogs {
  static Widget srxErrorDialog(String errorMessage, BuildContext context) {
    return AlertDialog(
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Icon(Icons.error, color: Theme.of(context).errorColor, size: 32),
            ),
            Text('srx.dialog.errortitle'.tr()),
          ],
        ),
        actions: [ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: Text('srx.common.ok'.tr()))],
        content: Text(errorMessage));
  }

  static Widget srxInfoDialog(String message, BuildContext context) {
    return AlertDialog(
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Icon(Icons.info, color: Theme.of(context).primaryColor, size: 32),
            ),
            Text('srx.dialog.informationtitle'.tr()),
          ],
        ),
        actions: [ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: Text('srx.common.ok'.tr()))],
        content: Text(message));
  }

  static Widget srxConfirmDialog(String message, BuildContext context) {
    return AlertDialog(
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Icon(Icons.help, color: Theme.of(context).accentColor, size: 32),
            ),
            Text('srx.dialog.confirmtitle'.tr()),
          ],
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(context).pop(false), child: Text('srx.common.cancel'.tr())),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: Text('srx.common.ok'.tr())),
        ],
        content: Text(message));
  }
}
