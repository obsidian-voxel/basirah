import 'package:flutter/material.dart';

import 'blockp_theme.dart';

/// Legacy palette used by the image lab, analytics and partner screens.
///
/// The five main screens draw from [BpPalette]; these constants are kept so
/// the older tools keep one consistent look. Values are the BlockP ones.
abstract final class AppColors {
  static const primary = Color(0xFF2F6FEB);
  static const primaryDeep = Color(0xFF1B4FD8);
  static const primarySoft = Color(0xFFD6E5FD);
  static const accent = Color(0xFF57A9FF);
  static const success = Color(0xFF34C759);
  static const warning = Color(0xFFF0A020);
  static const danger = Color(0xFFD9603F);

  static const canvasTop = Color(0xFFEAF1FE);
  static const canvasBottom = Color(0xFFEAF1FE);
  static const surface = Colors.white;
  static const border = Color(0xFFE2E9F3);
  static const ink = Color(0xFF0B2A4D);
  static const muted = Color(0xFF5C6C80);

  static const darkCanvasTop = Color(0xFF1B2531);
  static const darkCanvasBottom = Color(0xFF1B2531);
  static const darkSurface = Color(0xFF253141);
  static const darkBorder = Color(0xFF37424F);
  static const darkInk = Color(0xFFFFFFFF);
  static const darkMuted = Color(0xFFA7B3C1);
}

extension AppPalette on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get paletteSurface => isDark ? AppColors.darkSurface : AppColors.surface;
  Color get paletteBorder => isDark ? AppColors.darkBorder : AppColors.border;
  Color get paletteInk => isDark ? AppColors.darkInk : AppColors.ink;
  Color get paletteMuted => isDark ? AppColors.darkMuted : AppColors.muted;
  Color get palettePrimary => isDark ? const Color(0xFF8FB4FF) : AppColors.primary;

  /// Flat BlockP canvas; the reference uses one solid colour, not a gradient.
  LinearGradient get canvasGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const [AppColors.darkCanvasTop, AppColors.darkCanvasBottom]
            : const [AppColors.canvasTop, AppColors.canvasBottom],
      );
}

ThemeData buildLightTheme() => _build(Brightness.light);

ThemeData buildDarkTheme() => _build(Brightness.dark);

ThemeData _build(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final palette = isDark ? BpPalette.dark : BpPalette.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: palette.primary,
    brightness: brightness,
  ).copyWith(
    primary: palette.primary,
    secondary: palette.primary,
    surface: palette.canvas,
    error: AppColors.danger,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.canvas,
    splashFactory: InkRipple.splashFactory,
    fontFamily: BpType.family,
    // Anek Latin carries no Arabic glyphs, so Amiri backs every text style
    // that contains Arabic.
    fontFamilyFallback: const [BpType.arabicFamily],
    extensions: [palette],
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: palette.ink,
      displayColor: palette.ink,
      fontFamily: BpType.family,
      fontFamilyFallback: const [BpType.arabicFamily],
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: BpType.title.copyWith(color: palette.ink),
      iconTheme: IconThemeData(color: palette.ink),
    ),
    dividerTheme: DividerThemeData(
      color: palette.divider,
      space: 1,
      thickness: 1,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.switchOn
            : palette.switchOff,
      ),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      hintStyle: BpType.body.copyWith(color: palette.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BpRadii.pill),
        borderSide: BorderSide(color: palette.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BpRadii.pill),
        borderSide: BorderSide(color: palette.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BpRadii.pill),
        borderSide: BorderSide(color: palette.primary, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BpRadii.pill),
        ),
        textStyle: BpType.button,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.ink,
        minimumSize: const Size(0, 52),
        side: BorderSide(color: palette.divider, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BpRadii.pill),
        ),
        textStyle: BpType.button,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.primary,
        textStyle: BpType.button,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BpRadii.dialog),
      ),
      titleTextStyle: BpType.title.copyWith(color: palette.ink),
      contentTextStyle: BpType.body.copyWith(color: palette.muted),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? palette.card : palette.ink,
      contentTextStyle: BpType.body.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BpRadii.inner),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: palette.card,
      side: BorderSide(color: palette.divider),
      shape: const StadiumBorder(),
      labelStyle: BpType.small.copyWith(color: palette.ink),
    ),
  );
}
