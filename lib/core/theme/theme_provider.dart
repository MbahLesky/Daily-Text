import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for managing global application theme mode (System, Light, Dark)
/// with persistence via [SharedPreferences].
class ThemeProvider extends ChangeNotifier {
  ThemeProvider({ThemeMode initialMode = ThemeMode.system})
      : _themeMode = initialMode {
    _loadThemeMode();
  }

  static const String _prefThemeKey = 'app_theme_mode';

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  /// Returns true if currently resolved appearance is dark.
  bool isDarkMode(BuildContext context) {
    if (_themeMode == ThemeMode.dark) return true;
    if (_themeMode == ThemeMode.light) return false;
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }

  /// Updates the global theme mode and saves the choice to SharedPreferences.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final modeString = switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
      await prefs.setString(_prefThemeKey, modeString);
    } catch (e) {
      debugPrint('Error saving theme mode to SharedPreferences: $e');
    }
  }

  /// Toggles between light and dark mode.
  Future<void> toggleTheme(BuildContext context) async {
    final currentlyDark = isDarkMode(context);
    await setThemeMode(currentlyDark ? ThemeMode.light : ThemeMode.dark);
  }

  /// Loads the persisted theme mode from SharedPreferences.
  Future<void> _loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_prefThemeKey);
      if (savedMode != null) {
        final parsed = switch (savedMode) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };
        if (_themeMode != parsed) {
          _themeMode = parsed;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error loading theme mode from SharedPreferences: $e');
    }
  }

  /// Centralized light theme definition.
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF385E8E),
        primary: const Color(0xFF2C4D75),
        secondary: const Color(0xFFB57C2F),
        surface: const Color(0xFFF8F9FA),
        surfaceContainerHighest: const Color(0xFFE9ECEF),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF4F6F9),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Color(0xFF2C4D75),
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: const Color(0xFF2C4D75).withOpacity(0.15),
            width: 1,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
      ),
    );
  }

  /// Centralized dark theme definition.
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF385E8E),
        primary: const Color(0xFF7EA9DE),
        secondary: const Color(0xFFE5B869),
        surface: const Color(0xFF161B22),
        surfaceContainerHighest: const Color(0xFF212836),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0F1217),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Color(0xFF18202B),
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFF1A212B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: const Color(0xFF7EA9DE).withOpacity(0.25),
            width: 1,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF1B232F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF18202C),
      ),
    );
  }
}
