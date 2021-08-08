import 'package:flutter/material.dart';

class CustomTheme {
  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primarySwatch: _greyPalette,
    accentColor: Color(0xffB71C1C),
    errorColor: Color(0xfff62a00),
    inputDecorationTheme: InputDecorationTheme(errorStyle: TextStyle(height: 0.6)),
    //popupMenuTheme: PopupMenuThemeData(textStyle: TextStyle(fontSize: 12)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ButtonStyle(minimumSize: MaterialStateProperty.all(Size(150, 48)))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: ButtonStyle(minimumSize: MaterialStateProperty.all(Size(150, 48)))),
    textButtonTheme: TextButtonThemeData(style: ButtonStyle(minimumSize: MaterialStateProperty.all(Size(150, 48)))),
    textTheme: ThemeData.light().textTheme.copyWith(subtitle2: TextStyle(fontWeight: FontWeight.w600)),
  );

  // create with http://mcg.mbitson.com/
  static const int _grey = 0xFF616161;
  static const MaterialColor _greyPalette = MaterialColor(_grey, <int, Color>{
    50: Color(0xFFECECEC),
    100: Color(0xFFD0D0D0),
    200: Color(0xFFB0B0B0),
    300: Color(0xFF909090),
    400: Color(0xFF797979),
    500: Color(_grey),
    600: Color(0xFF595959),
    700: Color(0xFF4F4F4F),
    800: Color(0xFF454545),
    900: Color(0xFF333333),
  });
}

extension ThemeDataEx on ThemeData {
  CustomColors get custom => new CustomColors();

  Color getTextColor([Color bgColor = CustomTheme._greyPalette]) {
    return bgColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }
}

class CustomColors {
  Color connectedColor = Colors.green;
  Color disconnectedColor = Colors.red;
  Color watermark = Color(0xffe9e9e9);
}
