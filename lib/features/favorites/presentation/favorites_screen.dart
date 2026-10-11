import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/theme_provider.dart';
import '../../../core/tts/daily_text_tts_service.dart';
import '../../daily_text/data/daily_text_service.dart';
import '../data/favorite_item.dart';
import '../data/favorites_database.dart';

/// Dedicated screen to view, search, and manage favorite scriptures.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({
    super.key,
    required this.selectedLanguage,
    required this.fontScale,
    required this.onSelectDate,
  });

  final WolLanguage selectedLanguage;
  final double fontScale;
  final void Function(DateTime date) onSelectDate;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final DailyTextTtsService _ttsService = DailyTextTtsService();
  List<FavoriteItem> _favorites = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final Set<int> _expandedCards = {};

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  void dispose() {
    _ttsService.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoading = true);
    final items = await FavoritesDatabase.instance.getAllFavorites(
      searchQuery: _searchQuery,
    );
    if (mounted) {
      setState(() {
        _favorites = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteFavorite(FavoriteItem item) async {
    await FavoritesDatabase.instance.removeFavorite(
      item.date,
      rsconf: item.rsconf,
      locale: item.locale,
    );
    _loadFavorites();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Removed from favorites'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await FavoritesDatabase.instance.addFavorite(
                item.toDailyText(),
                note: item.note,
              );
              _loadFavorites();
            },
          ),
        ),
      );
    }
  }

  Future<void> _editNote(FavoriteItem item) async {
    final noteController = TextEditingController(text: item.note);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Personal Note / Reflection'),
        content: TextField(
          controller: noteController,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Write your thoughts or how this scripture applies to you…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2C4D75)),
            onPressed: () => Navigator.pop(ctx, noteController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      await FavoritesDatabase.instance.updateNote(
        item.id,
        item.dateKey,
        item.rsconf,
        item.locale,
        result,
      );
      _loadFavorites();
    }
  }

  Future<void> _shareFavorite(FavoriteItem item) async {
    final formattedDate = item.dateTitle.isNotEmpty
        ? item.dateTitle
        : DateFormat('EEEE, MMMM d, y').format(item.date);

    final buffer = StringBuffer()
      ..writeln('📖 Favorite Scripture — $formattedDate\n')
      ..writeln('"${item.scripture}"\n')
      ..writeln(item.comment);

    if (item.note.isNotEmpty) {
      buffer.writeln('\n💭 Note: ${item.note}');
    }
    if (item.reference.isNotEmpty) {
      buffer.writeln('\n${item.reference}');
    }

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: buffer.toString(),
          subject: 'JW Daily Text — $formattedDate',
        ),
      );
    } catch (_) {}
  }

  Future<void> _clearAllFavorites() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Favorites?'),
        content: const Text('Are you sure you want to remove all saved favorite scriptures?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FavoritesDatabase.instance.clearAll();
      _loadFavorites();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.favorite, color: Colors.amberAccent, size: 22),
            const SizedBox(width: 8),
            const Text('Favorite Scriptures', style: TextStyle(fontWeight: FontWeight.w600)),
            if (_favorites.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_favorites.length}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Appearance & Theme',
            icon: Icon(
              switch (context.watch<ThemeProvider>().themeMode) {
                ThemeMode.dark => Icons.dark_mode,
                ThemeMode.light => Icons.light_mode,
                ThemeMode.system => Icons.brightness_auto,
              },
            ),
            onPressed: () {
              context.read<ThemeProvider>().toggleTheme(context);
            },
          ),
          if (_favorites.isNotEmpty)
            IconButton(
              tooltip: 'Clear All',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clearAllFavorites,
            ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search scriptures, comments, or notes…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                          _loadFavorites();
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.2)),
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val);
                _loadFavorites();
              },
            ),
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _favorites.isEmpty
                    ? _buildEmptyState(context)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        itemCount: _favorites.length,
                        itemBuilder: (context, index) {
                          final item = _favorites[index];
                          final isExpanded = _expandedCards.contains(item.id ?? index);
                          return _buildFavoriteCard(context, item, index, isExpanded);
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: ValueListenableBuilder<TtsState>(
        valueListenable: _ttsService.stateNotifier,
        builder: (context, ttsState, _) {
          if (ttsState == TtsState.stopped) {
            return const SizedBox.shrink();
          }
          final isPlaying = ttsState == TtsState.playing;
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: const Color(0xFF2C4D75).withOpacity(0.2),
                  width: 1.5,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  const Icon(Icons.record_voice_over, color: Color(0xFFB57C2F), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isPlaying ? 'Reading Favorite Scripture…' : 'Audio Paused',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    tooltip: isPlaying ? 'Pause' : 'Resume',
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    color: const Color(0xFF2C4D75),
                    onPressed: () {
                      if (isPlaying) {
                        _ttsService.pause();
                      }
                    },
                  ),
                  IconButton(
                    tooltip: 'Stop',
                    icon: const Icon(Icons.stop),
                    color: Colors.redAccent,
                    onPressed: () => _ttsService.stop(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFavoriteCard(
    BuildContext context,
    FavoriteItem item,
    int index,
    bool isExpanded,
  ) {
    final theme = Theme.of(context);
    final cardId = item.id ?? index;
    final formattedDate = item.dateTitle.isNotEmpty
        ? item.dateTitle
        : DateFormat('EEEE, MMMM d, y').format(item.date);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: const Color(0xFF2C4D75).withOpacity(0.18),
          width: 1,
        ),
      ),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: Date and Unfavorite heart
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C4D75).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today, size: 12, color: Color(0xFF2C4D75)),
                      const SizedBox(width: 4),
                      Text(
                        formattedDate,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2C4D75),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Remove from Favorites',
                  icon: const Icon(Icons.favorite, color: Colors.redAccent, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _deleteFavorite(item),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Scripture
            SelectableText(
              item.scripture,
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.bold,
                fontSize: 15.5 * widget.fontScale,
                height: 1.45,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            // Personal Note if present
            if (item.note.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFB57C2F).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFB57C2F).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.edit_note, size: 16, color: Color(0xFFB57C2F)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.note,
                        style: TextStyle(
                          fontSize: 13 * widget.fontScale,
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Comment section
            if (isExpanded) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      item.comment,
                      style: TextStyle(
                        fontSize: 14 * widget.fontScale,
                        height: 1.5,
                      ),
                    ),
                    if (item.reference.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        item.reference,
                        style: TextStyle(
                          fontSize: 11 * widget.fontScale,
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            // Actions Row
            Row(
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedCards.remove(cardId);
                      } else {
                        _expandedCards.add(cardId);
                      }
                    });
                  },
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                  ),
                  label: Text(isExpanded ? 'Less' : 'Commentary'),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => _editNote(item),
                  icon: const Icon(Icons.edit, size: 14),
                  label: Text(item.note.isEmpty ? 'Add Note' : 'Edit Note'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Listen (TTS)',
                  icon: const Icon(Icons.volume_up, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _ttsService.speakDailyText(item.toDailyText(), full: isExpanded);
                  },
                ),
                IconButton(
                  tooltip: 'Share',
                  icon: const Icon(Icons.share, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _shareFavorite(item),
                ),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () {
                    widget.onSelectDate(item.date);
                    Navigator.pop(context);
                  },
                  child: const Text('Go to Day', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF2C4D75).withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite_border,
                size: 48,
                color: Color(0xFF2C4D75),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No matching favorites found'
                  : 'No Favorite Scriptures Yet',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try searching with different keywords.'
                  : 'Tap the heart icon on any daily text to save your favorite scriptures here for meditation and personal study.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).textTheme.bodySmall?.color,
                height: 1.4,
              ),
            ),
            if (_searchQuery.isEmpty) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2C4D75)),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.today, size: 16),
                label: const Text('Browse Today\'s Text'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
