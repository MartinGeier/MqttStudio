import 'package:flutter/material.dart';

class SrxNavigationService {
  final GlobalKey<NavigatorState> navigatorKey = new GlobalKey<NavigatorState>();
  final Widget loginPage;
  final Widget homePage;
  final bool animatePageTransistions;

  SrxNavigationService(this.loginPage, this.homePage, {this.animatePageTransistions = true});

  Future navigateToLogin() async {
    //navigatorKey.currentState?.popUntil((route) => route.isFirst);
    if (navigatorKey.currentState?.canPop() ?? false) {
      navigatorKey.currentState?.pop();
    }
    navigatorKey.currentState?.pushReplacement(MaterialPageRoute(builder: (context) => loginPage));
  }

  Future popOrHomeView() async {
    if (navigatorKey.currentState?.canPop() ?? false) {
      navigatorKey.currentState?.pop();
    } else {
      navigatorKey.currentState?.pushReplacement(MaterialPageRoute(builder: (context) => homePage));
    }
  }

  bool canPop() {
    return navigatorKey.currentState?.canPop() ?? false;
  }

  void pop<T extends Object?>([T? result]) {
    navigatorKey.currentState?.pop(result);
  }

  void pushReplacement(Widget destinationPage) async {
    await navigatorKey.currentState?.pushReplacement(animatePageTransistions
        ? MaterialPageRoute(builder: (_) => destinationPage)
        : PageRouteBuilder(pageBuilder: (_, __, ___) => destinationPage, transitionDuration: Duration(seconds: 0)));
  }

  Future<T?> push<T extends Object?>(Widget destinationPage) async {
    return await navigatorKey.currentState?.push(MaterialPageRoute(builder: (context) => destinationPage));
  }
}
