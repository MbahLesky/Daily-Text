import 'package:flutter_test/flutter_test.dart';
import 'package:jw_daily_text_widget/features/daily_text/data/daily_text.dart';

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

  group('DailyText.toWidgetData', () {
    test('includes scripture, comment, ISO date, and both URIs', () {
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
  });
}
