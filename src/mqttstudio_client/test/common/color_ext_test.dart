import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttstudio/common/colorExt.dart';

double lightness(Color color) => HSLColor.fromColor(color).lightness;

void main() {
  group('ColorBrightness', () {
    const color = Color(0xFF3F51B5);

    test('lighten increases the lightness by the given amount', () {
      expect(lightness(color.lighten(0.2)), closeTo(lightness(color) + 0.2, 0.01));
    });

    test('darken decreases the lightness by the given amount', () {
      expect(lightness(color.darken(0.2)), closeTo(lightness(color) - 0.2, 0.01));
    });

    test('lightness stays within 0 and 1', () {
      expect(lightness(Colors.white.lighten(0.5)), 1.0);
      expect(lightness(Colors.black.darken(0.5)), 0.0);
    });
  });
}
