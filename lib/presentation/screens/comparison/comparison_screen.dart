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
              final cs = Theme.of(context).colorScheme;
              final bg = isHighlight
                  ? AppTheme.accentGood.withValues(alpha: 0.1)
                  : i % 2 == 0 ? cs.surface : cs.surfaceContainerLow;
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
                    style: TextStyle(color: AppTheme.warning, fontSize: 12))),
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
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => Colors.blueGrey.shade800,
                  getTooltipItem: (group, groupIdx, rod, rodIdx) => BarTooltipItem(
                    '\$${(rod.toY / 1000).toStringAsFixed(1)}k saved',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
              barGroups: scenarios.asMap().entries.map((entry) =>
                BarChartGroupData(
                  x: entry.key,
                  barRods: [BarChartRodData(
                    toY: entry.value.$2.interestSaved,
                    color: entry.value.$1 == 0
                        ? const Color(0xFF94A3B8)
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
          const SizedBox(height: 24),

          // ── Cost Breakdown: Principal vs Interest ─────────────────────
          _CostBreakdownCard(
              result: result, input: input, fmt: fmt, isEs: isEs),
          const SizedBox(height: 80),
        ]),
      )),
      const AdFooter(),
    ]);
  }
}

// ── Principal vs Interest visual breakdown ─────────────────────────────────
class _CostBreakdownCard extends StatelessWidget {
  final PayoffResult result;
  final LoanInput    input;
  final NumberFormat fmt;
  final bool isEs;
  const _CostBreakdownCard({
    required this.result,
    required this.input,
    required this.fmt,
    required this.isEs,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final principal = input.loanAmount;
    final interest  = result.interestNormal;
    final total     = principal + interest;
    if (total <= 0) return const SizedBox.shrink();

    final pPct = principal / total;
    final iPct = interest  / total;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        isEs ? 'Desglose del Costo Total' : 'Total Cost Breakdown',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 12),
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            // Stacked bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 28,
                child: Row(children: [
                  Flexible(
                    flex: (pPct * 1000).round(),
                    child: Container(color: AppTheme.primary),
                  ),
                  Flexible(
                    flex: (iPct * 1000).round(),
                    child: Container(color: AppTheme.warning),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              _BreakdownLeg(
                color: AppTheme.primary,
                label: isEs ? 'Capital' : 'Principal',
                amount: fmt.format(principal),
                pct: '${(pPct * 100).toStringAsFixed(0)}%',
              ),
              const SizedBox(width: 12),
              _BreakdownLeg(
                color: AppTheme.warning,
                label: isEs ? 'Interés Total' : 'Total Interest',
                amount: fmt.format(interest),
                pct: '${(iPct * 100).toStringAsFixed(0)}%',
              ),
            ]),
            if (result.monthsSaved > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.accentGood.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppTheme.accentGood.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.savings_rounded,
                        color: AppTheme.accentGood, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '${isEs ? "Con pago extra, ahorras" : "With extra payment you save"} '
                      '${fmt.format(result.interestSaved)} '
                      '${isEs ? "en interés" : "in interest"}',
                      style: const TextStyle(
                          color: AppTheme.accentGood,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ]),
        ),
      ),
    ]);
  }
}

class _BreakdownLeg extends StatelessWidget {
  final Color  color;
  final String label, amount, pct;
  const _BreakdownLeg({
    required this.color,
    required this.label,
    required this.amount,
    required this.pct,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Row(children: [
      Container(
        width: 12, height: 12,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
        Text(amount,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Text(pct, style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ])),
    ]),
  );
}
