import 'dart:async';
import 'dart:math' show pow;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard, PaywallSoft;
import '../../../core/theme/app_theme.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/language/language_notifier.dart';
import '../../../core/services/pdf_export_service.dart';
import '../../../main.dart';
import '../../widgets/paywall_hard.dart';
import '../../widgets/paywall_soft.dart';
import '../../widgets/save_scenario_button.dart';

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
  /// Optional seed values from the main calculator so the first debt row
  /// reflects the user's actual loan instead of canned sample data.
  final double? seedBalance;
  final double? seedRate;
  const ConsolidationScreen({super.key, this.seedBalance, this.seedRate});

  @override
  State<ConsolidationScreen> createState() => _ConsolidationScreenState();
}

// Semantic domain colors — not in shared theme (savings/warning gradient)
const _savingsColor = Color(0xFF00C853);
const _savingsDarkColor = Color(0xFF009624);
const _warningDarkColor = Color(0xFFE65100);

class _ConsolidationScreenState extends State<ConsolidationScreen> {
  Timer? _calcDebounce;

  // Up to 4 debts. The first row is seeded from the main calculator's loan
  // (so the screen reflects the user's actual debt, per the auto-sync rule);
  // the second starts empty for the user to add another debt.
  late final List<_DebtEntry> _debts;

  // Consolidation loan inputs
  final _loanAmountCtrl = TextEditingController();
  final _consolidationRateCtrl = TextEditingController(text: '12.5');
  int _termMonths = 48;

  // Tracks the total balance the loan-amount field was last auto-synced to,
  // so we can tell "user hasn't touched it" apart from "total just changed".
  double _lastSyncedTotalBalance = 0;

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
    final seedBal = widget.seedBalance;
    final seedRate = widget.seedRate;
    _debts = [
      _DebtEntry(
        balance: (seedBal != null && seedBal > 0)
            ? seedBal.toStringAsFixed(0)
            : '',
        rate: (seedRate != null && seedRate > 0)
            ? seedRate.toStringAsFixed(2)
            : '',
      ),
      _DebtEntry(),
    ];
    AnalyticsService.instance.logScreenView('consolidation');
    isSpanishNotifier.addListener(_onLangChange);
    _calculate();
  }

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLangChange);
    _calcDebounce?.cancel();
    for (final d in _debts) {
      d.dispose();
    }
    _loanAmountCtrl.dispose();
    _consolidationRateCtrl.dispose();
    smartHistoryService.cancelPendingSave('loanpayoffus', 'consolidation');
    super.dispose();
  }

  void _onLangChange() => setState(() {});

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

  /// Total interest paid on a current debt via a real amortization loop —
  /// not the 0%-APR `balance / payment` shortcut, which ignores interest and
  /// understates the baseline (making consolidation look worse than it is).
  double _currentDebtTotalInterest(
      double balance, double annualRatePct, double payment) {
    if (balance <= 0 || payment <= 0) return 0;
    final r = annualRatePct / 100 / 12;
    double bal = balance, interestSum = 0;
    int month = 0;
    while (bal > 0.01 && month < 600) {
      final interest = bal * r;
      var principal = payment - interest;
      if (principal <= 0) break; // payment doesn't cover interest
      if (principal > bal) principal = bal;
      interestSum += interest;
      bal -= principal;
      month++;
    }
    return interestSum;
  }

  void _calculate() {
    unawaited(AnalyticsService.instance.maybeLogFirstCalculate());
    adService.onAction();
    // Current debts
    double totalBalance = 0;
    double totalPayment = 0;
    double weightedRateSum = 0;

    for (final debt in _debts) {
      final balance = _parseField(debt.balanceCtrl);
      final rate = _parseField(debt.rateCtrl);
      final paymentRaw = _parseField(debt.paymentCtrl);
      // Auto-calc payment if blank / zero.
      // Use 120 months (10yr) as a neutral default — a 60-month assumption
      // massively overestimates the payment for long-term debts like mortgages.
      final payment =
          paymentRaw > 0 ? paymentRaw : _calcMonthlyPayment(balance, rate, 120);

      totalBalance += balance;
      totalPayment += payment;
      weightedRateSum += rate * balance;
    }

    _totalCurrentBalance = totalBalance;
    _totalCurrentMonthlyPayment = totalPayment;
    _averageCurrentRate =
        totalBalance > 0 ? weightedRateSum / totalBalance : 0;

    // Sync loan amount field if user hasn't manually edited it since the
    // last auto-sync (compare against the previously-synced total, not the
    // just-reassigned _totalCurrentBalance, or this never re-triggers when
    // debts are added/edited).
    final loanAmountVal = _parseField(_loanAmountCtrl);
    if (loanAmountVal == 0 || loanAmountVal == _lastSyncedTotalBalance) {
      // Keep in sync with total balance
      _loanAmountCtrl.text = totalBalance > 0
          ? totalBalance.toStringAsFixed(0)
          : '';
      _lastSyncedTotalBalance = totalBalance;
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

  // ── SmartHistory ────────────────────────────────────────────────────────────
  double _roundTo(double v, double step) =>
      step == 0 ? v : (v / step).round() * step;

  Map<String, dynamic> _buildL1() => {
        'debt_count': _debts.length,
        'total_balance': _totalCurrentBalance,
        'consolidation_rate': _parseField(_consolidationRateCtrl),
        'monthly_savings': _monthlySavings,
        'term_months': _termMonths,
      };

  Map<String, dynamic> _buildL2() => {
        // Mirrors the generic loan-history schema (loan_type/loan_amount/
        // interest_rate/monthly_payment/normal_months/interest_saved) so the
        // DB adapter (loan_payoff_us_database_adapter.dart) populates the flat
        // `history` columns instead of defaulting them to 0/null. Without
        // these, HistoryScreen._load() treats the row as a corrupted auto-save
        // (loan_amount==0 && interest_rate==0) and silently deletes it.
        'loan_type': 'Consolidation',
        'loan_amount': _totalCurrentBalance,
        'interest_rate': _parseField(_consolidationRateCtrl),
        'monthly_payment': _consolidationPayment,
        'extra_payment': 0.0,
        'normal_months': _termMonths,
        'interest_saved': _monthlySavings > 0
            ? _monthlySavings * _termMonths
            : 0.0,
        'inputs': {
          'debts': _debts
              .map((d) => {
                    'balance': _parseField(d.balanceCtrl),
                    'rate': _parseField(d.rateCtrl),
                    'payment': _parseField(d.paymentCtrl),
                  })
              .toList(),
          'consolidation_rate': _parseField(_consolidationRateCtrl),
          'term_months': _termMonths,
        },
        'results': {
          'total_balance': _totalCurrentBalance,
          'total_current_monthly': _totalCurrentMonthlyPayment,
          'consolidation_payment': _consolidationPayment,
          'total_consolidation_cost': _totalConsolidationCost,
          'total_consolidation_interest': _totalConsolidationInterest,
          'monthly_savings': _monthlySavings,
          'avg_current_rate': _averageCurrentRate,
        },
      };

  void _scheduleAutoSave() {
    if (_totalCurrentBalance <= 0 || _consolidationPayment <= 0) return;
    final hash = ResultHasher.hashMixed({
      'total_balance': _roundTo(_totalCurrentBalance, 1000),
      'consolidation_rate': _roundTo(_parseField(_consolidationRateCtrl), 0.25),
      'term_months': _termMonths.toDouble(),
      'debt_count': _debts.length.toDouble(),
    });
    smartHistoryService.scheduleAutoSave(
      appKey: 'loanpayoffus',
      screenId: 'consolidation',
      inputHash: hash,
      l1: _buildL1(),
      l2: _buildL2(),
    );
    historyRefreshNotifier.value++;
  }

  Future<void> _saveScenario(String? label) async {
    if (_totalCurrentBalance <= 0 || _consolidationPayment <= 0) return;
    final hash = ResultHasher.hashMixed({
      'total_balance': _roundTo(_totalCurrentBalance, 1000),
      'consolidation_rate': _roundTo(_parseField(_consolidationRateCtrl), 0.25),
      'term_months': _termMonths.toDouble(),
      'debt_count': _debts.length.toDouble(),
    });
    await smartHistoryService.saveScenario(
      appKey: 'loanpayoffus',
      screenId: 'consolidation',
      inputHash: hash,
      l1: _buildL1(),
      l2: _buildL2(),
      label: label,
    );
    historyRefreshNotifier.value++;
    try { AnalyticsService.instance.logSave(); } catch (_) {}
    try { AnalyticsService.instance.logResultSaved(); } catch (_) {}
    adService.onSave();
    final trigger = await paywallSession.recordAction();
    if (!mounted) return;
    if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
    if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
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
    _scheduleAutoSave();
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
          onChanged: (_) {
            _calcDebounce?.cancel();
            _calcDebounce = Timer(const Duration(milliseconds: 400), () {
              if (mounted) setState(() => _calculate());
              _scheduleAutoSave();
            });
          },
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
                onChanged: (_) {
                  setState(() => _calculate());
                  _scheduleAutoSave();
                },
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
            return Scaffold(
              appBar: AppBar(
                title: Text(isEs
                    ? 'Consolidación de Deudas'
                    : 'Debt Consolidation'),
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              body: CalcwisePageEntrance(
                  child: Column(
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
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                _addDebt();
                              },
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
                                _scheduleAutoSave();
                              },
                            ),
                          ),

                          const SizedBox(height: AppSpacing.lg),

                          // ── RESULTS ───────────────────────────────────────
                          if (hasResult) ...[
                            // Hero savings card
                            CalcwiseStaggerItem(
                              index: 0,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.xxl,
                                  horizontal: AppSpacing.xl,
                                ),
                                decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: _monthlySavings > 0
                                      ? [
                                          _savingsColor,
                                          _savingsDarkColor,
                                        ]
                                      : [
                                          AppTheme.warning,
                                          _warningDarkColor,
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
                            ),

                            const SizedBox(height: AppSpacing.md),

                            // First metric row: Current Monthly | New Payment | Savings
                            CalcwiseStaggerItem(
                              index: 1,
                              child: IntrinsicHeight(
                                child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                              ),
                            ),

                            const SizedBox(height: AppSpacing.sm),

                            // Second metric row: Term | Debts Count | Total Interest
                            CalcwiseStaggerItem(
                              index: 2,
                              child: IntrinsicHeight(
                              child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                            ),
                            ),

                            const SizedBox(height: AppSpacing.sm),

                            // Third metric row: Total Cost + spacer tile
                            CalcwiseStaggerItem(
                              index: 3,
                              child: IntrinsicHeight(
                                child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _ConsolidationMetricTile(
                                    label: isEs
                                        ? 'Costo Total (consolidación)'
                                        : 'Total Cost (consolidation)',
                                    value: AmountFormatter.ui(
                                      _totalConsolidationCost,
                                      'USD',
                                    ),
                                    icon: Icons.account_balance_wallet_outlined,
                                    color: AppTheme.warning,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  _ConsolidationMetricTile(
                                    label: isEs
                                        ? 'Plazo nuevo'
                                        : 'New Term',
                                    value: isEs
                                        ? '$_termMonths meses'
                                        : '$_termMonths months',
                                    icon: Icons.calendar_today_outlined,
                                    color: AppTheme.primary,
                                  ),
                                ],
                              ),
                              ),
                            ),

                            const SizedBox(height: AppSpacing.md),

                            // Verdict chip
                            CalcwiseStaggerItem(
                              index: 4,
                              child: Container(
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
                          const SizedBox(height: AppSpacing.lg),
                          SaveScenarioButton(onSave: _saveScenario),
                            const SizedBox(height: AppSpacing.sm),
                            if (hasResult)
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    HapticFeedback.mediumImpact();
                                    final consolidationRate =
                                        _parseField(_consolidationRateCtrl);
                                    final totalCurrentInterest =
                                        _debts.fold<double>(0, (sum, d) {
                                      final bal = _parseField(d.balanceCtrl);
                                      final rate = _parseField(d.rateCtrl);
                                      final pmt = _parseField(d.paymentCtrl) > 0
                                          ? _parseField(d.paymentCtrl)
                                          : _calcMonthlyPayment(bal, rate, 120);
                                      return sum +
                                          _currentDebtTotalInterest(
                                              bal, rate, pmt);
                                    });
                                    PdfExportService.exportConsolidation(
                                      context,
                                      loans: _debts
                                          .map(
                                            (d) => (
                                              balance: _parseField(d.balanceCtrl),
                                              rate: _parseField(d.rateCtrl),
                                              payment: _parseField(d.paymentCtrl) > 0
                                                  ? _parseField(d.paymentCtrl)
                                                  : _calcMonthlyPayment(
                                                      _parseField(d.balanceCtrl),
                                                      _parseField(d.rateCtrl),
                                                      120,
                                                    ),
                                            ),
                                          )
                                          .toList(),
                                      consolidationRate: consolidationRate,
                                      termMonths: _termMonths,
                                      currentTotalPayment:
                                          _totalCurrentMonthlyPayment,
                                      consolidationPayment: _consolidationPayment,
                                      totalInterestCurrent: totalCurrentInterest,
                                      totalInterestConsolidated:
                                          _totalConsolidationInterest,
                                      netMonthlySavings: _monthlySavings,
                                      isEs: isEs,
                                    );
                                  },
                                  icon: isPremium
                                      ? const Icon(
                                          Icons.picture_as_pdf_rounded,
                                          size: 18,
                                        )
                                      : const Icon(
                                          Icons.lock_outline_rounded,
                                          size: 18,
                                        ),
                                  label: Text(
                                    isEs ? 'Exportar PDF' : 'Export PDF',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.primary,
                                    side: const BorderSide(
                                        color: AppTheme.primary),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppRadius.mdPlus),
                                    ),
                                    minimumSize:
                                        const Size.fromHeight(44),
                                  ),
                                ),
                              ),
                          const SizedBox(height: AppSpacing.listBottomInset),
                        ],
                      ),
                    ),
                  ),
                  const CalcwiseAdFooter(),
                ],
              )),
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
