import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Tailwind Colors
  static const primaryColor = Color(0xFF137FEC);

  static const bgLight = Color(0xFFF6F7F8);
  static const bgDark = Color(0xFF101922);

  static const sidebarLight = Colors.white;
  static const sidebarDark = Color(0xFF0F172A); // slate-900

  static const textLight = Color(0xFF0F172A); // slate-900
  static const textDark = Color(0xFFF1F5F9); // slate-100

  static const borderLight = Color(0xFFE2E8F0); // slate-200
  static const borderDark = Color(0xFF1E293B); // slate-800

  // Семантические цвета (единые для SnackBar, статусов, бейджей)
  static const successColor = Color(0xFF15803D); // green-700
  static const successColorDark = Color(0xFF4ADE80); // green-400 для тёмной темы
  static const errorColor = Color(0xFFB91C1C); // red-700
  static const errorColorDark = Color(0xFFF87171); // red-400 для тёмной темы
  static const warningColor = Color(0xFFB45309); // amber-700
  static const warningColorDark = Color(0xFFFBBF24); // amber-400 для тёмной темы

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: bgLight,
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        surface: sidebarLight,
        onSurface: textLight,
        outline: borderLight,
        outlineVariant: Color(0xFFF1F5F9), // slate-100
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      dividerTheme: const DividerThemeData(color: borderLight, space: 1),
      iconTheme: const IconThemeData(color: textLight),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: bgDark,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        surface: sidebarDark,
        onSurface: textDark,
        outline: borderDark,
        outlineVariant: Color(0xFF0F172A), // slate-900
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      dividerTheme: const DividerThemeData(color: borderDark, space: 1),
      iconTheme: const IconThemeData(color: textDark),
    );
  }
}
