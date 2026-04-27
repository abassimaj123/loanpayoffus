import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ads/ad_footer.dart';
import '../../../core/language/language_notifier.dart';
import '../../../domain/usecases/loan_calculator.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../providers/loan_provider.dart';

class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});
  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  DateTime? _deadline;
  double?   _requiredExtra;
  final _fmt = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    isSpanishNotifier.addListener(_onLangChange);
  }

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLangChange);
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 365 * 5)),
      firstDate:   DateTime.now().add(const Duration(days: 30)),
      lastDate:    DateTime.now().add(const Duration(days: 365 * 50)),
    );
    if (picked == null) return;
    setState(() => _deadline = picked);
    _calculateRequired();
  }

  void _calculateRequired() {
    if (_deadline == null) return;
    final input   = ref.read(loanInputProvider);
    final months  = (_deadline!.difference(DateTime.now()).inDays / 30).floor();
    if (months <= 0) return;
    final required = LoanCalculator.requiredExtraForTarget(
      input.loanAmount, input.interestRatePct, input.monthlyPayment, months);
    setState(() => _requiredExtra = required);
  }

  @override
  Widget build(BuildContext context) {
    final result  = ref.watch(payoffResultProvider);
    final input   = ref.watch(loanInputProvider);
    final isEs    = isSpanishNotifier.value;
    final dynamic s = isEs ? AppStringsES() : AppStringsEN();

    if (result == null) {
      return Column(children: [
        Expanded(child: Center(child: Text(s.enterLoan))),
        const AdFooter(),
      ]);
    }

    final currentPayoff = DateTime.now()
        .add(Duration(days: result.extraMonths * 30));

    return Column(children: [
      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Milestones
          Card(
            color: AppTheme.primary.withValues(alpha: 0.05),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppTheme.primary, width: 0.5)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.payoffMilestones,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _Milestone(s.paid25, result.normalMonths > 0 &&
                    result.schedule.length < result.normalMonths * 0.75),
                _Milestone(s.paid50, result.normalMonths > 0 &&
                    result.schedule.length < result.normalMonths * 0.50),
                _Milestone(s.paid75, result.normalMonths > 0 &&
                    result.schedule.length < result.normalMonths * 0.25),
                _Milestone(s.paidOff, false),
                const SizedBox(height: 8),
                Text(
                  'Loan: ${_fmt.format(input.loanAmount)} @ ${input.interestRatePct}%',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Current payoff date
          Card(child: ListTile(
            leading: const Icon(Icons.calendar_today, color: AppTheme.primary),
            title: Text(s.currentPayoffDate),
            subtitle: Text(
              '${currentPayoff.month}/${currentPayoff.year}'
              '  (${result.extraMonths} ${s.months})',
              style: const TextStyle(
                fontWeight: FontWeight.bold, color: AppTheme.primary)),
          )),
          const SizedBox(height: 16),

          // Interest saved so far
          Card(child: ListTile(
            leading: const Icon(Icons.savings, color: AppTheme.accentGood),
            title: Text(s.interestSavedExtra),
            subtitle: Text(
              _fmt.format(result.interestSaved),
              style: const TextStyle(
                fontWeight: FontWeight.bold, color: AppTheme.accentGood,
                fontSize: 18)),
          )),
          const SizedBox(height: 24),

          // Set payoff goal
          Text(s.setPayoffGoal,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.date_range),
            label: Text(_deadline == null
              ? s.chooseTargetDate
              : '${s.goalPrefix} ${_deadline!.month}/${_deadline!.day}/${_deadline!.year}'),
          ),
          if (_requiredExtra != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.accentGood.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.accentGood),
              ),
              child: Column(children: [
                Text(s.extraRequired,
                  style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Text(_fmt.format(_requiredExtra),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
                    color: AppTheme.accentGood)),
                Text(s.perMonth,
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ]),
            ),
          ],
          const SizedBox(height: 80),
        ]),
      )),
      const AdFooter(),
    ]);
  }
}

class _Milestone extends StatelessWidget {
  final String label;
  final bool   done;
  const _Milestone(this.label, this.done);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
        color: done ? AppTheme.accentGood : Colors.grey, size: 18),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(
        color: done ? AppTheme.accentGood : Colors.grey)),
    ]),
  );
}
