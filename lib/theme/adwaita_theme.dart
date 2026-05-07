import 'package:flutter/material.dart';

class AdwaitaColors {
  static const accent = Color(0xFF3584E4);
  static const warning = Color(0xFFE5A50A);
  static const destructive = Color(0xFFC01C28);
  static const success = Color(0xFF26A269);

  static const darkWindow = Color(0xFF242424);
  static const darkView = Color(0xFF1E1E1E);
  static const darkHeader = Color(0xFF303030);
  static const darkSidebar = Color(0xFF2A2A2A);
  static const darkBorder = Color(0xFF3D3D3D);
  static const darkMuted = Color(0xFFB8B8B8);

  static const terminalBackground = Color(0xFF300A24);
  static const terminalForeground = Color(0xFFF6F5F4);
  static const terminalSelection = Color(0x665E5C64);
}

class AdwaitaTheme {
  static ThemeData dark() {
    return _buildDarkTheme();
  }

  static ThemeData _buildDarkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AdwaitaColors.accent,
      brightness: Brightness.dark,
      primary: AdwaitaColors.accent,
      surface: AdwaitaColors.darkWindow,
      error: AdwaitaColors.destructive,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme.copyWith(
        surface: AdwaitaColors.darkWindow,
        surfaceContainer: AdwaitaColors.darkView,
        surfaceContainerHighest: AdwaitaColors.darkSidebar,
        outline: AdwaitaColors.darkBorder,
        outlineVariant: AdwaitaColors.darkBorder,
      ),
      scaffoldBackgroundColor: AdwaitaColors.darkWindow,
      fontFamily: 'Cantarell',
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(fontSize: 15),
        bodyMedium: TextStyle(fontSize: 14),
        bodySmall: TextStyle(fontSize: 13),
      ).apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
        backgroundColor: AdwaitaColors.darkHeader,
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AdwaitaColors.darkView,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AdwaitaColors.darkBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AdwaitaColors.darkView,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AdwaitaColors.darkSidebar,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AdwaitaColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AdwaitaColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AdwaitaColors.accent, width: 2),
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AdwaitaColors.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: Colors.white,
        minVerticalPadding: 8,
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AdwaitaColors.darkView,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.42),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AdwaitaColors.darkBorder),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AdwaitaColors.darkHeader,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: AdwaitaColors.accent,
      ),
    );
  }
}
