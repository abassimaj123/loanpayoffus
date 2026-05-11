import '../models/debt_item.dart';

class DebtPayoffDate {
  final String name;
  final int    monthPaidOff;

  const DebtPayoffDate({required this.name, required this.monthPaidOff});
}

class StrategyResult {
  final int                  totalMonths;
  final double               totalInterest;
  final List<DebtPayoffDate> debtPayoffDates;

  const StrategyResult({
    required this.totalMonths,
    required this.totalInterest,
    required this.debtPayoffDates,
  });
}

class DebtStrategyCalculator {
  // ---------- Avalanche: highest-rate first ----------
  static StrategyResult runAvalanche(
      List<DebtItem> debts, double extraMonthly) {
    return _run(
      debts:        debts,
      extraMonthly: extraMonthly,
      comparator:   (a, b) => b.annualRate.compareTo(a.annualRate),
    );
  }

  // ---------- Snowball: lowest-balance first ----------
  static StrategyResult runSnowball(
      List<DebtItem> debts, double extraMonthly) {
    return _run(
      debts:        debts,
      extraMonthly: extraMonthly,
      comparator:   (a, b) => a.balance.compareTo(b.balance),
    );
  }

  // ---------- Shared simulation core ----------
  static StrategyResult _run({
    required List<DebtItem> debts,
    required double         extraMonthly,
    required int Function(DebtItem, DebtItem) comparator,
  }) {
    if (debts.isEmpty) {
      return const StrategyResult(
          totalMonths: 0, totalInterest: 0, debtPayoffDates: []);
    }

    // Working state: mutable balances keyed by index
    final balances = List<double>.from(debts.map((d) => d.balance));
    final payoffDates = <DebtPayoffDate>[];
    double totalInterest = 0;
    int    month         = 0;

    while (balances.any((b) => b > 0.005) && month < 1200) {
      month++;

      // 1. Build list of active (unpaid) indices sorted by strategy priority
      final activeIndices = [
        for (int i = 0; i < debts.length; i++)
          if (balances[i] > 0.005) i
      ]..sort((a, b) => comparator(debts[a], debts[b]));

      // 2. Pay minimum on every active debt; collect freed-up payments
      double leftover = extraMonthly;

      for (final i in activeIndices) {
        final r        = debts[i].annualRate / 100 / 12;
        final interest = balances[i] * r;
        totalInterest += interest;

        var principal = debts[i].minPayment - interest;
        if (principal < 0) principal = 0;
        if (principal > balances[i]) principal = balances[i];

        balances[i] -= principal;
        if (balances[i] < 0) balances[i] = 0;
      }

      // 3. Apply extra to the priority debt
      for (final i in activeIndices) {
        if (leftover <= 0) break;
        final apply = leftover < balances[i] ? leftover : balances[i];
        balances[i] -= apply;
        if (balances[i] < 0) balances[i] = 0;
        leftover -= apply;
      }

      // 4. Snowball: freed minimums roll into leftover for next month
      //    (handled implicitly: paid-off debts no longer receive min payment,
      //     so their minimum amount becomes available extra in subsequent months)
      //    We add freed minimums as additional extra on priority debt.
      double freed = 0;
      for (int i = 0; i < debts.length; i++) {
        if (balances[i] <= 0.005 &&
            !payoffDates.any((p) => p.name == debts[i].name)) {
          payoffDates.add(DebtPayoffDate(name: debts[i].name, monthPaidOff: month));
          freed += debts[i].minPayment;
          balances[i] = 0;
        }
      }

      // Freed minimums go to priority debt next month — captured by modifying
      // extraMonthly for the next iteration
      extraMonthly += freed;
    }

    payoffDates.sort((a, b) => a.monthPaidOff.compareTo(b.monthPaidOff));

    return StrategyResult(
      totalMonths:    month,
      totalInterest:  totalInterest,
      debtPayoffDates: payoffDates,
    );
  }
}
