import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'daily_text.dart';
import 'daily_text_cache_manager.dart';

/// Language configuration for Watchtower Online Library (WOL).
class WolLanguage {
  const WolLanguage({
    required this.name,
    required this.nativeName,
    required this.locale,
    required this.rsconf,
  });

  final String name;
  final String nativeName;
  final String locale;
  final String rsconf;

  static const List<WolLanguage> supportedLanguages = [
    WolLanguage(name: 'English', nativeName: 'English', locale: 'e', rsconf: '1'),
    WolLanguage(
      name: 'Pidgin (West Africa)',
      nativeName: 'Pidgin (West Africa)',
      locale: 'pgw',
      rsconf: '429',
    ),
    WolLanguage(name: 'Spanish', nativeName: 'Español', locale: 's', rsconf: '4'),
    WolLanguage(name: 'French', nativeName: 'Français', locale: 'f', rsconf: '30'),
    WolLanguage(name: 'German', nativeName: 'Deutsch', locale: 'x', rsconf: '10'),
    WolLanguage(name: 'Portuguese', nativeName: 'Português', locale: 't', rsconf: '5'),
    WolLanguage(name: 'Italian', nativeName: 'Italiano', locale: 'i', rsconf: '6'),
    WolLanguage(name: 'Japanese', nativeName: '日本語', locale: 'j', rsconf: '7'),
    WolLanguage(name: 'Tagalog', nativeName: 'Tagalog', locale: 'tg', rsconf: '27'),
    WolLanguage(name: 'Russian', nativeName: 'Русский', locale: 'u', rsconf: '32'),
  ];
}

/// Network service that fetches Jehovah's Witnesses daily text content
/// from the public Watchtower Online Library JSON endpoint, with integrated
/// offline caching via [DailyTextCacheManager].
class DailyTextService {
  DailyTextService({
    this.rsconf = '1',
    this.locale = 'e',
    DailyTextCacheManager? cacheManager,
  }) : cacheManager = cacheManager ?? DailyTextCacheManager();

  /// WOL's region/subdomain code for the language edition (e.g. '1' = English).
  final String rsconf;

  /// WOL's locale code for the language edition (e.g. 'e' = English).
  final String locale;

  /// Local caching layer for persistent offline storage.
  final DailyTextCacheManager cacheManager;

  static const int _maxRetries = 2;
  static const Duration _requestTimeout = Duration(seconds: 12);

  /// Builds the candidate URLs for fetching daily text for [date].
  List<Uri> _buildCandidateUris(DateTime date, String targetRsconf, String targetLocale) {
    final year = date.year;
    final month = date.month;
    final day = date.day;
    final path = 'wol/dt/r$targetRsconf/lp-$targetLocale/$year/$month/$day';

    final uris = <Uri>[];

    if (kIsWeb) {
      // In web applet environment, relative /wol-proxy/ routes through local nginx
      uris.add(Uri.parse('/wol-proxy/$path'));
    }

    // Direct official endpoint
    uris.add(Uri.parse('https://wol.jw.org/$path'));

    // Optional web CORS fallback proxy if direct connection fails on web
    if (kIsWeb) {
      uris.add(Uri.parse(
        'https://api.allorigins.win/raw?url=${Uri.encodeComponent('https://wol.jw.org/$path')}',
      ));
    }

    return uris;
  }

  /// Fetches the daily text for [date] (defaults to today).
  ///
  /// Flow:
  /// 1. If [forceRefresh] is false, checks local offline cache first.
  /// 2. If not found or forced, fetches from network with retries.
  /// 3. On network success, saves the scripture to offline cache.
  /// 4. On network failure, falls back to local cache or last known entry.
  Future<DailyText> fetchDailyText({
    DateTime? date,
    bool forceRefresh = false,
    String? overrideRsconf,
    String? overrideLocale,
  }) async {
    final targetDate = date ?? DateTime.now();
    final activeRsconf = overrideRsconf ?? rsconf;
    final activeLocale = overrideLocale ?? locale;

    // 1. Check local offline cache
    if (!forceRefresh) {
      final cached = await cacheManager.get(
        targetDate,
        rsconf: activeRsconf,
        locale: activeLocale,
      );
      if (cached != null) {
        return cached.copyWith(isCached: true);
      }
    }

    // 2. Fetch from network
    Object? lastError;
    final candidateUris = _buildCandidateUris(targetDate, activeRsconf, activeLocale);

    for (final uri in candidateUris) {
      for (var attempt = 0; attempt <= _maxRetries; attempt++) {
        try {
          final response = await http.get(
            uri,
            headers: {
              'Accept': 'application/json, text/plain, */*',
              'User-Agent': 'JWDailyText/1.0 (Android/Flutter)',
            },
          ).timeout(_requestTimeout);

          if (response.statusCode != 200) {
            throw DailyTextException('WOL returned HTTP ${response.statusCode}');
          }

          final decoded = jsonDecode(response.body);
          if (decoded is! Map<String, dynamic>) {
            throw const DailyTextException('Invalid response format from WOL');
          }

          final items = decoded['items'] as List?;
          if (items == null || items.isEmpty) {
            throw DailyTextException('No daily text items found for $targetDate');
          }

          final item = items.first as Map<String, dynamic>;
          final dailyText = DailyText.fromJson(
            item,
            targetDate,
            rsconf: activeRsconf,
            locale: activeLocale,
          );

          // Save to persistent offline cache
          await cacheManager.save(dailyText);

          return dailyText;
        } catch (error) {
          lastError = error;
          if (attempt < _maxRetries) {
            await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
          }
        }
      }
    }

    // 3. Fallback to cached data if network failed completely
    final fallbackCache = await cacheManager.get(
      targetDate,
      rsconf: activeRsconf,
      locale: activeLocale,
    ) ?? await cacheManager.getLastSaved();

    if (fallbackCache != null) {
      return fallbackCache.copyWith(isCached: true);
    }

    throw DailyTextException('Failed to fetch daily text from WOL: $lastError');
  }

  /// Prefetches a range of upcoming days to ensure offline availability.
  Future<int> prefetchDays({
    required DateTime startDate,
    int count = 7,
  }) async {
    int saved = 0;
    for (int i = 0; i < count; i++) {
      final date = startDate.add(Duration(days: i));
      try {
        final hasCached = await cacheManager.hasCache(date, rsconf: rsconf, locale: locale);
        if (!hasCached) {
          await fetchDailyText(date: date, forceRefresh: true);
          saved++;
        }
      } catch (e) {
        debugPrint('Prefetch failed for date $date: $e');
      }
    }
    return saved;
  }

  /// Retrieves all cached daily text records for offline reading.
  Future<List<DailyText>> getAllCachedEntries() =>
      cacheManager.getAllCachedEntries(rsconf: rsconf, locale: locale);

  /// Clears stored offline cache entries.
  Future<void> clearCache() => cacheManager.clearAll(rsconf: rsconf, locale: locale);
}

/// Thrown when the daily text cannot be fetched or parsed.
class DailyTextException implements Exception {
  const DailyTextException(this.message);

  final String message;

  @override
  String toString() => 'DailyTextException: $message';
}
