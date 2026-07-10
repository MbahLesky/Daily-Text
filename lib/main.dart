import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'core/home_widget/background_worker.dart';
import 'core/home_widget/home_widget_service.dart';
import 'features/daily_text/data/daily_text.dart';
import 'features/daily_text/data/daily_text_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Workmanager().initialize(callbackDispatcher);
  Workmanager().registerPeriodicTask(
    dailyTextRefreshTask,
    dailyTextRefreshTask,
    frequency: const Duration(hours: 12),
    constraints: Constraints(networkType: NetworkType.connected),
  );

  runApp(const DailyTextApp());
}

class DailyTextApp extends StatelessWidget {
  const DailyTextApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Text',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4A6DA7),
        useMaterial3: true,
      ),
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
  static const _service = DailyTextService();

  late Future<DailyText> _dailyTextFuture;

  @override
  void initState() {
    super.initState();
    _dailyTextFuture = _loadAndPublish();
  }

  /// Fetches today's text and immediately pushes it to the home widget so
  /// opening the app always keeps the widget in sync.
  Future<DailyText> _loadAndPublish() async {
    final dailyText = await _service.fetchDailyText();
    await HomeWidgetService.updateWidget(dailyText);
    return dailyText;
  }

  Future<void> _refresh() async {
    final next = _loadAndPublish();
    setState(() => _dailyTextFuture = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily Text')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<DailyText>(
          future: _dailyTextFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorView(onRetry: _refresh);
            }
            return _DailyTextView(dailyText: snapshot.data!);
          },
        ),
      ),
    );
  }
}

class _DailyTextView extends StatelessWidget {
  const _DailyTextView({required this.dailyText});

  final DailyText dailyText;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          dailyText.scripture,
          style: textTheme.titleLarge?.copyWith(fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 16),
        Text(dailyText.comment, style: textTheme.bodyLarge),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, size: 48),
          const SizedBox(height: 12),
          const Text("Couldn't load today's text."),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
