import 'package:flutter/material.dart';

SnackBar errorSnackBar(String errorMessage, BuildContext context) {
  return SnackBar(
    content: Text(errorMessage),
    backgroundColor: Theme.of(context).colorScheme.error,
    behavior: SnackBarBehavior.floating,
    duration: Duration(seconds: 10),
    padding: EdgeInsets.all(12),
  );
}
