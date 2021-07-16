import 'package:get_it/get_it.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Center(
            child: SizedBox(
      height: 500,
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        Image.asset(
          'assets/images/logo.png',
          height: 150,
        ),
        SizedBox(width: 300, child: SrxLoginFormWidget(GetIt.I.get<SrxSessionController>()))
      ]),
    )));
  }
}
