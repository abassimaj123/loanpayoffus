import 'dart:convert';

import 'package:calcwise_core/calcwise_core.dart' show DatabaseAdapter;
import 'database_helper.dart';

/// DatabaseAdapter implementation for LoanPayoffUS.
///
/// Bridges SmartHistoryService (which speaks HistoryEntry / l1_json / l2_json)
/// to LoanPayoffUS's flat sqflite `history` table.
///
/// `app_key` / `screen_id` are always 'loanpayoffus' / 'calculator' for this
/// app. The flat columns (loan_amount, interest_rate, …) are preserved so the
/// existing HistoryDetailScreen continues to read them directly.
class LoanPayoffUSDatabaseAdapter implements DatabaseAdapter {
  static const _appKey = 'loanpayoffus';
  static const _screenId = 'calculator';

  // ── Insert ──────────────────────────────────────────────────────────────────

  @override
  Future<int> insertRow(Map<String, dynamic> row) async {
    final l2 = jsonDecode(row['l2_json'] as String) as Map<String, dynamic>;
    final savedAt = DateTime.fromMillisecondsSinceEpoch(row['saved_at'] as int);

    return DatabaseHelper.instance.insertHistory({
      'loan_type': (l2['loan_type'] as String?) ?? '',
      'loan_amount': (l2['loan_amount'] as num?)?.toDouble() ?? 0.0,
      'interest_rate': (l2['interest_rate'] as num?)?.toDouble() ?? 0.0,
      'monthly_payment': (l2['monthly_payment'] as num?)?.toDouble() ?? 0.0,
      'extra_payment': (l2['extra_payment'] as num?)?.toDouble() ?? 0.0,
      'normal_months': (l2['normal_months'] as num?)?.toInt() ?? 0,
      'interest_saved': (l2['interest_saved'] as num?)?.toDouble() ?? 0.0,
      'created_at': savedAt.toIso8601String(),
      'input_hash': row['result_hash'],
      'is_pinned': row['is_pinned'] ?? 0,
      'pin_label': row['pin_label'],
      'pin_order': row['pin_order'] ?? 0,
      'l1_json': row['l1_json'],
    });
  }

  // ── Query ────────────────────────────────────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>> getRows({
    required String appKey,
    String? screenId,
    bool? isPinned,
    int? limit,
  }) async {
    final db = await DatabaseHelper.instance.database;
    String? where;
    List<dynamic>? whereArgs;
    if (isPinned != null) {
      where = 'is_pinned = ?';
      whereArgs = [isPinned ? 1 : 0];
    }
    final rows = await db.query(
      'history',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'is_pinned DESC, pin_order DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(_toAdapterRow).toList();
  }

  @override
  Future<Map<String, dynamic>?> getRowByHash({
    required String appKey,
    required String resultHash,
  }) async {
    final row = await DatabaseHelper.instance.getHistoryByHash(resultHash);
    return row == null ? null : _toAdapterRow(row);
  }

  // ── Update / Delete ──────────────────────────────────────────────────────────

  @override
  Future<int> updateRow(int id, Map<String, dynamic> values) async {
    return DatabaseHelper.instance.updateHistoryEntry(id, values);
  }

  @override
  Future<int> deleteRow(int id) async {
    await DatabaseHelper.instance.deleteHistory(id);
    return 1;
  }

  // ── Count / Eviction ─────────────────────────────────────────────────────────

  @override
  Future<int> countRows({required String appKey, bool? isPinned}) async {
    return DatabaseHelper.instance.countHistory(isPinned: isPinned);
  }

  @override
  Future<List<Map<String, dynamic>>> getOldestAutoSaves({
    required String appKey,
    required int limit,
  }) async {
    final rows = await DatabaseHelper.instance.getOldestAutoSaves(limit);
    return rows.map(_toAdapterRow).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getOldestPinned({
    required String appKey,
    required int limit,
  }) async {
    final rows = await DatabaseHelper.instance.getOldestPinnedEntries(limit);
    return rows.map(_toAdapterRow).toList();
  }

  // ── Mapping ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> _toAdapterRow(Map<String, dynamic> row) {
    final createdAt =
        DateTime.tryParse(row['created_at'] as String? ?? '')
            ?.millisecondsSinceEpoch ??
        0;
    final l1Json = (row['l1_json'] as String?) ?? _buildDefaultL1Json(row);
    final l2Json = _buildL2Json(row);
    return {
      'id': row['id'],
      'app_key': _appKey,
      'screen_id': _screenId,
      'result_hash': (row['input_hash'] as String?) ?? '',
      'l1_json': l1Json,
      'l2_json': l2Json,
      'saved_at': createdAt,
      'is_pinned': (row['is_pinned'] as int?) ?? 0,
      'pin_label': row['pin_label'],
      'pin_order': (row['pin_order'] as int?) ?? 0,
    };
  }

  String _buildDefaultL1Json(Map<String, dynamic> row) {
    return jsonEncode({
      'loan_type': row['loan_type'],
      'loan_amount': (row['loan_amount'] as num?)?.toDouble() ?? 0.0,
      'monthly_payment': (row['monthly_payment'] as num?)?.toDouble() ?? 0.0,
      'interest_rate': (row['interest_rate'] as num?)?.toDouble() ?? 0.0,
    });
  }

  String _buildL2Json(Map<String, dynamic> row) {
    return jsonEncode({
      'loan_type': row['loan_type'],
      'loan_amount': row['loan_amount'],
      'interest_rate': row['interest_rate'],
      'monthly_payment': row['monthly_payment'],
      'extra_payment': row['extra_payment'],
      'normal_months': row['normal_months'],
      'interest_saved': row['interest_saved'],
    });
  }
}
