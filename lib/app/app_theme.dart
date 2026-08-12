import 'package:flutter/material.dart';

import 'theme_controller.dart';

class AppTheme {
  AppTheme._();

  static ColorScheme get _activeScheme {
    final seed = themeController.colorTheme.seed;
    return ColorScheme.fromSeed(
      seedColor: seed,
      brightness: themeController.darkMode ? Brightness.dark : Brightness.light,
    ).copyWith(primary: seed);
  }

  static Color get primaryBlue => _activeScheme.primary;
  static Color get deepBlue => _activeScheme.primary;
  static Color get accentCyan => _activeScheme.secondary;
  static Color get leafGreen => _activeScheme.tertiary;
  static Color get ink => _activeScheme.onSurface;
  static Color get muted => _activeScheme.onSurfaceVariant;
  static Color get pageBg => _activeScheme.surface;
  static Color get surface => _activeScheme.surface;
  static Color get cardBorder => _activeScheme.outlineVariant;
  static Color get softBlue => _activeScheme.primaryContainer;
  static Color get softGreen => _activeScheme.secondaryContainer;
  static Color get aiPurple => _activeScheme.tertiary;
  static Color get softShadow => _activeScheme.shadow.withValues(alpha: 0.12);

  static Color get healthGreen => _activeScheme.tertiary;
  static Color get techBlue => _activeScheme.primary;

  static Color meal(BuildContext context) =>
      Theme.of(context).colorScheme.tertiary;

  static Color exercise(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Color.alphaBlend(
      const Color(0xFF24A06B).withValues(alpha: 0.62),
      scheme.primary,
    );
  }

  static Color medicine(BuildContext context) =>
      Theme.of(context).colorScheme.error;

  static Color weight(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  static Color water(BuildContext context) =>
      Theme.of(context).colorScheme.secondary;

  static Color success(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF62D49A)
          : const Color(0xFF16794B);

  static Color warning(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFFFC266)
          : const Color(0xFFA65A00);
  static Color accent(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  static Color accentStrong(BuildContext context) {
    final hsl = HSLColor.fromColor(accent(context));
    return hsl
        .withLightness((hsl.lightness - 0.14).clamp(0.18, 0.58))
        .toColor();
  }

  static LinearGradient accentGradient(BuildContext context) => LinearGradient(
        colors: [
          Theme.of(context).colorScheme.primary,
          Theme.of(context).colorScheme.secondary,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient accentSoftGradient(BuildContext context) =>
      LinearGradient(
        colors: [
          Theme.of(context).colorScheme.surface,
          Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.55),
          Theme.of(context).colorScheme.secondaryContainer,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static ThemeData get light => lightFor(themeController.colorTheme.seed);

  static ThemeData lightFor(Color seed) {
    final generatedScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );
    final colorScheme = generatedScheme.copyWith(
      primary: seed,
      onPrimary: Colors.white,
      primaryContainer: Color.alphaBlend(
        seed.withValues(alpha: 0.14),
        generatedScheme.surface,
      ),
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
      scaffoldBackgroundColor: colorScheme.surface,
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
            headlineLarge: TextStyle(
              fontSize: 30,
              height: 1.25,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
            headlineMedium: TextStyle(
              fontSize: 26,
              height: 1.3,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
            headlineSmall: TextStyle(
              fontSize: 22,
              height: 1.35,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
            titleLarge: TextStyle(
              fontSize: 20,
              height: 1.4,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
            titleMedium: TextStyle(
              fontSize: 16,
              height: 1.45,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
            bodyLarge: TextStyle(fontSize: 16, height: 1.55, color: ink),
            bodyMedium: TextStyle(fontSize: 14, height: 1.55, color: ink),
            bodySmall: TextStyle(fontSize: 12, height: 1.5, color: muted),
          ),
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: colorScheme.surface,
        toolbarHeight: 64,
        titleSpacing: 20,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        elevation: 2,
        shadowColor: Colors.transparent,
        surfaceTintColor: colorScheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        labelStyle:
            TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16),
        errorMaxLines: 2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
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
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          minimumSize: const Size(48, 50),
          side: BorderSide(color: colorScheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
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
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 12,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: colorScheme.surfaceContainerLow,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: colorScheme.outline, width: 1.4),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
        ),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
        circularTrackColor: colorScheme.surfaceContainerHighest,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerHigh,
        surfaceTintColor: colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.14),
        height: 72,
        elevation: 0,
        surfaceTintColor: colorScheme.surfaceContainer,
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

  static ThemeData get dark => darkFor(themeController.colorTheme.seed);

  static ThemeData darkFor(Color seed) {
    final generatedScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    final scheme = generatedScheme.copyWith(
      primary: seed,
      onSurface: const Color(0xFFF5ECE7),
      onSurfaceVariant: const Color(0xFFCBBDB5),
      outline: const Color(0xFF9D8B82),
      outlineVariant: const Color(0xFF5C4D46),
    );
    final textTheme = ThemeData.dark()
        .textTheme
        .apply(
          fontFamily: 'NotoSansSC',
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        )
        .copyWith(
          headlineLarge: TextStyle(
            fontSize: 30,
            height: 1.3,
            letterSpacing: -0.2,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
          headlineMedium: TextStyle(
            fontSize: 26,
            height: 1.35,
            letterSpacing: -0.1,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
          headlineSmall: TextStyle(
            fontSize: 22,
            height: 1.4,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
          titleLarge: TextStyle(
            fontSize: 20,
            height: 1.45,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            height: 1.5,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            height: 1.6,
            letterSpacing: 0.1,
            fontWeight: FontWeight.w400,
            color: scheme.onSurface,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            height: 1.5,
            letterSpacing: 0.1,
            fontWeight: FontWeight.w400,
            color: scheme.onSurface,
          ),
          bodySmall: TextStyle(
            fontSize: 12,
            height: 1.55,
            letterSpacing: 0.1,
            fontWeight: FontWeight.w400,
            color: scheme.onSurfaceVariant,
          ),
          labelLarge: TextStyle(
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
          labelMedium: TextStyle(
            fontSize: 12,
            height: 1.45,
            fontWeight: FontWeight.w500,
            color: scheme.onSurfaceVariant,
          ),
        );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansSC',
      brightness: Brightness.dark,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: scheme.surface,
        toolbarHeight: 64,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(48, 52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(48, 50),
          side: BorderSide(color: scheme.outlineVariant),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(48, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 12,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        height: 72,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurface,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primaryContainer
                : Colors.transparent,
          ),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.outlineVariant),
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: scheme.outline, width: 1.4),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
        thumbColor: WidgetStatePropertyAll(scheme.onPrimary),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
