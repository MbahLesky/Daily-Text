import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'daily_text.dart';

/// Local caching service using SharedPreferences to store fetched daily scriptures
/// and comments so they remain fully accessible when the device is offline.
class DailyTextCacheManager {
  DailyTextCacheManager({SharedPreferences? preferences}) : _prefs = preferences;

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  /// Formats date to a standardized ISO date key (YYYY-MM-DD).
  static String formatDateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _cacheKey(DateTime date, String rsconf, String locale) {
    return 'jw_dt_cache_${rsconf}_${locale}_${formatDateKey(date)}';
  }

  static String _indexKey(String rsconf, String locale) {
    return 'jw_dt_index_${rsconf}_$locale';
  }

  static const String _lastKnownKey = 'jw_dt_last_known_entry';

  /// Saves a [DailyText] into local storage and updates the cache index.
  Future<void> save(DailyText dailyText) async {
    try {
      final prefs = await _getPrefs();
      final dateKey = formatDateKey(dailyText.date);
      final key = _cacheKey(dailyText.date, dailyText.rsconf, dailyText.locale);
      final jsonString = jsonEncode(dailyText.toJson());

      // Save item data
      await prefs.setString(key, jsonString);

      // Save as latest known entry for fallback
      await prefs.setString(_lastKnownKey, jsonString);

      // Maintain list of cached dates for offline browsing
      final indexKey = _indexKey(dailyText.rsconf, dailyText.locale);
      final existingIndex = prefs.getStringList(indexKey) ?? <String>[];
      if (!existingIndex.contains(dateKey)) {
        final updatedIndex = List<String>.from(existingIndex)..add(dateKey);
        updatedIndex.sort();
        await prefs.setStringList(indexKey, updatedIndex);
      }
    } catch (e) {
      debugPrint('DailyTextCacheManager: Error saving daily text: $e');
    }
  }

  /// Retrieves cached daily text for a given [date] and language edition.
  Future<DailyText?> get(
    DateTime date, {
    String rsconf = '1',
    String locale = 'e',
  }) async {
    try {
      final prefs = await _getPrefs();
      final key = _cacheKey(date, rsconf, locale);
      final raw = prefs.getString(key);
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return DailyText.fromCache(map);
      }
    } catch (e) {
      debugPrint('DailyTextCacheManager: Error retrieving cache: $e');
    }
    return null;
  }

  /// Checks if a cache entry exists for the given [date].
  Future<bool> hasCache(
    DateTime date, {
    String rsconf = '1',
    String locale = 'e',
  }) async {
    try {
      final prefs = await _getPrefs();
      final key = _cacheKey(date, rsconf, locale);
      return prefs.containsKey(key);
    } catch (_) {
      return false;
    }
  }

  /// Retrieves the most recently viewed or saved daily text entry.
  /// Used as a resilient offline fallback when the specific target date is not cached.
  Future<DailyText?> getLastSaved() async {
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(_lastKnownKey);
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return DailyText.fromCache(map);
      }
    } catch (_) {}
    return null;
  }

  /// Retrieves all cached dates currently available offline for the specified language.
  Future<List<DateTime>> getCachedDates({
    String rsconf = '1',
    String locale = 'e',
  }) async {
    try {
      final prefs = await _getPrefs();
      final indexKey = _indexKey(rsconf, locale);
      final list = prefs.getStringList(indexKey) ?? <String>[];
      final dates = <DateTime>[];
      for (final item in list) {
        final parsed = DateTime.tryParse(item);
        if (parsed != null) dates.add(parsed);
      }
      dates.sort((a, b) => b.compareTo(a)); // Descending order
      return dates;
    } catch (_) {
      return [];
    }
  }

  /// Retrieves all cached daily text records for offline reading.
  Future<List<DailyText>> getAllCachedEntries({
    String rsconf = '1',
    String locale = 'e',
  }) async {
    final dates = await getCachedDates(rsconf: rsconf, locale: locale);
    final entries = <DailyText>[];
    for (final d in dates) {
      final item = await get(d, rsconf: rsconf, locale: locale);
      if (item != null) entries.add(item);
    }
    return entries;
  }

  /// Returns the total count of offline cached scriptures.
  Future<int> getCachedCount({
    String rsconf = '1',
    String locale = 'e',
  }) async {
    final dates = await getCachedDates(rsconf: rsconf, locale: locale);
    return dates.length;
  }

  /// Removes an entry from offline storage.
  Future<void> remove(
    DateTime date, {
    String rsconf = '1',
    String locale = 'e',
  }) async {
    try {
      final prefs = await _getPrefs();
      final dateKey = formatDateKey(date);
      final key = _cacheKey(date, rsconf, locale);
      await prefs.remove(key);

      final indexKey = _indexKey(rsconf, locale);
      final list = prefs.getStringList(indexKey) ?? <String>[];
      if (list.contains(dateKey)) {
        final updated = List<String>.from(list)..remove(dateKey);
        await prefs.setStringList(indexKey, updated);
      }
    } catch (_) {}
  }

  /// Clears all stored daily texts for the specified language or all languages.
  Future<void> clearAll({String? rsconf, String? locale}) async {
    try {
      final prefs = await _getPrefs();
      final keys = prefs.getKeys();

      for (final key in keys) {
        if (key.startsWith('jw_dt_cache_') || key.startsWith('jw_dt_index_') || key == _lastKnownKey) {
          if (rsconf != null && locale != null) {
            if (key.contains('_${rsconf}_$locale')) {
              await prefs.remove(key);
            }
          } else {
            await prefs.remove(key);
          }
        }
      }
    } catch (_) {}
  }
}
