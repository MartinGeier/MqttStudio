import 'package:flutter/material.dart';

class AppColorScheme {
  static Color _primaryColor = _bluePalette;
  static Color _accentColor = Color(0xffB71C1C);
  static Color _errorColor = Color(0xfff62a00);

  static ColorScheme _lightScheme = ColorScheme.light().copyWith(primary: _primaryColor, secondary: _accentColor, error: _errorColor);

  static ThemeData lightTheme = ThemeData.from(colorScheme: _lightScheme);

  // create with http://mcg.mbitson.com/
  static const int _gray = 0xFF616161;
  static const MaterialColor _bluePalette = MaterialColor(_gray, <int, Color>{
    50: Color(0xFFECECEC),
    100: Color(0xFFD0D0D0),
    200: Color(0xFFB0B0B0),
    300: Color(0xFF909090),
    400: Color(0xFF797979),
    500: Color(_gray),
    600: Color(0xFF595959),
    700: Color(0xFF4F4F4F),
    800: Color(0xFF454545),
    900: Color(0xFF333333),
  });
}

extension ThemeDataEx on ThemeData {
  CustomColors get custom => new CustomColors();
}

class CustomColors {
  Color connectedColor = Colors.green;
}
