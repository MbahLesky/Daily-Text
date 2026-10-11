import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../daily_text/data/daily_text.dart';
import '../../daily_text/data/daily_text_cache_manager.dart';
import 'favorite_item.dart';

/// SQLite Database Manager for saving, querying, and managing favorite scriptures.
/// Uses native SQLite on Android/iOS and persistent local storage on Web/desktop.
class FavoritesDatabase {
  static final FavoritesDatabase instance = FavoritesDatabase._internal();

  FavoritesDatabase._internal();

  static const String _tableName = 'favorites';
  static const String _dbFileName = 'jw_daily_text_favorites.db';
  static const int _dbVersion = 1;

  Database? _database;
  bool _useFallback = false;

  /// Initializes the SQLite database or sets up fallback storage.
  Future<Database?> _getDb() async {
    if (_useFallback || kIsWeb) return null;
    if (_database != null) return _database;

    try {
      final dbPath = p.join(await getDatabasesPath(), _dbFileName);

      _database = await openDatabase(
        dbPath,
        version: _dbVersion,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $_tableName (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              date_key TEXT NOT NULL,
              scripture TEXT NOT NULL,
              comment TEXT NOT NULL,
              date_title TEXT,
              publication_title TEXT,
              reference TEXT,
              rsconf TEXT,
              locale TEXT,
              created_at TEXT NOT NULL,
              note TEXT,
              UNIQUE(date_key, rsconf, locale)
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_favorites_date ON $_tableName (date_key, rsconf, locale)',
          );
        },
      );
      return _database;
    } catch (e) {
      debugPrint('FavoritesDatabase: SQLite init ($e), using local fallback storage');
      _useFallback = true;
      return null;
    }
  }

  // --- CRUD Operations ---

  /// Checks if a scripture for [date] is saved as a favorite.
  Future<bool> isFavorite(
    DateTime date, {
    String rsconf = '1',
    String locale = 'e',
  }) async {
    final dateKey = DailyTextCacheManager.formatDateKey(date);
    final db = await _getDb();

    if (db != null) {
      try {
        final result = await db.query(
          _tableName,
          columns: ['id'],
          where: 'date_key = ? AND rsconf = ? AND locale = ?',
          whereArgs: [dateKey, rsconf, locale],
          limit: 1,
        );
        return result.isNotEmpty;
      } catch (e) {
        debugPrint('Error checking favorite in SQLite: $e');
      }
    }

    return _isFavoriteFallback(dateKey, rsconf, locale);
  }

  /// Adds a [DailyText] to the SQLite favorites table.
  Future<void> addFavorite(DailyText dailyText, {String note = ''}) async {
    final dateKey = DailyTextCacheManager.formatDateKey(dailyText.date);
    final item = FavoriteItem(
      dateKey: dateKey,
      scripture: dailyText.scripture,
      comment: dailyText.comment,
      dateTitle: dailyText.dateTitle,
      publicationTitle: dailyText.publicationTitle,
      reference: dailyText.reference,
      rsconf: dailyText.rsconf,
      locale: dailyText.locale,
      createdAt: DateTime.now(),
      note: note,
    );

    final db = await _getDb();
    if (db != null) {
      try {
        await db.insert(
          _tableName,
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return;
      } catch (e) {
        debugPrint('Error inserting into SQLite: $e');
      }
    }

    await _saveFavoriteFallback(item);
  }

  /// Removes a scripture from the favorites database.
  Future<void> removeFavorite(
    DateTime date, {
    String rsconf = '1',
    String locale = 'e',
  }) async {
    final dateKey = DailyTextCacheManager.formatDateKey(date);
    final db = await _getDb();

    if (db != null) {
      try {
        await db.delete(
          _tableName,
          where: 'date_key = ? AND rsconf = ? AND locale = ?',
          whereArgs: [dateKey, rsconf, locale],
        );
        return;
      } catch (e) {
        debugPrint('Error deleting from SQLite: $e');
      }
    }

    await _removeFavoriteFallback(dateKey, rsconf, locale);
  }

  /// Toggles favorite status for [dailyText] and returns true if now favorited.
  Future<bool> toggleFavorite(DailyText dailyText) async {
    final exists = await isFavorite(
      dailyText.date,
      rsconf: dailyText.rsconf,
      locale: dailyText.locale,
    );
    if (exists) {
      await removeFavorite(
        dailyText.date,
        rsconf: dailyText.rsconf,
        locale: dailyText.locale,
      );
      return false;
    } else {
      await addFavorite(dailyText);
      return true;
    }
  }

  /// Retrieves all saved favorites, ordered by newest first.
  Future<List<FavoriteItem>> getAllFavorites({
    String? rsconf,
    String? locale,
    String? searchQuery,
  }) async {
    final db = await _getDb();

    if (db != null) {
      try {
        String? where;
        List<Object?>? whereArgs;

        final conditions = <String>[];
        final args = <Object?>[];

        if (rsconf != null && locale != null) {
          conditions.add('rsconf = ? AND locale = ?');
          args.addAll([rsconf, locale]);
        }

        if (searchQuery != null && searchQuery.trim().isNotEmpty) {
          final query = '%${searchQuery.trim()}%';
          conditions.add(
            '(scripture LIKE ? OR comment LIKE ? OR note LIKE ? OR date_title LIKE ?)',
          );
          args.addAll([query, query, query, query]);
        }

        if (conditions.isNotEmpty) {
          where = conditions.join(' AND ');
          whereArgs = args;
        }

        final maps = await db.query(
          _tableName,
          where: where,
          whereArgs: whereArgs,
          orderBy: 'created_at DESC',
        );

        return maps.map((m) => FavoriteItem.fromMap(m)).toList();
      } catch (e) {
        debugPrint('Error reading favorites from SQLite: $e');
      }
    }

    return _getAllFavoritesFallback(
      rsconf: rsconf,
      locale: locale,
      searchQuery: searchQuery,
    );
  }

  /// Updates personal reflection note on a favorite item.
  Future<void> updateNote(int? id, String dateKey, String rsconf, String locale, String note) async {
    final db = await _getDb();
    if (db != null) {
      try {
        if (id != null) {
          await db.update(
            _tableName,
            {'note': note},
            where: 'id = ?',
            whereArgs: [id],
          );
        } else {
          await db.update(
            _tableName,
            {'note': note},
            where: 'date_key = ? AND rsconf = ? AND locale = ?',
            whereArgs: [dateKey, rsconf, locale],
          );
        }
        return;
      } catch (e) {
        debugPrint('Error updating note in SQLite: $e');
      }
    }

    await _updateNoteFallback(dateKey, rsconf, locale, note);
  }

  /// Returns total count of favorite scriptures.
  Future<int> getCount({String? rsconf, String? locale}) async {
    final db = await _getDb();
    if (db != null) {
      try {
        final result = await db.rawQuery(
          rsconf != null && locale != null
              ? 'SELECT COUNT(*) as count FROM $_tableName WHERE rsconf = ? AND locale = ?'
              : 'SELECT COUNT(*) as count FROM $_tableName',
          rsconf != null && locale != null ? [rsconf, locale] : null,
        );
        return Sqflite.firstIntValue(result) ?? 0;
      } catch (e) {
        debugPrint('Error counting favorites in SQLite: $e');
      }
    }

    final fallback = await _getAllFavoritesFallback(rsconf: rsconf, locale: locale);
    return fallback.length;
  }

  /// Clears all favorites.
  Future<void> clearAll() async {
    final db = await _getDb();
    if (db != null) {
      try {
        await db.delete(_tableName);
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jw_daily_text_favorites_store');
  }

  // --- Fallback SharedPreferences Implementation ---

  static const String _fallbackKey = 'jw_daily_text_favorites_store';

  Future<Map<String, dynamic>> _readFallbackStore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_fallbackKey);
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeFallbackStore(Map<String, dynamic> store) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fallbackKey, jsonEncode(store));
  }

  Future<bool> _isFavoriteFallback(String dateKey, String rsconf, String locale) async {
    final store = await _readFallbackStore();
    final key = '${rsconf}_${locale}_$dateKey';
    return store.containsKey(key);
  }

  Future<void> _saveFavoriteFallback(FavoriteItem item) async {
    final store = await _readFallbackStore();
    final key = '${item.rsconf}_${item.locale}_${item.dateKey}';
    store[key] = item.toMap();
    await _writeFallbackStore(store);
  }

  Future<void> _removeFavoriteFallback(String dateKey, String rsconf, String locale) async {
    final store = await _readFallbackStore();
    final key = '${rsconf}_${locale}_$dateKey';
    store.remove(key);
    await _writeFallbackStore(store);
  }

  Future<void> _updateNoteFallback(String dateKey, String rsconf, String locale, String note) async {
    final store = await _readFallbackStore();
    final key = '${rsconf}_${locale}_$dateKey';
    if (store.containsKey(key)) {
      final map = Map<String, dynamic>.from(store[key] as Map);
      map['note'] = note;
      store[key] = map;
      await _writeFallbackStore(store);
    }
  }

  Future<List<FavoriteItem>> _getAllFavoritesFallback({
    String? rsconf,
    String? locale,
    String? searchQuery,
  }) async {
    final store = await _readFallbackStore();
    var list = store.values
        .map((val) => FavoriteItem.fromMap(Map<String, dynamic>.from(val as Map)))
        .toList();

    if (rsconf != null && locale != null) {
      list = list.where((f) => f.rsconf == rsconf && f.locale == locale).toList();
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      list = list.where((f) {
        return f.scripture.toLowerCase().contains(q) ||
            f.comment.toLowerCase().contains(q) ||
            f.note.toLowerCase().contains(q) ||
            f.dateTitle.toLowerCase().contains(q);
      }).toList();
    }

    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }
}
