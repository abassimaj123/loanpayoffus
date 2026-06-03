import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../../../core/theme/app_theme.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/language/language_notifier.dart';
import '../../../domain/models/amortization_entry.dart';
import '../../../domain/usecases/loan_calculator.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../../main.dart' show paywallSession;
import '../../providers/loan_provider.dart';

class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});
  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  DateTime? _deadline;
  double? _requiredExtra;

  @override
  void initState() {
    super.initState();
    isSpanishNotifier.addListener(_onLangChange);
    // Session-based gate — tab visible, paywall appears progressively after N sessions
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final trigger = await paywallSession.recordAction();
      if (!mounted || freemiumService.hasFullAccess) return;
      if (trigger == PaywallTrigger.soft)
        PaywallSoft.show(
          context,
          isSpanish: isSpanishNotifier.value,
          onUnlock: () => PaywallHard.show(context),
        );
      if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
    });
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
      firstDate: DateTime.now().add(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 50)),
    );
    if (picked == null) return;
    setState(() => _deadline = picked);
    _calculateRequired();
  }

  void _calculateRequired() {
    if (_deadline == null) return;
    final input = ref.read(loanInputProvider);
    final months = (_deadline!.difference(DateTime.now()).inDays / 30).floor();
    if (months <= 0) return;
    final required = LoanCalculator.requiredExtraForTarget(
      input.loanAmount,
      input.interestRatePct,
      input.monthlyPayment,
      months,
    );
    setState(() => _requiredExtra = required);
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(payoffResultProvider);
    final input = ref.watch(loanInputProvider);
    // Re-run _calculateRequired whenever the loan inputs change while a
    // deadline is already set, so the displayed extra-payment stays current.
    ref.listen(loanInputProvider, (_, __) {
      if (_deadline != null) _calculateRequired();
    });
    final isEs = isSpanishNotifier.value;
    final AppStrings s = isEs ? AppStringsES() : AppStringsEN();

    if (result == null) {
      return Column(
        children: [
          Expanded(child: Center(child: Text(s.enterLoan))),
          const CalcwiseAdFooter(),
        ],
      );
    }

    final currentPayoff = DateTime.now().add(
      Duration(days: result.extraMonths * 30),
    );
    final dateFmt = DateFormat('MMM yyyy');

    // ── Compute balance-based milestone months from the schedule ──────────────
    final loanAmt = input.loanAmount;
    final sched = result.schedule;
    int monthAt(double targetRatio) {
      for (final AmortizationEntry e in sched) {
        if (loanAmt > 0 && e.balance <= loanAmt * targetRatio) return e.month;
      }
      return sched.isNotEmpty ? sched.last.month : result.extraMonths;
    }

    final mo25 = monthAt(0.75); // 25% of balance paid
    final mo50 = monthAt(0.50); // 50% paid
    final mo75 = monthAt(0.25); // 75% paid
    final hasExtra = result.monthsSaved > 0;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Time saved hero (only shown when extra payment is active) ──
                if (hasExtra) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xl,
                      horizontal: AppSpacing.xl,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.xxl),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.rocket_launch_rounded,
                              color: Colors.white70,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isEs
                                  ? 'AHORRAS CON PAGO EXTRA'
                                  : 'YOU SAVE WITH EXTRA PAYMENT',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: AppTextSize.xs,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          '${result.yearsSaved}y ${result.remMonthsSaved}m',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.mdPlus,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(AppRadius.xxl),
                          ),
                          child: Text(
                            '${AmountFormatter.ui(result.interestSaved, 'USD')} ${isEs ? "en interés ahorrado" : "in interest saved"}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: AppTextSize.md,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],

                // Milestones
                Card(
                  color: AppTheme.primary.withValues(alpha: 0.05),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    side: const BorderSide(color: AppTheme.primary, width: 0.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.payoffMilestones,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _Milestone(
                          '${s.paid25}  —  ${isEs ? "mes" : "mo"} $mo25',
                          hasExtra && mo25 < result.normalMonths,
                        ),
                        _Milestone(
                          '${s.paid50}  —  ${isEs ? "mes" : "mo"} $mo50',
                          hasExtra && mo50 < result.normalMonths,
                        ),
                        _Milestone(
                          '${s.paid75}  —  ${isEs ? "mes" : "mo"} $mo75',
                          hasExtra && mo75 < result.normalMonths,
                        ),
                        _Milestone(
                          '${s.paidOff}  —  ${dateFmt.format(currentPayoff)}',
                          hasExtra,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Loan: ${AmountFormatter.ui(loanAmt, 'USD')} @ ${input.interestRatePct}%',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.45),
                            fontSize: AppTextSize.sm,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Current payoff date
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.calendar_today,
                      color: AppTheme.primary,
                    ),
                    title: Text(s.currentPayoffDate),
                    subtitle: Text(
                      '${dateFmt.format(currentPayoff)}  (${result.extraMonths} ${s.months})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Interest saved so far
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.savings,
                      color: AppTheme.accentGood,
                    ),
                    title: Text(s.interestSavedExtra),
                    subtitle: Text(
                      AmountFormatter.ui(result.interestSaved, 'USD'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentGood,
                        fontSize: AppTextSize.subtitle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),

                // Set payoff goal
                Text(
                  s.setPayoffGoal,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextSize.bodyLg,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _deadline == null
                        ? s.chooseTargetDate
                        : '${s.goalPrefix} ${DateFormat('MMM d, yyyy').format(_deadline!)}',
                  ),
                ),
                if (_requiredExtra != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: AppTheme.accentGood.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppTheme.accentGood),
                    ),
                    child: Column(
                      children: [
                        Text(
                          s.extraRequired,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          AmountFormatter.ui(_requiredExtra!, 'USD'),
                          style: const TextStyle(
                            fontSize: AppTextSize.display,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accentGood,
                          ),
                        ),
                        Text(
                          s.perMonth,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.45),
                            fontSize: AppTextSize.md,
                          ),
                        ),
                      ],
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
    );
  }
}

class _Milestone extends StatelessWidget {
  final String label;
  final bool done;
  const _Milestone(this.label, this.done);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          color: done
              ? AppTheme.accentGood
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
          size: 18,
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: TextStyle(
            color: done
                ? AppTheme.accentGood
                : Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
      ],
    ),
  );
}
