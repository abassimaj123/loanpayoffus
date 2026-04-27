import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ads/ad_service.dart';
import '../../../core/ads/ad_footer.dart';
import '../../../core/db/database_helper.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/freemium/paywall_service.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../domain/models/loan_input.dart';
import '../../../domain/models/loan_type.dart';
import '../../../domain/usecases/loan_calculator.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../../core/language/language_notifier.dart';
import '../../providers/loan_provider.dart';
import '../../widgets/paywall_soft.dart';
import '../../widgets/paywall_hard.dart';

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
  final _amountCtrl   = TextEditingController(text: '400000');
  final _rateCtrl     = TextEditingController(text: '6.2');
  final _paymentCtrl  = TextEditingController();
  double _extra       = 0;
  double _extraSlider = 0;
  bool   _extraOneTime = false; // toggle: monthly vs one-time extra

  final _fmt = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    isSpanishNotifier.addListener(_onLangChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    AdService.instance.onCalculation();
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
    final gate = await paywallService.recordAction();
    if (!mounted) return;
    if (gate == PaywallGate.hard) {
      await PaywallHard.show(context);
    } else if (gate == PaywallGate.soft) {
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
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? prefix, String? suffix}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(
          labelText: label, prefixText: prefix, suffixText: suffix,
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DropdownButtonFormField<LoanType>(
            value: _type,
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
          _field(s.loanAmount,     _amountCtrl, prefix: '\$'),
          _field(s.interestRate,   _rateCtrl,   suffix: '%'),
          _field(s.monthlyPayment, _paymentCtrl, prefix: '\$'),

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
                      ? Colors.purple.shade100
                      : AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _extraOneTime ? Colors.purple : AppTheme.primary,
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
                    color: _extraOneTime ? Colors.purple : AppTheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _extra > 0 ? AppTheme.accentGood : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _extraOneTime
                    ? _fmt.format(_extra)
                    : '${_fmt.format(_extra)}/mo',
                style: TextStyle(
                  color: _extra > 0 ? Colors.white : Colors.grey.shade600,
                  fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ]),
          Slider(
            value: _extraSlider,
            min: 0, max: _extraOneTime ? 10000 : 1000,
            divisions: 100,
            label: _fmt.format(_extraSlider),
            activeColor: _extraOneTime ? Colors.purple : AppTheme.primary,
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
                color: Colors.grey.shade600,
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
          const SizedBox(height: 80),
        ]),
      )),
      const AdFooter(),
    ]);
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  final Color  color;
  const _InfoCard({required this.title, required this.rows, required this.color});
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
            Text(r.$1, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
            Text(r.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                color: color == Colors.grey.shade600 ? Colors.black87 : color)),
          ]),
        )),
      ]),
    ),
  );
}
