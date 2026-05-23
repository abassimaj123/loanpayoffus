// Pure Dart — no Flutter imports.
// Implements Snowball & Avalanche multi-debt payoff simulations with:
//   • month-by-month payment allocations per debt
//   • per-debt payoff date
//   • total interest and total months
//   • minimum-only baseline for "interest saved" computation

import '../../domain/models/debt_item.dart';

// ---------------------------------------------------------------------------
// Value types
// ---------------------------------------------------------------------------

/// One month's payment record for a single debt.
class MonthlyAllocation {
  final int month;
  final String debtName;
  final double interest;
  final double principal;
  final double endingBalance;

  const MonthlyAllocation({
    required this.month,
    required this.debtName,
    required this.interest,
    required this.principal,
    required this.endingBalance,
  });
}

/// Per-debt summary in a strategy run.
class DebtPayoffSummary {
  final String name;
  final int monthPaidOff; // 1-based month number
  final double interestPaid;

  const DebtPayoffSummary({
    required this.name,
    required this.monthPaidOff,
    required this.interestPaid,
  });
}

/// Full result of a strategy simulation.
class EngineResult {
  /// Total months until all debts reach zero.
  final int totalMonths;

  /// Total interest paid across all debts.
  final double totalInterest;

  /// Per-debt payoff summaries, ordered by payoff month (earliest first).
  final List<DebtPayoffSummary> payoffOrder;

  /// Complete month-by-month allocation table (all debts, all months).
  /// Premium-gated in the UI.
  final List<MonthlyAllocation> monthlyAllocations;

  const EngineResult({
    required this.totalMonths,
    required this.totalInterest,
    required this.payoffOrder,
    required this.monthlyAllocations,
  });
}

// ---------------------------------------------------------------------------
// Strategy enum
// ---------------------------------------------------------------------------

enum PayoffStrategy { avalanche, snowball }

// ---------------------------------------------------------------------------
// Snowflake (one-time windfall) parameters
// ---------------------------------------------------------------------------

/// Describes a one-time extra principal payment applied in a specific month.
class SnowflakePayment {
  /// Dollar amount of the windfall payment.
  final double amount;

  /// 1-based month number when the payment is applied (1 = now).
  final int month;

  const SnowflakePayment({required this.amount, required this.month});
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

class DebtStrategyEngine {
  DebtStrategyEngine._();

  // ---------- Public API ----------

  static EngineResult run({
    required List<DebtItem> debts,
    required double extraMonthly,
    required PayoffStrategy strategy,
    SnowflakePayment? snowflake,
  }) {
    return _simulate(
      debts: debts,
      extraMonthly: extraMonthly,
      comparator: _comparatorFor(strategy),
      snowflake: snowflake,
    );
  }

  /// Run with zero extra payment to get the minimum-only baseline.
  static EngineResult runMinimumOnly(List<DebtItem> debts) {
    // Use avalanche order for minimum-only; order doesn't matter for total
    // interest when extra = 0, but avalanche is the conventional baseline.
    return _simulate(
      debts: debts,
      extraMonthly: 0,
      comparator: _comparatorFor(PayoffStrategy.avalanche),
    );
  }

  // ---------- Internals ----------

  static int Function(DebtItem, DebtItem) _comparatorFor(PayoffStrategy s) {
    switch (s) {
      case PayoffStrategy.avalanche:
        return (a, b) => b.annualRate.compareTo(a.annualRate);
      case PayoffStrategy.snowball:
        return (a, b) => a.balance.compareTo(b.balance);
    }
  }

  static EngineResult _simulate({
    required List<DebtItem> debts,
    required double extraMonthly,
    required int Function(DebtItem, DebtItem) comparator,
    SnowflakePayment? snowflake,
  }) {
    if (debts.isEmpty) {
      return const EngineResult(
        totalMonths: 0,
        totalInterest: 0,
        payoffOrder: [],
        monthlyAllocations: [],
      );
    }

    // Mutable working state
    final balances = List<double>.from(debts.map((d) => d.balance));
    final debtInterest = List<double>.filled(debts.length, 0.0);
    final payoffSummaries = <DebtPayoffSummary>[];
    final allocations = <MonthlyAllocation>[];
    final recordedPayoff = List<bool>.filled(debts.length, false);

    double runningExtra = extraMonthly;
    double totalInterest = 0;
    int month = 0;
    const int maxMonths = 1200; // 100-year safety cap

    while (balances.any((b) => b > 0.005) && month < maxMonths) {
      month++;

      // Build priority-sorted list of active debt indices
      final active = [
        for (int i = 0; i < debts.length; i++)
          if (balances[i] > 0.005) i,
      ]..sort((a, b) => comparator(debts[a], debts[b]));

      // Step 1 — accrue interest and apply minimum payments
      for (final i in active) {
        final monthlyRate = debts[i].annualRate / 100 / 12;
        final interest = balances[i] * monthlyRate;
        totalInterest += interest;
        debtInterest[i] += interest;

        var principal = debts[i].minPayment - interest;
        if (principal < 0) principal = 0;
        if (principal > balances[i]) principal = balances[i];

        final endBalance = balances[i] - principal;
        balances[i] = endBalance < 0 ? 0 : endBalance;

        allocations.add(
          MonthlyAllocation(
            month: month,
            debtName: debts[i].name,
            interest: interest,
            principal: principal,
            endingBalance: balances[i],
          ),
        );
      }

      // Step 2 — apply extra to priority debt (first active by strategy order)
      // If this is the snowflake month, add the windfall to the extra pool.
      double snowflakeThisMonth = 0;
      if (snowflake != null && month == snowflake.month) {
        snowflakeThisMonth = snowflake.amount;
      }
      double leftover = runningExtra + snowflakeThisMonth;
      for (final i in active) {
        if (leftover <= 0) break;
        if (balances[i] <= 0.005) continue;
        final apply = leftover < balances[i] ? leftover : balances[i];
        balances[i] -= apply;
        if (balances[i] < 0) balances[i] = 0;
        leftover -= apply;

        // Update the last allocation entry for this debt this month
        // (update endingBalance to reflect extra payment)
        for (int k = allocations.length - 1; k >= 0; k--) {
          if (allocations[k].month == month &&
              allocations[k].debtName == debts[i].name) {
            allocations[k] = MonthlyAllocation(
              month: allocations[k].month,
              debtName: allocations[k].debtName,
              interest: allocations[k].interest,
              principal: allocations[k].principal + apply,
              endingBalance: balances[i],
            );
            break;
          }
        }
      }

      // Step 3 — snowball: freed minimum payments roll into runningExtra
      double freed = 0;
      for (int i = 0; i < debts.length; i++) {
        if (!recordedPayoff[i] && balances[i] <= 0.005) {
          recordedPayoff[i] = true;
          payoffSummaries.add(
            DebtPayoffSummary(
              name: debts[i].name,
              monthPaidOff: month,
              interestPaid: debtInterest[i],
            ),
          );
          freed += debts[i].minPayment;
          balances[i] = 0;
        }
      }
      runningExtra += freed;
    }

    payoffSummaries.sort((a, b) => a.monthPaidOff.compareTo(b.monthPaidOff));

    return EngineResult(
      totalMonths: month,
      totalInterest: totalInterest,
      payoffOrder: payoffSummaries,
      monthlyAllocations: allocations,
    );
  }
}
