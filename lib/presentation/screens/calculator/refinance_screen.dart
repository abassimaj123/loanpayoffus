import 'dart:math' show pow;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard;
import '../../../core/theme/app_theme.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/language/language_notifier.dart';
import '../../widgets/paywall_hard.dart';

class RefinanceScreen extends StatefulWidget {
  const RefinanceScreen({super.key});

  @override
  State<RefinanceScreen> createState() => _RefinanceScreenState();
}

class _RefinanceScreenState extends State<RefinanceScreen> {
  // Input controllers — pre-filled so results appear immediately on open
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _calculate();
    });
  }

  @override
  void dispose() {
    _balanceCtrl.dispose();
    _currentRateCtrl.dispose();
    _currentMonthsCtrl.dispose();
    _newRateCtrl.dispose();
    _newTermCtrl.dispose();
    _closingCostsCtrl.dispose();
    super.dispose();
  }

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
          onChanged: (_) => setState(() => _calculate()),
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
            if (!isPremium) {
              return Scaffold(
                appBar: AppBar(
                  title: Text(isEs
                      ? 'Calculadora de Refinanciamiento'
                      : 'Refinance Calculator'),
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
                        Text(
                          isEs ? 'Función Premium' : 'Premium Feature',
                          style: const TextStyle(
                            fontSize: AppTextSize.title,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          isEs
                              ? 'Desbloquea la Calculadora de Refinanciamiento con una suscripción Pro.'
                              : 'Unlock the Refinance Calculator with a Pro subscription.',
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
                    ? 'Calculadora de Refinanciamiento'
                    : 'Refinance Calculator'),
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

                            const SizedBox(height: AppSpacing.md),

                            // Row 1: Break-even / Total Savings / New Monthly
                            Row(
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

                            const SizedBox(height: AppSpacing.sm),

                            // Row 2: Total cost current / Total cost new
                            Row(
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
