import 'package:flutter/material.dart';

abstract class Palette {
  static const bg = Color(0xFF0E1012),
      surface = Color(0xFF15181B),
      raised = Color(0xFF1C2024),
      border = Color(0xFF2B3035),
      text = Color(0xFFF4F2EF),
      muted = Color(0xFF9A9FA5),
      accent = Color(0xFFFF5A1F),
      success = Color(0xFF76CBA3),
      warning = Color(0xFFF3BD68),
      danger = Color(0xFFFF8585);
}

TextStyle mono({
  double size = 11,
  Color color = Palette.muted,
  FontWeight weight = FontWeight.w400,
}) => TextStyle(
  fontFamily: 'IBM Plex Mono',
  fontSize: size,
  color: color,
  fontWeight: weight,
  letterSpacing: .5,
);
ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: Palette.bg,
  fontFamily: 'Archivo',
  colorScheme: ColorScheme.dark(
    primary: Palette.accent,
    onPrimary: Palette.bg,
    surface: Palette.surface,
    onSurface: Palette.text,
    error: Palette.danger,
    outline: Palette.border,
  ),
  textTheme: ThemeData.dark().textTheme.apply(
    fontFamily: 'Archivo',
    bodyColor: Palette.text,
    displayColor: Palette.text,
  ),
  dividerColor: Palette.border,
  dividerTheme: DividerThemeData(color: Palette.border, space: 1),
  appBarTheme: AppBarTheme(
    backgroundColor: Palette.bg,
    foregroundColor: Palette.text,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: Palette.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: BorderSide(color: Palette.border),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Palette.surface,
    labelStyle: TextStyle(color: Palette.muted),
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(2),
      borderSide: BorderSide(color: Palette.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(2),
      borderSide: BorderSide(color: Palette.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(2),
      borderSide: BorderSide(color: Palette.accent),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: Palette.accent,
      foregroundColor: Palette.bg,
      minimumSize: Size(0, 48),
      textStyle: TextStyle(
        fontFamily: 'Archivo',
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: Palette.text,
      minimumSize: Size(0, 48),
      side: BorderSide(color: Palette.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      textStyle: TextStyle(fontWeight: FontWeight.w600),
      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: Palette.accent),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: Palette.raised,
    selectedColor: Palette.accent.withValues(alpha: .15),
    side: BorderSide(color: Palette.border),
    labelStyle: TextStyle(fontSize: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: Palette.raised,
    contentTextStyle: TextStyle(color: Palette.text),
    behavior: SnackBarBehavior.floating,
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Palette.surface,
    indicatorColor: Palette.accent.withValues(alpha: .18),
    labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 10)),
  ),
);
