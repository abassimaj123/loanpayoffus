import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart' show Insight, InsightSeverity;
export 'package:calcwise_core/calcwise_core.dart' show Insight, InsightSeverity;

// ── Engine ────────────────────────────────────────────────────────────────────

class InsightEngine {
  InsightEngine._();

  /// Returns up to [maxCount] insights (most actionable first) given the
  /// loan payoff calculation inputs and results.
  static List<Insight> generate({
    required double balance,
    required double annualRatePct,
    required double monthlyPayment,
    required int    monthsToPayoff,
    required double totalInterest,
    double? extraMonthlyPayment,
    int?    monthsSavedWithExtra,
    double? interestSavedWithExtra,
    bool    isEs = false,
    int     maxCount = 3,
  }) {
    final insights = <Insight>[];

    // ── 1. Total interest warning ─────────────────────────────────────────────
    if (balance > 0 && totalInterest > balance * 0.5) {
      final pct = (totalInterest / balance * 100).round();
      insights.add(Insight(
        severity: InsightSeverity.alert,
        icon:     Icons.warning_amber_rounded,
        title: isEs
            ? 'Alto Costo de Interés'
            : 'High Interest Cost',
        body: isEs
            ? 'Pagarás ${_fmt(totalInterest)} en intereses — $pct% de tu saldo original.'
            : 'You\'ll pay ${_fmt(totalInterest)} in interest — $pct% of your balance.',
      ));
    }

    // ── 2. Minimum payment danger ─────────────────────────────────────────────
    // Estimate payoff years at current monthly payment
    if (monthsToPayoff > 84) { // > 7 years
      final years = (monthsToPayoff / 12).toStringAsFixed(1);
      insights.add(Insight(
        severity: InsightSeverity.alert,
        icon:     Icons.access_time_rounded,
        title: isEs
            ? 'Pago Mínimo Peligroso'
            : 'Minimum Payment Danger',
        body: isEs
            ? 'A ${_fmt(monthlyPayment)}/mes, estarás en deuda por $years años.'
            : 'At ${_fmt(monthlyPayment)}/mo minimum, you\'ll be debt-free in $years years.',
      ));
    }

    // ── 3. Extra payment savings ──────────────────────────────────────────────
    if (extraMonthlyPayment != null &&
        extraMonthlyPayment > 0 &&
        monthsSavedWithExtra != null &&
        monthsSavedWithExtra > 0 &&
        interestSavedWithExtra != null &&
        interestSavedWithExtra > 0) {
      insights.add(Insight(
        severity: InsightSeverity.good,
        icon:     Icons.rocket_launch_outlined,
        title: isEs
            ? 'Pago Extra Acelera tu Deuda'
            : 'Extra Payment Boost',
        body: isEs
            ? 'Agregar ${_fmt(extraMonthlyPayment)}/mes recorta $monthsSavedWithExtra meses y ahorra ${_fmt(interestSavedWithExtra)} en intereses.'
            : 'Adding ${_fmt(extraMonthlyPayment)}/mo cuts payoff by $monthsSavedWithExtra months and saves ${_fmt(interestSavedWithExtra)} in interest.',
      ));
    }

    // ── 4. Debt avalanche tip ─────────────────────────────────────────────────
    if (annualRatePct >= 15.0) {
      insights.add(Insight(
        severity: InsightSeverity.warning,
        icon:     Icons.trending_down_outlined,
        title: isEs
            ? 'Estrategia Avalancha'
            : 'Avalanche Strategy',
        body: isEs
            ? 'Con una tasa del ${annualRatePct.toStringAsFixed(1)}%, pagar esta deuda primero (método avalancha) minimiza el interés total.'
            : 'At ${annualRatePct.toStringAsFixed(1)}% APR, paying this debt first (avalanche method) saves the most in total interest.',
      ));
    }

    // ── 5. Payoff motivation ──────────────────────────────────────────────────
    if (monthsToPayoff > 0 && monthsToPayoff < 24) {
      insights.add(Insight(
        severity: InsightSeverity.good,
        icon:     Icons.emoji_events_outlined,
        title: isEs
            ? '¡Casi Libre de Deuda!'
            : 'Almost Debt-Free!',
        body: isEs
            ? '¡Vas camino a estar libre de deuda en $monthsToPayoff meses!'
            : 'You\'re on track to be debt-free in $monthsToPayoff months!',
      ));
    } else if (monthsToPayoff >= 24 && monthsToPayoff <= 60) {
      final years = (monthsToPayoff / 12).toStringAsFixed(1);
      insights.add(Insight(
        severity: InsightSeverity.good,
        icon:     Icons.check_circle_outline,
        title: isEs
            ? 'Ritmo Constante'
            : 'Steady Progress',
        body: isEs
            ? 'Buen ritmo — libre de deuda en $years años.'
            : 'Steady pace — debt-free in $years years.',
      ));
    }

    // ── Fallback: always show at least one insight after calculation ──────────
    if (insights.isEmpty && totalInterest > 0) {
      insights.add(Insight(
        severity: InsightSeverity.good,
        icon:     Icons.info_outline,
        title: isEs ? 'Costo Total de Interés' : 'Total Interest Cost',
        body: isEs
            ? 'Pagarás ${_fmt(totalInterest)} en intereses totales sobre este préstamo.'
            : 'You\'ll pay ${_fmt(totalInterest)} in total interest on this loan.',
      ));
    }

    // Prioritise alerts > warnings > good, cap at maxCount
    final alerts   = insights.where((i) => i.severity == InsightSeverity.alert).toList();
    final warnings = insights.where((i) => i.severity == InsightSeverity.warning).toList();
    final goods    = insights.where((i) => i.severity == InsightSeverity.good).toList();

    final ordered = [...alerts, ...warnings, ...goods];
    return ordered.take(maxCount).toList();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static String _fmt(double amount) {
    final abs = amount.abs();
    String str;
    if (abs >= 1000000) {
      str = '\$${(abs / 1000000).toStringAsFixed(2)}M';
    } else if (abs >= 1000) {
      str = '\$${(abs / 1000).toStringAsFixed(1)}K';
    } else {
      str = '\$${abs.toStringAsFixed(0)}';
    }
    return amount < 0 ? '-$str' : str;
  }
}
