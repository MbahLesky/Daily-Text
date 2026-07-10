import 'dart:convert';

import 'package:http/http.dart' as http;

import 'daily_text.dart';

/// Fetches the Jehovah's Witnesses daily text from the public Watchtower
/// Online Library JSON endpoint.
///
/// This talks to an unofficial, undocumented endpoint used by wol.jw.org
/// itself — there's no official public API. `rsconf`/`locale` select the
/// language edition (defaults are English).
class DailyTextService {
  const DailyTextService({
    this.rsconf = '1',
    this.locale = 'e',
  });

  /// WOL's region/subdomain code for the language edition (e.g. '1' = English).
  final String rsconf;

  /// WOL's locale code for the language edition (e.g. 'e' = English).
  final String locale;

  static const _maxRetries = 2;
  static const _requestTimeout = Duration(seconds: 10);

  Uri _buildUri(DateTime date) => Uri.parse(
        'https://wol.jw.org/wol/dt/r$rsconf/lp-$locale'
        '/${date.year}/${date.month}/${date.day}',
      );

  /// Fetches the daily text for [date] (defaults to today).
  ///
  /// Retries transient failures with linear backoff before giving up.
  /// Throws [DailyTextException] if the request or parsing ultimately fails.
  Future<DailyText> fetchDailyText({DateTime? date}) async {
    final targetDate = date ?? DateTime.now();
    Object? lastError;

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final response =
            await http.get(_buildUri(targetDate)).timeout(_requestTimeout);

        if (response.statusCode != 200) {
          throw DailyTextException(
            'WOL returned HTTP ${response.statusCode}',
          );
        }

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final items = body['items'] as List?;
        if (items == null || items.isEmpty) {
          throw DailyTextException('No daily text found for $targetDate');
        }

        return DailyText.fromJson(
          items.first as Map<String, dynamic>,
          targetDate,
          rsconf: rsconf,
          locale: locale,
        );
      } catch (error) {
        lastError = error;
        if (attempt < _maxRetries) {
          await Future.delayed(Duration(seconds: attempt + 1));
        }
      }
    }

    throw DailyTextException('Failed to fetch daily text: $lastError');
  }
}

/// Thrown when the daily text can't be fetched or parsed.
class DailyTextException implements Exception {
  const DailyTextException(this.message);

  final String message;

  @override
  String toString() => 'DailyTextException: $message';
}
