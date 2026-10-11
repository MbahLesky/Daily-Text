import 'package:flutter_test/flutter_test.dart';
import 'package:jw_daily_text_widget/features/daily_text/data/daily_text.dart';
import 'package:jw_daily_text_widget/features/daily_text/data/daily_text_cache_manager.dart';
import 'package:jw_daily_text_widget/features/favorites/data/favorite_item.dart';
import 'package:jw_daily_text_widget/features/favorites/data/favorites_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final date = DateTime(2026, 7, 9);

  group('DailyText.fromJson', () {
    test('parses a single paragraph as scripture with an empty comment', () {
      final dailyText = DailyText.fromJson(
        {'content': '<p>Trust in Jehovah with all your heart.—Prov. 3:5.</p>'},
        date,
      );

      expect(
        dailyText.scripture,
        'Trust in Jehovah with all your heart.—Prov. 3:5.',
      );
      expect(dailyText.comment, isEmpty);
      expect(dailyText.date, date);
    });

    test('joins multiple comment paragraphs with a blank line', () {
      final dailyText = DailyText.fromJson(
        {
          'content': '<p>For I well know the thoughts that I am thinking '
              'toward you.—Isa. 55:8.</p>'
              '<p>Jehovah does not think the way humans think.</p>'
              '<p>We can always trust his guidance.</p>',
        },
        date,
      );

      expect(
        dailyText.scripture,
        'For I well know the thoughts that I am thinking toward you.—Isa. 55:8.',
      );
      expect(
        dailyText.comment,
        'Jehovah does not think the way humans think.\n\n'
        'We can always trust his guidance.',
      );
    });

    test('strips nested inline tags from each paragraph', () {
      final dailyText = DailyText.fromJson(
        {
          'content': '<p><strong>Love</strong> your neighbor.</p>'
              '<p>This is <em>the</em> second commandment.</p>',
        },
        date,
      );

      expect(dailyText.scripture, 'Love your neighbor.');
      expect(dailyText.comment, 'This is the second commandment.');
    });

    test('decodes HTML entities and extracts heading title', () {
      final dailyText = DailyText.fromJson(
        {
          'content': '<header><h2>Thursday, October&nbsp;8</h2></header>'
              '<p>Trust in God&mdash;He cares for you.</p>'
              '<p>&ldquo;Never be anxious.&rdquo;</p>',
        },
        date,
      );

      expect(dailyText.dateTitle, 'Thursday, October 8');
      expect(dailyText.scripture, 'Trust in God—He cares for you.');
      expect(dailyText.comment, '“Never be anxious.”');
    });

    test('throws FormatException when content has no paragraphs', () {
      expect(
        () => DailyText.fromJson(
          {'content': '<div>No paragraphs here</div>'},
          date,
        ),
        throwsFormatException,
      );
    });

    test('throws FormatException when content is empty', () {
      expect(
        () => DailyText.fromJson({'content': ''}, date),
        throwsFormatException,
      );
    });

    test('throws FormatException when the content key is missing entirely', () {
      expect(
        () => DailyText.fromJson(<String, dynamic>{}, date),
        throwsFormatException,
      );
    });

    test('defaults rsconf/locale and builds URIs from the cached date', () {
      final dailyText = DailyText.fromJson(
        {'content': '<p>Scripture text.</p>'},
        DateTime(2026, 7, 10),
      );

      expect(dailyText.jwpubUri, 'jwpub://dt/r1/lp-e/2026/7/10');
      expect(dailyText.webUri, 'https://wol.jw.org/en/wol/dt/r1/lp-e/2026/7/10');
    });

    test('threads a non-default rsconf/locale into the URIs', () {
      final dailyText = DailyText.fromJson(
        {'content': '<p>Scripture text.</p>'},
        DateTime(2026, 7, 10),
        rsconf: '2',
        locale: 'es',
      );

      expect(dailyText.jwpubUri, 'jwpub://dt/r2/lp-es/2026/7/10');
      expect(dailyText.webUri, 'https://wol.jw.org/en/wol/dt/r2/lp-es/2026/7/10');
    });
  });

  group('DailyText.toWidgetData and Cache', () {
    test('includes scripture, comment, ISO date, and both URIs in widget data', () {
      final entryDate = DateTime(2026, 7, 10);
      final dailyText = DailyText.fromJson(
        {'content': '<p>Scripture.</p><p>Comment.</p>'},
        entryDate,
      );

      expect(dailyText.toWidgetData(), {
        'scripture': 'Scripture.',
        'comment': 'Comment.',
        'date': entryDate.toIso8601String(),
        'jwpubUri': 'jwpub://dt/r1/lp-e/2026/7/10',
        'webUri': 'https://wol.jw.org/en/wol/dt/r1/lp-e/2026/7/10',
      });
    });

    test('serializes to JSON and restores from cache faithfully', () {
      final entryDate = DateTime(2026, 7, 10);
      final original = DailyText(
        scripture: 'Scripture verse',
        comment: 'Comment explanation',
        date: entryDate,
        dateTitle: 'Friday, July 10',
        publicationTitle: 'Examining the Scriptures Daily',
        reference: 'es26 pp. 10-12',
        rsconf: '1',
        locale: 'e',
      );

      final json = original.toJson();
      final restored = DailyText.fromCache(json);

      expect(restored.scripture, original.scripture);
      expect(restored.comment, original.comment);
      expect(restored.dateTitle, original.dateTitle);
      expect(restored.isCached, isTrue);
      expect(restored.jwpubUri, original.jwpubUri);
    });
  });

  group('DailyTextCacheManager', () {
    late DailyTextCacheManager cacheManager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      cacheManager = DailyTextCacheManager();
    });

    test('saves and retrieves daily text by date', () async {
      final sample = DailyText(
        scripture: 'Do not be anxious about anything.—Phil. 4:6',
        comment: 'Jehovah invites us to turn to him in prayer.',
        date: DateTime(2026, 10, 8),
        dateTitle: 'Thursday, October 8',
      );

      await cacheManager.save(sample);

      final cached = await cacheManager.get(DateTime(2026, 10, 8));
      expect(cached, isNotNull);
      expect(cached!.scripture, 'Do not be anxious about anything.—Phil. 4:6');
      expect(cached.comment, 'Jehovah invites us to turn to him in prayer.');
      expect(cached.isCached, isTrue);

      final hasCache = await cacheManager.hasCache(DateTime(2026, 10, 8));
      expect(hasCache, isTrue);
    });

    test('maintains list of cached dates and counts', () async {
      final d1 = DateTime(2026, 10, 8);
      final d2 = DateTime(2026, 10, 9);

      await cacheManager.save(DailyText(
        scripture: 'Verse 1',
        comment: 'Comment 1',
        date: d1,
      ));

      await cacheManager.save(DailyText(
        scripture: 'Verse 2',
        comment: 'Comment 2',
        date: d2,
      ));

      final count = await cacheManager.getCachedCount();
      expect(count, 2);

      final dates = await cacheManager.getCachedDates();
      expect(dates.length, 2);
    });

    test('retrieves last saved entry as fallback', () async {
      final sample = DailyText(
        scripture: 'Last verse',
        comment: 'Last comment',
        date: DateTime(2026, 10, 8),
      );

      await cacheManager.save(sample);

      final last = await cacheManager.getLastSaved();
      expect(last, isNotNull);
      expect(last!.scripture, 'Last verse');
    });

    test('clears offline cache', () async {
      await cacheManager.save(DailyText(
        scripture: 'V',
        comment: 'C',
        date: DateTime(2026, 10, 8),
      ));

      expect(await cacheManager.getCachedCount(), 1);

      await cacheManager.clearAll();
      expect(await cacheManager.getCachedCount(), 0);
    });
  });

  group('Favorites and SQLite Models', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('FavoriteItem maps to and from Map accurately', () {
      final item = FavoriteItem(
        id: 1,
        dateKey: '2026-10-08',
        scripture: 'Trust in Jehovah with all your heart.—Prov. 3:5',
        comment: 'We must lean on Jehovah rather than human reasoning.',
        dateTitle: 'Thursday, October 8',
        publicationTitle: 'Examining the Scriptures Daily',
        reference: 'es26 p. 100',
        rsconf: '1',
        locale: 'e',
        createdAt: DateTime(2026, 10, 8, 8, 30),
        note: 'A very encouraging scripture',
      );

      final map = item.toMap();
      expect(map['id'], 1);
      expect(map['date_key'], '2026-10-08');
      expect(map['note'], 'A very encouraging scripture');

      final fromMap = FavoriteItem.fromMap(map);
      expect(fromMap.id, 1);
      expect(fromMap.scripture, item.scripture);
      expect(fromMap.note, item.note);
      expect(fromMap.toDailyText().scripture, item.scripture);
    });

    test('FavoritesDatabase adds, queries, toggles and clears favorites', () async {
      final db = FavoritesDatabase.instance;
      await db.clearAll();

      final text = DailyText(
        scripture: 'Do not be anxious.—Phil. 4:6',
        comment: 'Turn to prayer in all situations.',
        date: DateTime(2026, 10, 8),
        dateTitle: 'Thursday, October 8',
      );

      expect(await db.isFavorite(text.date), isFalse);

      await db.addFavorite(text, note: 'Daily reminder');
      expect(await db.isFavorite(text.date), isTrue);
      expect(await db.getCount(), 1);

      final favorites = await db.getAllFavorites();
      expect(favorites.length, 1);
      expect(favorites.first.scripture, 'Do not be anxious.—Phil. 4:6');
      expect(favorites.first.note, 'Daily reminder');

      // Toggle off
      final toggledOff = await db.toggleFavorite(text);
      expect(toggledOff, isFalse);
      expect(await db.isFavorite(text.date), isFalse);
      expect(await db.getCount(), 0);
    });
  });
}
