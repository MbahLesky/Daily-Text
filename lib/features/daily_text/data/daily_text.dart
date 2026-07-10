/// A single day's JW daily text: the scripture and its accompanying comment.
class DailyText {
  const DailyText({
    required this.scripture,
    required this.comment,
    required this.date,
    this.rsconf = '1',
    this.locale = 'e',
  });

  final String scripture;
  final String comment;
  final DateTime date;

  /// WOL's region/subdomain code for the language edition (e.g. '1' = English).
  final String rsconf;

  /// WOL's locale code for the language edition (e.g. 'e' = English).
  final String locale;

  /// Deep link that opens this day directly in JW Library, if installed.
  String get jwpubUri =>
      'jwpub://dt/r$rsconf/lp-$locale/${date.year}/${date.month}/${date.day}';

  /// Browser fallback for when JW Library isn't installed.
  String get webUri => 'https://wol.jw.org/en/wol/dt/r$rsconf/lp-$locale'
      '/${date.year}/${date.month}/${date.day}';

  /// Flattens this entry into the string map the native widgets read from
  /// shared storage. [jwpubUri]/[webUri] are included so the widget tap
  /// handler never has to reconstruct the URL scheme itself.
  Map<String, String> toWidgetData() => {
        'scripture': scripture,
        'comment': comment,
        'date': date.toIso8601String(),
        'jwpubUri': jwpubUri,
        'webUri': webUri,
      };

  /// Builds a [DailyText] from one `items[]` entry of the WOL daily-text
  /// JSON response. The `content` field is an HTML fragment: the first
  /// paragraph is the scripture, the remaining paragraphs are the comment.
  factory DailyText.fromJson(
    Map<String, dynamic> json,
    DateTime date, {
    String rsconf = '1',
    String locale = 'e',
  }) {
    final html = json['content'] as String? ?? '';
    final paragraphs = _extractParagraphs(html);

    if (paragraphs.isEmpty) {
      throw const FormatException('Daily text content had no paragraphs');
    }

    return DailyText(
      scripture: paragraphs.first,
      comment: paragraphs.skip(1).join('\n\n'),
      date: date,
      rsconf: rsconf,
      locale: locale,
    );
  }

  static List<String> _extractParagraphs(String html) {
    final matches = RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true).allMatches(html);
    return matches
        .map((match) => _stripHtml(match.group(1) ?? ''))
        .where((text) => text.isNotEmpty)
        .toList();
  }

  static String _stripHtml(String html) =>
      html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
}
