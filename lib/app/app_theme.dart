import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color healthGreen = Color(0xFF2BBE7A);
  static const Color techBlue = Color(0xFF1E88E5);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: healthGreen),
        scaffoldBackgroundColor: const Color(0xFFF7F9FB),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1F2937),
          elevation: 0.5,
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: healthGreen,
          brightness: Brightness.dark,
        ),
      );
}
