import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'design_tokens.dart';

/// Семантические цвета, которых нет в [ColorScheme].
///
/// Числовые значения — `docs/design/variant-10/tokens.json`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceHover,
    required this.field,
    required this.border,
    required this.controlBorder,
    required this.text,
    required this.textMuted,
    required this.primary,
    required this.onPrimary,
    required this.selection,
    required this.selectionSurface,
    required this.success,
    required this.warning,
    required this.error,
    required this.primaryTop,
    required this.primaryBottom,
  });

  /// Промежутки и основа workspace.
  final Color canvas;

  /// Верхние панели, карточки, редактор.
  final Color surface;

  /// Приподнятые кнопки и токены ключевых слов.
  final Color surfaceRaised;

  /// Наведение на интерактивную поверхность.
  final Color surfaceHover;

  /// Углублённое поле ввода.
  final Color field;

  /// Декоративный разделитель.
  final Color border;

  /// Граница контрола там, где она нужна для распознавания.
  final Color controlBorder;

  /// Основной текст.
  final Color text;

  /// Второстепенный текст. Не ослаблять дополнительной прозрачностью.
  final Color textMuted;

  /// Основное действие и акцент.
  final Color primary;

  /// Текст на primary.
  final Color onPrimary;

  /// Выделение и фокус.
  final Color selection;

  /// Слабая заливка выделенной поверхности.
  final Color selectionSurface;

  final Color success;
  final Color warning;
  final Color error;

  /// Верх и низ мягкого перехода основной кнопки.
  final Color primaryTop;
  final Color primaryBottom;

  static AppPalette of(BuildContext context) {
    return Theme.of(context).extension<AppPalette>() ?? dark;
  }

  static const AppPalette dark = AppPalette(
    canvas: Color(0xFF1B2228),
    surface: Color(0xFF252D34),
    surfaceRaised: Color(0xFF303A44),
    surfaceHover: Color(0xFF384550),
    field: Color(0xFF1D252C),
    border: Color(0xFF455361),
    controlBorder: Color(0xFF76899B),
    text: Color(0xFFEDF2F7),
    textMuted: Color(0xFFB3C0CC),
    primary: Color(0xFFB9CEE5),
    onPrimary: Color(0xFF17232F),
    selection: Color(0xFF83B9F2),
    selectionSurface: Color(0xFF2A4057),
    success: Color(0xFF87D5AA),
    warning: Color(0xFFF2CA7D),
    error: Color(0xFFF2969C),
    primaryTop: Color(0xFFCCDCF0),
    primaryBottom: Color(0xFFAFC4DE),
  );

  /// Светлая тема не утверждалась отдельно: сохраняем рабочие светлые
  /// поверхности, переносим те же семантические роли и читаемый акцент.
  static const AppPalette light = AppPalette(
    canvas: Color(0xFFEEF1F4),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF5F7F9),
    surfaceHover: Color(0xFFE9EEF2),
    field: Color(0xFFF1F4F7),
    border: Color(0xFFD8DFE5),
    controlBorder: Color(0xFF8B98A6),
    text: Color(0xFF17232F),
    textMuted: Color(0xFF55636F),
    primary: Color(0xFF137FEC),
    onPrimary: Color(0xFFFFFFFF),
    selection: Color(0xFF137FEC),
    selectionSurface: Color(0xFFE3F0FE),
    success: Color(0xFF15803D),
    warning: Color(0xFFB45309),
    error: Color(0xFFB91C1C),
    primaryTop: Color(0xFF137FEC),
    primaryBottom: Color(0xFF137FEC),
  );

  @override
  AppPalette copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceHover,
    Color? field,
    Color? border,
    Color? controlBorder,
    Color? text,
    Color? textMuted,
    Color? primary,
    Color? onPrimary,
    Color? selection,
    Color? selectionSurface,
    Color? success,
    Color? warning,
    Color? error,
    Color? primaryTop,
    Color? primaryBottom,
  }) {
    return AppPalette(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      field: field ?? this.field,
      border: border ?? this.border,
      controlBorder: controlBorder ?? this.controlBorder,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      selection: selection ?? this.selection,
      selectionSurface: selectionSurface ?? this.selectionSurface,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      primaryTop: primaryTop ?? this.primaryTop,
      primaryBottom: primaryBottom ?? this.primaryBottom,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return AppPalette(
      canvas: mix(canvas, other.canvas),
      surface: mix(surface, other.surface),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      surfaceHover: mix(surfaceHover, other.surfaceHover),
      field: mix(field, other.field),
      border: mix(border, other.border),
      controlBorder: mix(controlBorder, other.controlBorder),
      text: mix(text, other.text),
      textMuted: mix(textMuted, other.textMuted),
      primary: mix(primary, other.primary),
      onPrimary: mix(onPrimary, other.onPrimary),
      selection: mix(selection, other.selection),
      selectionSurface: mix(selectionSurface, other.selectionSurface),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      error: mix(error, other.error),
      primaryTop: mix(primaryTop, other.primaryTop),
      primaryBottom: mix(primaryBottom, other.primaryBottom),
    );
  }
}

/// Тема StockFlow: графитовая основа, светлый пыльно-синий акцент.
class AppTheme {
  static const primaryColor = Color(0xFFB9CEE5);

  static const bgLight = Color(0xFFEEF1F4);
  static const bgDark = Color(0xFF1B2228);

  static const sidebarLight = Color(0xFFFFFFFF);
  static const sidebarDark = Color(0xFF252D34);

  static const textLight = Color(0xFF17232F);
  static const textDark = Color(0xFFEDF2F7);

  static const borderLight = Color(0xFFD8DFE5);
  static const borderDark = Color(0xFF455361);

  static const successColor = Color(0xFF15803D);
  static const successColorDark = Color(0xFF87D5AA);
  static const errorColor = Color(0xFFB91C1C);
  static const errorColorDark = Color(0xFFF2969C);
  static const warningColor = Color(0xFFB45309);
  static const warningColorDark = Color(0xFFF2CA7D);

  static ThemeData get lightTheme => _build(light: true);

  static ThemeData get darkTheme => _build(light: false);

  static ThemeData _build({required bool light}) {
    final palette = light ? AppPalette.light : AppPalette.dark;
    final brightness = light ? Brightness.light : Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: palette.primary,
      onPrimary: palette.onPrimary,
      secondary: palette.selection,
      onSecondary: palette.onPrimary,
      error: palette.error,
      onError: light ? Colors.white : const Color(0xFF2A1113),
      surface: palette.surface,
      onSurface: palette.text,
      surfaceContainerHighest: palette.surfaceRaised,
      surfaceContainerHigh: palette.surfaceRaised,
      surfaceContainer: palette.surface,
      surfaceContainerLow: palette.canvas,
      surfaceContainerLowest: palette.canvas,
      outline: palette.border,
      outlineVariant: light
          ? const Color(0xFFE4E9ED)
          : const Color(0xFF333D47),
      errorContainer: light ? const Color(0xFFFBE6E7) : const Color(0xFF4A2428),
      onErrorContainer: light
          ? const Color(0xFF8C1D22)
          : const Color(0xFFF7C9CC),
    );

    final baseTextTheme = GoogleFonts.interTextTheme(
      light ? ThemeData.light().textTheme : ThemeData.dark().textTheme,
    );
    final textTheme = baseTextTheme
        .copyWith(
          displaySmall: baseTextTheme.displaySmall?.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
          titleLarge: baseTextTheme.titleLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
          titleMedium: baseTextTheme.titleMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
          bodyMedium: baseTextTheme.bodyMedium?.copyWith(
            fontSize: 14,
            height: 1.4,
          ),
          bodySmall: baseTextTheme.bodySmall?.copyWith(
            fontSize: 12,
            height: 1.35,
          ),
          labelLarge: baseTextTheme.labelLarge?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
          labelMedium: baseTextTheme.labelMedium?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        )
        .apply(bodyColor: palette.text, displayColor: palette.text);

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.canvas,
      canvasColor: palette.canvas,
      extensions: <ThemeExtension<dynamic>>[palette],
      textTheme: textTheme,
      iconTheme: IconThemeData(color: palette.textMuted, size: 18),
      dividerTheme: DividerThemeData(
        color: palette.border,
        thickness: AppStroke.normal,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(0, AppSizes.controlHeight),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          ),
          shape: WidgetStatePropertyAll(controlShape),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return palette.surfaceRaised.withValues(alpha: 0.6);
            }
            if (states.contains(WidgetState.pressed)) {
              return palette.primaryBottom;
            }
            return palette.primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.disabled)
                ? palette.textMuted
                : palette.onPrimary;
          }),
          overlayColor: WidgetStatePropertyAll(
            palette.onPrimary.withValues(alpha: 0.08),
          ),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSizes.controlHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          foregroundColor: palette.text,
          backgroundColor: palette.surfaceRaised,
          side: BorderSide(
            color: palette.controlBorder,
            width: AppStroke.normal,
          ),
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppSizes.controlHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          foregroundColor: palette.text,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(AppSizes.iconHitArea, AppSizes.iconHitArea),
          foregroundColor: palette.textMuted,
          highlightColor: palette.surfaceHover,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.field,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        hintStyle: TextStyle(color: palette.textMuted, fontSize: 13),
        labelStyle: TextStyle(color: palette.textMuted, fontSize: 13),
        floatingLabelStyle: TextStyle(color: palette.text, fontSize: 13),
        helperStyle: TextStyle(color: palette.textMuted, fontSize: 12),
        errorStyle: TextStyle(color: palette.error, fontSize: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: palette.controlBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: palette.controlBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(
            color: palette.selection,
            width: AppStroke.focus,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: palette.border),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: palette.controlBorder, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.selection
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(
          light ? Colors.white : palette.onPrimary,
        ),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: palette.border),
        ),
        textStyle: TextStyle(color: palette.text, fontSize: 12),
        waitDuration: const Duration(milliseconds: 500),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        textStyle: TextStyle(color: palette.text, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: palette.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceRaised,
        contentTextStyle: TextStyle(color: palette.text, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.primary,
        linearTrackColor: palette.field,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          palette.controlBorder.withValues(alpha: 0.6),
        ),
        radius: const Radius.circular(AppRadius.card),
        thickness: const WidgetStatePropertyAll(8),
      ),
      dividerColor: palette.border,
    );
  }
}
