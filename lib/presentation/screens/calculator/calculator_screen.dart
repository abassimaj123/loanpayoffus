import 'dart:async';
import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/db/database_helper.dart';
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
import '../../providers/loan_provider.dart';
import '../../widgets/paywall_soft.dart';
import '../../widgets/paywall_hard.dart';
import '../../widgets/insight_card.dart';
import '../../../core/utils/insight_engine.dart';

double _parseNum(String v) {
  if (v.isEmpty) return 0.0;
  final s = (v.contains('.') && v.contains(','))
      ? v.replaceAll(',', '')
      : v.replaceAll(',', '.');
  return double.tryParse(s.trim()) ?? 0.0;
}

class CalculatorScreen extends ConsumerStatefulWidget {
  const CalculatorScreen({super.key});
  @override
  ConsumerState<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends ConsumerState<CalculatorScreen> {
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

  // Biweekly results (computed alongside main calculation)
  Map<String, double>? _biweeklyData;

  final _fmt = NumberFormat.currency(
    locale: 'en_US',
    symbol: '\$',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('calculator');
    isSpanishNotifier.addListener(_onLangChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    });
  }

  @override
  void dispose() {
    _adDebounce?.cancel();
    _saveDebounce?.cancel();
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
    });
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

    // For one-time extra, effective extra = spread across remaining months
    final effectiveExtra = _extraOneTime && _extra > 0 && monthlyPmt > 0
        ? _extra / (amount / monthlyPmt).clamp(1, 600)
        : _extra;

    final input = LoanInput(
      loanType: _type,
      loanAmount: amount,
      interestRatePct: rate,
      monthlyPayment: monthlyPmt,
      extraPayment: effectiveExtra,
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
    _adDebounce = Timer(const Duration(milliseconds: 1500), () {
      adService.onAction();
    });
    // Haptic only fires the first time a result appears (not on every keystroke)
    final currentResult = ref.read(payoffResultProvider);
    if (currentResult != null && !_hadResult) {
      _hadResult = true;
      HapticFeedback.mediumImpact();
    }
    // Save after 2 s of inactivity — prevents flooding history on every keystroke
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 2000), () {
      _saveToHistory(input);
    });

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
      // Emotional trigger: user sees significant savings → ask for review
      if (result.monthsSaved > 12) {
        CalcwiseReviewService.instance.requestAfterPremium();
      }
    }
  }

  Future<void> _saveToHistory(LoanInput input) async {
    if (input.loanAmount <= 0 || input.interestRatePct <= 0) return;
    final count = await DatabaseHelper.instance.countHistory();
    if (!freemiumService.hasFullAccess &&
        count >= freemiumService.historyLimit) {
      if (mounted) {
        AnalyticsService.instance.logPaywallViewed('history_limit');
        PaywallSoft.show(
          context,
          featureTitle: isSpanishNotifier.value
              ? 'Historial ilimitado'
              : 'Unlimited history',
        );
      }
      return;
    }
    final result = ref.read(payoffResultProvider);
    try {
      await DatabaseHelper.instance.insertHistory({
        'loan_type': input.loanType.label,
        'loan_amount': input.loanAmount,
        'interest_rate': input.interestRatePct,
        'monthly_payment': input.monthlyPayment,
        'extra_payment': input.extraPayment,
        'normal_months': result?.normalMonths ?? 0,
        'interest_saved': result?.interestSaved ?? 0,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
    try {
      AnalyticsService.instance.logSave();
    } catch (_) {}
    try {
      AnalyticsService.instance.logResultSaved();
    } catch (_) {}
    adService.onSave();
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
        helperStyle: const TextStyle(fontSize: 10),
        errorText: errorText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.mdPlus,
        ),
      ),
      onChanged: (_) => _recalculate(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(payoffResultProvider);
    final input = ref.watch(loanInputProvider);
    final isEs = isSpanishNotifier.value;
    final AppStrings s = isEs ? AppStringsES() : AppStringsEN();

    // Debt-free date based on extra schedule
    final debtFreeDate = result != null
        ? DateTime.now().add(Duration(days: result.extraMonths * 30))
        : null;
    final debtFreeDateStr = debtFreeDate != null
        ? DateFormat('MMM yyyy').format(debtFreeDate)
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
                  child: CalcwisePageEntrance(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<LoanType>(
                          initialValue: _type,
                          decoration: InputDecoration(
                            labelText: s.loanType,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.mdPlus,
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
                          hint: '15 000',
                          isCurrency: true,
                          errorText:
                              _validated && _parseNum(_amountCtrl.text) <= 0
                              ? 'Required'
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
                              ? 'Required'
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
                              ? 'Invalid'
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
                            fmt: _fmt,
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
                            GestureDetector(
                              onTap: () {
                                setState(() => _extraOneTime = !_extraOneTime);
                                _recalculate();
                              },
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
                                    ? _fmt.format(_extra)
                                    : '${_fmt.format(_extra)}/mo',
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
                                '${_fmt.format(_extraSlider)}${_extraOneTime ? '' : '/mo'}',
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
                                            fontSize: 9,
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
                                    begin: const Offset(0, 0.04),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: result != null
                              ? KeyedSubtree(
                                  key: const ValueKey('results'),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Hero savings card with debt-free date
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: AppSpacing.xxl,
                                          horizontal: AppSpacing.xl,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: result.monthsSaved > 0
                                              ? const LinearGradient(
                                                  colors: [
                                                    CalcwiseSemanticColors
                                                        .successDeep,
                                                    CalcwiseSemanticColors
                                                        .successDark,
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                )
                                              : const LinearGradient(
                                                  colors: [
                                                    AppTheme.primary,
                                                    AppTheme.primaryDark,
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            if (result.monthsSaved > 0) ...[
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  const Icon(
                                                    Icons.savings_rounded,
                                                    color: Colors.white70,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(
                                                    width: AppSpacing.xs,
                                                  ),
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
                                              const SizedBox(
                                                height: AppSpacing.sm,
                                              ),
                                              Text(
                                                _fmt.format(
                                                  result.interestSaved,
                                                ),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: AppTextSize.hero,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: -1.5,
                                                ),
                                              ),
                                              const SizedBox(
                                                height: AppSpacing.xs,
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal:
                                                          AppSpacing.mdPlus,
                                                      vertical: 5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        AppRadius.xxl,
                                                      ),
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
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  const Icon(
                                                    Icons.schedule_rounded,
                                                    color: Colors.white70,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(
                                                    width: AppSpacing.xs,
                                                  ),
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
                                              const SizedBox(
                                                height: AppSpacing.smPlus,
                                              ),
                                              Text(
                                                '${result.normalMonths ~/ 12} yrs ${result.normalMonths % 12} mos',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 30,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                            // ── Debt-free date chip ──
                                            if (debtFreeDateStr.isNotEmpty) ...[
                                              const SizedBox(
                                                height: AppSpacing.smPlus,
                                              ),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  const Icon(
                                                    Icons
                                                        .event_available_rounded,
                                                    color: Colors.white60,
                                                    size: 15,
                                                  ),
                                                  const SizedBox(
                                                    width: AppSpacing.xs,
                                                  ),
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
                                            if (result.interestNormal > 0 &&
                                                input.loanAmount > 0) ...[
                                              const SizedBox(
                                                height: AppSpacing.xs,
                                              ),
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
                                      ),
                                      const SizedBox(height: AppSpacing.lg),

                                      Row(
                                        children: [
                                          Expanded(
                                            child: _InfoCard(
                                              title: s.withoutExtra,
                                              rows: [
                                                (
                                                  s.payoff,
                                                  '${result.normalMonths ~/ 12}y ${result.normalMonths % 12}m',
                                                ),
                                                (
                                                  s.interest,
                                                  _fmt.format(
                                                    result.interestNormal,
                                                  ),
                                                ),
                                                (
                                                  s.totalPaid,
                                                  _fmt.format(
                                                    result.totalPaidNormal,
                                                  ),
                                                ),
                                              ],
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.outline,
                                              isNeutral: true,
                                            ),
                                          ),
                                          const SizedBox(width: AppSpacing.md),
                                          if (input.extraPayment > 0)
                                            Expanded(
                                              child: _InfoCard(
                                                title: _extraOneTime
                                                    ? '${_fmt.format(_extra)} ${isEs ? "único" : "one-time"}'
                                                    : '+${_fmt.format(_extra)}/mo',
                                                rows: [
                                                  (
                                                    s.payoff,
                                                    '${result.extraMonths ~/ 12}y ${result.extraMonths % 12}m',
                                                  ),
                                                  (
                                                    s.interest,
                                                    _fmt.format(
                                                      result.interestExtra,
                                                    ),
                                                  ),
                                                  (
                                                    s.totalPaid,
                                                    _fmt.format(
                                                      result.totalPaidExtra,
                                                    ),
                                                  ),
                                                ],
                                                color: AppTheme.accentGood,
                                              ),
                                            ),
                                        ],
                                      ),
                                      // ── Debt-Free Date Banner ──
                                      if (result.monthsSaved > 0) ...[
                                        const SizedBox(height: AppSpacing.lg),
                                        _DebtFreeDateBanner(
                                          result: result,
                                          isEs: isEs,
                                          fmt: _fmt,
                                        ),
                                      ],

                                      // ── Balance Over Time chart ──
                                      ...[
                                        const SizedBox(height: AppSpacing.lg),
                                        _BalanceChart(
                                          result: result,
                                          isEs: isEs,
                                        ),
                                      ],

                                      // ── Smart Insights ──
                                      ...[
                                        const SizedBox(height: AppSpacing.lg),
                                        InsightCard(
                                          isSpanish: isEs,
                                          insights: InsightEngine.generate(
                                            balance: input.loanAmount,
                                            annualRatePct:
                                                input.interestRatePct,
                                            monthlyPayment:
                                                input.monthlyPayment,
                                            monthsToPayoff: result.normalMonths,
                                            totalInterest:
                                                result.interestNormal,
                                            extraMonthlyPayment:
                                                input.extraPayment > 0
                                                ? input.extraPayment
                                                : null,
                                            monthsSavedWithExtra:
                                                input.extraPayment > 0
                                                ? result.monthsSaved
                                                : null,
                                            interestSavedWithExtra:
                                                input.extraPayment > 0
                                                ? result.interestSaved
                                                : null,
                                            isEs: isEs,
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.sm),
                                        Text(
                                          isEs
                                              ? 'Solo para fines informativos. No es asesoramiento financiero.'
                                              : 'For informational purposes only. Not financial advice.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.45),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                )
                              : Padding(
                                  key: const ValueKey('empty'),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.xxxl,
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.account_balance_rounded,
                                        size: 48,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.3),
                                      ),
                                      const SizedBox(height: AppSpacing.md),
                                      Text(
                                        isEs
                                            ? 'Ingresa los valores para ver los resultados'
                                            : 'Enter values above to see results',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: AppTextSize.body,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ), // CalcwisePageEntrance closes
                ),
              ),
            ),
          ),
          const CalcwiseAdFooter(),
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
                  Text(
                    r.$1,
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.55),
                      fontSize: AppTextSize.xs,
                    ),
                  ),
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
  final NumberFormat fmt;

  const _DebtFreeDateBanner({
    required this.result,
    required this.isEs,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final debtFreeDate = DateTime.now().add(
      Duration(days: result.extraMonths * 30),
    );
    final dateStr = DateFormat('MMMM yyyy').format(debtFreeDate);
    final yrs = result.monthsSaved ~/ 12;
    final mos = result.monthsSaved % 12;
    final soonerLabel = isEs
        ? '${yrs > 0 ? "${yrs}a " : ""}${mos}m antes — ahorras ${fmt.format(result.interestSaved)}'
        : '${yrs > 0 ? "${yrs}y " : ""}${mos}m sooner — save ${fmt.format(result.interestSaved)}';
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
        border: Border(
          left: BorderSide(color: AppTheme.primary, width: 3),
          top: BorderSide(
            color: AppTheme.primary.withValues(alpha: 0.2),
            width: 1,
          ),
          right: BorderSide(
            color: AppTheme.primary.withValues(alpha: 0.2),
            width: 1,
          ),
          bottom: BorderSide(
            color: AppTheme.primary.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const Text('🎯', style: TextStyle(fontSize: AppTextSize.titleMd)),
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
                  color: const Color(0xFF64748B),
                  label: isEs ? 'Normal' : 'Baseline',
                ),
                const SizedBox(width: AppSpacing.mdPlus),
                _LegendDot(
                  color: AppTheme.primary,
                  label: isEs ? 'Con Extra' : 'Accelerated',
                ),
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
                            fontSize: 9,
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
                                fontSize: 9,
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
                    // Baseline (gray)
                    LineChartBarData(
                      spots: normalSpots,
                      isCurved: true,
                      color: const Color(0xFF94A3B8),
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                    // Accelerated (primary)
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
  final NumberFormat fmt;
  final bool isEs;

  const _BiweeklyCard({
    required this.data,
    required this.fmt,
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
                  value: fmt.format(biweeklyPayment),
                  color: AppTheme.primary,
                ),
              ),
              Expanded(
                child: _BwRow(
                  label: isEs ? 'Total en interés' : 'Total interest',
                  value: fmt.format(totalInterest),
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
                  value: fmt.format(interestSaved),
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
          fontSize: 10,
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
