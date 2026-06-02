import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/language/language_notifier.dart';
import '../../../domain/models/loan_input.dart';
import '../../../domain/models/payoff_result.dart';
import '../../../domain/usecases/loan_calculator.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../providers/loan_provider.dart';
import 'package:calcwise_core/calcwise_core.dart';

class ComparisonScreen extends ConsumerWidget {
  const ComparisonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(payoffResultProvider);
    final input = ref.watch(loanInputProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) =>
          _buildContent(context, result, input, isEs),
    );
  }

  Widget _buildContent(
    BuildContext context,
    PayoffResult? result,
    LoanInput input,
    bool isEs,
  ) {
    final AppStrings s = isEs ? AppStringsES() : AppStringsEN();

    if (result == null) {
      return Column(
        children: [
          Expanded(child: Center(child: Text(s.enterLoan))),
          const CalcwiseAdFooter(),
        ],
      );
    }

    final extras = [0.0, 100.0, 200.0, 500.0];
    if (input.extraPayment > 0 && !extras.contains(input.extraPayment)) {
      extras.add(input.extraPayment);
    }
    extras.sort();

    final scenarios = extras.map((extra) {
      final r = LoanCalculator.calculate(
        LoanInput(
          loanType: input.loanType,
          loanAmount: input.loanAmount,
          interestRatePct: input.interestRatePct,
          monthlyPayment: input.monthlyPayment,
          extraPayment: extra,
        ),
      );
      return (extra, r);
    }).toList();

    final maxSaved = scenarios
        .map((sc) => sc.$2.interestSaved)
        .reduce((a, b) => a > b ? a : b);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.extraScenarios,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextSize.bodyLg,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Card(
                  child: Column(
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.smPlus,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                s.extraMo,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppTextSize.sm,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                s.payoff,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppTextSize.sm,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                s.interest,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppTextSize.sm,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                s.saved,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppTextSize.sm,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...scenarios.asMap().entries.map((entry) {
                        final i = entry.key;
                        final extra = entry.value.$1;
                        final r = entry.value.$2;
                        final isHighlight =
                            extra == input.extraPayment && extra > 0;
                        final cs = Theme.of(context).colorScheme;
                        final bg = isHighlight
                            ? AppTheme.accentGood.withValues(alpha: 0.1)
                            : i % 2 == 0
                            ? cs.surface
                            : cs.surfaceContainerLow;
                        return Container(
                          color: bg,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.smPlus,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  extra == 0 ? s.none : AmountFormatter.ui(extra, 'USD'),
                                  style: TextStyle(
                                    fontWeight: isHighlight
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isHighlight
                                        ? AppTheme.accentGood
                                        : null,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${r.extraMonths ~/ 12}y ${r.extraMonths % 12}m',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontWeight: isHighlight
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  AmountFormatter.ui(r.interestExtra, 'USD'),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: AppTheme.warning,
                                    fontSize: AppTextSize.sm,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  extra == 0
                                      ? '-'
                                      : AmountFormatter.ui(r.interestSaved, 'USD'),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    color: AppTheme.accentGood,
                                    fontWeight: FontWeight.w600,
                                    fontSize: AppTextSize.sm,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),

                Text(
                  s.interestSavedChart,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextSize.bodyLg,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    _ChartLegendItem(
                      color: Theme.of(context).colorScheme.outline,
                      label: s.none,
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    _ChartLegendItem(
                      color: AppTheme.accentGood,
                      label: s.withExtraLabel,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 220,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxSaved * 1.15 + 1,
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) =>
                              Theme.of(context).colorScheme.inverseSurface,
                          getTooltipItem: (group, groupIdx, rod, rodIdx) =>
                              BarTooltipItem(
                                '\$${(rod.toY / 1000).toStringAsFixed(1)}k saved',
                                TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onInverseSurface,
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppTextSize.sm,
                                ),
                              ),
                        ),
                      ),
                      barGroups: scenarios
                          .asMap()
                          .entries
                          .map(
                            (entry) => BarChartGroupData(
                              x: entry.key,
                              barRods: [
                                BarChartRodData(
                                  toY: entry.value.$2.interestSaved,
                                  color: entry.value.$1 == 0
                                      ? Theme.of(context).colorScheme.outline
                                      : AppTheme.accentGood,
                                  width: 22,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.xs,
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, _) {
                              final idx = v.toInt();
                              if (idx < 0 || idx >= scenarios.length)
                                return const SizedBox();
                              final extra = scenarios[idx].$1;
                              return Text(
                                extra == 0 ? '\$0' : '+\$${extra.toInt()}',
                                style: const TextStyle(fontSize: AppTextSize.xs),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 60,
                            getTitlesWidget: (v, _) => Text(
                              '\$${(v / 1000).toStringAsFixed(0)}k',
                              style: const TextStyle(fontSize: AppTextSize.xs),
                            ),
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),

                // ── Cost Breakdown: Principal vs Interest ─────────────────────
                _CostBreakdownCard(
                  result: result,
                  input: input,
                  isEs: isEs,
                ),
                const SizedBox(height: AppSpacing.listBottomInset),
              ],
            ),
          ),
        ),
        const CalcwiseAdFooter(),
      ],
    );
  }
}

// ── Principal vs Interest visual breakdown ─────────────────────────────────
class _CostBreakdownCard extends StatelessWidget {
  final PayoffResult result;
  final LoanInput input;
  final bool isEs;
  const _CostBreakdownCard({
    required this.result,
    required this.input,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    final principal = input.loanAmount;
    final interest = result.interestNormal;
    final total = principal + interest;
    if (total <= 0) return const SizedBox.shrink();

    final pPct = principal / total;
    final iPct = interest / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isEs ? 'Desglose del Costo Total' : 'Total Cost Breakdown',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: AppTextSize.bodyLg,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                // Stacked bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(
                    height: 28,
                    child: Row(
                      children: [
                        Flexible(
                          flex: (pPct * 1000).round(),
                          child: Container(color: AppTheme.primary),
                        ),
                        Flexible(
                          flex: (iPct * 1000).round(),
                          child: Container(color: AppTheme.warning),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.mdPlus),
                Row(
                  children: [
                    _BreakdownLeg(
                      color: AppTheme.primary,
                      label: isEs ? 'Capital' : 'Principal',
                      amount: AmountFormatter.ui(principal, 'USD'),
                      pct: '${(pPct * 100).toStringAsFixed(0)}%',
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _BreakdownLeg(
                      color: AppTheme.warning,
                      label: isEs ? 'Interés Total' : 'Total Interest',
                      amount: AmountFormatter.ui(interest, 'USD'),
                      pct: '${(iPct * 100).toStringAsFixed(0)}%',
                    ),
                  ],
                ),
                if (result.monthsSaved > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accentGood.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.mdPlus),
                      border: Border.all(
                        color: AppTheme.accentGood.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.savings_rounded,
                          color: AppTheme.accentGood,
                          size: 16,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '${isEs ? "Con pago extra, ahorras" : "With extra payment you save"} '
                          '${AmountFormatter.ui(result.interestSaved, 'USD')} '
                          '${isEs ? "en interés" : "in interest"}',
                          style: const TextStyle(
                            color: AppTheme.accentGood,
                            fontSize: AppTextSize.sm,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BreakdownLeg extends StatelessWidget {
  final Color color;
  final String label, amount, pct;
  const _BreakdownLeg({
    required this.color,
    required this.label,
    required this.amount,
    required this.pct,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: AppTextSize.xs,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              Text(
                amount,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextSize.md,
                ),
              ),
              Text(
                pct,
                style: TextStyle(
                  fontSize: AppTextSize.xs,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ── Chart legend item (color swatch + label) ───────────────────────────────
class _ChartLegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _ChartLegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
      ),
      const SizedBox(width: AppSpacing.xs),
      Text(
        label,
        style: TextStyle(
          fontSize: AppTextSize.xs,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    ],
  );
}
