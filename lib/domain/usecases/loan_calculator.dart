import 'dart:math' as math;
import '../models/amortization_entry.dart';
import '../models/loan_input.dart';
import '../models/payoff_result.dart';

class LoanCalculator {
  static double computeMonthlyPayment(
    double amount,
    double annualRatePct,
    int termMonths,
  ) {
    if (annualRatePct == 0) return amount / termMonths;
    final r = annualRatePct / 100 / 12;
    return amount *
        (r * math.pow(1 + r, termMonths)) /
        (math.pow(1 + r, termMonths) - 1);
  }

  static List<AmortizationEntry> buildSchedule(
    double loanAmount,
    double annualRatePct,
    double monthlyPayment,
    double extraPayment,
  ) {
    final schedule = <AmortizationEntry>[];
    final r = annualRatePct / 100 / 12;
    double balance = loanAmount;
    int month = 1;

    while (balance > 0.01 && month <= 600) {
      final interest = balance * r;
      var principal = monthlyPayment - interest + extraPayment;
      if (principal <= 0) principal = 0.01; // avoid infinite loop
      if (principal > balance) principal = balance;
      final payment = interest + principal;
      balance -= principal;
      if (balance < 0) balance = 0;

      schedule.add(
        AmortizationEntry(
          month: month,
          payment: payment,
          principal: principal,
          interest: interest,
          balance: balance,
          extraPayment: extraPayment,
        ),
      );
      month++;
      if (balance <= 0) break;
    }
    return schedule;
  }

  static PayoffResult calculate(LoanInput input) {
    final normalSched = buildSchedule(
      input.loanAmount,
      input.interestRatePct,
      input.monthlyPayment,
      0,
    );
    final extraSched = buildSchedule(
      input.loanAmount,
      input.interestRatePct,
      input.monthlyPayment,
      input.extraPayment,
    );

    final normalMonths = normalSched.length;
    final extraMonths = extraSched.length;
    final monthsSaved = (normalMonths - extraMonths).clamp(0, normalMonths);

    final interestNormal = normalSched.fold<double>(
      0,
      (s, e) => s + e.interest,
    );
    final interestExtra = extraSched.fold<double>(0, (s, e) => s + e.interest);
    final interestSaved = (interestNormal - interestExtra).clamp(
      0.0,
      double.infinity,
    );

    final totalNormal = normalSched.fold<double>(0, (s, e) => s + e.payment);
    final totalExtra = extraSched.fold<double>(0, (s, e) => s + e.payment);

    return PayoffResult(
      normalMonths: normalMonths,
      extraMonths: extraMonths,
      monthsSaved: monthsSaved,
      interestNormal: interestNormal,
      interestExtra: interestExtra,
      interestSaved: interestSaved,
      totalPaidNormal: totalNormal,
      totalPaidExtra: totalExtra,
      schedule: extraSched,
      normalSchedule: normalSched,
    );
  }

  /// Biweekly payment mode.
  ///
  /// payment = monthlyPayment / 2, 26 payments/year
  /// effectiveMonthly = biweeklyPayment * 26 / 12  (≈ 13 monthly payments/yr)
  static Map<String, double> calculateBiweekly(
    double principal,
    double annualRatePct,
    int termMonths,
  ) {
    final monthlyPayment = computeMonthlyPayment(
      principal,
      annualRatePct,
      termMonths,
    );
    final biweeklyPayment = monthlyPayment / 2;
    final effectiveMonthly = biweeklyPayment * 26 / 12;

    final monthlySched = buildSchedule(
      principal,
      annualRatePct,
      monthlyPayment,
      0,
    );
    final biweeklySched = buildSchedule(
      principal,
      annualRatePct,
      effectiveMonthly,
      0,
    );

    final interestMonthly = monthlySched.fold<double>(
      0,
      (s, e) => s + e.interest,
    );
    final interestBiweekly = biweeklySched.fold<double>(
      0,
      (s, e) => s + e.interest,
    );

    final monthsSaved = (monthlySched.length - biweeklySched.length)
        .clamp(0, monthlySched.length)
        .toDouble();
    final interestSaved = (interestMonthly - interestBiweekly).clamp(
      0.0,
      double.infinity,
    );

    return {
      'biweeklyPayment': biweeklyPayment,
      'totalInterest': interestBiweekly,
      'monthsSaved': monthsSaved,
      'interestSaved': interestSaved,
    };
  }

  static double requiredExtraForTarget(
    double loanAmount,
    double annualRatePct,
    double monthlyPayment,
    int targetMonths,
  ) {
    double lo = 0, hi = loanAmount;
    for (int i = 0; i < 50; i++) {
      final mid = (lo + hi) / 2;
      final sched = buildSchedule(
        loanAmount,
        annualRatePct,
        monthlyPayment,
        mid,
      );
      if (sched.length <= targetMonths) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return (lo + hi) / 2;
  }
}
