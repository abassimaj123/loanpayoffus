import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

final isSpanishNotifier = ValueNotifier<bool>(false);

/// Initialises [isSpanishNotifier] from saved preference or system locale.
/// Saved 'language' key ('en'/'es') takes priority; falls back to system locale
/// (Spanish only if languageCode == 'es', English for everything else).
Future<void> loadSavedLanguage() async {
  final locales = PlatformDispatcher.instance.locales;
  final systemLang = locales.isNotEmpty ? locales.first.languageCode : 'en';
  final prefs = await SharedPreferences.getInstance();
  final savedLang = prefs.getString('language');
  isSpanishNotifier.value = (savedLang ?? systemLang) == 'es';
}
