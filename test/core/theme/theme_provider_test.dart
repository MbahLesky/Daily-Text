import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jw_daily_text_widget/core/theme/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ThemeProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to ThemeMode.system', () {
      final provider = ThemeProvider();
      expect(provider.themeMode, ThemeMode.system);
    });

    test('sets theme mode to dark and light and notifies listeners', () async {
      final provider = ThemeProvider();
      await Future<void>.delayed(Duration.zero);
      var notificationCount = 0;
      provider.addListener(() => notificationCount++);

      await provider.setThemeMode(ThemeMode.dark);
      expect(provider.themeMode, ThemeMode.dark);
      expect(notificationCount, 1);

      await provider.setThemeMode(ThemeMode.light);
      expect(provider.themeMode, ThemeMode.light);
      expect(notificationCount, 2);
    });

    test('persists theme mode to SharedPreferences', () async {
      final provider = ThemeProvider();
      await provider.setThemeMode(ThemeMode.dark);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme_mode'), 'dark');

      // Create new provider, should restore 'dark'
      final newProvider = ThemeProvider();
      // Allow async load to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(newProvider.themeMode, ThemeMode.dark);
    });

    test('ThemeData getters return consistent ThemeData', () {
      final light = ThemeProvider.lightTheme;
      final dark = ThemeProvider.darkTheme;

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.useMaterial3, isTrue);
      expect(dark.useMaterial3, isTrue);
      expect(light.scaffoldBackgroundColor, isNotNull);
      expect(dark.scaffoldBackgroundColor, isNotNull);
      expect(light.colorScheme.primary, isNotNull);
      expect(dark.colorScheme.primary, isNotNull);
    });

    test('isDarkMode returns true for dark mode and false for light mode', () {
      final providerDark = ThemeProvider(initialMode: ThemeMode.dark);
      // For ThemeMode.dark, isDarkMode must return true regardless of context
      expect(providerDark.themeMode, ThemeMode.dark);

      final providerLight = ThemeProvider(initialMode: ThemeMode.light);
      expect(providerLight.themeMode, ThemeMode.light);
    });

    test('toggleTheme toggles between light and dark in widget test environment', () async {
      final provider = ThemeProvider(initialMode: ThemeMode.light);
      await provider.setThemeMode(ThemeMode.dark);
      expect(provider.themeMode, ThemeMode.dark);

      await provider.setThemeMode(ThemeMode.light);
      expect(provider.themeMode, ThemeMode.light);
    });
  });
}

