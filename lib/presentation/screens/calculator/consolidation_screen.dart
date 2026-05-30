import 'dart:math' show pow;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard;
import '../../../core/theme/app_theme.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/language/language_notifier.dart';
import '../../widgets/paywall_hard.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model for a single debt entry
// ─────────────────────────────────────────────────────────────────────────────
class _DebtEntry {
  final TextEditingController balanceCtrl;
  final TextEditingController rateCtrl;
  final TextEditingController paymentCtrl;

  _DebtEntry({
    String balance = '',
    String rate = '',
    String payment = '',
  })  : balanceCtrl = TextEditingController(text: balance),
        rateCtrl = TextEditingController(text: rate),
        paymentCtrl = TextEditingController(text: payment);

  void dispose() {
    balanceCtrl.dispose();
    rateCtrl.dispose();
    paymentCtrl.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ConsolidationScreen
// ─────────────────────────────────────────────────────────────────────────────
class ConsolidationScreen extends StatefulWidget {
  const ConsolidationScreen({super.key});

  @override
  State<ConsolidationScreen> createState() => _ConsolidationScreenState();
}

class _ConsolidationScreenState extends State<ConsolidationScreen> {
  // Up to 4 debts — start with 2 pre-filled samples
  final List<_DebtEntry> _debts = [
    _DebtEntry(balance: '8000', rate: '19.99', payment: ''),
    _DebtEntry(balance: '5000', rate: '14.5', payment: ''),
  ];

  // Consolidation loan inputs
  final _loanAmountCtrl = TextEditingController();
  final _consolidationRateCtrl = TextEditingController(text: '12.5');
  int _termMonths = 48;

  // Results
  double _totalCurrentBalance = 0;
  double _totalCurrentMonthlyPayment = 0;
  double _consolidationPayment = 0;
  double _totalConsolidationCost = 0;
  double _totalConsolidationInterest = 0;
  double _monthlySavings = 0;
  double _averageCurrentRate = 0;

  static const List<int> _termOptions = [24, 36, 48, 60, 72];

  @override
  void initState() {
    super.initState();
    _calculate();
  }

  @override
  void dispose() {
    for (final d in _debts) {
      d.dispose();
    }
    _loanAmountCtrl.dispose();
    _consolidationRateCtrl.dispose();
    super.dispose();
  }

  double _parseField(TextEditingController ctrl) {
    final text = ctrl.text.replaceAll(',', '.');
    return double.tryParse(text.trim()) ?? 0.0;
  }

  double _calcMonthlyPayment(double balance, double annualRatePct, int months) {
    if (balance <= 0 || months <= 0) return 0;
    if (annualRatePct <= 0) return balance / months;
    final r = annualRatePct / 100 / 12;
    return balance * r / (1 - pow(1 + r, -months));
  }

  void _calculate() {
    // Current debts
    double totalBalance = 0;
    double totalPayment = 0;
    double weightedRateSum = 0;

    for (final debt in _debts) {
      final balance = _parseField(debt.balanceCtrl);
      final rate = _parseField(debt.rateCtrl);
      final paymentRaw = _parseField(debt.paymentCtrl);
      // Auto-calc payment if blank / zero (assuming 5yr / 60-month term)
      final payment =
          paymentRaw > 0 ? paymentRaw : _calcMonthlyPayment(balance, rate, 60);

      totalBalance += balance;
      totalPayment += payment;
      weightedRateSum += rate * balance;
    }

    _totalCurrentBalance = totalBalance;
    _totalCurrentMonthlyPayment = totalPayment;
    _averageCurrentRate =
        totalBalance > 0 ? weightedRateSum / totalBalance : 0;

    // Sync loan amount field if user hasn't manually edited it
    final loanAmountVal = _parseField(_loanAmountCtrl);
    if (loanAmountVal == 0 || loanAmountVal == _totalCurrentBalance) {
      // Keep in sync with total balance
      _loanAmountCtrl.text = totalBalance > 0
          ? totalBalance.toStringAsFixed(0)
          : '';
    }

    // Consolidation loan
    final loanAmount = _parseField(_loanAmountCtrl);
    final consolidationRate = _parseField(_consolidationRateCtrl);

    if (loanAmount > 0 && consolidationRate > 0 && _termMonths > 0) {
      final r = consolidationRate / 100 / 12;
      _consolidationPayment =
          loanAmount * r / (1 - pow(1 + r, -_termMonths));
      _totalConsolidationCost = _consolidationPayment * _termMonths;
      _totalConsolidationInterest = _totalConsolidationCost - loanAmount;
    } else {
      _consolidationPayment = 0;
      _totalConsolidationCost = 0;
      _totalConsolidationInterest = 0;
    }

    _monthlySavings = _totalCurrentMonthlyPayment - _consolidationPayment;
  }

  void _addDebt() {
    if (_debts.length >= 4) return;
    setState(() {
      _debts.add(_DebtEntry());
    });
  }

  void _removeDebt(int index) {
    if (_debts.length <= 1) return;
    setState(() {
      _debts[index].dispose();
      _debts.removeAt(index);
      _calculate();
    });
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.smPlus),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: AppTextSize.xs,
            fontWeight: FontWeight.w700,
            color: AppTheme.primary,
            letterSpacing: 0.8,
          ),
        ),
      );

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? prefix,
    String? suffix,
    String? hint,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            labelText: label,
            prefixText: prefix,
            suffixText: suffix,
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
          ),
          onChanged: (_) => setState(() => _calculate()),
        ),
      );

  Widget _debtCard(int index, bool isEs) {
    final debt = _debts[index];
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(
          color: AppTheme.primary.withValues(alpha: 0.2),
        ),
      ),
      color: AppTheme.primary.withValues(alpha: 0.03),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        fontSize: AppTextSize.sm,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  isEs ? 'Deuda ${index + 1}' : 'Debt ${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextSize.body,
                    color: AppTheme.primaryDark,
                  ),
                ),
                const Spacer(),
                if (_debts.length > 1)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: AppTheme.warning,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _removeDebt(index),
                    tooltip: isEs ? 'Eliminar' : 'Remove',
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _field(
              isEs ? 'Saldo (\$)' : 'Balance (\$)',
              debt.balanceCtrl,
              prefix: '\$',
            ),
            _field(
              isEs ? 'Tasa de Interés' : 'Interest Rate',
              debt.rateCtrl,
              suffix: '%',
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: TextField(
                controller: debt.paymentCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: isEs
                      ? 'Pago Mensual (opcional)'
                      : 'Monthly Payment (optional)',
                  prefixText: '\$',
                  hintText: isEs ? 'Auto-calculado' : 'Auto-calculated',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                ),
                onChanged: (_) => setState(() => _calculate()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasResult =
        _consolidationPayment > 0 && _totalCurrentMonthlyPayment > 0;
    final consolidationRate = _parseField(_consolidationRateCtrl);
    final isGood =
        _monthlySavings > 0 && consolidationRate < _averageCurrentRate;
    final isPartial = _monthlySavings > 0 && !isGood;

    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: freemiumService.hasFullAccessNotifier,
          builder: (context, isPremium, _) {
            if (!isPremium) {
              return Scaffold(
                appBar: AppBar(
                  title: Text(isEs
                      ? 'Consolidación de Deudas'
                      : 'Debt Consolidation'),
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline_rounded,
                            size: 56, color: AppTheme.primary),
                        const SizedBox(height: AppSpacing.lg),
                        const Text(
                          'Premium Feature',
                          style: TextStyle(
                            fontSize: AppTextSize.title,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          isEs
                              ? 'Desbloquea la Calculadora de Consolidación con una suscripción Pro.'
                              : 'Unlock the Debt Consolidation Calculator with a Pro subscription.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: AppTextSize.body,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        FilledButton(
                          onPressed: () => PaywallHard.show(context),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 52),
                          ),
                          child: Text(isEs ? 'Desbloquear Pro' : 'Unlock Pro'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Scaffold(
              appBar: AppBar(
                title: Text(isEs
                    ? 'Consolidación de Deudas'
                    : 'Debt Consolidation'),
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              body: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── CURRENT DEBTS ─────────────────────────────────
                          _sectionHeader(
                            isEs ? 'Deudas Actuales' : 'Current Debts',
                          ),

                          ...List.generate(
                            _debts.length,
                            (i) => _debtCard(i, isEs),
                          ),

                          // Add Debt button
                          if (_debts.length < 4)
                            OutlinedButton.icon(
                              onPressed: _addDebt,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: Text(
                                isEs ? 'Agregar Deuda' : 'Add Debt',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.primary,
                                side: BorderSide(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.5),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.lg),
                                ),
                                minimumSize:
                                    const Size(double.infinity, 44),
                              ),
                            ),

                          const SizedBox(height: AppSpacing.xxl),

                          // ── CONSOLIDATION LOAN ────────────────────────────
                          _sectionHeader(
                            isEs
                                ? 'Préstamo de Consolidación'
                                : 'Consolidation Loan',
                          ),

                          _field(
                            isEs
                                ? 'Monto del Préstamo'
                                : 'Loan Amount',
                            _loanAmountCtrl,
                            prefix: '\$',
                            hint: isEs
                                ? 'Auto-calculado del total'
                                : 'Auto-filled from total',
                          ),
                          _field(
                            isEs
                                ? 'Tasa de Interés'
                                : 'Interest Rate',
                            _consolidationRateCtrl,
                            suffix: '%',
                          ),

                          // Term dropdown
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.md),
                            child: DropdownButtonFormField<int>(
                              value: _termMonths,
                              decoration: InputDecoration(
                                labelText: isEs
                                    ? 'Plazo (meses)'
                                    : 'Term (months)',
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.lg),
                                ),
                              ),
                              items: _termOptions
                                  .map(
                                    (t) => DropdownMenuItem(
                                      value: t,
                                      child: Text('$t ${isEs ? "meses" : "months"}'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() {
                                  _termMonths = v;
                                  _calculate();
                                });
                              },
                            ),
                          ),

                          const SizedBox(height: AppSpacing.lg),

                          // ── RESULTS ───────────────────────────────────────
                          if (hasResult) ...[
                            // Hero savings card
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.xxl,
                                horizontal: AppSpacing.xl,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: _monthlySavings > 0
                                      ? [
                                          const Color(0xFF00C853),
                                          const Color(0xFF009624),
                                        ]
                                      : [
                                          AppTheme.warning,
                                          const Color(0xFFE65100),
                                        ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(AppRadius.xxl),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    _monthlySavings > 0
                                        ? (isEs ? 'AHORRAS' : 'YOU SAVE')
                                        : (isEs
                                            ? 'SIN AHORRO MENSUAL'
                                            : 'NO MONTHLY SAVINGS'),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: AppTextSize.md,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    _monthlySavings > 0
                                        ? '${AmountFormatter.ui(_monthlySavings, 'USD')}/mo'
                                        : '${AmountFormatter.ui(-_monthlySavings, 'USD')}/mo ${isEs ? "más" : "more"}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: AppTextSize.hero,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: AppSpacing.md),

                            // First metric row: Current Monthly | New Payment | Savings
                            Row(
                              children: [
                                _ConsolidationMetricTile(
                                  label: isEs
                                      ? 'Total Actual/mes'
                                      : 'Current Monthly Total',
                                  value: AmountFormatter.ui(
                                    _totalCurrentMonthlyPayment,
                                    'USD',
                                  ),
                                  icon: Icons.credit_card_rounded,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                _ConsolidationMetricTile(
                                  label: isEs
                                      ? 'Nuevo Pago'
                                      : 'New Monthly Payment',
                                  value: AmountFormatter.ui(
                                    _consolidationPayment,
                                    'USD',
                                  ),
                                  icon: Icons.payments_outlined,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                _ConsolidationMetricTile(
                                  label: isEs
                                      ? 'Ahorro Mensual'
                                      : 'Monthly Savings',
                                  value: AmountFormatter.ui(
                                    _monthlySavings.abs(),
                                    'USD',
                                  ),
                                  icon: Icons.savings_outlined,
                                  color: _monthlySavings > 0
                                      ? AppTheme.accentGood
                                      : AppTheme.warning,
                                ),
                              ],
                            ),

                            const SizedBox(height: AppSpacing.sm),

                            // Second metric row: Term | Debts Count | Total Interest
                            Row(
                              children: [
                                _ConsolidationMetricTile(
                                  label: isEs
                                      ? 'Plazo Consolidación'
                                      : 'Consolidation Term',
                                  value: isEs
                                      ? '$_termMonths meses'
                                      : '$_termMonths months',
                                  icon: Icons.timer_outlined,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                _ConsolidationMetricTile(
                                  label: isEs
                                      ? 'Deudas Consolidadas'
                                      : 'Total Debts Consolidated',
                                  value: '${_debts.length}',
                                  icon: Icons.merge_rounded,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                _ConsolidationMetricTile(
                                  label: isEs
                                      ? 'Interés Total (consolidación)'
                                      : 'Total Interest (consolidation)',
                                  value: AmountFormatter.ui(
                                    _totalConsolidationInterest,
                                    'USD',
                                  ),
                                  icon: Icons.percent_rounded,
                                  color: AppTheme.warning,
                                ),
                              ],
                            ),

                            const SizedBox(height: AppSpacing.md),

                            // Verdict chip
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                                vertical: AppSpacing.smPlus,
                              ),
                              decoration: BoxDecoration(
                                color: isGood
                                    ? AppTheme.accentGood
                                        .withValues(alpha: 0.1)
                                    : isPartial
                                        ? AppTheme.warning
                                            .withValues(alpha: 0.1)
                                        : CalcwiseSemanticColors.errorDark
                                            .withValues(alpha: 0.08),
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(AppRadius.xl),
                                ),
                                border: Border.all(
                                  color: isGood
                                      ? AppTheme.accentGood
                                          .withValues(alpha: 0.4)
                                      : isPartial
                                          ? AppTheme.warning
                                              .withValues(alpha: 0.4)
                                          : CalcwiseSemanticColors.errorDark
                                              .withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isGood
                                        ? Icons.check_circle_outline_rounded
                                        : isPartial
                                            ? Icons.warning_amber_rounded
                                            : Icons.cancel_outlined,
                                    color: isGood
                                        ? AppTheme.accentGood
                                        : isPartial
                                            ? AppTheme.warning
                                            : CalcwiseSemanticColors.error(Theme.of(context).brightness),
                                    size: 18,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Flexible(
                                    child: Text(
                                      isGood
                                          ? (isEs
                                              ? 'La consolidación tiene sentido'
                                              : 'Consolidation makes sense')
                                          : isPartial
                                              ? (isEs
                                                  ? 'Pagos menores pero plazo más largo'
                                                  : 'Lower payments but longer payoff')
                                              : (isEs
                                                  ? 'No es beneficioso — mantén tus deudas actuales'
                                                  : 'Not beneficial — keep current debts'),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: AppTextSize.body,
                                        color: isGood
                                            ? AppTheme.accentGood
                                            : isPartial
                                                ? AppTheme.warning
                                                : CalcwiseSemanticColors.error(Theme.of(context).brightness),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: AppSpacing.lg),
                          ],

                          // Empty state — shown when no results yet
                          if (!hasResult) ...[
                            const SizedBox(height: AppSpacing.xl),
                            Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.merge_rounded,
                                    size: 48,
                                    color: AppTheme.primary.withValues(alpha: 0.3),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  Text(
                                    isEs
                                        ? 'Ingresa los valores para ver el análisis'
                                        : 'Enter values to see the analysis',
                                    style: TextStyle(
                                      fontSize: AppTextSize.body,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.45),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                          ],

                          // Disclaimer
                          Text(
                            isEs
                                ? 'Solo para fines informativos. No es asesoramiento financiero.'
                                : 'For informational purposes only. Not financial advice.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: AppTextSize.xs,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.45),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.listBottomInset),
                        ],
                      ),
                    ),
                  ),
                  const CalcwiseAdFooter(),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Metric tile (local to consolidation screen)
// ─────────────────────────────────────────────────────────────────────────────
class _ConsolidationMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const _ConsolidationMetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primary;
    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: c.withValues(alpha: 0.25)),
        ),
        color: c.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.mdPlus,
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: c),
              const SizedBox(height: AppSpacing.xs),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextSize.md,
                  color: c,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppTextSize.xs,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55),
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
