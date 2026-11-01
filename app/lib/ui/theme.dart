import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Colour roles from the PyCrow design system. Widgets read roles, never hex:
/// `AppColors.of(context).muted`. Light and dark follow the OS.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.surface,
    required this.raised,
    required this.raisedAlt,
    required this.raisedTinted,
    required this.hairline,
    required this.hairlineStrong,
    required this.ink,
    required this.muted,
    required this.placeholder,
    required this.inkDisabled,
    required this.accent,
    required this.accentHover,
    required this.accentPress,
    required this.accentInk,
    required this.accentSoft,
    required this.accentSoftInk,
    required this.controlHover,
    required this.controlPress,
    required this.controlDisabled,
    required this.danger,
    required this.dangerSoft,
  });

  final Color surface, raised, raisedAlt, raisedTinted, hairline;
  final Color hairlineStrong, ink, muted, placeholder, inkDisabled;
  final Color accent, accentHover, accentPress, accentInk, accentSoft;
  final Color accentSoftInk, controlHover, controlPress, controlDisabled;
  final Color danger, dangerSoft;

  static const light = AppColors(
    surface: Color(0xfff3f6f8),
    raised: Color(0xffffffff),
    raisedAlt: Color(0xfff8fafb),
    raisedTinted: Color(0xfff1f8f6),
    hairline: Color(0xffdce4eb),
    hairlineStrong: Color(0xffc4d0da),
    ink: Color(0xff182b3a),
    muted: Color(0xff5c6b7a),
    placeholder: Color(0xff6b7885),
    inkDisabled: Color(0xff7f8c98),
    accent: Color(0xff0b7469),
    accentHover: Color(0xff0a6660),
    accentPress: Color(0xff08564f),
    accentInk: Color(0xffffffff),
    accentSoft: Color(0xffe5f3f0),
    accentSoftInk: Color(0xff15605a),
    controlHover: Color(0xffedf2f6),
    controlPress: Color(0xffe2e8ee),
    controlDisabled: Color(0xffedf1f4),
    danger: Color(0xffa82f1c),
    dangerSoft: Color(0xfffff0ec),
  );

  static const dark = AppColors(
    surface: Color(0xff121a21),
    raised: Color(0xff1a232b),
    raisedAlt: Color(0xff161f26),
    raisedTinted: Color(0xff16211f),
    hairline: Color(0xff2b3844),
    hairlineStrong: Color(0xff3a4a58),
    ink: Color(0xffe8eef3),
    muted: Color(0xff93a3b0),
    placeholder: Color(0xff8593a1),
    inkDisabled: Color(0xff657380),
    accent: Color(0xff2bb3a1),
    accentHover: Color(0xff31bdaa),
    accentPress: Color(0xff239789),
    accentInk: Color(0xff04211d),
    accentSoft: Color(0xff0e2a27),
    accentSoftInk: Color(0xff7fd8c9),
    controlHover: Color(0xff222d37),
    controlPress: Color(0xff2a3742),
    controlDisabled: Color(0xff1c252d),
    danger: Color(0xfff08a75),
    dangerSoft: Color(0xff2d1713),
  );

  static AppColors of(BuildContext context) => Theme.of(context).appColors;

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

/// PyCrow tempo: press 90, hover/focus 110, appear 180, travel 260 ms.
abstract final class Motion {
  static const fast = Duration(milliseconds: 110);
  static const base = Duration(milliseconds: 180);
  static const slow = Duration(milliseconds: 260);
  static const easeOut = Cubic(0.215, 0.61, 0.355, 1);
}

/// Faces by job: `text` for everything read or operated, `display` for the
/// app name and page titles, `mono` for data (CEFR, counts, shortcuts).
abstract final class AppFonts {
  static bool get _windows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  static String? get text => _windows ? 'Segoe UI Variable Text' : null;
  static String? get display => _windows ? 'Segoe UI Variable Display' : null;
  static String get mono => _windows ? 'Cascadia Mono' : 'monospace';
  static const fallback = ['Segoe UI', 'Roboto', 'Noto Sans', 'sans-serif'];
  static const monoFallback = ['Consolas', 'Roboto Mono', 'monospace'];

  // A phone is held further away than a tray popup; body text gains 1px.
  static double get bump => _windows ? 0 : 1;
}

extension AppText on ThemeData {
  /// Pages shown inside a plain MaterialApp (tests) get the matching palette.
  AppColors get appColors =>
      extension<AppColors>() ??
      (brightness == Brightness.dark ? AppColors.dark : AppColors.light);

  /// 19/28: the term and meaning a screen exists for.
  TextStyle get reading => textTheme.bodyLarge!.copyWith(
    fontSize: 19 + AppFonts.bump,
    height: 28 / 19,
  );

  /// 11/14 mono: CEFR levels, counts, shortcuts.
  TextStyle get code => TextStyle(
    fontFamily: AppFonts.mono,
    fontFamilyFallback: AppFonts.monoFallback,
    fontSize: 11 + AppFonts.bump,
    height: 14 / 11,
    color: appColors.muted,
  );
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.light ? AppColors.light : AppColors.dark;
  final b = AppFonts.bump;
  TextStyle text(double size, double line, FontWeight weight, Color color) =>
      TextStyle(
        fontFamily: AppFonts.text,
        fontFamilyFallback: AppFonts.fallback,
        fontSize: size + b,
        height: line / size,
        fontWeight: weight,
        color: color,
      );
  TextStyle display(double size, double line, FontWeight weight) => TextStyle(
    fontFamily: AppFonts.display,
    fontFamilyFallback: AppFonts.fallback,
    fontSize: size + b,
    height: line / size,
    fontWeight: weight,
    color: c.ink,
  );
  final title = display(23, 26, FontWeight.w700);
  final controlStrong = text(15, 20, FontWeight.w600, c.ink);
  final control = text(15, 20, FontWeight.w400, c.ink);
  final body = text(13, 18, FontWeight.w400, c.ink);
  final caption = text(11, 16, FontWeight.w600, c.muted);
  final label = body.copyWith(fontWeight: FontWeight.w600);
  final textTheme = TextTheme(
    displaySmall: display(30, 34, FontWeight.w700),
    headlineMedium: title,
    headlineSmall: title,
    titleLarge: display(15, 20, FontWeight.w600),
    titleMedium: controlStrong,
    titleSmall: label,
    bodyLarge: control,
    bodyMedium: body,
    bodySmall: caption.copyWith(fontWeight: FontWeight.w400, fontSize: 12 + b),
    labelLarge: label,
    labelMedium: caption,
    labelSmall: caption,
  );
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.accentInk,
    primaryContainer: c.accentSoft,
    onPrimaryContainer: c.accentSoftInk,
    secondary: c.accent,
    onSecondary: c.accentInk,
    secondaryContainer: c.accentSoft,
    onSecondaryContainer: c.accentSoftInk,
    tertiary: c.accentSoftInk,
    onTertiary: c.accentInk,
    error: c.danger,
    onError: c.raised,
    errorContainer: c.dangerSoft,
    onErrorContainer: c.danger,
    surface: c.raised,
    onSurface: c.ink,
    onSurfaceVariant: c.muted,
    surfaceContainerLowest: c.raised,
    surfaceContainerLow: c.raisedAlt,
    surfaceContainer: c.raisedAlt,
    surfaceContainerHigh: c.raised,
    surfaceContainerHighest: c.controlHover,
    outline: c.hairlineStrong,
    outlineVariant: c.hairline,
    shadow: const Color(0xff182b3a),
    inverseSurface: c.ink,
    onInverseSurface: c.surface,
    inversePrimary: c.accentSoft,
    surfaceTint: Colors.transparent,
  );
  const small = BorderRadius.all(Radius.circular(8));
  const large = BorderRadius.all(Radius.circular(12));
  WidgetStateProperty<T> states<T>(T rest, {T? hover, T? press, T? off}) =>
      WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return off ?? rest;
        if (s.contains(WidgetState.pressed)) return press ?? hover ?? rest;
        if (s.contains(WidgetState.hovered) ||
            s.contains(WidgetState.focused)) {
          return hover ?? rest;
        }
        return rest;
      });
  final focusRing = WidgetStateProperty.resolveWith<BorderSide?>(
    (s) => s.contains(WidgetState.focused)
        ? BorderSide(color: c.accent, width: 2)
        : null,
  );
  final buttonShape = WidgetStatePropertyAll<OutlinedBorder>(
    const RoundedRectangleBorder(borderRadius: small),
  );
  const buttonSize = WidgetStatePropertyAll(Size(64, 36));
  const buttonPadding = WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 16),
  );
  final field = OutlineInputBorder(
    borderRadius: small,
    borderSide: BorderSide(color: c.hairline),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: textTheme,
    fontFamily: AppFonts.text,
    fontFamilyFallback: AppFonts.fallback,
    extensions: [c],
    scaffoldBackgroundColor: c.surface,
    canvasColor: c.surface,
    dividerColor: c.hairline,
    hoverColor: c.controlHover,
    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.standard,
    dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: title.copyWith(fontSize: 19 + b),
      iconTheme: IconThemeData(color: c.muted, size: 20),
      actionsIconTheme: IconThemeData(color: c.muted, size: 20),
    ),
    cardTheme: CardThemeData(
      color: c.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      shadowColor: const Color(0x14182b3a),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: large,
        side: BorderSide(color: c.hairline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: states(
          c.accent,
          hover: c.accentHover,
          press: c.accentPress,
          off: c.controlDisabled,
        ),
        foregroundColor: states(c.accentInk, off: c.inkDisabled),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        textStyle: WidgetStatePropertyAll(label),
        shape: buttonShape,
        minimumSize: buttonSize,
        padding: buttonPadding,
        side: focusRing,
        elevation: states(0.0, hover: 2.0, press: 0.0),
        shadowColor: const WidgetStatePropertyAll(Color(0x33182b3a)),
        iconSize: const WidgetStatePropertyAll(16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: states(c.ink, off: c.inkDisabled),
        backgroundColor: states(
          c.raised,
          hover: c.controlHover,
          press: c.controlPress,
          off: c.raised,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStateProperty.resolveWith(
          (s) => BorderSide(
            color: s.contains(WidgetState.focused)
                ? c.accent
                : c.hairlineStrong,
            width: s.contains(WidgetState.focused) ? 2 : 1,
          ),
        ),
        textStyle: WidgetStatePropertyAll(label),
        shape: buttonShape,
        minimumSize: buttonSize,
        padding: buttonPadding,
        iconColor: states(c.muted, off: c.inkDisabled),
        iconSize: const WidgetStatePropertyAll(16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: states(c.ink, off: c.inkDisabled),
        backgroundColor: states(
          Colors.transparent,
          hover: c.controlHover,
          press: c.controlPress,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        textStyle: WidgetStatePropertyAll(label),
        shape: buttonShape,
        minimumSize: buttonSize,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12),
        ),
        side: focusRing,
        iconColor: states(c.muted, off: c.inkDisabled),
        iconSize: const WidgetStatePropertyAll(16),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: states(c.muted, off: c.inkDisabled),
        backgroundColor: states(
          Colors.transparent,
          hover: c.controlHover,
          press: c.controlPress,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: buttonShape,
        side: focusRing,
        iconSize: const WidgetStatePropertyAll(18),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.raised,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: field,
      enabledBorder: field,
      disabledBorder: field.copyWith(
        borderSide: BorderSide(color: c.controlDisabled),
      ),
      focusedBorder: field.copyWith(
        borderSide: BorderSide(color: c.accent, width: 2),
      ),
      errorBorder: field.copyWith(borderSide: BorderSide(color: c.danger)),
      labelStyle: body.copyWith(color: c.muted),
      floatingLabelStyle: caption.copyWith(color: c.accentSoftInk),
      hintStyle: control.copyWith(color: c.placeholder),
      helperStyle: textTheme.bodySmall,
      prefixIconColor: c.muted,
      suffixIconColor: c.muted,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.accentSoft,
      indicatorShape: const RoundedRectangleBorder(borderRadius: small),
      selectedIconTheme: IconThemeData(color: c.accentSoftInk, size: 20),
      unselectedIconTheme: IconThemeData(color: c.muted, size: 20),
      selectedLabelTextStyle: caption.copyWith(color: c.ink),
      unselectedLabelTextStyle: caption,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.raised,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.accentSoft,
      indicatorShape: const RoundedRectangleBorder(borderRadius: small),
      height: 64,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 20,
          color: s.contains(WidgetState.selected) ? c.accentSoftInk : c.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => caption.copyWith(
          color: s.contains(WidgetState.selected) ? c.ink : c.muted,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.raisedAlt,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: large,
        side: BorderSide(color: c.hairline),
      ),
      titleTextStyle: display(19, 24, FontWeight.w600),
      contentTextStyle: body,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: small,
        side: BorderSide(color: c.hairline),
      ),
      textStyle: body,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.raised),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: small,
            side: BorderSide(color: c.hairline),
          ),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: body.copyWith(color: c.surface),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: small),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: c.ink, borderRadius: small),
      textStyle: caption.copyWith(color: c.surface),
      waitDuration: const Duration(milliseconds: 400),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.muted,
      titleTextStyle: controlStrong,
      subtitleTextStyle: body.copyWith(color: c.muted),
      shape: const RoundedRectangleBorder(borderRadius: small),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.controlHover,
      side: BorderSide.none,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      labelStyle: caption.copyWith(color: c.ink),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: states(c.raised, off: c.controlDisabled),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.hairlineStrong,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(c.accentInk),
      side: BorderSide(color: c.hairlineStrong, width: 1.5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: c.accentSoft,
      linearMinHeight: 3,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionColor: c.accent.withValues(alpha: 0.2),
      selectionHandleColor: c.accent,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}
