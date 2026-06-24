import 'dart:async';
import 'dart:math' show pow;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/language/language_notifier.dart';
import '../../../core/services/pdf_export_service.dart';
import '../../../main.dart';
import '../../providers/loan_provider.dart';
import '../../widgets/save_scenario_button.dart';

// Semantic domain colors — not in shared theme (savings/warning gradient)
const _savingsColor = Color(0xFF00C853);
const _savingsDarkColor = Color(0xFF009624);
const _warningDarkColor = Color(0xFFE65100);

class RefinanceScreen extends ConsumerStatefulWidget {
  const RefinanceScreen({super.key});

  @override
  ConsumerState<RefinanceScreen> createState() => _RefinanceScreenState();
}

class _RefinanceScreenState extends ConsumerState<RefinanceScreen> {
  Timer? _calcDebounce;

  // Input controllers — pre-filled from main loan provider, fallback to defaults
  final _balanceCtrl = TextEditingController(text: '15000');
  final _currentRateCtrl = TextEditingController(text: '5.5');
  final _currentMonthsCtrl = TextEditingController(text: '60');
  final _newRateCtrl = TextEditingController(text: '4.0');
  final _newTermCtrl = TextEditingController(text: '60');
  final _closingCostsCtrl = TextEditingController(text: '0');

  // Results
  double _currentPmt = 0;
  double _newPmt = 0;
  double _monthlySavings = 0;
  double _totalCurrentCost = 0;
  double _totalNewCost = 0;
  double _totalSavings = 0;
  int _breakEvenMonths = 0;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('refinance');
    isSpanishNotifier.addListener(_onLangChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Pre-fill balance and current rate from the main loan calculator.
      // Only overwrite defaults when the user has actually entered a loan
      // (loanAmount > 0 guards against the provider's own default values
      // being a worse UX than our own sensible defaults).
      final loanInput = ref.read(loanInputProvider);
      if (loanInput.loanAmount > 0) {
        _balanceCtrl.text = loanInput.loanAmount.toStringAsFixed(0);
        _currentRateCtrl.text = loanInput.interestRatePct.toStringAsFixed(2);
      }
      _calculate();
    });
  }

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLangChange);
    _calcDebounce?.cancel();
    _balanceCtrl.dispose();
    _currentRateCtrl.dispose();
    _currentMonthsCtrl.dispose();
    _newRateCtrl.dispose();
    _newTermCtrl.dispose();
    _closingCostsCtrl.dispose();
    smartHistoryService.cancelPendingSave('loanpayoffus', 'refinance');
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  double _parseField(TextEditingController ctrl) {
    final text = ctrl.text.replaceAll(',', '.');
    return double.tryParse(text.trim()) ?? 0.0;
  }

  double _calcMonthlyPayment(
      double balance, double annualRatePct, int months) {
    if (balance <= 0 || months <= 0) return 0;
    if (annualRatePct <= 0) return balance / months;
    final r = annualRatePct / 100 / 12;
    return balance * r / (1 - pow(1 + r, -months));
  }

  void _calculate() {
    unawaited(AnalyticsService.instance.maybeLogFirstCalculate());
    final balance = _parseField(_balanceCtrl);
    final currentRate = _parseField(_currentRateCtrl);
    final currentMonths = _parseField(_currentMonthsCtrl).toInt();
    final newRate = _parseField(_newRateCtrl);
    final newMonths = _parseField(_newTermCtrl).toInt();
    final closingCosts = _parseField(_closingCostsCtrl);

    // Guard: avoid division by zero / nonsensical output
    if (balance <= 0 || currentMonths <= 0 || newMonths <= 0) {
      setState(() {
        _currentPmt = 0;
        _newPmt = 0;
        _monthlySavings = 0;
        _totalCurrentCost = 0;
        _totalNewCost = 0;
        _totalSavings = 0;
        _breakEvenMonths = 0;
      });
      return;
    }

    final cp = _calcMonthlyPayment(balance, currentRate, currentMonths);
    final np = _calcMonthlyPayment(balance, newRate, newMonths);
    final ms = cp - np;
    final tcc = cp * currentMonths;
    final tnc = np * newMonths + closingCosts;

    setState(() {
      _currentPmt = cp;
      _newPmt = np;
      _monthlySavings = ms;
      _totalCurrentCost = tcc;
      _totalNewCost = tnc;
      _totalSavings = tcc - tnc;
      _breakEvenMonths = closingCosts > 0 && ms > 0
          ? (closingCosts / ms).ceil()
          : 0;
    });
    _scheduleAutoSave();
  }

  // ── SmartHistory ────────────────────────────────────────────────────────────
  double _roundTo(double v, double step) =>
      step == 0 ? v : (v / step).round() * step;

  Map<String, dynamic> _buildL1() => {
        'balance': _parseField(_balanceCtrl),
        'monthly_savings': _monthlySavings,
        'total_savings': _totalSavings,
        'break_even_months': _breakEvenMonths,
      };

  Map<String, dynamic> _buildL2() => {
        'inputs': {
          'balance': _parseField(_balanceCtrl),
          'current_rate': _parseField(_currentRateCtrl),
          'current_months': _parseField(_currentMonthsCtrl).toInt(),
          'new_rate': _parseField(_newRateCtrl),
          'new_months': _parseField(_newTermCtrl).toInt(),
          'closing_costs': _parseField(_closingCostsCtrl),
        },
        'results': {
          'current_pmt': _currentPmt,
          'new_pmt': _newPmt,
          'monthly_savings': _monthlySavings,
          'total_current_cost': _totalCurrentCost,
          'total_new_cost': _totalNewCost,
          'total_savings': _totalSavings,
          'break_even_months': _breakEvenMonths,
        },
      };

  void _scheduleAutoSave() {
    if (_currentPmt <= 0) return;
    final hash = ResultHasher.hashMixed({
      'balance': _roundTo(_parseField(_balanceCtrl), 1000),
      'cur_rate': _roundTo(_parseField(_currentRateCtrl), 0.25),
      'new_rate': _roundTo(_parseField(_newRateCtrl), 0.25),
      'new_months': _roundTo(_parseField(_newTermCtrl), 12),
    });
    smartHistoryService.scheduleAutoSave(
      appKey: 'loanpayoffus',
      screenId: 'refinance',
      inputHash: hash,
      l1: _buildL1(),
      l2: _buildL2(),
    );
    historyRefreshNotifier.value++;
  }

  Future<void> _saveScenario(String? label) async {
    if (_currentPmt <= 0) return;
    final hash = ResultHasher.hashMixed({
      'balance': _roundTo(_parseField(_balanceCtrl), 1000),
      'cur_rate': _roundTo(_parseField(_currentRateCtrl), 0.25),
      'new_rate': _roundTo(_parseField(_newRateCtrl), 0.25),
      'new_months': _roundTo(_parseField(_newTermCtrl), 12),
    });
    await smartHistoryService.saveScenario(
      appKey: 'loanpayoffus',
      screenId: 'refinance',
      inputHash: hash,
      l1: _buildL1(),
      l2: _buildL2(),
      label: label,
    );
    historyRefreshNotifier.value++;
    try { AnalyticsService.instance.logSave(); } catch (_) {}
    try { AnalyticsService.instance.logResultSaved(); } catch (_) {}
    adService.onSave();
    paywallSession.recordAction().ignore();
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
    TextInputAction textInputAction = TextInputAction.next,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: textInputAction,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(
            labelText: label,
            prefixText: prefix,
            suffixText: suffix,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
          ),
          onChanged: (_) {
            _calcDebounce?.cancel();
            _calcDebounce = Timer(const Duration(milliseconds: 400), () {
              if (mounted) setState(() => _calculate());
            });
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final newMonths = _parseField(_newTermCtrl).toInt();
    final hasResult = _newPmt > 0 && _currentPmt > 0;
    final isGood = _totalSavings > 0 &&
        (_breakEvenMonths == 0 || _breakEvenMonths < newMonths);

    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: freemiumService.hasFullAccessNotifier,
          builder: (context, isPremium, _) {
            return Scaffold(
              appBar: AppBar(
                title: Text(isEs
                    ? 'Calculadora de Refinanciamiento'
                    : 'Refinance Calculator'),
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
                          // ── CURRENT LOAN ─────────────────────────────────
                          _sectionHeader(
                            isEs ? 'Préstamo Actual' : 'Current Loan',
                          ),
                          _field(
                            isEs ? 'Saldo Actual' : 'Current Balance',
                            _balanceCtrl,
                            prefix: '\$',
                          ),
                          _field(
                            isEs ? 'Tasa Actual' : 'Current Rate',
                            _currentRateCtrl,
                            suffix: '%',
                          ),
                          _field(
                            isEs ? 'Meses Restantes' : 'Remaining Months',
                            _currentMonthsCtrl,
                            suffix: isEs ? 'meses' : 'mo',
                          ),

                          const SizedBox(height: AppSpacing.xxl),

                          // ── NEW LOAN ──────────────────────────────────────
                          _sectionHeader(
                            isEs ? 'Nuevo Préstamo' : 'New Loan',
                          ),
                          _field(
                            isEs ? 'Nueva Tasa' : 'New Rate',
                            _newRateCtrl,
                            suffix: '%',
                          ),
                          _field(
                            isEs ? 'Nuevo Plazo' : 'New Term',
                            _newTermCtrl,
                            suffix: isEs ? 'meses' : 'mo',
                          ),
                          _field(
                            isEs ? 'Costos de Cierre' : 'Closing Costs',
                            _closingCostsCtrl,
                            prefix: '\$',
                            textInputAction: TextInputAction.done,
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
                                            ? 'PAGO MÁS ALTO'
                                            : 'HIGHER PAYMENT'),
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

                            // Row 1: Break-even / Total Savings / New Monthly
                            CalcwiseStaggerItem(
                              index: 1,
                              child: IntrinsicHeight(
                                child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _RefinanceMetricTile(
                                    label: isEs
                                        ? 'Punto de Equilibrio'
                                        : 'Break-even',
                                    value: _breakEvenMonths > 0
                                        ? '$_breakEvenMonths ${isEs ? "meses" : "months"}'
                                        : 'N/A',
                                    icon: Icons.timer_outlined,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  _RefinanceMetricTile(
                                    label: isEs
                                        ? 'Ahorro Total'
                                        : 'Total Savings',
                                    value: AmountFormatter.ui(
                                        _totalSavings, 'USD'),
                                    icon: Icons.savings_outlined,
                                    color: _totalSavings >= 0
                                        ? AppTheme.accentGood
                                        : AppTheme.warning,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  _RefinanceMetricTile(
                                    label: isEs
                                        ? 'Nuevo Pago Mensual'
                                        : 'New Monthly',
                                    value: AmountFormatter.ui(_newPmt, 'USD'),
                                    icon: Icons.calendar_today_rounded,
                                  ),
                                ],
                              ),
                              ),
                            ),

                            const SizedBox(height: AppSpacing.sm),

                            // Row 2: Total cost current / Total cost new
                            CalcwiseStaggerItem(
                              index: 2,
                              child: IntrinsicHeight(
                                child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                _RefinanceMetricTile(
                                  label: isEs
                                      ? 'Costo Total Actual'
                                      : 'Current Total Cost',
                                  value: AmountFormatter.ui(
                                      _totalCurrentCost, 'USD'),
                                  icon: Icons.credit_card_rounded,
                                  color: AppTheme.warning,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                _RefinanceMetricTile(
                                  label: isEs
                                      ? 'Nuevo Costo Total'
                                      : 'New Total Cost',
                                  value: AmountFormatter.ui(
                                      _totalNewCost, 'USD'),
                                  icon: Icons.payments_outlined,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                _RefinanceMetricTile(
                                  label: isEs
                                      ? 'Pago Actual'
                                      : 'Current Monthly',
                                  value: AmountFormatter.ui(
                                      _currentPmt, 'USD'),
                                  icon: Icons.calendar_month_rounded,
                                ),
                              ],
                              ),
                              ),
                            ),

                            const SizedBox(height: AppSpacing.md),

                            // Verdict chip
                            CalcwiseStaggerItem(
                              index: 3,
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
                                    : AppTheme.warning
                                        .withValues(alpha: 0.1),
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(AppRadius.xl),
                                ),
                                border: Border.all(
                                  color: isGood
                                      ? AppTheme.accentGood
                                          .withValues(alpha: 0.4)
                                      : AppTheme.warning
                                          .withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isGood
                                        ? Icons.check_circle_outline_rounded
                                        : Icons.warning_amber_rounded,
                                    color: isGood
                                        ? AppTheme.accentGood
                                        : AppTheme.warning,
                                    size: 18,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Flexible(
                                    child: Text(
                                      isGood
                                          ? (isEs
                                              ? 'El refinanciamiento tiene sentido'
                                              : 'Refinancing makes sense')
                                          : (isEs
                                              ? 'No es conveniente'
                                              : 'Not worth it'),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: AppTextSize.body,
                                        color: isGood
                                            ? AppTheme.accentGood
                                            : AppTheme.warning,
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

                          // Empty state
                          if (!hasResult) ...[
                            const SizedBox(height: AppSpacing.xl),
                            Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.compare_arrows_rounded,
                                    size: 48,
                                    color:
                                        AppTheme.primary.withValues(alpha: 0.3),
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
                          if (isPremium) ...[
                            const SizedBox(height: AppSpacing.lg),
                            SaveScenarioButton(onSave: _saveScenario),
                            const SizedBox(height: AppSpacing.sm),
                            if (hasResult)
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    HapticFeedback.mediumImpact();
                                    PdfExportService.exportRefinance(
                                    context,
                                    currentBalance:
                                        _parseField(_balanceCtrl),
                                    currentRate:
                                        _parseField(_currentRateCtrl),
                                    remainingMonths:
                                        _parseField(_currentMonthsCtrl).toInt(),
                                    newRate: _parseField(_newRateCtrl),
                                    newTermMonths:
                                        _parseField(_newTermCtrl).toInt(),
                                    closingCosts:
                                        _parseField(_closingCostsCtrl),
                                    currentPayment: _currentPmt,
                                    newPayment: _newPmt,
                                    monthlySavings: _monthlySavings,
                                    breakEvenMonths: _breakEvenMonths,
                                    totalSavings: _totalSavings,
                                    isEs: isEs,
                                  );
                                  },
                                  icon: const Icon(
                                    Icons.picture_as_pdf_rounded,
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
                          ],
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
// Metric tile (local to refinance screen)
// ─────────────────────────────────────────────────────────────────────────────
class _RefinanceMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const _RefinanceMetricTile({
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
