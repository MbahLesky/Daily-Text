/// A single day's JW daily text: the scripture, its accompanying comment,
/// publication details, and deep links.
class DailyText {
  const DailyText({
    required this.scripture,
    required this.comment,
    required this.date,
    this.dateTitle = '',
    this.publicationTitle = 'Examining the Scriptures Daily',
    this.reference = '',
    this.rsconf = '1',
    this.locale = 'e',
    this.isCached = false,
    this.fetchedAt,
  });

  final String scripture;
  final String comment;
  final DateTime date;
  final String dateTitle;
  final String publicationTitle;
  final String reference;

  /// WOL's region/subdomain code for the language edition (e.g. '1' = English).
  final String rsconf;

  /// WOL's locale code for the language edition (e.g. 'e' = English).
  final String locale;

  /// Whether this entry was retrieved from local offline cache.
  final bool isCached;

  /// Timestamp when this daily text was fetched.
  final DateTime? fetchedAt;

  /// Deep link that opens this day directly in the JW Library app, if installed.
  String get jwpubUri =>
      'jwpub://dt/r$rsconf/lp-$locale/${date.year}/${date.month}/${date.day}';

  /// Browser fallback for when JW Library is not installed.
  String get webUri =>
      'https://wol.jw.org/en/wol/dt/r$rsconf/lp-$locale/${date.year}/${date.month}/${date.day}';

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

  /// Serializes to a JSON map for local cache storage.
  Map<String, dynamic> toJson() => {
        'scripture': scripture,
        'comment': comment,
        'date': date.toIso8601String(),
        'dateTitle': dateTitle,
        'publicationTitle': publicationTitle,
        'reference': reference,
        'rsconf': rsconf,
        'locale': locale,
        'fetchedAt': (fetchedAt ?? DateTime.now()).toIso8601String(),
      };

  /// Restores a [DailyText] instance from local cache JSON.
  factory DailyText.fromCache(Map<String, dynamic> json) {
    return DailyText(
      scripture: json['scripture'] as String? ?? '',
      comment: json['comment'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      dateTitle: json['dateTitle'] as String? ?? '',
      publicationTitle: json['publicationTitle'] as String? ?? 'Examining the Scriptures Daily',
      reference: json['reference'] as String? ?? '',
      rsconf: json['rsconf'] as String? ?? '1',
      locale: json['locale'] as String? ?? 'e',
      isCached: true,
      fetchedAt: DateTime.tryParse(json['fetchedAt'] as String? ?? ''),
    );
  }

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

    final dateTitle = _extractDateTitle(html);
    final pubTitle = json['publicationTitle'] as String? ?? 'Examining the Scriptures Daily';
    final reference = json['reference'] as String? ?? json['caption'] as String? ?? '';

    return DailyText(
      scripture: paragraphs.first,
      comment: paragraphs.skip(1).join('\n\n'),
      date: date,
      dateTitle: dateTitle,
      publicationTitle: pubTitle,
      reference: reference,
      rsconf: rsconf,
      locale: locale,
      isCached: false,
      fetchedAt: DateTime.now(),
    );
  }

  /// Extracts paragraphs (<p>...</p>) while stripping HTML and decoding entities.
  static List<String> _extractParagraphs(String html) {
    final matches = RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true).allMatches(html);
    return matches
        .map((match) => _stripHtml(match.group(1) ?? ''))
        .where((text) => text.isNotEmpty)
        .toList();
  }

  /// Extracts the date title heading (<header><h2>...</h2></header>) if present.
  static String _extractDateTitle(String html) {
    final match = RegExp(r'<h[1-3][^>]*>(.*?)</h[1-3]>', dotAll: true).firstMatch(html);
    if (match != null) {
      return _stripHtml(match.group(1) ?? '');
    }
    return '';
  }

  /// Strips HTML tags and normalizes common HTML entities.
  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#160;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&rsquo;', '’')
        .replaceAll('&lsquo;', '‘')
        .replaceAll('&rdquo;', '”')
        .replaceAll('&ldquo;', '“')
        .replaceAll('&mdash;', '—')
        .replaceAll('&#8212;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&#8211;', '–')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  DailyText copyWith({
    String? scripture,
    String? comment,
    DateTime? date,
    String? dateTitle,
    String? publicationTitle,
    String? reference,
    String? rsconf,
    String? locale,
    bool? isCached,
    DateTime? fetchedAt,
  }) {
    return DailyText(
      scripture: scripture ?? this.scripture,
      comment: comment ?? this.comment,
      date: date ?? this.date,
      dateTitle: dateTitle ?? this.dateTitle,
      publicationTitle: publicationTitle ?? this.publicationTitle,
      reference: reference ?? this.reference,
      rsconf: rsconf ?? this.rsconf,
      locale: locale ?? this.locale,
      isCached: isCached ?? this.isCached,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }
}
