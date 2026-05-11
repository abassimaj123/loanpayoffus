import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';

class AppTheme {
  AppTheme._();

  // Deep Purple identity — "debt freedom"
  static const Color primary     = Color(0xFF512DA8); // Deep Purple 700
  static const Color accent      = Color(0xFFF59E0B);

  static const Color primaryDark = Color(0xFF311B92); // Deep Purple 900
  static const Color accentGood  = Color(0xFF00C853); // Green A700
  static const Color warning     = Color(0xFFFF6D00); // Deep Orange A400
  static const Color neutral     = Color(0xFFD1C4E9); // Deep Purple 100
  static const Color dangerRed   = Color(0xFFDC2626); // Semantic danger/error red

  static ThemeData get light => CalcwiseThemeFactory.buildLight(primary: primary, accent: accent);
  static ThemeData get dark  => CalcwiseThemeFactory.buildDark(primary: primary, accent: accent);
}
