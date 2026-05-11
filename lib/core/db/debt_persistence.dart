// Persists and loads the user's debt list via SharedPreferences (JSON).
// No Flutter imports — uses only dart:convert + shared_preferences.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/debt_item.dart';

class DebtPersistence {
  DebtPersistence._();
  static final DebtPersistence instance = DebtPersistence._();

  static const _key = 'debt_strategy_list_v1';

  Future<List<DebtItem>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_key);
      if (raw == null) return [];
      final list  = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => DebtItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<DebtItem> debts) async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = jsonEncode(debts.map((d) => d.toJson()).toList());
    await prefs.setString(_key, raw);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
