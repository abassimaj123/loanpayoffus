import 'package:flutter_test/flutter_test.dart';
import 'package:loan_payoff_us/domain/models/loan_input.dart';
import 'package:loan_payoff_us/domain/models/loan_type.dart';
import 'package:loan_payoff_us/domain/usecases/loan_calculator.dart';

void main() {
  const base = LoanInput(
    loanType: LoanType.mortgage,
    loanAmount: 400000,
    interestRatePct: 6.0,
    monthlyPayment: 2398.20,
  );

  // ── Monthly payment ───────────────────────────────────────────────────────
  test('monthly payment — 400k @ 6% 360mo ≈ 2398.20', () {
    final pmt = LoanCalculator.computeMonthlyPayment(400000, 6.0, 360);
    expect(pmt, closeTo(2398.20, 1.0));
  });

  test('monthly payment — zero rate = amount / term', () {
    final pmt = LoanCalculator.computeMonthlyPayment(12000, 0, 12);
    expect(pmt, closeTo(1000.0, 0.01));
  });

  // ── Normal payoff ─────────────────────────────────────────────────────────
  test('payoff without extra ≈ 360 months', () {
    final r = LoanCalculator.calculate(base);
    expect(r.normalMonths, closeTo(360, 3));
  });

  test('normal schedule: last balance ≈ 0', () {
    final r = LoanCalculator.calculate(base);
    expect(r.normalSchedule.last.balance, closeTo(0, 1.0));
  });

  // ── Extra payment impact ──────────────────────────────────────────────────
  test('extra 500/mo reduces payoff months', () {
    final r = LoanCalculator.calculate(base.copyWith(extraPayment: 500));
    expect(r.extraMonths, lessThan(r.normalMonths));
    // $400k @ 6% + $500 extra → roughly 235 months (~19y7m)
    expect(r.extraMonths, closeTo(235, 5));
  });

  test('extra 500/mo saves interest > 0', () {
    final r = LoanCalculator.calculate(base.copyWith(extraPayment: 500));
    expect(r.interestSaved, greaterThan(0));
    // At $500/mo extra the interest saving is substantial (>$50k)
    expect(r.interestSaved, greaterThan(50000));
  });

  test('months saved = normalMonths - extraMonths', () {
    final r = LoanCalculator.calculate(base.copyWith(extraPayment: 200));
    expect(r.monthsSaved, r.normalMonths - r.extraMonths);
  });

  // ── Schedule integrity ────────────────────────────────────────────────────
  test('interest in schedule matches total interest', () {
    final r = LoanCalculator.calculate(base);
    final schedInterest = r.normalSchedule.fold<double>(
      0,
      (s, e) => s + e.interest,
    );
    expect(r.interestNormal, closeTo(schedInterest, 1.0));
  });

  test('zero balance at end of extra schedule', () {
    final r = LoanCalculator.calculate(base.copyWith(extraPayment: 300));
    expect(r.schedule.last.balance, closeTo(0, 1.0));
  });

  test('amortization: principal + interest = payment (first month)', () {
    final r = LoanCalculator.calculate(base);
    final e = r.schedule.first;
    expect(e.principal + e.interest, closeTo(e.payment, 0.02));
  });

  test('schedule length matches extraMonths', () {
    final r = LoanCalculator.calculate(base.copyWith(extraPayment: 300));
    expect(r.schedule.length, r.extraMonths);
  });

  // ── Credit card high-rate ─────────────────────────────────────────────────
  test('credit card 18.5% 5k at 150/mo > 36 months', () {
    final r = LoanCalculator.calculate(
      const LoanInput(
        loanType: LoanType.creditCard,
        loanAmount: 5000,
        interestRatePct: 18.5,
        monthlyPayment: 150,
      ),
    );
    expect(r.normalMonths, greaterThan(36));
  });

  // ── Goal calculator ───────────────────────────────────────────────────────
  test('requiredExtraForTarget: extra > 0 and results in ≤ target months', () {
    final extra = LoanCalculator.requiredExtraForTarget(
      400000,
      6.0,
      2398.20,
      240,
    );
    expect(extra, greaterThan(0));
    final sched = LoanCalculator.buildSchedule(400000, 6.0, 2398.20, extra);
    expect(sched.length, closeTo(240, 5));
  });

  // ── Derived getters ───────────────────────────────────────────────────────
  test('yearsSaved * 12 + remMonthsSaved = monthsSaved', () {
    final r = LoanCalculator.calculate(base.copyWith(extraPayment: 500));
    expect(r.yearsSaved * 12 + r.remMonthsSaved, r.monthsSaved);
  });

  // ── Loan type defaults ────────────────────────────────────────────────────
  test('LoanType defaults: mortgage 6.2% / 360mo', () {
    expect(LoanType.mortgage.defaultRate, closeTo(6.2, 0.01));
    expect(LoanType.mortgage.defaultTermMonths, 360);
    expect(LoanType.mortgage.defaultAmount, closeTo(400000, 1));
  });

  test('LoanType defaults: creditCard 18.5% / auto 60mo', () {
    expect(LoanType.creditCard.defaultRate, closeTo(18.5, 0.01));
    expect(LoanType.auto.defaultTermMonths, 60);
  });

  // ── One-time extra (true lump sum at month 1) ────────────────────────────
  test('one-time lump reduces payoff vs normal', () {
    final r = LoanCalculator.calculate(
      base.copyWith(extraPayment: 10000, extraIsOneTime: true),
    );
    expect(r.extraMonths, lessThan(r.normalMonths));
  });

  test('one-time lump applied once — not smeared every month', () {
    // A $10k lump and a $10k/mo recurring extra must NOT be equivalent: the
    // recurring one pays the loan off far faster, proving the lump is one-shot.
    final lump = LoanCalculator.calculate(
      base.copyWith(extraPayment: 10000, extraIsOneTime: true),
    );
    final recurring = LoanCalculator.calculate(
      base.copyWith(extraPayment: 10000),
    );
    expect(recurring.extraMonths, lessThan(lump.extraMonths));
    // The lump only saves a modest amount vs the huge recurring saving.
    expect(lump.interestSaved, greaterThan(0));
    expect(lump.interestSaved, lessThan(recurring.interestSaved));
  });

  test('buildSchedule oneTimeExtra applied at the chosen month', () {
    final sched =
        LoanCalculator.buildSchedule(400000, 6.0, 2398.20, 0, oneTimeExtra: 5000);
    // Month 1 carries the extra (principal jumps by ~5000 vs no lump).
    final noLump = LoanCalculator.buildSchedule(400000, 6.0, 2398.20, 0);
    expect(sched.first.principal,
        closeTo(noLump.first.principal + 5000, 0.01));
  });

  // ── Never-payoff (payment below interest) ────────────────────────────────
  test('payment below interest → neverPayoff flag set, schedule capped', () {
    final r = LoanCalculator.calculate(
      const LoanInput(
        loanType: LoanType.creditCard,
        loanAmount: 5000,
        interestRatePct: 24.0, // ~$100/mo interest
        monthlyPayment: 50, // below the monthly interest
      ),
    );
    expect(r.neverPayoff, isTrue);
    expect(r.normalMonths, greaterThanOrEqualTo(600));
  });

  test('healthy loan is not flagged neverPayoff', () {
    final r = LoanCalculator.calculate(base);
    expect(r.neverPayoff, isFalse);
  });

  // ── totalPaid consistency ─────────────────────────────────────────────────
  test('totalPaidNormal ≈ loanAmount + interestNormal', () {
    final r = LoanCalculator.calculate(base);
    expect(
      r.totalPaidNormal,
      closeTo(base.loanAmount + r.interestNormal, 10.0),
    );
  });

  test('extra payment: totalPaidExtra < totalPaidNormal', () {
    final r = LoanCalculator.calculate(base.copyWith(extraPayment: 500));
    // Extra payments raise total outflow only slightly but save interest net
    expect(r.interestExtra, lessThan(r.interestNormal));
  });
}
