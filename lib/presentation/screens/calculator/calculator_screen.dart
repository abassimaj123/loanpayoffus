import 'dart:async';
import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ads/ad_service.dart';
import '../../../core/ads/ad_footer.dart';
import '../../../core/db/database_helper.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../main.dart' show paywallSession;
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
import '../../../core/review/review_service.dart';
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
  LoanType _type      = LoanType.mortgage;
  final _amountCtrl   = TextEditingController(text: '15000');
  final _rateCtrl     = TextEditingController(text: '5.5');
  final _paymentCtrl  = TextEditingController(text: '300');
  Timer? _adDebounce;
  double _extra       = 0;
  double _extraSlider = 0;
  bool   _extraOneTime  = false; // toggle: monthly vs one-time extra
  bool   _biweekly      = false; // toggle: monthly vs biweekly mode

  // Biweekly results (computed alongside main calculation)
  Map<String, double>? _biweeklyData;

  final _fmt = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    isSpanishNotifier.addListener(_onLangChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // _paymentCtrl is pre-filled with '300', only auto-compute if still empty
      if (mounted && _paymentCtrl.text.isEmpty) {
        final amount = _parseNum(_amountCtrl.text);
        final rate   = _parseNum(_rateCtrl.text);
        _paymentCtrl.text =
            LoanCalculator.computeMonthlyPayment(amount, rate, _type.defaultTermMonths)
                .toStringAsFixed(2);
      }
    });
  }

  @override
  void dispose() {
    _adDebounce?.cancel();
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
      _rateCtrl.text   = t.defaultRate.toString();
      _paymentCtrl.clear();
    });
    _recalculate();
  }

  Future<void> _recalculate() async {
    final amount   = _parseNum(_amountCtrl.text);
    final rate     = _parseNum(_rateCtrl.text);
    final computed = LoanCalculator.computeMonthlyPayment(
        amount, rate, _type.defaultTermMonths);
    final payment = double.tryParse(
        (_paymentCtrl.text.contains('.') && _paymentCtrl.text.contains(','))
            ? _paymentCtrl.text.replaceAll(',', '')
            : _paymentCtrl.text.replaceAll(',', '.'));
    final monthlyPmt = (payment != null && payment > 0) ? payment : computed;

    // For one-time extra, effective extra = spread across remaining months
    final effectiveExtra = _extraOneTime && _extra > 0 && monthlyPmt > 0
        ? _extra / (amount / monthlyPmt).clamp(1, 600)
        : _extra;

    final input = LoanInput(
      loanType:        _type,
      loanAmount:      amount,
      interestRatePct: rate,
      monthlyPayment:  monthlyPmt,
      extraPayment:    effectiveExtra,
    );
    ref.read(loanInputProvider.notifier).update(input);

    // Compute biweekly data whenever amount/rate/term are valid
    if (amount > 0 && rate > 0) {
      setState(() {
        _biweeklyData = LoanCalculator.calculateBiweekly(
            amount, rate, _type.defaultTermMonths);
      });
    }

    _adDebounce?.cancel();
    _adDebounce = Timer(const Duration(milliseconds: 1500), () {
      AdService.instance.onCalculation();
    });
    HapticFeedback.mediumImpact();
    _saveToHistory(input);

    // Analytics + paywall gate
    final result = ref.read(payoffResultProvider);
    if (result != null && amount > 0 && rate > 0) {
      AnalyticsService.instance.logCalculation(
        loanType:      _type.label,
        loanAmount:    amount,
        interestRate:  rate,
        extraPayment:  _extra,
        monthsSaved:   result.monthsSaved,
        interestSaved: result.interestSaved,
      );
    }
    final gate = await paywallSession.recordAction();
    if (!mounted) return;
    if (gate == PaywallTrigger.hard) {
      await PaywallHard.show(context);
    } else if (gate == PaywallTrigger.soft) {
      await PaywallSoft.show(context);
    }
  }

  Future<void> _saveToHistory(LoanInput input) async {
    if (input.loanAmount <= 0 || input.interestRatePct <= 0) return;
    final count = await DatabaseHelper.instance.countHistory();
    if (!freemiumService.isPremium && count >= freemiumService.historyLimit) return;
    final result = ref.read(payoffResultProvider);
    await DatabaseHelper.instance.insertHistory({
      'loan_type':       input.loanType.label,
      'loan_amount':     input.loanAmount,
      'interest_rate':   input.interestRatePct,
      'monthly_payment': input.monthlyPayment,
      'extra_payment':   input.extraPayment,
      'normal_months':   result?.normalMonths ?? 0,
      'interest_saved':  result?.interestSaved ?? 0,
      'created_at':      DateTime.now().toIso8601String(),
    });
    try { AnalyticsService.instance.logSave(); } catch (_) {}
    ReviewService.instance.requestAfterSave();
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? prefix, String? suffix, String hint = ''}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(
          labelText: label, prefixText: prefix, suffixText: suffix,
          hintText: hint.isEmpty ? null : hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onChanged: (_) => _recalculate(),
      ),
    );

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(payoffResultProvider);
    final input  = ref.watch(loanInputProvider);
    final isEs   = isSpanishNotifier.value;
    final dynamic s = isEs ? AppStringsES() : AppStringsEN();

    // Debt-free date based on extra schedule
    final debtFreeDate = result != null
        ? DateTime.now().add(Duration(days: result.extraMonths * 30))
        : null;
    final debtFreeDateStr = debtFreeDate != null
        ? DateFormat('MMM yyyy').format(debtFreeDate)
        : '';

    return Column(children: [
      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: CalcwisePageEntrance(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DropdownButtonFormField<LoanType>(
            initialValue: _type,
            decoration: InputDecoration(
              labelText: s.loanType,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            items: LoanType.values.map((t) =>
              DropdownMenuItem(value: t, child: Text(t.label))).toList(),
            onChanged: _onTypeChanged,
          ),
          const SizedBox(height: 12),
          _field(s.loanAmount,     _amountCtrl,  prefix: '\$', hint: '15 000'),
          _field(s.interestRate,   _rateCtrl,    suffix: '%',  hint: '5.5'),
          _field(s.monthlyPayment, _paymentCtrl, prefix: '\$', hint: '300'),

          // ── Monthly / Biweekly toggle ──
          const SizedBox(height: 4),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                label: Text(isEs ? 'Mensual' : 'Monthly'),
                icon: const Icon(Icons.calendar_month_outlined, size: 16),
              ),
              ButtonSegment(
                value: true,
                label: Text(isEs ? 'Quincenal' : 'Biweekly'),
                icon: const Icon(Icons.date_range_outlined, size: 16),
              ),
            ],
            selected: {_biweekly},
            onSelectionChanged: (v) {
              setState(() => _biweekly = v.first);
              _recalculate();
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppTheme.primary;
                }
                return null;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return null;
              }),
            ),
          ),

          // ── Biweekly result card ──
          if (_biweekly && _biweeklyData != null) ...[
            const SizedBox(height: 12),
            _BiweeklyCard(data: _biweeklyData!, fmt: _fmt, isEs: isEs),
          ],

          const SizedBox(height: 8),
          // ── Extra payment row with monthly/one-time toggle ──
          Row(children: [
            const Icon(Icons.add_circle_outline, size: 18, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(s.extraPayment,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15,
                  color: AppTheme.primaryDark)),
            const Spacer(),
            // One-time / Monthly toggle
            GestureDetector(
              onTap: () {
                setState(() => _extraOneTime = !_extraOneTime);
                _recalculate();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _extraOneTime
                      ? AppTheme.neutral
                      : AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
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
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _extra > 0
                    ? AppTheme.accentGood
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _extraOneTime
                    ? _fmt.format(_extra)
                    : '${_fmt.format(_extra)}/mo',
                style: TextStyle(
                  color: _extra > 0
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ]),
          Slider(
            value: _extraSlider,
            min: 0, max: _extraOneTime ? 10000 : 1000,
            divisions: 100,
            label: _fmt.format(_extraSlider),
            activeColor: AppTheme.primary,
            onChanged: (v) {
              setState(() { _extra = v; _extraSlider = v; });
              _recalculate();
            },
          ),

          const SizedBox(height: 16),
          if (result != null) ...[
            // Hero savings card with debt-free date
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Column(children: [
                if (result.monthsSaved > 0) ...[
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.savings_rounded, color: Colors.white70, size: 18),
                    const SizedBox(width: 6),
                    Text(s.youCouldSave,
                      style: const TextStyle(color: Colors.white70, fontSize: 13,
                          letterSpacing: 1.2)),
                  ]),
                  const SizedBox(height: 8),
                  Text(_fmt.format(result.interestSaved),
                    style: const TextStyle(color: Colors.white, fontSize: 36,
                        fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${s.inInterest}  •  ${result.yearsSaved}y ${result.remMonthsSaved}m ${s.faster}',
                      style: const TextStyle(color: Colors.white, fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  ),
                ] else ...[
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.schedule_rounded, color: Colors.white70, size: 18),
                    const SizedBox(width: 6),
                    Text(s.payoffTimeline,
                      style: const TextStyle(color: Colors.white70, fontSize: 13,
                          letterSpacing: 1.2)),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                    '${result.normalMonths ~/ 12} yrs ${result.normalMonths % 12} mos',
                    style: const TextStyle(color: Colors.white, fontSize: 30,
                        fontWeight: FontWeight.bold)),
                ],
                // ── Debt-free date chip ──
                if (debtFreeDateStr.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.event_available_rounded, color: Colors.white60, size: 15),
                    const SizedBox(width: 5),
                    Text(
                      '${s.debtFreeDate}: $debtFreeDateStr',
                      style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  ]),
                ],
                // ── Interest-to-loan ratio insight ──
                if (result.interestNormal > 0 && input.loanAmount > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${isEs ? "Pagas" : "You pay"} ${((result.interestNormal / input.loanAmount) * 100).toStringAsFixed(0)}% '
                    '${isEs ? "del préstamo en intereses" : "of loan amount in interest"}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 16),

            Row(children: [
              Expanded(child: _InfoCard(
                title: s.withoutExtra,
                rows: [
                  (s.payoff,    '${result.normalMonths ~/ 12}y ${result.normalMonths % 12}m'),
                  (s.interest,  _fmt.format(result.interestNormal)),
                  (s.totalPaid, _fmt.format(result.totalPaidNormal)),
                ],
                color: Theme.of(context).colorScheme.outline,
                isNeutral: true,
              )),
              const SizedBox(width: 12),
              if (input.extraPayment > 0)
                Expanded(child: _InfoCard(
                  title: _extraOneTime
                      ? '${_fmt.format(_extra)} ${isEs ? "único" : "one-time"}'
                      : '+${_fmt.format(_extra)}/mo',
                  rows: [
                    (s.payoff,    '${result.extraMonths ~/ 12}y ${result.extraMonths % 12}m'),
                    (s.interest,  _fmt.format(result.interestExtra)),
                    (s.totalPaid, _fmt.format(result.totalPaidExtra)),
                  ],
                  color: AppTheme.accentGood,
                )),
            ]),
          ],
          // ── Balance Over Time chart ──
          if (result != null) ...[
            const SizedBox(height: 16),
            _BalanceChart(result: result, isEs: isEs),
          ],

          // ── Smart Insights ──
          if (result != null) ...[
            const SizedBox(height: 16),
            InsightCard(
              isSpanish: isEs,
              insights: InsightEngine.generate(
                balance:               input.loanAmount,
                annualRatePct:         input.interestRatePct,
                monthlyPayment:        input.monthlyPayment,
                monthsToPayoff:        result.normalMonths,
                totalInterest:         result.interestNormal,
                extraMonthlyPayment:   input.extraPayment > 0 ? input.extraPayment : null,
                monthsSavedWithExtra:  input.extraPayment > 0 ? result.monthsSaved : null,
                interestSavedWithExtra: input.extraPayment > 0 ? result.interestSaved : null,
                isEs: isEs,
              ),
            ),
          ],

          const SizedBox(height: 80),
        ])),  // CalcwisePageEntrance closes
          ),
        ),
      )),
      const AdFooter(),
    ]);
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  final Color  color;
  final bool   isNeutral;
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
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: color.withValues(alpha: 0.4), width: 1.5),
    ),
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(title,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11,
                letterSpacing: 0.5)),
        ),
        const SizedBox(height: 10),
        ...rows.map((r) => Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(r.$1, style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                fontSize: 11)),
            Text(r.$2, style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isNeutral
                    ? Theme.of(context).colorScheme.onSurface
                    : color)),
          ]),
        )),
      ]),
    ),
  );
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
    // Sample every N months to keep data points manageable
    const maxPoints = 60;
    final normalLen = result.normalSchedule.length;
    final extraLen  = result.schedule.length;
    final maxLen    = normalLen > extraLen ? normalLen : extraLen;
    final step      = (maxLen / maxPoints).ceil().clamp(1, maxLen);

    List<FlSpot> sampleSpots(List spots, int len) {
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

    final normalSpots = sampleSpots(
      [
        FlSpot(0, result.normalSchedule.isNotEmpty
            ? (result.normalSchedule.first.balance +
                   result.normalSchedule.first.principal) /
                1000
            : 0),
        ...List.generate(normalLen,
            (i) => FlSpot((i + 1).toDouble(),
                result.normalSchedule[i].balance / 1000)),
      ],
      normalLen + 1,
    );

    final extraSpots = sampleSpots(
      [
        FlSpot(0, result.schedule.isNotEmpty
            ? (result.schedule.first.balance +
                   result.schedule.first.principal) /
                1000
            : 0),
        ...List.generate(extraLen,
            (i) => FlSpot((i + 1).toDouble(),
                result.schedule[i].balance / 1000)),
      ],
      extraLen + 1,
    );

    // Y-axis max (in $K)
    final maxBalance = normalSpots.isNotEmpty ? normalSpots.first.y : 1.0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.show_chart_rounded, size: 18, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text(
              isEs ? 'Saldo en el Tiempo' : 'Balance Over Time',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.primary),
            ),
          ]),
          const SizedBox(height: 6),
          // Legend
          Row(children: [
            _LegendDot(color: const Color(0xFF64748B),
                label: isEs ? 'Normal' : 'Baseline'),
            const SizedBox(width: 14),
            _LegendDot(color: AppTheme.primary,
                label: isEs ? 'Con Extra' : 'Accelerated'),
          ]),
          const SizedBox(height: 12),
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
                    getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                      '\$${(s.y).toStringAsFixed(0)}K',
                      const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    )).toList(),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
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
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
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
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
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
        ]),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color  color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
        ],
      );
}

// ---------------------------------------------------------------------------
// Biweekly result card
// ---------------------------------------------------------------------------
class _BiweeklyCard extends StatelessWidget {
  final Map<String, double> data;
  final NumberFormat        fmt;
  final bool                isEs;

  const _BiweeklyCard({
    required this.data,
    required this.fmt,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    final biweeklyPayment = data['biweeklyPayment'] ?? 0;
    final totalInterest   = data['totalInterest']   ?? 0;
    final monthsSaved     = (data['monthsSaved']    ?? 0).toInt();
    final interestSaved   = data['interestSaved']   ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppTheme.primary.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.date_range_outlined, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(
            isEs ? 'Modo Quincenal' : 'Biweekly Mode',
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppTheme.primaryDark),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
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
        ]),
        const SizedBox(height: 6),
        Row(children: [
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
        ]),
      ]),
    );
  }
}

class _BwRow extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _BwRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      );
}
