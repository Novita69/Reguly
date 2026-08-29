// lib/shared/themes/app_theme.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // ── Colour tokens ──────────────────────────────────────────────
  static const primary   = Color(0xFF5C4DFF);
  static const secondary = Color(0xFF4ECDC4);
  static const success   = Color(0xFF10B981);
  static const warning   = Color(0xFFF59E0B);
  static const error     = Color(0xFFEF4444);

  // Light surface tokens
  static const bgLight   = Color(0xFFF5F7FA);
  static const cardLight = Color(0xFFFFFFFF);
  static const darkText  = Color(0xFF1A1A2E);
  static const greyText  = Color(0xFF6B7280);

  // Dark surface tokens
  static const bgDark    = Color(0xFF0F0F1A);
  static const cardDark  = Color(0xFF1A1A2E);
  static const darkCard2 = Color(0xFF252542);

  // ── Shared helpers ─────────────────────────────────────────────
  static InputDecorationTheme _inputDecoration(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF252542) : Colors.white,
      hintStyle: TextStyle(
        color: isDark ? Colors.white38 : const Color(0xFFADB5BD),
        fontSize: 14,
      ),
      labelStyle: TextStyle(
        color: isDark ? Colors.white70 : const Color(0xFF6B7280),
      ),
      prefixIconColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.focused)) return primary;
        return isDark ? Colors.white38 : const Color(0xFFADB5BD);
      }),
      suffixIconColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.focused)) return primary;
        return isDark ? Colors.white38 : const Color(0xFFADB5BD);
      }),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      errorStyle: const TextStyle(color: error, fontSize: 12),
    );
  }

  static ElevatedButtonThemeData get _elevatedBtn => ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  );

  static TextButtonThemeData _textBtn(Brightness b) => TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: primary,
      textStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
  );

  static ChipThemeData _chipTheme(Brightness b) {
    final isDark = b == Brightness.dark;
    return ChipThemeData(
      backgroundColor: isDark ? const Color(0xFF252542) : const Color(0xFFF0EFFF),
      labelStyle: TextStyle(
        color: isDark ? Colors.white70 : darkText,
        fontSize: 12,
      ),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  static CardThemeData _cardTheme(Brightness b) {
    final isDark = b == Brightness.dark;
    return CardThemeData(
      color: isDark ? cardDark : cardLight,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: EdgeInsets.zero,
    );
  }

  // ── Light Theme ────────────────────────────────────────────────
  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        secondary: secondary,
        brightness: Brightness.light,
        error: error,
        surface: cardLight,
      ),
      scaffoldBackgroundColor: bgLight,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: darkText,
        displayColor: darkText,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: darkText,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: darkText,
        ),
        iconTheme: IconThemeData(color: darkText),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      ),
      elevatedButtonTheme: _elevatedBtn,
      textButtonTheme: _textBtn(Brightness.light),
      inputDecorationTheme: _inputDecoration(Brightness.light),
      cardTheme: _cardTheme(Brightness.light),
      chipTheme: _chipTheme(Brightness.light),
      dividerColor: const Color(0xFFE5E7EB),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primary,
        unselectedItemColor: Color(0xFFADB5BD),
        elevation: 0,
        showSelectedLabels: true,
        showUnselectedLabels: true,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkText,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Dark Theme ─────────────────────────────────────────────────
  static ThemeData get darkTheme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        secondary: secondary,
        brightness: Brightness.dark,
        error: error,
        surface: cardDark,
      ),
      scaffoldBackgroundColor: bgDark,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: cardDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        iconTheme: IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      elevatedButtonTheme: _elevatedBtn,
      textButtonTheme: _textBtn(Brightness.dark),
      inputDecorationTheme: _inputDecoration(Brightness.dark),
      cardTheme: _cardTheme(Brightness.dark),
      chipTheme: _chipTheme(Brightness.dark),
      dividerColor: Colors.white12,
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: cardDark,
        selectedItemColor: primary,
        unselectedItemColor: Color(0xFF6B7280),
        elevation: 0,
        showSelectedLabels: true,
        showUnselectedLabels: true,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkCard2,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
