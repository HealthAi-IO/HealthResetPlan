import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color primaryBlue = Color(0xFF0B91E5);
  static const Color deepBlue = Color(0xFF102844);
  static const Color accentCyan = Color(0xFF4ED8CF);
  static const Color leafGreen = Color(0xFF62D873);
  static const Color ink = Color(0xFF10243E);
  static const Color muted = Color(0xFF65788B);
  static const Color pageBg = Color(0xFFF4F8FB);
  static const Color cardBorder = Color(0xFFDDE7EF);
  static const Color softBlue = Color(0xFFEAF7FE);
  static const Color softGreen = Color(0xFFECF9F0);
  static const Color aiPurple = Color(0xFF625EF6);

  static const Color healthGreen = primaryBlue;
  static const Color techBlue = deepBlue;
  static Color accent(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  static Color accentStrong(BuildContext context) {
    final hsl = HSLColor.fromColor(accent(context));
    return hsl
        .withLightness((hsl.lightness - 0.14).clamp(0.18, 0.58))
        .toColor();
  }

  static LinearGradient accentGradient(BuildContext context) => LinearGradient(
        colors: [accentStrong(context), accentCyan],
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
      surface: Colors.white,
    );
    final colorScheme = generatedScheme.copyWith(
      primary: seed,
      onPrimary: Colors.white,
      secondary: accentCyan,
      onSecondary: deepBlue,
      secondaryContainer: const Color(0xFFDDF8F5),
      onSecondaryContainer: deepBlue,
      tertiary: leafGreen,
      onTertiary: deepBlue,
      tertiaryContainer: softGreen,
      onTertiaryContainer: deepBlue,
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
      fontFamily: 'NotoSansSC',
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
      textTheme: ThemeData.light()
          .textTheme
          .apply(
            fontFamily: 'NotoSansSC',
            bodyColor: ink,
            displayColor: ink,
          )
          .copyWith(
            headlineLarge: const TextStyle(
              fontSize: 30,
              height: 1.25,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
            headlineMedium: const TextStyle(
              fontSize: 26,
              height: 1.3,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
            headlineSmall: const TextStyle(
              fontSize: 22,
              height: 1.35,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
            titleLarge: const TextStyle(
              fontSize: 20,
              height: 1.4,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
            titleMedium: const TextStyle(
              fontSize: 16,
              height: 1.45,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
            bodyLarge: const TextStyle(fontSize: 16, height: 1.55, color: ink),
            bodyMedium: const TextStyle(fontSize: 14, height: 1.55, color: ink),
            bodySmall: const TextStyle(fontSize: 12, height: 1.5, color: muted),
          ),
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
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
        toolbarHeight: 64,
        titleSpacing: 20,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(color: muted, fontSize: 16),
        hintStyle: const TextStyle(color: Color(0xFF8A9AAA), fontSize: 16),
        errorMaxLines: 2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 52),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          minimumSize: const Size(48, 50),
          side: const BorderSide(color: cardBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          minimumSize: const Size(48, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: muted,
        textColor: ink,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 12,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: deepBlue,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          side: const WidgetStatePropertyAll(BorderSide(color: cardBorder)),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: const BorderSide(color: Color(0xFFA8B7C4), width: 1.4),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.primary
              : const Color(0xFFD5DEE6),
        ),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryBlue,
        linearTrackColor: Color(0xFFDCECF7),
        circularTrackColor: Color(0xFFDCECF7),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.14),
        height: 72,
        elevation: 0,
        surfaceTintColor: Colors.white,
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
        fontFamily: 'NotoSansSC',
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
