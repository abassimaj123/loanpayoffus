// Golden reference tests — LoanPayoffUS
// Focus: rate is PERCENT (7.0, not 0.07) + wrong-unit smoke test
// Source: standard PMT formula, US consumer finance calculators.

import 'package:flutter_test/flutter_test.dart';
import 'package:loan_payoff_us/domain/usecases/loan_calculator.dart';

void main() {
  void approx(double actual, double expected, {double tol = 1.0}) {
    expect(actual, closeTo(expected, tol),
        reason: 'Expected ~$expected, got $actual');
  }

  // ── computeMonthlyPayment — rate is PERCENT ───────────────────────────────

  group('LoanCalculator.computeMonthlyPayment — rate is PERCENT (7.0, not 0.07)', () {
    test('LP-G1: \$15,000 @ 7.0% / 48mo → \$359.24', () {
      approx(LoanCalculator.computeMonthlyPayment(15000, 7.0, 48), 359.24, tol: 0.5);
    });

    test('LP-G2: \$25,000 @ 9.9% / 60mo → ≈ \$530', () {
      approx(LoanCalculator.computeMonthlyPayment(25000, 9.9, 60), 530, tol: 2.0);
    });

    test('LP-G3: 0% rate → amount / termMonths', () {
      approx(LoanCalculator.computeMonthlyPayment(10000, 0.0, 60), 166.67, tol: 0.01);
    });

    test('LP-G4: total interest = payment×months - principal ≈ \$2,243', () {
      final payment = LoanCalculator.computeMonthlyPayment(15000, 7.0, 48);
      approx(payment * 48 - 15000, 2243, tol: 5);
    });
  });

  // ── wrong-unit smoke test ────────────────────────────────────────────────

  group('Wrong-unit detection: passing 0.07 instead of 7.0', () {
    test('LP-W1: decimal rate → payment ≈ \$313 not \$359 (13% error, detectable)', () {
      // At near-zero rate, payment ≈ principal/n = 15000/48 = $312.50
      // Difference from correct ($359.24) is $46.74 — clearly wrong
      final wrong = LoanCalculator.computeMonthlyPayment(15000, 0.07, 48);
      expect(wrong, isNot(closeTo(359.24, 30))); // differs by ~46 → not within 30
      expect(wrong, lessThan(330));               // result is noticeably low
    });
  });

  // ── buildSchedule integrity ───────────────────────────────────────────────

  group('LoanCalculator.buildSchedule', () {
    test('LP-G5: first month interest = balance × rate/12', () {
      const amount = 15000.0;
      final payment = LoanCalculator.computeMonthlyPayment(amount, 7.0, 48);
      final schedule = LoanCalculator.buildSchedule(amount, 7.0, payment, 0);
      approx(schedule.first.interest, amount * (7.0 / 100 / 12), tol: 0.01);
    });

    test('LP-G6: 48-month loan → 48 entries', () {
      final payment = LoanCalculator.computeMonthlyPayment(15000, 7.0, 48);
      expect(LoanCalculator.buildSchedule(15000, 7.0, payment, 0).length, 48);
    });

    test('LP-G7: final balance ≈ \$0', () {
      final payment = LoanCalculator.computeMonthlyPayment(15000, 7.0, 48);
      final schedule = LoanCalculator.buildSchedule(15000, 7.0, payment, 0);
      approx(schedule.last.balance, 0.0, tol: 0.10);
    });

    test('LP-G8: extra payment reduces total interest', () {
      final payment = LoanCalculator.computeMonthlyPayment(15000, 7.0, 48);
      final noExtra = LoanCalculator.buildSchedule(15000, 7.0, payment, 0);
      final withExtra = LoanCalculator.buildSchedule(15000, 7.0, payment, 100);
      expect(withExtra.fold<double>(0.0, (s, e) => s + e.interest),
          lessThan(noExtra.fold<double>(0.0, (s, e) => s + e.interest)));
    });
  });
}
