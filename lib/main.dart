import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:workmanager/workmanager.dart';

import 'core/home_widget/background_worker.dart';
import 'core/home_widget/home_widget_service.dart';
import 'core/notifications/notification_service.dart';
import 'core/theme/theme_provider.dart';
import 'core/tts/daily_text_tts_service.dart';
import 'features/daily_text/data/daily_text.dart';
import 'features/daily_text/data/daily_text_cache_manager.dart';
import 'features/daily_text/data/daily_text_service.dart';
import 'features/favorites/data/favorites_database.dart';
import 'features/favorites/presentation/favorites_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize daily reminder notification service
  await NotificationService.instance.initialize();

  if (!kIsWeb) {
    try {
      Workmanager().initialize(callbackDispatcher);
      Workmanager().registerPeriodicTask(
        dailyTextRefreshTask,
        dailyTextRefreshTask,
        frequency: const Duration(hours: 12),
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (e) {
      debugPrint('Workmanager init skipped: $e');
    }
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const DailyTextApp(),
    ),
  );
}

class DailyTextApp extends StatelessWidget {
  const DailyTextApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      title: 'JW Daily Text',
      debugShowCheckedModeBanner: false,
      theme: ThemeProvider.lightTheme,
      darkTheme: ThemeProvider.darkTheme,
      themeMode: themeProvider.themeMode,
      home: const DailyTextScreen(),
    );
  }
}

class DailyTextScreen extends StatefulWidget {
  const DailyTextScreen({super.key});

  @override
  State<DailyTextScreen> createState() => _DailyTextScreenState();
}

class _DailyTextScreenState extends State<DailyTextScreen> {
  DateTime _selectedDate = DateTime.now();
  WolLanguage _selectedLanguage = WolLanguage.supportedLanguages.first; // English

  late DailyTextService _service;
  Future<DailyText>? _dailyTextFuture;
  int _cachedCount = 0;
  bool _isPrefetching = false;
  DailyText? _latestFetchedText;
  double _fontScale = 1.0;
  static const String _fontScalePrefKey = 'user_scripture_font_scale';
  bool _isCurrentFavorite = false;
  int _favoritesCount = 0;
  final DailyTextTtsService _ttsService = DailyTextTtsService();

  @override
  void initState() {
    super.initState();
    _loadFontScale();
    _updateService();
    _loadDailyText(forceRefresh: false);
    _refreshCachedCount();
    _checkFavoriteStatus(_selectedDate);
  }

  @override
  void dispose() {
    _ttsService.dispose();
    super.dispose();
  }

  Future<void> _checkFavoriteStatus(DateTime date) async {
    try {
      final isFav = await FavoritesDatabase.instance.isFavorite(
        date,
        rsconf: _selectedLanguage.rsconf,
        locale: _selectedLanguage.locale,
      );
      final count = await FavoritesDatabase.instance.getCount(
        rsconf: _selectedLanguage.rsconf,
        locale: _selectedLanguage.locale,
      );
      if (mounted) {
        setState(() {
          _isCurrentFavorite = isFav;
          _favoritesCount = count;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleFavorite(DailyText dailyText) async {
    try {
      final nowFav = await FavoritesDatabase.instance.toggleFavorite(dailyText);
      final count = await FavoritesDatabase.instance.getCount(
        rsconf: _selectedLanguage.rsconf,
        locale: _selectedLanguage.locale,
      );
      if (mounted) {
        setState(() {
          _isCurrentFavorite = nowFav;
          _favoritesCount = count;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nowFav ? 'Saved to Favorites!' : 'Removed from Favorites'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
    }
  }

  Future<void> _loadFontScale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scale = prefs.getDouble(_fontScalePrefKey) ?? 1.0;
      if (mounted) {
        setState(() => _fontScale = scale);
      }
    } catch (e) {
      debugPrint('Error loading font scale: $e');
    }
  }

  Future<void> _updateFontScale(double scale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_fontScalePrefKey, scale);
      if (mounted) {
        setState(() => _fontScale = scale);
      }
    } catch (e) {
      debugPrint('Error saving font scale: $e');
    }
  }

  void _updateService() {
    _service = DailyTextService(
      rsconf: _selectedLanguage.rsconf,
      locale: _selectedLanguage.locale,
    );
  }

  Future<void> _refreshCachedCount() async {
    final count = await _service.cacheManager.getCachedCount(
      rsconf: _selectedLanguage.rsconf,
      locale: _selectedLanguage.locale,
    );
    if (mounted) {
      setState(() => _cachedCount = count);
    }
  }

  void _loadDailyText({bool forceRefresh = false}) {
    setState(() {
      _dailyTextFuture = _fetchAndPublish(
        date: _selectedDate,
        forceRefresh: forceRefresh,
      );
    });
    _refreshCachedCount();
    _checkFavoriteStatus(_selectedDate);
  }

  Future<DailyText> _fetchAndPublish({
    required DateTime date,
    required bool forceRefresh,
  }) async {
    final result = await _service.fetchDailyText(
      date: date,
      forceRefresh: forceRefresh,
      overrideRsconf: _selectedLanguage.rsconf,
      overrideLocale: _selectedLanguage.locale,
    );

    _latestFetchedText = result;

    // Sync today to native Android home screen widget
    final isToday = _isSameDay(date, DateTime.now());
    if (isToday) {
      await HomeWidgetService.updateWidget(result);
    }

    _refreshCachedCount();
    return result;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _changeDate(DateTime newDate) {
    _ttsService.stop();
    setState(() {
      _selectedDate = newDate;
    });
    _loadDailyText();
  }

  void _changeLanguage(WolLanguage newLang) {
    if (_selectedLanguage == newLang) return;
    _ttsService.stop();
    setState(() {
      _selectedLanguage = newLang;
      _updateService();
    });
    _loadDailyText(forceRefresh: true);
  }

  Future<void> _toggleTts(DailyText dailyText) async {
    final state = _ttsService.stateNotifier.value;
    if (state == TtsState.playing) {
      await _ttsService.pause();
    } else if (state == TtsState.paused) {
      await _ttsService.resume(dailyText);
    } else {
      await _ttsService.speakDailyText(dailyText, full: true);
    }
  }

  void _showTtsSettingsSheet(DailyText dailyText) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final currentRate = _ttsService.speechRateNotifier.value;

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2C4D75).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.record_voice_over, color: Color(0xFF2C4D75)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Audio Reading (TTS)',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Voice language: ${_selectedLanguage.name}',
                              style: const TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Reading Speed',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final rate in [0.75, 1.0, 1.25, 1.5])
                        ChoiceChip(
                          label: Text('${rate}x'),
                          selected: (currentRate - rate).abs() < 0.05,
                          onSelected: (_) async {
                            await _ttsService.setRate(rate);
                            setSheetState(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Reading Options',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.menu_book, color: Color(0xFF2C4D75)),
                    title: const Text('Read Full Daily Text'),
                    subtitle: const Text('Reads theme scripture, citation & complete commentary'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _ttsService.speakDailyText(dailyText, full: true);
                    },
                  ),
                  const Divider(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.format_quote, color: Color(0xFFB57C2F)),
                    title: const Text('Read Scripture Only'),
                    subtitle: const Text('Reads only the theme scripture verse and citation'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _ttsService.speakDailyText(dailyText, full: false);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );

    if (picked != null && !_isSameDay(picked, _selectedDate)) {
      _changeDate(picked);
    }
  }

  Future<void> _launchUrlSafe(String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        if (urlString.startsWith('jwpub://')) {
          final webFallback =
              'https://wol.jw.org/en/wol/dt/r${_selectedLanguage.rsconf}/lp-${_selectedLanguage.locale}/${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}';
          await launchUrl(Uri.parse(webFallback), mode: LaunchMode.externalApplication);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the link.')),
          );
        }
      }
    } catch (_) {
      if (urlString.startsWith('jwpub://')) {
        final webFallback =
            'https://wol.jw.org/en/wol/dt/r${_selectedLanguage.rsconf}/lp-${_selectedLanguage.locale}/${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}';
        await launchUrl(Uri.parse(webFallback), mode: LaunchMode.externalApplication);
      }
    }
  }

  void _copyToClipboard(DailyText text, {bool full = false}) {
    final formattedDate = DateFormat('EEEE, MMMM d, y').format(text.date);
    final buffer = StringBuffer();
    buffer.writeln(text.scripture);
    if (full) {
      buffer.writeln();
      buffer.writeln(text.comment);
      buffer.writeln();
      buffer.writeln('— Examining the Scriptures Daily ($formattedDate)');
      buffer.writeln(text.webUri);
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(full ? 'Copied daily text and comment' : 'Copied scripture to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _shareDailyText(DailyText text, {bool scriptureOnly = false}) async {
    final formattedDate = text.dateTitle.isNotEmpty
        ? text.dateTitle
        : DateFormat('EEEE, MMMM d, y').format(text.date);

    final buffer = StringBuffer();
    if (scriptureOnly) {
      buffer.writeln('"$text.scripture"');
      buffer.writeln('— JW Daily Text ($formattedDate)');
      buffer.writeln(text.webUri);
    } else {
      buffer.writeln('📖 JW Daily Text — $formattedDate\n');
      buffer.writeln('"${text.scripture}"\n');
      buffer.writeln(text.comment);
      if (text.reference.isNotEmpty) {
        buffer.writeln('\n${text.reference}');
      }
      buffer.writeln('\nRead on Watchtower Online Library:');
      buffer.writeln(text.webUri);
    }

    final shareText = buffer.toString();

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: shareText,
          subject: 'JW Daily Text — $formattedDate',
        ),
      );
    } catch (e) {
      debugPrint('SharePlus error: $e');
      Clipboard.setData(ClipboardData(text: shareText));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied daily text to clipboard ready to share!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showShareOptions(DailyText text) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final formattedDate = text.dateTitle.isNotEmpty
            ? text.dateTitle
            : DateFormat('EEEE, MMMM d, y').format(text.date);

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C4D75).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.share, color: Color(0xFF2C4D75)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Share Daily Text',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          formattedDate,
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C4D75).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.menu_book, color: Color(0xFF2C4D75)),
                ),
                title: const Text(
                  'Share Full Daily Text',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                subtitle: const Text('Includes theme scripture, commentary & WOL link'),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareDailyText(text, scriptureOnly: false);
                },
              ),
              const Divider(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB57C2F).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.format_quote, color: Color(0xFFB57C2F)),
                ),
                title: const Text(
                  'Share Scripture Only',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                subtitle: const Text('Quick quote of the theme scripture verse'),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareDailyText(text, scriptureOnly: true);
                },
              ),
              const Divider(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.copy, color: Colors.grey),
                ),
                title: const Text(
                  'Copy to Clipboard',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                subtitle: const Text('Copy scripture and comment to paste anywhere'),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyToClipboard(text, full: true);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showThemeSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final themeProvider = ctx.watch<ThemeProvider>();
        final currentMode = themeProvider.themeMode;
        final isDark = themeProvider.isDarkMode(ctx);
        final theme = Theme.of(ctx);

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isDark ? Icons.dark_mode : Icons.light_mode,
                      color: isDark ? const Color(0xFF7EA9DE) : theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Appearance & Theme',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Choose light, dark, or system appearance',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Quick toggle switch for Dark Mode
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF7EA9DE).withOpacity(0.15)
                        : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.dark_mode,
                    color: isDark ? const Color(0xFF7EA9DE) : Colors.grey,
                  ),
                ),
                title: const Text(
                  'Dark Mode',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                subtitle: Text(
                  isDark ? 'Active' : 'Off',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? theme.colorScheme.primary : Colors.grey,
                  ),
                ),
                value: isDark,
                onChanged: (val) {
                  themeProvider.setThemeMode(val ? ThemeMode.dark : ThemeMode.light);
                },
              ),
              const Divider(height: 20),
              const Text(
                'Theme Mode',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              RadioListTile<ThemeMode>(
                contentPadding: EdgeInsets.zero,
                value: ThemeMode.system,
                groupValue: currentMode,
                title: const Text(
                  'System Default',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                ),
                subtitle: const Text(
                  'Automatically matches device system theme',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                secondary: const Icon(Icons.brightness_auto),
                onChanged: (mode) {
                  if (mode != null) themeProvider.setThemeMode(mode);
                },
              ),
              RadioListTile<ThemeMode>(
                contentPadding: EdgeInsets.zero,
                value: ThemeMode.light,
                groupValue: currentMode,
                title: const Text(
                  'Light',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                ),
                subtitle: const Text(
                  'Bright and clean reading background',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                secondary: const Icon(Icons.light_mode, color: Color(0xFFB57C2F)),
                onChanged: (mode) {
                  if (mode != null) themeProvider.setThemeMode(mode);
                },
              ),
              RadioListTile<ThemeMode>(
                contentPadding: EdgeInsets.zero,
                value: ThemeMode.dark,
                groupValue: currentMode,
                title: const Text(
                  'Dark',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                ),
                subtitle: const Text(
                  'Soft dark colors, comfortable for nighttime reading',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                secondary: const Icon(Icons.dark_mode, color: Color(0xFF7EA9DE)),
                onChanged: (mode) {
                  if (mode != null) themeProvider.setThemeMode(mode);
                },
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final themeProvider = ctx.watch<ThemeProvider>();
        final currentMode = themeProvider.themeMode;
        final isDark = themeProvider.isDarkMode(ctx);
        final theme = Theme.of(ctx);

        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.settings, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Settings',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Appearance, readability & preferences',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // SECTION 1: Appearance & Dark Mode
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.15)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isDark ? Icons.dark_mode : Icons.light_mode,
                              color: isDark ? const Color(0xFF7EA9DE) : const Color(0xFFB57C2F),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Appearance & Dark Mode',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          subtitle: Text(
                            isDark ? 'Active (dark theme)' : 'Off (light theme)',
                            style: TextStyle(fontSize: 13, color: isDark ? theme.colorScheme.primary : Colors.grey),
                          ),
                          value: isDark,
                          onChanged: (val) {
                            themeProvider.setThemeMode(val ? ThemeMode.dark : ThemeMode.light);
                          },
                        ),
                        const Divider(height: 16),
                        const Text(
                          'Theme Mode Preference',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
                        ),
                        const SizedBox(height: 6),
                        RadioListTile<ThemeMode>(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: ThemeMode.system,
                          groupValue: currentMode,
                          title: const Text('System Default'),
                          subtitle: const Text('Follows system appearance setting', style: TextStyle(fontSize: 12)),
                          secondary: const Icon(Icons.brightness_auto, size: 20),
                          onChanged: (mode) {
                            if (mode != null) themeProvider.setThemeMode(mode);
                          },
                        ),
                        RadioListTile<ThemeMode>(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: ThemeMode.light,
                          groupValue: currentMode,
                          title: const Text('Light'),
                          subtitle: const Text('Clean and bright appearance', style: TextStyle(fontSize: 12)),
                          secondary: const Icon(Icons.light_mode, size: 20, color: Color(0xFFB57C2F)),
                          onChanged: (mode) {
                            if (mode != null) themeProvider.setThemeMode(mode);
                          },
                        ),
                        RadioListTile<ThemeMode>(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: ThemeMode.dark,
                          groupValue: currentMode,
                          title: const Text('Dark'),
                          subtitle: const Text('Soft dark appearance for night reading', style: TextStyle(fontSize: 12)),
                          secondary: const Icon(Icons.dark_mode, size: 20, color: Color(0xFF7EA9DE)),
                          onChanged: (mode) {
                            if (mode != null) themeProvider.setThemeMode(mode);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // SECTION 2: Text Size & Readability
                ListTile(
                  leading: const Icon(Icons.format_size),
                  title: const Text('Text Size & Readability'),
                  subtitle: Text('Current scale: ${(_fontScale * 100).toInt()}%'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showFontSizeDialog();
                  },
                ),

                // SECTION 3: Morning Reminder
                ListTile(
                  leading: const Icon(Icons.alarm),
                  title: const Text('Morning Reminder Notification'),
                  subtitle: const Text('Daily scripture alerts at your chosen time'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showNotificationSettings();
                  },
                ),

                // SECTION 4: Audio / Text-to-Speech
                if (_latestFetchedText != null)
                  ListTile(
                    leading: const Icon(Icons.volume_up_outlined),
                    title: const Text('Audio Reading (TTS) Options'),
                    subtitle: Text('Current rate: ${_ttsService.speechRateNotifier.value.toStringAsFixed(2)}x'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showTtsSettingsSheet(_latestFetchedText!);
                    },
                  ),

                // SECTION 5: Offline Storage
                ListTile(
                  leading: const Icon(Icons.offline_pin_outlined),
                  title: const Text('Offline Storage & Cache'),
                  subtitle: Text('$_cachedCount scriptures saved offline'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showOfflineManagerSheet();
                  },
                ),

                // SECTION 6: Home Screen Widget
                ListTile(
                  leading: const Icon(Icons.widgets_outlined),
                  title: const Text('Home Screen Widget Info'),
                  subtitle: const Text('Setup instructions and widget sync'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showWidgetInstructions();
                  },
                ),

                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showFontSizeDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2C4D75).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.format_size, color: Color(0xFF2C4D75)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Text Size',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Current: ${(_fontScale * 100).round()}%',
                              style: const TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          _updateFontScale(1.0);
                          setSheetState(() {});
                        },
                        icon: const Icon(Icons.restart_alt, size: 16),
                        label: const Text('Reset'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Slider
                  Row(
                    children: [
                      const Text('A', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Slider(
                          value: _fontScale,
                          min: 0.8,
                          max: 1.5,
                          divisions: 7,
                          label: '${(_fontScale * 100).round()}%',
                          activeColor: const Color(0xFF2C4D75),
                          onChanged: (val) {
                            _updateFontScale(val);
                            setSheetState(() {});
                          },
                        ),
                      ),
                      const Text('A', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Preset buttons
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildPresetChip('Small (85%)', 0.85, setSheetState),
                      _buildPresetChip('Normal (100%)', 1.0, setSheetState),
                      _buildPresetChip('Large (120%)', 1.2, setSheetState),
                      _buildPresetChip('X-Large (140%)', 1.4, setSheetState),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Preview:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '"Trust in Jehovah with all your heart, and do not rely on your own understanding."—Prov. 3:5.',
                          style: TextStyle(
                            fontSize: 17 * _fontScale,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Jehovah is ready to guide our steps each day through his Word.',
                          style: TextStyle(
                            fontSize: 15.5 * _fontScale,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPresetChip(String label, double scale, StateSetter setSheetState) {
    final isSelected = (_fontScale - scale).abs() < 0.05;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        _updateFontScale(scale);
        setSheetState(() {});
      },
    );
  }

  void _showNotificationSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            return FutureBuilder<Map<String, dynamic>>(
              future: Future.wait([
                NotificationService.instance.isReminderEnabled(),
                NotificationService.instance.getReminderTime(),
              ]).then((results) => {
                    'enabled': results[0] as bool,
                    'time': results[1] as TimeOfDay,
                  }),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                bool enabled = snapshot.data!['enabled'] as bool;
                TimeOfDay time = snapshot.data!['time'] as TimeOfDay;

                String formatTimeOfDay(TimeOfDay t) {
                  final now = DateTime.now();
                  final dt = DateTime(now.year, now.month, now.day, t.hour, t.minute);
                  return DateFormat.jm().format(dt);
                }

                // Common preset morning times
                final presets = const [
                  TimeOfDay(hour: 6, minute: 30),
                  TimeOfDay(hour: 7, minute: 0),
                  TimeOfDay(hour: 7, minute: 30),
                  TimeOfDay(hour: 8, minute: 0),
                  TimeOfDay(hour: 9, minute: 0),
                ];

                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.notifications_active, color: theme.colorScheme.primary),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Daily Reminder',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Reminds you every day to read the daily scripture',
                                  style: TextStyle(fontSize: 13, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Enable Morning Reminder',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        subtitle: Text(
                          enabled
                              ? 'Scheduled daily at ${formatTimeOfDay(time)}'
                              : 'Notifications are turned off',
                          style: TextStyle(
                            fontSize: 13,
                            color: enabled ? theme.colorScheme.primary : Colors.grey,
                          ),
                        ),
                        value: enabled,
                        onChanged: (val) async {
                          await NotificationService.instance.updateReminderSettings(
                            enabled: val,
                            hour: time.hour,
                            minute: time.minute,
                          );
                          setSheetState(() {});
                        },
                      ),
                      const Divider(height: 24),

                      // Quick preset times
                      if (enabled) ...[
                        const Text(
                          'Quick Preset Times',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: presets.map((preset) {
                              final isSelected =
                                  preset.hour == time.hour && preset.minute == time.minute;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(formatTimeOfDay(preset)),
                                  selected: isSelected,
                                  onSelected: (selected) async {
                                    if (selected) {
                                      await NotificationService.instance.updateReminderSettings(
                                        enabled: true,
                                        hour: preset.hour,
                                        minute: preset.minute,
                                      );
                                      setSheetState(() {});
                                    }
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        enabled: enabled,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: enabled
                                ? theme.colorScheme.primary.withOpacity(0.12)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.schedule,
                            color: enabled ? theme.colorScheme.primary : Colors.grey,
                          ),
                        ),
                        title: const Text(
                          'Custom Reminder Time',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        subtitle: const Text('Tap to set a specific hour and minute'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: enabled
                                ? theme.colorScheme.primary.withOpacity(0.12)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: enabled
                                  ? theme.colorScheme.primary.withOpacity(0.3)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            formatTimeOfDay(time),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: enabled ? theme.colorScheme.primary : Colors.grey,
                            ),
                          ),
                        ),
                        onTap: enabled
                            ? () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: time,
                                );
                                if (picked != null) {
                                  await NotificationService.instance.updateReminderSettings(
                                    enabled: enabled,
                                    hour: picked.hour,
                                    minute: picked.minute,
                                  );
                                  setSheetState(() {});
                                }
                              }
                            : null,
                      ),
                      const SizedBox(height: 16),

                      // Explanatory note
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                enabled
                                    ? 'A local notification will sound daily at ${formatTimeOfDay(time)} reminding you to read today\'s scripture and commentary.'
                                    : 'Enable the reminder to receive a daily morning prompt for Examining the Scriptures Daily.',
                                style: const TextStyle(fontSize: 12, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Test notification button
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await NotificationService.instance.showTestNotification(
                                  scripture: _latestFetchedText?.scripture,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Test notification sent! Check your notification tray.'),
                                      behavior: SnackBarBehavior.floating,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.send, size: 16),
                              label: const Text('Send Test Notification Now'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showOfflineManagerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return FutureBuilder<List<DateTime>>(
              future: _service.cacheManager.getCachedDates(
                rsconf: _selectedLanguage.rsconf,
                locale: _selectedLanguage.locale,
              ),
              builder: (context, snapshot) {
                final cachedDates = snapshot.data ?? [];
                final theme = Theme.of(context);

                return Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.75,
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2C4D75).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.offline_pin, color: Color(0xFF2C4D75)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Offline Storage',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '${cachedDates.length} days saved for offline reading (${_selectedLanguage.name})',
                                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isPrefetching
                                  ? null
                                  : () async {
                                      setSheetState(() => _isPrefetching = true);
                                      setState(() => _isPrefetching = true);

                                      final count = await _service.prefetchDays(
                                        startDate: DateTime.now(),
                                        count: 7,
                                      );

                                      if (mounted) {
                                        setSheetState(() => _isPrefetching = false);
                                        setState(() => _isPrefetching = false);
                                        _refreshCachedCount();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Downloaded $count upcoming days for offline use!'),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    },
                              icon: _isPrefetching
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.download, size: 16),
                              label: const Text('Download 7 Days'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            tooltip: 'Clear Cache',
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Clear Offline Cache?'),
                                  content: const Text(
                                    'This will delete all saved scriptures for offline viewing.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('Clear'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                await _service.clearCache();
                                setSheetState(() {});
                                _refreshCachedCount();
                                _loadDailyText(forceRefresh: true);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Saved Dates (Tap to view):',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: cachedDates.isEmpty
                            ? Center(
                                child: Text(
                                  'No days currently cached.\nBrowse days or tap "Download 7 Days" to save.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: theme.hintColor, fontSize: 13),
                                ),
                              )
                            : ListView.builder(
                                itemCount: cachedDates.length,
                                itemBuilder: (context, index) {
                                  final date = cachedDates[index];
                                  final isCurrent = _isSameDay(date, _selectedDate);

                                  return ListTile(
                                    dense: true,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    selected: isCurrent,
                                    selectedTileColor: const Color(0xFF2C4D75).withOpacity(0.1),
                                    leading: Icon(
                                      Icons.calendar_month,
                                      size: 18,
                                      color: isCurrent ? const Color(0xFF2C4D75) : theme.hintColor,
                                    ),
                                    title: Text(
                                      DateFormat('EEEE, MMMM d, y').format(date),
                                      style: TextStyle(
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    trailing: isCurrent
                                        ? const Icon(Icons.check_circle, size: 18, color: Color(0xFF2C4D75))
                                        : null,
                                    onTap: () {
                                      Navigator.pop(context);
                                      _changeDate(date);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showWidgetInstructions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C4D75).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.widgets, color: Color(0xFF2C4D75)),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Home Screen Widget',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Keep today’s scripture on your home screen',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Live widget preview
              const Text(
                'Widget Preview:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C4D75),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF4A6DA7)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'DAILY TEXT',
                          style: TextStyle(
                            color: Color(0xFFE0B066),
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _latestFetchedText?.dateTitle.isNotEmpty == true
                              ? _latestFetchedText!.dateTitle
                              : DateFormat('EEEE, MMMM d').format(_selectedDate),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _latestFetchedText?.scripture ?? 'Loading today\'s text…',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _latestFetchedText?.comment ?? 'Commentary will appear here.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Tap to open in JW Library / WOL',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _buildStepRow(
                '1',
                'Go to your Android home screen and touch and hold an empty space.',
              ),
              const SizedBox(height: 12),
              _buildStepRow(
                '2',
                'Tap Widgets from the popup menu.',
              ),
              const SizedBox(height: 12),
              _buildStepRow(
                '3',
                'Find "JW Daily Text" and drag the widget onto your home screen.',
              ),
              const SizedBox(height: 12),
              _buildStepRow(
                '4',
                'Tapping the widget opens directly in JW Library or Watchtower Online Library (WOL).',
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        if (_latestFetchedText != null) {
                          await HomeWidgetService.updateWidget(_latestFetchedText!);
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Widget updated with current text!'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.sync, size: 16),
                      label: const Text('Sync Widget'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2C4D75),
                      ),
                      child: const Text('Got it'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStepRow(String step, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(
            color: Color(0xFF2C4D75),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, height: 1.35),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _isSameDay(_selectedDate, DateTime.now());
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_stories, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Text(
              'JW Daily Text',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 19),
            ),
          ],
        ),
        actions: [
          // Favorites Section
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                tooltip: 'Favorite Scriptures',
                icon: const Icon(Icons.favorite),
                color: _favoritesCount > 0 ? Colors.redAccent : Colors.white,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FavoritesScreen(
                        selectedLanguage: _selectedLanguage,
                        fontScale: _fontScale,
                        onSelectDate: (d) => _changeDate(d),
                      ),
                    ),
                  ).then((_) => _checkFavoriteStatus(_selectedDate));
                },
              ),
              if (_favoritesCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$_favoritesCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Appearance & Dark Mode setting
          IconButton(
            tooltip: 'Appearance & Theme',
            icon: Icon(
              switch (context.watch<ThemeProvider>().themeMode) {
                ThemeMode.dark => Icons.dark_mode,
                ThemeMode.light => Icons.light_mode,
                ThemeMode.system => Icons.brightness_auto,
              },
            ),
            onPressed: _showThemeSettingsSheet,
          ),
          // Text size setting
          IconButton(
            tooltip: 'Text Size',
            icon: const Icon(Icons.format_size),
            onPressed: _showFontSizeDialog,
          ),
          // Daily reminder notification settings
          IconButton(
            tooltip: 'Morning Reminder',
            icon: const Icon(Icons.alarm),
            onPressed: _showNotificationSettings,
          ),
          // Offline storage button
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                tooltip: 'Offline Storage',
                icon: const Icon(Icons.offline_pin_outlined),
                onPressed: _showOfflineManagerSheet,
              ),
              if (_cachedCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Color(0xFFB57C2F),
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$_cachedCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Language selector
          PopupMenuButton<WolLanguage>(
            tooltip: 'Language',
            icon: const Icon(Icons.language),
            initialValue: _selectedLanguage,
            onSelected: _changeLanguage,
            itemBuilder: (context) {
              return WolLanguage.supportedLanguages.map((lang) {
                return PopupMenuItem<WolLanguage>(
                  value: lang,
                  child: Row(
                    children: [
                      Text(
                        lang.nativeName,
                        style: TextStyle(
                          fontWeight:
                              lang == _selectedLanguage ? FontWeight.bold : FontWeight.normal,
                          color: lang == _selectedLanguage ? theme.colorScheme.primary : null,
                        ),
                      ),
                      const Spacer(),
                      if (lang == _selectedLanguage)
                        Icon(Icons.check, size: 18, color: theme.colorScheme.primary),
                    ],
                  ),
                );
              }).toList();
            },
          ),
          // Widget instructions
          IconButton(
            tooltip: 'Home Widget Info',
            icon: const Icon(Icons.widgets_outlined),
            onPressed: _showWidgetInstructions,
          ),
          // Force refresh
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadDailyText(forceRefresh: true),
          ),
          // Settings
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // Date navigation header bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withOpacity(0.15),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous Day',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _changeDate(_selectedDate.subtract(const Duration(days: 1))),
                ),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              DateFormat('EEEE, MMM d, y').format(_selectedDate),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: theme.colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next Day',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _changeDate(_selectedDate.add(const Duration(days: 1))),
                ),
                if (!isToday)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _changeDate(DateTime.now()),
                      icon: const Icon(Icons.today, size: 16),
                      label: const Text('Today', style: TextStyle(fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
          // Main content
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                _loadDailyText(forceRefresh: true);
                await _dailyTextFuture;
              },
              child: FutureBuilder<DailyText>(
                future: _dailyTextFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _buildLoadingSkeleton(context);
                  }

                  if (snapshot.hasError) {
                    return _buildErrorView(
                      context,
                      snapshot.error.toString(),
                      onRetry: () => _loadDailyText(forceRefresh: true),
                    );
                  }

                  final dailyText = snapshot.data;
                  if (dailyText == null) {
                    return _buildErrorView(
                      context,
                      'No content available',
                      onRetry: () => _loadDailyText(forceRefresh: true),
                    );
                  }

                  return _buildDailyTextView(context, dailyText);
                },
              ),
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
          return _buildTtsPlayerBar(context, isPlaying);
        },
      ),
    );
  }

  Widget _buildDailyTextView(BuildContext context, DailyText dailyText) {
    final theme = Theme.of(context);
    final formattedDate = dailyText.dateTitle.isNotEmpty
        ? dailyText.dateTitle
        : DateFormat('EEEE, MMMM d, y').format(dailyText.date);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        // Meta header chip
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: dailyText.isCached
                    ? Colors.amber.withOpacity(0.15)
                    : const Color(0xFF2C4D75).withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    dailyText.isCached ? Icons.offline_pin : Icons.cloud_done_outlined,
                    size: 14,
                    color: dailyText.isCached ? Colors.amber[800] : const Color(0xFF2C4D75),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    dailyText.isCached ? 'Offline Cache' : 'Live from wol.jw.org',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: dailyText.isCached ? Colors.amber[900] : const Color(0xFF2C4D75),
                    ),
                  ),
                ],
              ),
            ),
            if (dailyText.fetchedAt != null) ...[
              const SizedBox(width: 8),
              Text(
                'Synced ${DateFormat('MMM d, h:mm a').format(dailyText.fetchedAt!)}',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.hintColor,
                ),
              ),
            ],
            const Spacer(),
            Text(
              _selectedLanguage.nativeName,
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodySmall?.color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Scripture Card
        Card(
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
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C4D75),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'THEME SCRIPTURE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: _isCurrentFavorite ? 'Remove from Favorites' : 'Add to Favorites',
                      icon: Icon(
                        _isCurrentFavorite ? Icons.favorite : Icons.favorite_border,
                        color: _isCurrentFavorite ? Colors.redAccent : null,
                        size: 20,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _toggleFavorite(dailyText),
                    ),
                    ValueListenableBuilder<TtsState>(
                      valueListenable: _ttsService.stateNotifier,
                      builder: (context, ttsState, _) {
                        final isPlaying = ttsState == TtsState.playing;
                        final isPaused = ttsState == TtsState.paused;
                        return IconButton(
                          tooltip: isPlaying
                              ? 'Pause Reading'
                              : (isPaused ? 'Resume Reading' : 'Listen with TTS'),
                          icon: Icon(
                            isPlaying
                                ? Icons.pause_circle_filled
                                : (isPaused ? Icons.play_circle_fill : Icons.volume_up),
                            color: (isPlaying || isPaused) ? const Color(0xFFB57C2F) : null,
                            size: 20,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _toggleTts(dailyText),
                        );
                      },
                    ),
                    IconButton(
                      tooltip: 'Share Scripture',
                      icon: const Icon(Icons.share, size: 18),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _showShareOptions(dailyText),
                    ),
                    IconButton(
                      tooltip: 'Copy Scripture',
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _copyToClipboard(dailyText, full: false),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  formattedDate,
                  style: TextStyle(
                    fontSize: 13 * _fontScale,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  dailyText.scripture,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    fontSize: 17 * _fontScale,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Comment Card
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.comment_outlined,
                      size: 16,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Explanation & Context',
                      style: TextStyle(
                        fontSize: 12 * _fontScale,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.secondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(
                  dailyText.comment,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.6,
                    fontSize: 15.5 * _fontScale,
                  ),
                ),
                if (dailyText.reference.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Divider(color: theme.dividerColor.withOpacity(0.1)),
                  const SizedBox(height: 8),
                  Text(
                    dailyText.reference,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      fontSize: 12 * _fontScale,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Action Buttons Row
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            ValueListenableBuilder<TtsState>(
              valueListenable: _ttsService.stateNotifier,
              builder: (context, ttsState, _) {
                final isPlaying = ttsState == TtsState.playing;
                return FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: isPlaying
                        ? const Color(0xFFB57C2F)
                        : const Color(0xFF385E8E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _toggleTts(dailyText),
                  icon: Icon(isPlaying ? Icons.pause : Icons.volume_up, size: 18),
                  label: Text(isPlaying ? 'Pause Audio' : 'Listen to Scripture'),
                );
              },
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2C4D75),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _showShareOptions(dailyText),
              icon: const Icon(Icons.share, size: 16),
              label: const Text('Share Daily Text'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _launchUrlSafe(dailyText.jwpubUri),
              icon: const Icon(Icons.launch, size: 16),
              label: const Text('Open in JW Library'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _launchUrlSafe(dailyText.webUri),
              icon: const Icon(Icons.open_in_browser, size: 16),
              label: const Text('Read on WOL'),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Home screen widget promo card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF2C4D75).withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF2C4D75).withOpacity(0.12),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C4D75).withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.home_outlined, color: Color(0xFF2C4D75)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Android Home Widget',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Displays today’s text right on your home screen.',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () async {
                      await HomeWidgetService.updateWidget(dailyText);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Home widget synced!'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('Sync'),
                  ),
                  TextButton(
                    onPressed: _showWidgetInstructions,
                    child: const Text('Setup'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTtsPlayerBar(BuildContext context, bool isPlaying) {
    final theme = Theme.of(context);
    final currentRate = _ttsService.speechRateNotifier.value;
    final currentSection = _ttsService.currentSectionNotifier.value;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
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
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isPlaying
                    ? const Color(0xFFB57C2F).withOpacity(0.15)
                    : const Color(0xFF2C4D75).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying ? Icons.record_voice_over : Icons.pause,
                color: isPlaying ? const Color(0xFFB57C2F) : const Color(0xFF2C4D75),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPlaying ? 'Reading Daily Text…' : 'Reading Paused',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    currentSection.isNotEmpty
                        ? currentSection
                        : '${_selectedLanguage.name} • ${currentRate}x speed',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Speed Chip
            ActionChip(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              labelPadding: const EdgeInsets.symmetric(horizontal: 6),
              label: Text('${currentRate}x', style: const TextStyle(fontSize: 11)),
              onPressed: () {
                final nextRate = currentRate >= 1.5 ? 0.75 : (currentRate + 0.25);
                _ttsService.setRate(nextRate);
                setState(() {});
              },
            ),
            const SizedBox(width: 4),
            // Play/Pause Button
            IconButton(
              tooltip: isPlaying ? 'Pause' : 'Resume',
              icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill),
              color: const Color(0xFF2C4D75),
              iconSize: 32,
              onPressed: () {
                if (_latestFetchedText != null) {
                  _toggleTts(_latestFetchedText!);
                }
              },
            ),
            // Stop Button
            IconButton(
              tooltip: 'Stop',
              icon: const Icon(Icons.stop_circle_outlined),
              color: Colors.redAccent,
              iconSize: 26,
              onPressed: () => _ttsService.stop(),
            ),
            if (_latestFetchedText != null)
              IconButton(
                tooltip: 'TTS Settings',
                icon: const Icon(Icons.tune, size: 20),
                onPressed: () => _showTtsSettingsSheet(_latestFetchedText!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            color: Color(0xFF2C4D75),
          ),
          const SizedBox(height: 18),
          Text(
            'Fetching daily scripture from wol.jw.org…',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(
    BuildContext context,
    String errorMessage, {
    required VoidCallback onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_off, size: 40, color: Colors.redAccent),
            ),
            const SizedBox(height: 16),
            const Text(
              'Couldn\'t load daily text',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage.contains('DailyTextException')
                  ? errorMessage.replaceAll('DailyTextException: ', '')
                  : 'Please check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2C4D75),
                  ),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    final webFallback =
                        'https://wol.jw.org/en/wol/dt/r${_selectedLanguage.rsconf}/lp-${_selectedLanguage.locale}/${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}';
                    _launchUrlSafe(webFallback);
                  },
                  icon: const Icon(Icons.open_in_browser, size: 16),
                  label: const Text('Open on WOL'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
