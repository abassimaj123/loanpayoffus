import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ads/ad_footer.dart';
import '../../../core/language/language_notifier.dart';
import '../../../domain/models/loan_input.dart';
import '../../../domain/models/payoff_result.dart';
import '../../../domain/usecases/loan_calculator.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../providers/loan_provider.dart';

class ComparisonScreen extends ConsumerWidget {
  const ComparisonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(payoffResultProvider);
    final input  = ref.watch(loanInputProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) => _buildContent(context, result, input, isEs),
    );
  }

  Widget _buildContent(BuildContext context, PayoffResult? result, LoanInput input, bool isEs) {
    final dynamic s = isEs ? AppStringsES() : AppStringsEN();
    final fmt     = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);

    if (result == null) {
      return Column(children: [
        Expanded(child: Center(child: Text(s.enterLoan))),
        const AdFooter(),
      ]);
    }

    final extras = [0.0, 100.0, 200.0, 500.0];
    if (input.extraPayment > 0 && !extras.contains(input.extraPayment)) {
      extras.add(input.extraPayment);
    }
    extras.sort();

    final scenarios = extras.map((extra) {
      final r = LoanCalculator.calculate(LoanInput(
        loanType:        input.loanType,
        loanAmount:      input.loanAmount,
        interestRatePct: input.interestRatePct,
        monthlyPayment:  input.monthlyPayment,
        extraPayment:    extra,
      ));
      return (extra, r);
    }).toList();

    final maxSaved = scenarios
        .map((sc) => sc.$2.interestSaved)
        .reduce((a, b) => a > b ? a : b);

    return Column(children: [
      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.extraScenarios,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Card(child: Column(children: [
            Container(
              decoration: const BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12), topRight: Radius.circular(12)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                Expanded(flex: 2, child: Text(s.extraMo,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 2, child: Text(s.payoff,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  textAlign: TextAlign.right)),
                Expanded(flex: 2, child: Text(s.interest,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  textAlign: TextAlign.right)),
                Expanded(flex: 2, child: Text(s.saved,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  textAlign: TextAlign.right)),
              ]),
            ),
            ...scenarios.asMap().entries.map((entry) {
              final i         = entry.key;
              final extra     = entry.value.$1;
              final r         = entry.value.$2;
              final isHighlight = extra == input.extraPayment && extra > 0;
              final bg = isHighlight
                  ? AppTheme.accentGood.withValues(alpha: 0.1)
                  : i % 2 == 0 ? Colors.white : Colors.grey.shade50;
              return Container(
                color: bg,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  Expanded(flex: 2, child: Text(
                    extra == 0 ? s.none : fmt.format(extra),
                    style: TextStyle(
                      fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
                      color: isHighlight ? AppTheme.accentGood : null))),
                  Expanded(flex: 2, child: Text(
                    '${r.extraMonths ~/ 12}y ${r.extraMonths % 12}m',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal))),
                  Expanded(flex: 2, child: Text(
                    fmt.format(r.interestExtra),
                    textAlign: TextAlign.right,
                    style: TextStyle(color: Colors.orange.shade700, fontSize: 12))),
                  Expanded(flex: 2, child: Text(
                    extra == 0 ? '-' : fmt.format(r.interestSaved),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: AppTheme.accentGood, fontWeight: FontWeight.w600, fontSize: 12))),
                ]),
              );
            }),
          ])),
          const SizedBox(height: 24),

          Text(s.interestSavedChart,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: BarChart(BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxSaved * 1.15 + 1,
              barGroups: scenarios.asMap().entries.map((entry) =>
                BarChartGroupData(
                  x: entry.key,
                  barRods: [BarChartRodData(
                    toY: entry.value.$2.interestSaved,
                    color: entry.value.$1 == 0
                        ? Colors.grey.shade400
                        : AppTheme.accentGood,
                    width: 22,
                    borderRadius: BorderRadius.circular(4),
                  )],
                )).toList(),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= scenarios.length) return const SizedBox();
                    final extra = scenarios[idx].$1;
                    return Text(
                      extra == 0 ? '\$0' : '+\$${extra.toInt()}',
                      style: const TextStyle(fontSize: 10));
                  },
                )),
                leftTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 60,
                  getTitlesWidget: (v, _) => Text(
                    '\$${(v / 1000).toStringAsFixed(0)}k',
                    style: const TextStyle(fontSize: 10)),
                )),
                topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
            )),
          ),
          const SizedBox(height: 80),
        ]),
      )),
      const AdFooter(),
    ]);
  }
}
