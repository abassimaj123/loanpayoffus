import 'dart:async';
import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard, PaywallSoft;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'refinance_screen.dart';
import 'consolidation_screen.dart';
import '../../widgets/paywall_hard.dart';
import '../../widgets/paywall_soft.dart';
import '../../../core/services/pdf_export_service.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../main.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../domain/models/loan_input.dart';
import '../../../domain/models/payoff_result.dart';
import '../../../domain/models/loan_type.dart';
import '../../../domain/usecases/loan_calculator.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../../core/language/language_notifier.dart';
import '../../../core/utils/milestone_tracker.dart';
import '../../providers/loan_provider.dart';
import '../../widgets/insight_card.dart';
import '../../widgets/milestone_celebration.dart';
import '../../widgets/save_scenario_button.dart';
import '../../../core/utils/insight_engine.dart';

/// Debt-free date [months] from today using real calendar months
/// (not a 30-day approximation, which drifts ~6 days/year).
DateTime _debtFreeDate(int months) {
  final now = DateTime.now();
  return DateTime(now.year, now.month + months, now.day);
}

/// Formats a payoff duration, showing "50+ yrs" when the schedule hit the
/// 600-month cap (loan never amortizes at the entered payment).
String _fmtPayoff(int months, bool isEs) {
  if (months >= 600) return isEs ? '50+ años' : '50+ yrs';
  return '${months ~/ 12}y ${months % 12}m';
}

double _parseNum(String v) {
  if (v.isEmpty) return 0.0;
  String s;
  if (v.contains('.') && v.contains(',')) {
    // Both separators: the last one is the decimal separator
    s = v.lastIndexOf('.') > v.lastIndexOf(',')
        ? v.replaceAll(',', '')               // US: 1,234.56
        : v.replaceAll('.', '').replaceAll(',', '.'); // EU: 1.234,56
  } else if (v.contains(',')) {
    final parts = v.split(',');
    // All groups after the first comma are 3 digits → US thousands separator
    s = parts.sublist(1).every((p) => p.length == 3)
        ? v.replaceAll(',', '')   // 15,000 or 1,000,000 → 15000
        : v.replaceAll(',', '.'); // 15,5 EU decimal → 15.5
  } else {
    s = v;
  }
  return double.tryParse(s.trim()) ?? 0.0;
}

class CalculatorScreen extends ConsumerStatefulWidget {
  const CalculatorScreen({super.key});
  @override
  ConsumerState<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends ConsumerState<CalculatorScreen>
    with CalcwiseAutoCalcMixin {
  LoanType _type = LoanType.mortgage;
  final _amountCtrl = TextEditingController(text: '15000');
  final _rateCtrl = TextEditingController(text: '5.5');
  final _paymentCtrl = TextEditingController(text: '300');
  Timer? _adDebounce;
  Timer? _saveDebounce;
  double _extra = 0;
  double _extraSlider = 0;
  bool _extraOneTime = false; // toggle: monthly vs one-time extra
  bool _biweekly = false; // toggle: monthly vs biweekly mode
  bool _validated = false; // inline validation flag
  bool _hadResult = false; // tracks first-result haptic
  bool _celebrationShown = false; // tracks debt-free celebration

  // Biweekly results (computed alongside main calculation)
  Map<String, double>? _biweeklyData;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('calculator');
    isSpanishNotifier.addListener(_onLangChange);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // _paymentCtrl is pre-filled with '300', only auto-compute if still empty
      if (mounted && _paymentCtrl.text.isEmpty) {
        final amount = _parseNum(_amountCtrl.text);
        final rate = _parseNum(_rateCtrl.text);
        _paymentCtrl.text = LoanCalculator.computeMonthlyPayment(
          amount,
          rate,
          _type.defaultTermMonths,
        ).toStringAsFixed(2);
      }
      // Auto-calculate on first open so result is visible immediately
      if (mounted) await _recalculate();
    });
  }

  @override
  void dispose() {
    _adDebounce?.cancel();
    _saveDebounce?.cancel();
    smartHistoryService.cancelPendingSave('loanpayoffus', 'calculator');
    isSpanishNotifier.removeListener(_onLangChange);
    _amountCtrl.dispose();
    _rateCtrl.dispose();
    _paymentCtrl.dispose();
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  void _onTypeChanged(LoanType? t) {
    if (t == null) return;
    setState(() {
      _type = t;
      _amountCtrl.text = t.defaultAmount.toStringAsFixed(0);
      _rateCtrl.text = t.defaultRate.toString();
      _paymentCtrl.clear();
      _celebrationShown = false;
    });
    // Reset milestone flags since the user started a new loan type
    MilestoneTracker.instance.reset();
    _recalculate();
  }

  Future<void> _recalculate() async {
    if (!_validated) setState(() => _validated = true);
    final amount = _parseNum(_amountCtrl.text);
    final rate = _parseNum(_rateCtrl.text);
    final computed = LoanCalculator.computeMonthlyPayment(
      amount,
      rate,
      _type.defaultTermMonths,
    );
    final payment = double.tryParse(
      (_paymentCtrl.text.contains('.') && _paymentCtrl.text.contains(','))
          ? _paymentCtrl.text.replaceAll(',', '')
          : _paymentCtrl.text.replaceAll(',', '.'),
    );
    final monthlyPmt = (payment != null && payment > 0) ? payment : computed;

    final input = LoanInput(
      loanType: _type,
      loanAmount: amount,
      interestRatePct: rate,
      monthlyPayment: monthlyPmt,
      // One-time extra is applied as a true lump sum at month 1 by the engine
      // (extraIsOneTime), not smeared across the term.
      extraPayment: _extra,
      extraIsOneTime: _extraOneTime,
    );
    ref.read(loanInputProvider.notifier).update(input);

    // Compute biweekly data whenever amount/rate/term are valid
    if (amount > 0 && rate > 0) {
      setState(() {
        _biweeklyData = LoanCalculator.calculateBiweekly(
          amount,
          rate,
          _type.defaultTermMonths,
        );
      });
    }

    _adDebounce?.cancel();
    // Skip the interstitial debounce entirely when this recalculation is
    // about to trigger the "Debt Free!" milestone celebration — an
    // interstitial popping right before/during that dialog is the worst
    // possible timing.
    final resultForAdGate = ref.read(payoffResultProvider);
    final aboutToCelebrate = resultForAdGate != null &&
        !_celebrationShown &&
        (resultForAdGate.extraMonths <= 1 || resultForAdGate.extraMonths <= 0);
    if (!aboutToCelebrate) {
      _adDebounce = Timer(const Duration(milliseconds: 1500), () {
        adService.onAction();
      });
    }
    // Haptic only fires the first time a result appears (not on every keystroke)
    final currentResult = ref.read(payoffResultProvider);
    if (currentResult != null && !_hadResult) {
      _hadResult = true;
      HapticFeedback.mediumImpact();
    }
    // Analytics
    final result = ref.read(payoffResultProvider);
    if (result != null && amount > 0 && rate > 0) {
      AnalyticsService.instance.logCalculation(
        loanType: _type.label,
        loanAmount: amount,
        interestRate: rate,
        extraPayment: _extra,
        monthsSaved: result.monthsSaved,
        interestSaved: result.interestSaved,
      );
      AnalyticsService.instance.logCalculationCompleted(
        params: {
          'loan_type': _type.label,
          'loan_amount': amount.round(),
          'interest_rate': rate,
          'months_saved': result.monthsSaved,
        },
      );
      AnalyticsService.instance.maybeLogFirstCalculate();
      // Emotional trigger: user sees significant savings → ask for review
      if (result.monthsSaved > 12) {
        CalcwiseReviewService.instance.requestAfterPremium();
      }
    }

    if (mounted && !freemiumService.hasFullAccess) {
      final trigger = await paywallSession.recordAction();
      if (!mounted) return;
      if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
      if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
    }

    // SmartHistory auto-save (debounced + hash dedup + ring buffer).
    _scheduleAutoSave(input);

    // Milestone celebrations (debounced so UI is settled).
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 2000), () {
      _checkMilestones(ref.read(payoffResultProvider));
    });
  }

  // ── SmartHistory snapshot ───────────────────────────────────────────────────

  /// Builds the (hash, l1, l2) snapshot for the current result, or null when
  /// inputs are incomplete.
  ({String hash, Map<String, dynamic> l1, Map<String, dynamic> l2})?
  _buildSnapshot(LoanInput input) {
    if (input.loanAmount <= 0 || input.interestRatePct <= 0) return null;
    final result = ref.read(payoffResultProvider);
    if (result == null) return null;

    final hash = ResultHasher.hashMixed({
      'amount': ResultHasher.roundTo(input.loanAmount, 100),
      'rate': ResultHasher.roundTo(input.interestRatePct, 0.01),
      'payment': ResultHasher.roundTo(input.monthlyPayment, 10),
      'extra': ResultHasher.roundTo(input.extraPayment, 10),
      // Distinguishes a one-time lump sum from a recurring monthly extra so
      // two otherwise-identical scenarios don't collide into the same hash
      // (which would make SmartHistoryService treat them as duplicates).
      'extra_one_time': _extraOneTime,
      'type': input.loanType.name,
    });
    final l1 = {
      'loan_type': input.loanType.label,
      'loan_amount': input.loanAmount,
      'monthly_payment': input.monthlyPayment,
      'interest_rate': input.interestRatePct,
    };
    final l2 = {
      'loan_type': input.loanType.label,
      'loan_amount': input.loanAmount,
      'interest_rate': input.interestRatePct,
      'monthly_payment': input.monthlyPayment,
      // Store the raw user-entered extra amount for display in history/PDF.
      // For one-time payments _extra is the lump sum; for monthly it equals
      // input.extraPayment. The calculation results (normal_months,
      // interest_saved) are already pre-computed by the engine (one-time vs
      // monthly handled via LoanInput.extraIsOneTime).
      'extra_payment': _extra,
      // Persists whether the extra above is a one-time lump sum or a
      // recurring monthly extra, so restoring this scenario (or exporting
      // its PDF) doesn't silently mislabel/misinterpret it.
      'extra_one_time': _extraOneTime,
      'normal_months': result.normalMonths,
      'interest_saved': result.interestSaved,
    };
    return (hash: hash, l1: l1, l2: l2);
  }

  void _scheduleAutoSave(LoanInput input) {
    final snap = _buildSnapshot(input);
    if (snap == null) return;
    smartHistoryService.scheduleAutoSave(
      appKey: 'loanpayoffus',
      screenId: 'calculator',
      inputHash: snap.hash,
      l1: snap.l1,
      l2: snap.l2,
      onSaved: () {
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _saveScenario(String? label) async {
    final input = ref.read(loanInputProvider);
    final snap = _buildSnapshot(input);
    if (snap == null) return;
    HapticFeedback.mediumImpact();
    await smartHistoryService.saveScenario(
      appKey: 'loanpayoffus',
      screenId: 'calculator',
      inputHash: snap.hash,
      l1: snap.l1,
      l2: snap.l2,
      label: label,
    );
    historyRefreshNotifier.value++;
    try {
      AnalyticsService.instance.logSave();
    } catch (_) {}
    try {
      AnalyticsService.instance.logResultSaved();
    } catch (_) {}
    adService.onSave();
  }

  // ── Milestone celebrations ─────────────────────────────────────────────────

  /// Called after every recalculate cycle.
  /// Shows a full celebration when the loan is effectively paid off,
  /// and SnackBar nudges at 25/50/75% progress milestones.
  Future<void> _checkMilestones(PayoffResult? result) async {
    if (result == null || !mounted) return;
    final isEs = isSpanishNotifier.value;
    final normalMonths = result.normalMonths;
    if (normalMonths <= 0) return;

    // ── Full payoff celebration ──
    // Trigger when extra payments eliminate virtually the entire remaining term.
    final isFullyPaid = result.extraMonths <= 1 || result.extraMonths <= 0;
    if (isFullyPaid && !_celebrationShown) {
      _celebrationShown = true;
      final input = ref.read(loanInputProvider);
      final debtFreeDate = _debtFreeDate(result.extraMonths);
      final dateStr = DateFormat('MMMM yyyy', isEs ? 'es' : 'en').format(debtFreeDate);
      final shareText = isEs
          ? 'Estoy libre de deudas gracias a LoanPayoff US! '
                'Pagué mi ${input.loanType.label} completamente. '
                'Ahorro: ${AmountFormatter.ui(result.interestSaved, 'USD')} en intereses. '
                'Fecha libre: $dateStr'
          : 'I\'m debt-free with LoanPayoff US! '
                'Paid off my ${input.loanType.label}. '
                'Saved ${AmountFormatter.ui(result.interestSaved, 'USD')} in interest. '
                'Debt-free by: $dateStr';

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          MilestoneCelebrationDialog.show(
            context,
            shareText: shareText,
            isEs: isEs,
          );
        }
      });
      return;
    } else if (!isFullyPaid) {
      // Reset the celebration flag when user modifies inputs
      _celebrationShown = false;
    }

    // ── Partial milestone SnackBars (25 / 50 / 75 %) ──
    // Progress = months eliminated by extra payment / normal months
    final progressPct =
        ((normalMonths - result.extraMonths) / normalMonths * 100)
            .clamp(0, 100)
            .toInt();

    for (final milestone in [75, 50, 25]) {
      if (progressPct >= milestone) {
        final isNew = await MilestoneTracker.instance.claimIfNew(milestone);
        if (isNew && mounted) {
          final message = _milestoneMessage(milestone, isEs);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              margin: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              backgroundColor: AppTheme.primary,
            ),
          );
        }
        break; // only one milestone per recalculate
      }
    }
  }

  String _milestoneMessage(int pct, bool isEs) {
    switch (pct) {
      case 75:
        return isEs
            ? '\u{1F3AF} ¡75% completado! La meta está cerca.'
            : '\u{1F3AF} 75% there! Almost done.';
      case 50:
        return isEs
            ? '\u{1F3AF} ¡A mitad de camino! Sigue así.'
            : '\u{1F3AF} Halfway there! Keep going.';
      case 25:
      default:
        return isEs
            ? '\u{1F4AA} ¡25% completado! Buen comienzo.'
            : '\u{1F4AA} 25% done! Great start.';
    }
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? prefix,
    String? suffix,
    String hint = '',
    bool isCurrency = false,
    String? helperText,
    String? errorText,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: isCurrency
          ? [CurrencyInputFormatter(locale: 'en_US')]
          : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        suffixText: suffix,
        hintText: hint.isEmpty ? null : hint,
        helperText: errorText == null ? helperText : null,
        helperStyle: const TextStyle(fontSize: AppTextSize.xs),
        errorText: errorText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      onChanged: (_) => scheduleCalc(_recalculate),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(payoffResultProvider);
    final input = ref.watch(loanInputProvider);
    final isEs = isSpanishNotifier.value;
    final AppStrings s = isEs ? AppStringsES() : AppStringsEN();

    // Debt-free date based on extra schedule. Suppressed when the loan never
    // amortizes at the entered payment (schedule hit the 600-month cap).
    final debtFreeDate = (result != null && !result.neverPayoff)
        ? _debtFreeDate(result.extraMonths)
        : null;
    final debtFreeDateStr = debtFreeDate != null
        ? DateFormat('MMM yyyy', isEs ? 'es' : 'en').format(debtFreeDate)
        : '';

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        // ── Hero result card (result-first — top of screen) ──
                        AnimatedSwitcher(
                          duration: AppDuration.base,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.06),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          ),
                          child: result != null
                              ? Padding(
                                  key: const ValueKey('hero'),
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.lg,
                                  ),
                                  child: _HeroSavingsCard(
                                    result: result,
                                    input: input,
                                    debtFreeDateStr: debtFreeDateStr,
                                    isEs: isEs,
                                    s: s,
                                  ),
                                )
                              : const SizedBox.shrink(key: ValueKey('no-hero')),
                        ),
                        DropdownButtonFormField<LoanType>(
                          initialValue: _type,
                          decoration: InputDecoration(
                            labelText: s.loanType,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                            ),
                          ),
                          items: LoanType.values
                              .map(
                                (t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t.label),
                                ),
                              )
                              .toList(),
                          onChanged: _onTypeChanged,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _field(
                          s.loanAmount,
                          _amountCtrl,
                          prefix: '\$',
                          hint: '15,000',
                          isCurrency: true,
                          errorText:
                              _validated && _parseNum(_amountCtrl.text) <= 0
                              ? (isEs ? 'Requerido' : 'Required')
                              : null,
                        ),
                        _field(
                          s.interestRate,
                          _rateCtrl,
                          suffix: '%',
                          hint: '5.5',
                          helperText: isEs
                              ? 'Tasa predeterminada de 2026 — actualiza con tu tasa real'
                              : 'Default rate as of 2026 — update to your actual rate',
                          errorText:
                              _validated && _parseNum(_rateCtrl.text) <= 0
                              ? (isEs ? 'Requerido' : 'Required')
                              : null,
                        ),
                        _field(
                          s.monthlyPayment,
                          _paymentCtrl,
                          prefix: '\$',
                          hint: '300',
                          isCurrency: true,
                          errorText:
                              _validated && _parseNum(_paymentCtrl.text) < 0
                              ? (isEs ? 'No válido' : 'Invalid')
                              : null,
                        ),

                        // ── Monthly / Biweekly toggle ──
                        const SizedBox(height: AppSpacing.xs),
                        SegmentedButton<bool>(
                          segments: [
                            ButtonSegment(
                              value: false,
                              label: Text(isEs ? 'Mensual' : 'Monthly'),
                              icon: const Icon(
                                Icons.calendar_month_rounded,
                                size: 16,
                              ),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text(isEs ? 'Quincenal' : 'Biweekly'),
                              icon: const Icon(
                                Icons.date_range_rounded,
                                size: 16,
                              ),
                            ),
                          ],
                          selected: {_biweekly},
                          onSelectionChanged: (v) {
                            setState(() => _biweekly = v.first);
                            _recalculate();
                          },
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            backgroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.selected)) {
                                return AppTheme.primary;
                              }
                              return null;
                            }),
                            foregroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.selected)) {
                                return Theme.of(context).colorScheme.onPrimary;
                              }
                              return null;
                            }),
                          ),
                        ),

                        // ── Biweekly result card ──
                        if (_biweekly && _biweeklyData != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          _BiweeklyCard(
                            data: _biweeklyData!,
                            isEs: isEs,
                          ),
                        ],

                        const SizedBox(height: AppSpacing.sm),
                        // ── Extra payment row with monthly/one-time toggle ──
                        Row(
                          children: [
                            const Icon(
                              Icons.add_circle_outline,
                              size: 18,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              s.extraPayment,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: AppTextSize.bodyMd,
                                color: AppTheme.primaryDark,
                              ),
                            ),
                            const Spacer(),
                            // One-time / Monthly toggle
                            InkWell(
                              onTap: () {
                                setState(() => _extraOneTime = !_extraOneTime);
                                _recalculate();
                              },
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(minHeight: 48),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                    vertical: AppSpacing.xs,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _extraOneTime
                                        ? AppTheme.neutral
                                        : AppTheme.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.md,
                                    ),
                                    border: Border.all(
                                      color: AppTheme.primary,
                                      width: 1,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      _extraOneTime
                                          ? (isEs ? 'Único' : 'One-time')
                                          : (isEs ? 'Mensual' : 'Monthly'),
                                      style: TextStyle(
                                        fontSize: AppTextSize.xs,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: _extra > 0
                                    ? AppTheme.accentGood
                                    : Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.lg,
                                ),
                              ),
                              child: Text(
                                _extraOneTime
                                    ? AmountFormatter.ui(_extra, 'USD')
                                    : '${AmountFormatter.ui(_extra, 'USD')}/mo',
                                style: TextStyle(
                                  color: _extra > 0
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.onSurface
                                            .withValues(alpha: 0.6),
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppTextSize.md,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 14,
                            ),
                          ),
                          child: Slider(
                            value: _extraSlider,
                            min: 0,
                            max: _extraOneTime ? 10000 : 500,
                            divisions: _extraOneTime ? 100 : 50,
                            label:
                                '${AmountFormatter.ui(_extraSlider, 'USD')}${_extraOneTime ? '' : '/mo'}',
                            activeColor: AppTheme.primary,
                            onChanged: (v) {
                              // Snap to meaningful ticks when in monthly mode
                              double snapped = v;
                              if (!_extraOneTime) {
                                const ticks = [
                                  0.0,
                                  50.0,
                                  100.0,
                                  200.0,
                                  300.0,
                                  500.0,
                                ];
                                final nearest = ticks.reduce(
                                  (a, b) =>
                                      (a - v).abs() < (b - v).abs() ? a : b,
                                );
                                if ((nearest - v).abs() < 15) snapped = nearest;
                              }
                              setState(() {
                                _extra = snapped;
                                _extraSlider = snapped;
                              });
                              _recalculate();
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Text(
                            isEs
                                ? 'Paga más del mínimo cada mes para terminar antes'
                                : 'Pay more than required each month to finish sooner',
                            style: TextStyle(
                              fontSize: AppTextSize.xs,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                        // ── Tick labels ──
                        if (!_extraOneTime)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xxl,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children:
                                  ['\$0', '\$50', '\$100', '\$200', '\$500']
                                      .map(
                                        (t) => Text(
                                          t,
                                          style: TextStyle(
                                            fontSize: AppTextSize.xxs,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.45),
                                          ),
                                        ),
                                      )
                                      .toList(),
                            ),
                          ),
                        // ── "Pay off X months sooner" real-time chip ──
                        Builder(
                          builder: (context) {
                            final result = ref.watch(payoffResultProvider);
                            final monthsSaved = result?.monthsSaved ?? 0;
                            final isEs = isSpanishNotifier.value;
                            if (_extra <= 0 || monthsSaved <= 0)
                              return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.xs,
                              ),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.mdPlus,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentGood.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.xxl,
                                    ),
                                    border: Border.all(
                                      color: AppTheme.accentGood,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Text(
                                    isEs
                                        ? 'Liquidas ${monthsSaved ~/ 12}a ${monthsSaved % 12}m antes'
                                        : 'Pay off ${monthsSaved ~/ 12}y ${monthsSaved % 12}m sooner',
                                    style: const TextStyle(
                                      color: AppTheme.accentGood,
                                      fontWeight: FontWeight.bold,
                                      fontSize: AppTextSize.md,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: AppSpacing.lg),
                        AnimatedSwitcher(
                          duration: AppDuration.base,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.06),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: result != null
                              ? KeyedSubtree(
                                  key: const ValueKey('results'),
                                  child: CalcwisePageEntrance(
                                    child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // index 0 — Comparison info cards
                                      CalcwiseStaggerItem(
                                        index: 0,
                                        child: IntrinsicHeight(
                                          child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            Expanded(
                                              child: _InfoCard(
                                                title: s.withoutExtra,
                                                rows: [
                                                  (
                                                    s.payoff,
                                                    _fmtPayoff(result.normalMonths, isEs),
                                                  ),
                                                  (
                                                    s.interest,
                                                    AmountFormatter.ui(result.interestNormal, 'USD'),
                                                  ),
                                                  (
                                                    s.totalPaid,
                                                    AmountFormatter.ui(result.totalPaidNormal, 'USD'),
                                                  ),
                                                ],
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.outline,
                                                isNeutral: true,
                                              ),
                                            ),
                                            const SizedBox(
                                              width: AppSpacing.md,
                                            ),
                                            if (input.extraPayment > 0)
                                              Expanded(
                                                child: _InfoCard(
                                                  title: _extraOneTime
                                                      ? '${AmountFormatter.ui(_extra, 'USD')} ${isEs ? "único" : "one-time"}'
                                                      : '+${AmountFormatter.ui(_extra, 'USD')}/mo',
                                                  rows: [
                                                    (
                                                      s.payoff,
                                                      _fmtPayoff(result.extraMonths, isEs),
                                                    ),
                                                    (
                                                      s.interest,
                                                      AmountFormatter.ui(result.interestExtra, 'USD'),
                                                    ),
                                                    (
                                                      s.totalPaid,
                                                      AmountFormatter.ui(result.totalPaidExtra, 'USD'),
                                                    ),
                                                  ],
                                                  color: AppTheme.accentGood,
                                                ),
                                              ),
                                          ],
                                        ),
                                        ),
                                      ),
                                      // ── Debt-Free Date Banner ──
                                      if (result.monthsSaved > 0) ...[
                                        const SizedBox(height: AppSpacing.lg),
                                        _DebtFreeDateBanner(
                                          result: result,
                                          isEs: isEs,
                                        ),
                                      ],

                                      // ── Balance Over Time chart ──
                                      ...[
                                        const SizedBox(height: AppSpacing.lg),
                                        CalcwiseStaggerItem(
                                          index: 1,
                                          child: _BalanceChart(
                                            result: result,
                                            isEs: isEs,
                                          ),
                                        ),
                                      ],

                                      // ── Smart Insights ──
                                      ...[
                                        const SizedBox(height: AppSpacing.lg),
                                        CalcwiseStaggerItem(
                                          index: 2,
                                          child: InsightCard(
                                            isSpanish: isEs,
                                            insights: InsightEngine.generate(
                                              balance: input.loanAmount,
                                              annualRatePct:
                                                  input.interestRatePct,
                                              monthlyPayment:
                                                  input.monthlyPayment,
                                              monthsToPayoff:
                                                  result.normalMonths,
                                              totalInterest:
                                                  result.interestNormal,
                                              extraMonthlyPayment:
                                                  (input.extraPayment > 0 &&
                                                      !input.extraIsOneTime)
                                                  ? input.extraPayment
                                                  : null,
                                              monthsSavedWithExtra:
                                                  (input.extraPayment > 0 &&
                                                      !input.extraIsOneTime)
                                                  ? result.monthsSaved
                                                  : null,
                                              interestSavedWithExtra:
                                                  (input.extraPayment > 0 &&
                                                      !input.extraIsOneTime)
                                                  ? result.interestSaved
                                                  : null,
                                              isEs: isEs,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.lg),
                                        Text(
                                          isEs ? 'Más Calculadoras' : 'More Calculators',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: AppTextSize.bodyMd,
                                            color: AppTheme.primaryDark,
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.sm),
                                        // index 3 — Refinance Calculator CTA
                                        CalcwiseStaggerItem(
                                          index: 3,
                                          child: _RefinanceCta(
                                            isEs: isEs,
                                            input: input,
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.sm),
                                        CalcwiseStaggerItem(
                                          index: 4,
                                          child: _ConsolidationCta(
                                            isEs: isEs,
                                            input: input,
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        // ── Save Scenario (pinned history) ──
                                        SaveScenarioButton(
                                          onSave: _saveScenario,
                                        ),
                                        const SizedBox(height: AppSpacing.sm),
                                        // ── PDF Export ──
                                        Builder(
                                          builder: (ctx) {
                                            final res = ref.watch(payoffResultProvider);
                                            final inp = ref.watch(loanInputProvider);
                                            if (res == null) return const SizedBox.shrink();
                                            return SizedBox(
                                              width: double.infinity,
                                              child: OutlinedButton.icon(
                                                onPressed: () {
                                                    HapticFeedback.mediumImpact();
                                                    PdfExportService.exportCalculator(
                                                  ctx,
                                                  loanBalance: inp.loanAmount,
                                                  interestRate: inp.interestRatePct,
                                                  monthlyPayment: inp.monthlyPayment,
                                                  extraPayment: inp.extraPayment,
                                                  extraOneTime: inp.extraIsOneTime,
                                                  monthsWithout: res.normalMonths,
                                                  monthsWith: res.extraMonths,
                                                  interestWithout: res.interestNormal,
                                                  interestWith: res.interestExtra,
                                                  interestSaved: res.interestSaved,
                                                  monthsSaved: res.monthsSaved,
                                                  isEs: isEs,
                                                );},
                                                icon: const Icon(
                                                  Icons.picture_as_pdf_rounded,
                                                  size: 18,
                                                ),
                                                label: Text(isEs
                                                    ? 'Exportar PDF'
                                                    : 'Export PDF'),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: AppTheme.primary,
                                                  side: const BorderSide(
                                                      color: AppTheme.primary),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            AppRadius.mdPlus),
                                                  ),
                                                  minimumSize:
                                                      const Size.fromHeight(44),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(height: AppSpacing.sm),
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
                                      ],
                                    ],
                                  ),  // Column
                                  ),  // CalcwisePageEntrance
                                )     // KeyedSubtree
                              : KeyedSubtree(
                                  key: const ValueKey('empty'),
                                  child: CalcwiseEmptyState(
                                    icon: Icons.account_balance_rounded,
                                    title: isEs
                                        ? 'Sin préstamo aún'
                                        : 'No loans yet',
                                    body: isEs
                                        ? 'Ingresa los valores para ver tu plan de pago.'
                                        : 'Enter values above to see your payoff plan.',
                                  ),
                                ),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                      ],
                    ),  // Column
                  ),    // ConstrainedBox
                ),      // Center
              ),        // SingleChildScrollView
            ),          // Expanded
          const CalcwiseAdFooter(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero savings card (result-first — sits at the top of the screen)
// ---------------------------------------------------------------------------
class _HeroSavingsCard extends StatelessWidget {
  final PayoffResult result;
  final LoanInput input;
  final String debtFreeDateStr;
  final bool isEs;
  final AppStrings s;

  const _HeroSavingsCard({
    required this.result,
    required this.input,
    required this.debtFreeDateStr,
    required this.isEs,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xxl,
        horizontal: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        gradient: result.monthsSaved > 0
            ? const LinearGradient(
                colors: [
                  CalcwiseSemanticColors.successDeep,
                  CalcwiseSemanticColors.successDark,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [AppTheme.primary, AppTheme.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(AppRadius.xxl),
      ),
      child: Column(
        children: [
          if (result.monthsSaved > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.savings_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  s.youCouldSave,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: AppTextSize.md,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              AmountFormatter.ui(result.interestSaved, 'USD'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: AppTextSize.hero,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.mdPlus,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppRadius.xxl),
              ),
              child: Text(
                '${s.inInterest}  •  ${result.yearsSaved}y ${result.remMonthsSaved}m ${s.faster}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: AppTextSize.md,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  s.payoffTimeline,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: AppTextSize.md,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.smPlus),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                result.neverPayoff
                    ? (isEs ? '50+ años' : '50+ yrs')
                    : isEs
                        ? '${result.normalMonths ~/ 12} ${result.normalMonths ~/ 12 == 1 ? 'año' : 'años'} ${result.normalMonths % 12} ${result.normalMonths % 12 == 1 ? 'mes' : 'meses'}'
                        : '${result.normalMonths ~/ 12} ${result.normalMonths ~/ 12 == 1 ? 'yr' : 'yrs'} ${result.normalMonths % 12} ${result.normalMonths % 12 == 1 ? 'month' : 'months'}',
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: AppTextSize.hero,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (result.neverPayoff) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                isEs
                    ? 'El pago no cubre el interés — aumenta el pago mensual.'
                    : 'Payment doesn\'t cover interest — raise your monthly payment.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: AppTextSize.xs,
                ),
              ),
            ],
          ],
          // ── Debt-free date chip ──
          if (debtFreeDateStr.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.smPlus),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.event_available_rounded,
                  color: Colors.white60,
                  size: 15,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '${s.debtFreeDate}: $debtFreeDateStr',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: AppTextSize.sm,
                  ),
                ),
              ],
            ),
          ],
          // ── Interest-to-loan ratio insight ──
          if (result.interestNormal > 0 && input.loanAmount > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${isEs ? "Pagas" : "You pay"} ${((result.interestNormal / input.loanAmount) * 100).toStringAsFixed(0)}% '
              '${isEs ? "del préstamo en intereses" : "of loan amount in interest"}',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: AppTextSize.xs,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  final Color color;
  final bool isNeutral;
  const _InfoCard({
    required this.title,
    required this.rows,
    required this.color,
    this.isNeutral = false,
  });
  @override
  Widget build(BuildContext context) => Card(
    color: color.withValues(alpha: 0.05),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      side: BorderSide(color: color.withValues(alpha: 0.4), width: 1.5),
    ),
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: AppTextSize.xs,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.smPlus),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      r.$1,
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.55),
                        fontSize: AppTextSize.xs,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    r.$2,
                    style: TextStyle(
                      fontSize: AppTextSize.sm,
                      fontWeight: FontWeight.bold,
                      color: isNeutral
                          ? Theme.of(context).colorScheme.onSurface
                          : color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Debt-Free Date Banner
// ---------------------------------------------------------------------------
class _DebtFreeDateBanner extends StatelessWidget {
  final PayoffResult result;
  final bool isEs;

  const _DebtFreeDateBanner({
    required this.result,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    final debtFreeDate = _debtFreeDate(result.extraMonths);
    final dateStr = DateFormat('MMMM yyyy', isEs ? 'es' : 'en').format(debtFreeDate);
    final yrs = result.monthsSaved ~/ 12;
    final mos = result.monthsSaved % 12;
    final soonerLabel = isEs
        ? '${yrs > 0 ? "${yrs}a " : ""}${mos}m antes — ahorras ${AmountFormatter.ui(result.interestSaved, 'USD')}'
        : '${yrs > 0 ? "${yrs}y " : ""}${mos}m sooner — save ${AmountFormatter.ui(result.interestSaved, 'USD')}';
    final headerLabel = isEs ? 'LIBRE DE DEUDA EL' : 'DEBT-FREE BY';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.mdPlus,
        AppSpacing.lg,
        AppSpacing.mdPlus,
      ),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: AppTheme.primary),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.mdPlus,
                  AppSpacing.lg,
                  AppSpacing.mdPlus,
                ),
                child: Row(
                  children: [
                    const Text(
                      '🎯',
                      style: TextStyle(fontSize: AppTextSize.titleMd),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headerLabel,
                            style: TextStyle(
                              fontSize: AppTextSize.xs,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            dateStr,
                            style: const TextStyle(
                              fontSize: AppTextSize.display,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            soonerLabel,
                            style: TextStyle(
                              fontSize: AppTextSize.sm,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Balance Over Time chart
// ---------------------------------------------------------------------------
class _BalanceChart extends StatelessWidget {
  final PayoffResult result;
  final bool isEs;

  const _BalanceChart({required this.result, required this.isEs});

  @override
  Widget build(BuildContext context) {
    if (result.normalSchedule.isEmpty) return const SizedBox.shrink();
    // Sample every N months to keep data points manageable
    const maxPoints = 60;
    final normalLen = result.normalSchedule.length;
    final extraLen = result.schedule.length;
    final maxLen = normalLen > extraLen ? normalLen : extraLen;
    final step = (maxLen / maxPoints).ceil().clamp(1, maxLen);

    List<FlSpot> sampleSpots(List<FlSpot> spots, int len) {
      final out = <FlSpot>[];
      for (int i = 0; i < len; i += step) {
        out.add(spots[i]);
      }
      // Always include the final zero point
      if (out.isEmpty || out.last.x != len.toDouble()) {
        out.add(FlSpot(len.toDouble(), 0));
      }
      return out;
    }

    final normalSpots = sampleSpots([
      FlSpot(
        0,
        result.normalSchedule.isNotEmpty
            ? (result.normalSchedule.first.balance +
                      result.normalSchedule.first.principal) /
                  1000
            : 0,
      ),
      ...List.generate(
        normalLen,
        (i) =>
            FlSpot((i + 1).toDouble(), result.normalSchedule[i].balance / 1000),
      ),
    ], normalLen + 1);

    final extraSpots = sampleSpots([
      FlSpot(
        0,
        result.schedule.isNotEmpty
            ? (result.schedule.first.balance +
                      result.schedule.first.principal) /
                  1000
            : 0,
      ),
      ...List.generate(
        extraLen,
        (i) => FlSpot((i + 1).toDouble(), result.schedule[i].balance / 1000),
      ),
    ], extraLen + 1);

    // Y-axis max (in $K)
    final maxBalance = normalSpots.isNotEmpty ? normalSpots.first.y : 1.0;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.show_chart_rounded,
                  size: 18,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  isEs ? 'Saldo en el Tiempo' : 'Balance Over Time',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextSize.body,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            // Legend
            Row(
              children: [
                _LegendDot(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  label: isEs ? 'Normal' : 'Baseline',
                ),
                if (result.monthsSaved > 0) ...[
                  const SizedBox(width: AppSpacing.mdPlus),
                  _LegendDot(
                    color: AppTheme.primary,
                    label: isEs ? 'Con Extra' : 'Accelerated',
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: maxLen.toDouble(),
                  minY: 0,
                  maxY: maxBalance * 1.05,
                  clipData: const FlClipData.all(),
                  lineTouchData: LineTouchData(
                    handleBuiltInTouches: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots
                          .map(
                            (s) => LineTooltipItem(
                              '\$${(s.y).toStringAsFixed(0)}K',
                              const TextStyle(
                                color: Colors.white,
                                fontSize: AppTextSize.xs,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (v) => FlLine(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (v, _) => Text(
                          '\$${v.toStringAsFixed(0)}K',
                          style: TextStyle(
                            fontSize: AppTextSize.xs,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 20,
                        getTitlesWidget: (v, _) {
                          if (v == 0) return const SizedBox.shrink();
                          if (v % 12 == 0) {
                            return Text(
                              '${(v / 12).toInt()}y',
                              style: TextStyle(
                                fontSize: AppTextSize.xs,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.45),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  lineBarsData: [
                    // Baseline (gray, dashed for color-blind accessibility)
                    LineChartBarData(
                      spots: normalSpots,
                      isCurved: true,
                      color: Theme.of(context).colorScheme.outline,
                      barWidth: 2,
                      dashArray: CalcwiseChartTokens.secondarySeriesDash,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                    // Accelerated (primary) — only shown when extra payment is active
                    if (result.monthsSaved > 0)
                      LineChartBarData(
                        spots: extraSpots,
                        isCurved: true,
                        color: AppTheme.primary,
                        barWidth: 2.5,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: AppTheme.primary.withValues(alpha: 0.08),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: AppSpacing.xs),
      Text(
        label,
        style: TextStyle(
          fontSize: AppTextSize.xs,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Biweekly result card
// ---------------------------------------------------------------------------
class _BiweeklyCard extends StatelessWidget {
  final Map<String, double> data;
  final bool isEs;

  const _BiweeklyCard({
    required this.data,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    final biweeklyPayment = data['biweeklyPayment'] ?? 0;
    final totalInterest = data['totalInterest'] ?? 0;
    final monthsSaved = (data['monthsSaved'] ?? 0).toInt();
    final interestSaved = data['interestSaved'] ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.mdPlus,
        horizontal: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.date_range_rounded,
                size: 16,
                color: AppTheme.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                isEs ? 'Modo Quincenal' : 'Biweekly Mode',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextSize.md,
                  color: AppTheme.primaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.smPlus),
          Row(
            children: [
              Expanded(
                child: _BwRow(
                  label: isEs ? 'Pago c/2 semanas' : 'Payment every 2 wks',
                  value: AmountFormatter.ui(biweeklyPayment, 'USD'),
                  color: AppTheme.primary,
                ),
              ),
              Expanded(
                child: _BwRow(
                  label: isEs ? 'Total en interés' : 'Total interest',
                  value: AmountFormatter.ui(totalInterest, 'USD'),
                  color: AppTheme.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: _BwRow(
                  label: isEs ? 'Meses ahorrados' : 'Months saved',
                  value: '${monthsSaved ~/ 12}y ${monthsSaved % 12}m',
                  color: AppTheme.accentGood,
                ),
              ),
              Expanded(
                child: _BwRow(
                  label: isEs ? 'Interés ahorrado' : 'Interest saved',
                  value: AmountFormatter.ui(interestSaved, 'USD'),
                  color: AppTheme.accentGood,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BwRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _BwRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: AppTextSize.xs,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        value,
        style: TextStyle(
          fontSize: AppTextSize.md,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Consolidation Calculator CTA
// ---------------------------------------------------------------------------
class _ConsolidationCta extends StatelessWidget {
  final bool isEs;
  final LoanInput input;
  const _ConsolidationCta({required this.isEs, required this.input});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ConsolidationScreen(
              seedBalance: input.loanAmount,
              seedRate: input.interestRatePct,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.mdPlus,
        ),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(
                Icons.merge_rounded,
                color: AppTheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEs
                        ? 'Consolidación de Deudas'
                        : 'Debt Consolidation',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextSize.body,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    isEs
                        ? 'Combina tus deudas en un solo pago'
                        : 'Combine all your debts into one payment',
                    style: TextStyle(
                      fontSize: AppTextSize.xs,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppTheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Refinance Calculator CTA
// ---------------------------------------------------------------------------
class _RefinanceCta extends StatelessWidget {
  final bool isEs;
  final LoanInput input;
  const _RefinanceCta({required this.isEs, required this.input});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RefinanceScreen(
              seedBalance: input.loanAmount,
              seedRate: input.interestRatePct,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.mdPlus,
        ),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(
                Icons.compare_arrows_rounded,
                color: AppTheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEs
                        ? 'Calculadora de Refinanciamiento'
                        : 'Refinance Calculator',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextSize.body,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    isEs
                        ? 'Compara tu préstamo actual con una nueva tasa'
                        : 'Compare current loan vs new rate — break-even & savings',
                    style: TextStyle(
                      fontSize: AppTextSize.xs,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppTheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
