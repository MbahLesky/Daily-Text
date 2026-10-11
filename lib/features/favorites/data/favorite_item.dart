import '../../daily_text/data/daily_text.dart';

/// Represents a favorite scripture saved to the local SQLite database.
class FavoriteItem {
  const FavoriteItem({
    this.id,
    required this.dateKey,
    required this.scripture,
    required this.comment,
    this.dateTitle = '',
    this.publicationTitle = 'Examining the Scriptures Daily',
    this.reference = '',
    this.rsconf = '1',
    this.locale = 'e',
    required this.createdAt,
    this.note = '',
  });

  final int? id;
  final String dateKey;
  final String scripture;
  final String comment;
  final String dateTitle;
  final String publicationTitle;
  final String reference;
  final String rsconf;
  final String locale;
  final DateTime createdAt;
  final String note;

  DateTime get date => DateTime.tryParse(dateKey) ?? DateTime.now();

  DailyText toDailyText() {
    return DailyText(
      scripture: scripture,
      comment: comment,
      date: date,
      dateTitle: dateTitle,
      publicationTitle: publicationTitle,
      reference: reference,
      rsconf: rsconf,
      locale: locale,
      isCached: true,
      fetchedAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'date_key': dateKey,
      'scripture': scripture,
      'comment': comment,
      'date_title': dateTitle,
      'publication_title': publicationTitle,
      'reference': reference,
      'rsconf': rsconf,
      'locale': locale,
      'created_at': createdAt.toIso8601String(),
      'note': note,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory FavoriteItem.fromMap(Map<String, dynamic> map) {
    return FavoriteItem(
      id: map['id'] as int?,
      dateKey: map['date_key'] as String? ?? '',
      scripture: map['scripture'] as String? ?? '',
      comment: map['comment'] as String? ?? '',
      dateTitle: map['date_title'] as String? ?? '',
      publicationTitle:
          map['publication_title'] as String? ?? 'Examining the Scriptures Daily',
      reference: map['reference'] as String? ?? '',
      rsconf: map['rsconf'] as String? ?? '1',
      locale: map['locale'] as String? ?? 'e',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      note: map['note'] as String? ?? '',
    );
  }

  FavoriteItem copyWith({
    int? id,
    String? dateKey,
    String? scripture,
    String? comment,
    String? dateTitle,
    String? publicationTitle,
    String? reference,
    String? rsconf,
    String? locale,
    DateTime? createdAt,
    String? note,
  }) {
    return FavoriteItem(
      id: id ?? this.id,
      dateKey: dateKey ?? this.dateKey,
      scripture: scripture ?? this.scripture,
      comment: comment ?? this.comment,
      dateTitle: dateTitle ?? this.dateTitle,
      publicationTitle: publicationTitle ?? this.publicationTitle,
      reference: reference ?? this.reference,
      rsconf: rsconf ?? this.rsconf,
      locale: locale ?? this.locale,
      createdAt: createdAt ?? this.createdAt,
      note: note ?? this.note,
    );
  }
}
