import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

SnackBar errorSnackBar(String errorMessage, BuildContext context) {
  return SnackBar(
    content: Text(errorMessage),
    backgroundColor: Theme.of(context).errorColor,
    behavior: SnackBarBehavior.floating,
    duration: Duration(seconds: 6),
    padding: EdgeInsets.all(12),
  );
}
