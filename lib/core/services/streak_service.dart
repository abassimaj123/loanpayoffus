import '../db/database_helper.dart';

class StreakService {
  StreakService._();

  /// Computes the current payment streak (consecutive months with ≥1 payment).
  /// Uses debt_payments.date_iso (ISO8601 date string).
  static Future<int> computeStreak() async {
    final payments = await DatabaseHelper.instance.getDebtPayments();
    if (payments.isEmpty) return 0;

    // Build a set of "YYYY-MM" strings from all payments.
    final months = <String>{};
    for (final row in payments) {
      final dateStr = row['date_iso'] as String?;
      if (dateStr == null || dateStr.isEmpty) continue;
      final dt = DateTime.tryParse(dateStr);
      if (dt == null) continue;
      // Normalize to "YYYY-MM"
      months.add('${dt.year}-${dt.month.toString().padLeft(2, '0')}');
    }

    if (months.isEmpty) return 0;

    // Walk backwards from the current month, counting consecutive months present.
    final now = DateTime.now();
    int streak = 0;
    int year = now.year;
    int month = now.month;

    while (true) {
      final key = '$year-${month.toString().padLeft(2, '0')}';
      if (!months.contains(key)) break;
      streak++;
      // Move one month back.
      month--;
      if (month == 0) {
        month = 12;
        year--;
      }
      // Safety cap: do not walk more than 120 months (10 years).
      if (streak > 120) break;
    }

    return streak;
  }

  /// Returns the debt (from a list) closest to being paid off and estimated
  /// months remaining.
  ///
  /// [debtList] — list of maps with keys: id, name, balance, monthlyPayment, rate
  /// Returns {name, monthsLeft, balance} or null if list is empty.
  static Map<String, dynamic>? nextVictory(
    List<Map<String, dynamic>> debtList,
  ) {
    if (debtList.isEmpty) return null;

    Map<String, dynamic>? best;
    double bestMonths = double.infinity;

    for (final debt in debtList) {
      final balance = (debt['balance'] as num?)?.toDouble() ?? 0;
      final monthlyPayment = (debt['monthlyPayment'] as num?)?.toDouble() ?? 0;
      if (balance <= 0) continue;
      if (monthlyPayment <= 0) continue;

      // Simple months-to-payoff estimate (ignores interest for UI purposes).
      final months = balance / monthlyPayment;
      if (months < bestMonths) {
        bestMonths = months;
        best = {
          'name': debt['name'] as String? ?? '',
          'monthsLeft': months.ceil(),
          'balance': balance,
        };
      }
    }

    return best;
  }
}
