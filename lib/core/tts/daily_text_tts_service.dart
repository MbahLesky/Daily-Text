import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../features/daily_text/data/daily_text.dart';

enum TtsState { stopped, playing, paused }

/// Service managing Text-to-Speech playback for the JW daily scripture and commentary.
class DailyTextTtsService {
  DailyTextTtsService() {
    _initTts();
  }

  final FlutterTts _flutterTts = FlutterTts();

  final ValueNotifier<TtsState> stateNotifier =
      ValueNotifier<TtsState>(TtsState.stopped);

  final ValueNotifier<double> speechRateNotifier =
      ValueNotifier<double>(1.0);

  final ValueNotifier<String> currentSectionNotifier =
      ValueNotifier<String>('');

  bool _isInitialized = false;

  void _initTts() {
    if (_isInitialized) return;

    _flutterTts.setStartHandler(() {
      stateNotifier.value = TtsState.playing;
    });

    _flutterTts.setCompletionHandler(() {
      stateNotifier.value = TtsState.stopped;
      currentSectionNotifier.value = '';
    });

    _flutterTts.setPauseHandler(() {
      stateNotifier.value = TtsState.paused;
    });

    _flutterTts.setContinueHandler(() {
      stateNotifier.value = TtsState.playing;
    });

    _flutterTts.setCancelHandler(() {
      stateNotifier.value = TtsState.stopped;
      currentSectionNotifier.value = '';
    });

    _flutterTts.setErrorHandler((msg) {
      debugPrint('TTS Error: $msg');
      stateNotifier.value = TtsState.stopped;
      currentSectionNotifier.value = '';
    });

    _isInitialized = true;
  }

  /// Maps Watchtower library locale code to TTS language tag.
  static String mapLanguage(String locale) {
    switch (locale.toLowerCase()) {
      case 'e':
        return 'en-US';
      case 'pgw':
        return 'en-NG'; // Nigerian / West African English
      case 's':
        return 'es-ES';
      case 'f':
        return 'fr-FR';
      case 'x':
        return 'de-DE';
      case 't':
        return 'pt-BR';
      case 'i':
        return 'it-IT';
      case 'j':
        return 'ja-JP';
      case 'tg':
        return 'fil-PH';
      case 'u':
        return 'ru-RU';
      default:
        return 'en-US';
    }
  }

  /// Starts speaking the given [dailyText].
  /// If [full] is true, speaks date, scripture, and commentary.
  /// If [full] is false, speaks only date and theme scripture.
  Future<void> speakDailyText(
    DailyText dailyText, {
    bool full = true,
  }) async {
    try {
      await stop();

      final langCode = mapLanguage(dailyText.locale);
      await _flutterTts.setLanguage(langCode);

      // Default rate: 0.5 in flutter_tts corresponds to normal 1.0x speed on Android/iOS
      final adjustedRate = (speechRateNotifier.value * 0.5).clamp(0.1, 1.0);
      await _flutterTts.setSpeechRate(adjustedRate);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setVolume(1.0);

      final dateSpeech = dailyText.dateTitle.isNotEmpty
          ? dailyText.dateTitle
          : 'Today\'s scripture';

      final buffer = StringBuffer();
      buffer.writeln(dateSpeech);
      buffer.writeln('. ');
      buffer.writeln(dailyText.scripture);

      if (full && dailyText.comment.isNotEmpty) {
        buffer.writeln('. ');
        buffer.writeln(dailyText.comment);
      }

      currentSectionNotifier.value = full ? 'Reading full daily text' : 'Reading scripture';
      stateNotifier.value = TtsState.playing;

      final textToSpeak = _sanitizeTextForSpeech(buffer.toString());
      await _flutterTts.speak(textToSpeak);
    } catch (e) {
      debugPrint('Error starting TTS: $e');
      stateNotifier.value = TtsState.stopped;
      currentSectionNotifier.value = '';
    }
  }

  /// Pauses active speech.
  Future<void> pause() async {
    try {
      await _flutterTts.pause();
      stateNotifier.value = TtsState.paused;
    } catch (e) {
      debugPrint('Error pausing TTS: $e');
    }
  }

  /// Resumes playback or resumes speech.
  Future<void> resume(DailyText dailyText) async {
    if (stateNotifier.value == TtsState.paused) {
      // Some engines require re-calling speak
      await speakDailyText(dailyText);
    }
  }

  /// Stops TTS speech completely.
  Future<void> stop() async {
    try {
      await _flutterTts.stop();
      stateNotifier.value = TtsState.stopped;
      currentSectionNotifier.value = '';
    } catch (e) {
      debugPrint('Error stopping TTS: $e');
    }
  }

  /// Adjusts speech rate (e.g. 0.8x, 1.0x, 1.2x, 1.5x).
  Future<void> setRate(double rate) async {
    speechRateNotifier.value = rate;
    try {
      final adjustedRate = (rate * 0.5).clamp(0.1, 1.0);
      await _flutterTts.setSpeechRate(adjustedRate);
    } catch (_) {}
  }

  /// Cleans up special characters and HTML-like artifacts for natural voice synthesis.
  static String _sanitizeTextForSpeech(String text) {
    return text
        .replaceAll('—', ', ') // Replace em-dash with pause
        .replaceAll('–', ', ')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void dispose() {
    stop();
    stateNotifier.dispose();
    speechRateNotifier.dispose();
    currentSectionNotifier.dispose();
  }
}
