import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color primaryBlue = Color(0xFF0EA5E9);
  static const Color deepBlue = Color(0xFF075985);
  static const Color ink = Color(0xFF0F172A);
  static const Color muted = Color(0xFF475569);
  static const Color pageBg = Color(0xFFF8FAFC);
  static const Color cardBorder = Color(0xFFCBD5E1);

  static const Color healthGreen = primaryBlue;
  static const Color techBlue = deepBlue;
  static const List<String> fontFamilyFallback = [
    'PingFang SC',
    'Hiragino Sans GB',
    'Microsoft YaHei',
    'Noto Sans SC',
    'Roboto',
  ];

  static Color accent(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  static Color accentStrong(BuildContext context) {
    final hsl = HSLColor.fromColor(accent(context));
    return hsl
        .withLightness((hsl.lightness - 0.14).clamp(0.18, 0.58))
        .toColor();
  }

  static LinearGradient accentGradient(BuildContext context) => LinearGradient(
        colors: [accentStrong(context), accent(context)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient accentSoftGradient(BuildContext context) =>
      LinearGradient(
        colors: [
          Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6),
          Colors.white,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static ThemeData get light => lightFor(primaryBlue);

  static ThemeData lightFor(Color seed) {
    final generatedScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );
    final colorScheme = generatedScheme.copyWith(
      primary: seed,
      onPrimary: Colors.white,
      primaryContainer:
          Color.alphaBlend(seed.withValues(alpha: 0.12), Colors.white),
      onPrimaryContainer: HSLColor.fromColor(seed)
          .withLightness(
            (HSLColor.fromColor(seed).lightness - 0.16).clamp(0.16, 0.5),
          )
          .toColor(),
    );
    return ThemeData(
      useMaterial3: true,
      fontFamilyFallback: fontFamilyFallback,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: pageBg,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      textTheme: ThemeData.light().textTheme.apply(
            bodyColor: ink,
            displayColor: ink,
          ),
      visualDensity: VisualDensity.standard,
      dividerTheme: DividerThemeData(
        color: cardBorder,
        space: 1,
        thickness: 1,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: cardBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFBFDFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(44, 44),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          minimumSize: const Size(44, 44),
          side: const BorderSide(color: cardBorder),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.14),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : muted,
          ),
        ),
      ),
    );
  }

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        fontFamilyFallback: fontFamilyFallback,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: healthGreen,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F1C2E),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Color(0xFF162336),
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Color(0xFF162336),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF162336),
          indicatorColor: primaryBlue.withValues(alpha: 0.22),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? primaryBlue
                  : Colors.white54,
            ),
          ),
        ),
      );
}
