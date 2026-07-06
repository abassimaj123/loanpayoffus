import 'dart:isolate';
import 'dart:typed_data';

import 'package:intl/date_symbol_data_local.dart';
import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard;
import '../../../core/firebase/analytics_service.dart';
import '../../../core/services/pdf_export_service.dart' show PdfExportService;
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../main.dart' show paywallSession, smartHistoryService, historyRefreshNotifier, adService;
import '../../../core/language/language_notifier.dart';
import '../../../domain/models/amortization_entry.dart';
import '../../../domain/models/payoff_result.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../../domain/models/loan_input.dart';
import '../../providers/loan_provider.dart';
import '../../widgets/paywall_soft.dart';
import '../../widgets/paywall_hard.dart';
import '../../widgets/save_scenario_button.dart';
import '../../widgets/streak_card.dart';
import '../../widgets/next_victory_card.dart';
import '../../../core/db/debt_persistence.dart';
import '../../../core/services/streak_service.dart';
import '../../../domain/models/debt_item.dart';

/// Debt-free date [months] from today using real calendar months
/// (not a 30-day approximation, which drifts ~6 days/year).
DateTime _debtFreeDate(int months) {
  final now = DateTime.now();
  return DateTime(now.year, now.month + months, now.day);
}

// ── Payoff Plan PDF isolate support ─────────────────────────────────────────

class _AmortizationRow {
  final int month;
  final double payment;
  final double principal;
  final double interest;
  final double balance;
  const _AmortizationRow(this.month, this.payment, this.principal, this.interest, this.balance);
}

class _PayoffPlanPdfParams {
  // Summary data
  final int normalMonths;
  final int extraMonths;
  final int monthsSaved;
  final double interestNormal;
  final double interestExtra;
  final double interestSaved;
  final double totalPaidNormal;
  final double totalPaidExtra;
  // Amortization schedule (serialised)
  final List<_AmortizationRow> schedule;
  // Localised strings (resolved on main isolate)
  final String labelNavPayoffPlan;
  final String labelWithoutExtra;
  final String labelPayoff;
  final String labelInterest;
  final String labelTotalPaid;
  final String labelWithExtraLabel;
  final String labelSaved;
  final String labelSchedule;
  final String labelPayment;
  final String labelPrincipal;
  final String labelBalance;
  final String labelDisclaimer;
  final String labelCalculatedWith;
  final String labelPdfExportedSuccess;
  // Timestamp
  final int nowYear;
  final int nowMonth;
  final int nowDay;

  const _PayoffPlanPdfParams({
    required this.normalMonths,
    required this.extraMonths,
    required this.monthsSaved,
    required this.interestNormal,
    required this.interestExtra,
    required this.interestSaved,
    required this.totalPaidNormal,
    required this.totalPaidExtra,
    required this.schedule,
    required this.labelNavPayoffPlan,
    required this.labelWithoutExtra,
    required this.labelPayoff,
    required this.labelInterest,
    required this.labelTotalPaid,
    required this.labelWithExtraLabel,
    required this.labelSaved,
    required this.labelSchedule,
    required this.labelPayment,
    required this.labelPrincipal,
    required this.labelBalance,
    required this.labelDisclaimer,
    required this.labelCalculatedWith,
    required this.labelPdfExportedSuccess,
    required this.nowYear,
    required this.nowMonth,
    required this.nowDay,
  });
}

pw.Widget _payoffPdfSummaryRow(String label, String value, {bool highlight = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: highlight ? PdfColors.blue800 : PdfColors.black,
            ),
          ),
        ],
      ),
    );

pw.Widget _payoffPdfCell(String text, {bool header = false, bool bold = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.right,
        style: pw.TextStyle(
          fontSize: header ? 9 : 8,
          fontWeight: (header || bold) ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );

Future<Uint8List> _buildPayoffPlanPdf(_PayoffPlanPdfParams p) async {
  await initializeDateFormatting();
  final now = DateTime(p.nowYear, p.nowMonth, p.nowDay);
  final pdf = pw.Document();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(AppSpacing.xxxl),
      header: (_) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Loan Payoff US — ${p.labelNavPayoffPlan}',
            style: pw.TextStyle(fontSize: AppTextSize.body, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            DateFormat.yMMMMd().format(now),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Text(
            '${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
      build: (_) => [
        pw.SizedBox(height: 8),
        pw.Container(
          decoration: pw.BoxDecoration(
            color: PdfColors.blueGrey50,
            borderRadius: pw.BorderRadius.circular(AppRadius.xs),
          ),
          padding: const pw.EdgeInsets.all(AppSpacing.md),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                p.labelWithoutExtra,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: AppTextSize.sm),
              ),
              pw.SizedBox(height: 6),
              _payoffPdfSummaryRow(p.labelPayoff, '${p.normalMonths ~/ 12}y ${p.normalMonths % 12}m'),
              _payoffPdfSummaryRow(p.labelInterest, AmountFormatter.ui(p.interestNormal, 'USD')),
              _payoffPdfSummaryRow(p.labelTotalPaid, AmountFormatter.ui(p.totalPaidNormal, 'USD')),
              if (p.monthsSaved > 0) ...[
                pw.Divider(color: PdfColors.grey400),
                pw.Text(
                  p.labelWithExtraLabel,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: AppTextSize.sm),
                ),
                pw.SizedBox(height: 6),
                _payoffPdfSummaryRow(p.labelPayoff, '${p.extraMonths ~/ 12}y ${p.extraMonths % 12}m'),
                _payoffPdfSummaryRow(p.labelInterest, AmountFormatter.ui(p.interestExtra, 'USD')),
                _payoffPdfSummaryRow(p.labelTotalPaid, AmountFormatter.ui(p.totalPaidExtra, 'USD')),
                _payoffPdfSummaryRow(p.labelSaved, AmountFormatter.ui(p.interestSaved, 'USD'), highlight: true),
              ],
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          '${p.labelNavPayoffPlan} — ${p.labelSchedule}',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: AppTextSize.sm),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(2.2),
            2: pw.FlexColumnWidth(2.2),
            3: pw.FlexColumnWidth(2.2),
            4: pw.FlexColumnWidth(2.2),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
              children: [
                '#',
                p.labelPayment,
                p.labelPrincipal,
                p.labelInterest,
                p.labelBalance,
              ].map((h) => _payoffPdfCell(h, header: true)).toList(),
            ),
            ...p.schedule.asMap().entries.map((entry) {
              final i = entry.key;
              final r = entry.value;
              final bg = i.isEven ? PdfColors.white : PdfColors.grey50;
              return pw.TableRow(
                decoration: pw.BoxDecoration(color: bg),
                children: [
                  _payoffPdfCell('${r.month}'),
                  _payoffPdfCell(AmountFormatter.ui(r.payment, 'USD')),
                  _payoffPdfCell(AmountFormatter.ui(r.principal, 'USD')),
                  _payoffPdfCell(AmountFormatter.ui(r.interest, 'USD')),
                  _payoffPdfCell(AmountFormatter.ui(r.balance, 'USD'), bold: r.balance < 0.01),
                ],
              );
            }),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Divider(),
        pw.SizedBox(height: 6),
        pw.Text(p.labelDisclaimer, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        pw.Text(p.labelCalculatedWith, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
      ],
    ),
  );
  return pdf.save();
}

// ────────────────────────────────────────────────────────────────────────────

class PayoffPlanScreen extends ConsumerStatefulWidget {
  const PayoffPlanScreen({super.key});

  @override
  ConsumerState<PayoffPlanScreen> createState() => _PayoffPlanScreenState();
}

class _PayoffPlanScreenState extends ConsumerState<PayoffPlanScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('payoff_plan');
    isSpanishNotifier.addListener(_onLangChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final result = ref.read(payoffResultProvider);
      final input = ref.read(loanInputProvider);
      if (result != null) _scheduleAutoSave(result, input);
    });
  }

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLangChange);
    smartHistoryService.cancelPendingSave('loanpayoffus', 'payoff_plan');
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  double _roundTo(double v, double step) => (v / step).round() * step;

  void _scheduleAutoSave(PayoffResult result, LoanInput input) {
    final payoffDate = _debtFreeDate(result.extraMonths);
    final hash = ResultHasher.hashMixed({
      'loan_amount': _roundTo(input.loanAmount, 1000),
      'interest_rate': _roundTo(input.interestRatePct, 0.25),
      'monthly_payment': _roundTo(input.monthlyPayment, 10),
      'extra_payment': _roundTo(input.extraPayment, 50),
    });
    final l1 = <String, dynamic>{
      'payoff_months': result.extraMonths,
      'payoff_date': DateFormat('MMM yyyy', isSpanishNotifier.value ? 'es' : 'en').format(payoffDate),
      'total_interest': result.interestExtra.toStringAsFixed(0),
      'monthly_payment': input.monthlyPayment.toStringAsFixed(2),
      'extra_payment': input.extraPayment.toStringAsFixed(2),
    };
    final l2 = <String, dynamic>{
      'inputs': {
        'loan_amount': input.loanAmount,
        'interest_rate_pct': input.interestRatePct,
        'monthly_payment': input.monthlyPayment,
        'extra_payment': input.extraPayment,
      },
      'results': {
        'payoff_date': payoffDate.toIso8601String(),
        'total_interest': result.interestExtra,
        'monthly_payment': input.monthlyPayment,
        'extra_payment': input.extraPayment,
        'months_saved': result.monthsSaved,
        'interest_saved': result.interestSaved,
      },
    };
    smartHistoryService.scheduleAutoSave(
      appKey: 'loanpayoffus',
      screenId: 'payoff_plan',
      inputHash: hash,
      l1: l1,
      l2: l2,
    );
  }

  Future<void> _saveScenario(String? label) async {
    final result = ref.read(payoffResultProvider);
    final input = ref.read(loanInputProvider);
    if (result == null) return;
    HapticFeedback.mediumImpact();

    final hash = ResultHasher.hashMixed({
      'loan_amount': _roundTo(input.loanAmount, 1000),
      'interest_rate': _roundTo(input.interestRatePct, 0.25),
      'monthly_payment': _roundTo(input.monthlyPayment, 10),
      'extra_payment': _roundTo(input.extraPayment, 50),
    });

    final payoffDate = _debtFreeDate(result.extraMonths);

    final l1 = <String, dynamic>{
      'payoff_months': result.extraMonths,
      'payoff_date': DateFormat('MMM yyyy', isSpanishNotifier.value ? 'es' : 'en').format(payoffDate),
      'total_interest': result.interestExtra.toStringAsFixed(0),
      'monthly_payment': input.monthlyPayment.toStringAsFixed(2),
      'extra_payment': input.extraPayment.toStringAsFixed(2),
    };

    final l2 = <String, dynamic>{
      'inputs': {
        'loan_amount': input.loanAmount,
        'interest_rate_pct': input.interestRatePct,
        'monthly_payment': input.monthlyPayment,
        'extra_payment': input.extraPayment,
      },
      'results': {
        'payoff_date': payoffDate.toIso8601String(),
        'total_interest': result.interestExtra,
        'monthly_payment': input.monthlyPayment,
        'extra_payment': input.extraPayment,
        'months_saved': result.monthsSaved,
        'interest_saved': result.interestSaved,
      },
    };

    await smartHistoryService.saveScenario(
      appKey: 'loanpayoffus',
      screenId: 'payoff_plan',
      inputHash: hash,
      l1: l1,
      l2: l2,
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
    final trigger = await paywallSession.recordAction();
    if (!mounted) return;
    if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
    if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
  }

  Future<void> _share(
    BuildContext context,
    PayoffResult result,
    bool isEs,
  ) async {
    HapticFeedback.mediumImpact();
    final AppStrings s = isEs ? AppStringsES() : AppStringsEN();
    const sep = '─────────────────────';
    final buf = StringBuffer();
    buf.writeln('Loan Payoff US — ${s.navPayoffPlan}');
    buf.writeln(sep);
    buf.writeln(s.withoutExtra);
    buf.writeln(
      '${s.payoff}: ${result.normalMonths ~/ 12}y ${result.normalMonths % 12}m',
    );
    buf.writeln('${s.interest}: ${AmountFormatter.ui(result.interestNormal, 'USD')}');
    buf.writeln('${s.totalPaid}: ${AmountFormatter.ui(result.totalPaidNormal, 'USD')}');
    if (result.monthsSaved > 0) {
      buf.writeln(sep);
      buf.writeln(s.withExtraLabel);
      buf.writeln(
        '${s.payoff}: ${result.extraMonths ~/ 12}y ${result.extraMonths % 12}m',
      );
      buf.writeln('${s.interest}: ${AmountFormatter.ui(result.interestExtra, 'USD')}');
      buf.writeln('${s.totalPaid}: ${AmountFormatter.ui(result.totalPaidExtra, 'USD')}');
      buf.writeln('${s.saved}: ${AmountFormatter.ui(result.interestSaved, 'USD')}');
    }
    buf.writeln(sep);
    buf.writeln(s.calculatedWith);
    buf.write(isEs
        ? '\n📄 Exporta el reporte completo en PDF →'
        : '\n📄 Export the full PDF report in the app →');

    try {
      await Share.share(
        buf.toString(),
        subject: isEs
            ? 'Loan Payoff US — Plan de pago'
            : 'Loan Payoff US — Payoff Plan',
      );
    } catch (_) {}
  }

  Future<void> _exportPdf(
    BuildContext context,
    PayoffResult result,
    bool isEs,
  ) async {
    HapticFeedback.mediumImpact();
    final AppStrings s = isEs ? AppStringsES() : AppStringsEN();

    if (!freemiumService.hasFullAccess) {
      await PdfExportService.showUnlockOrPay(
        context,
        () => _doExportPdf(context, result, isEs),
      );
      return;
    }

    await _doExportPdf(context, result, isEs);
  }

  Future<void> _doExportPdf(
    BuildContext context,
    PayoffResult result,
    bool isEs,
  ) async {
    final AppStrings s = isEs ? AppStringsES() : AppStringsEN();
    final now = DateTime.now();

    // Resolve all data on main isolate before spawning
    final params = _PayoffPlanPdfParams(
      normalMonths: result.normalMonths,
      extraMonths: result.extraMonths,
      monthsSaved: result.monthsSaved,
      interestNormal: result.interestNormal,
      interestExtra: result.interestExtra,
      interestSaved: result.interestSaved,
      totalPaidNormal: result.totalPaidNormal,
      totalPaidExtra: result.totalPaidExtra,
      schedule: result.schedule
          .map((r) => _AmortizationRow(r.month, r.payment, r.principal, r.interest, r.balance))
          .toList(),
      labelNavPayoffPlan: s.navPayoffPlan,
      labelWithoutExtra: s.withoutExtra,
      labelPayoff: s.payoff,
      labelInterest: s.interest,
      labelTotalPaid: s.totalPaid,
      labelWithExtraLabel: s.withExtraLabel,
      labelSaved: s.saved,
      labelSchedule: s.schedule,
      labelPayment: s.payment,
      labelPrincipal: s.principal,
      labelBalance: s.balance,
      labelDisclaimer: s.disclaimer,
      labelCalculatedWith: s.calculatedWith,
      labelPdfExportedSuccess: s.pdfExportedSuccess,
      nowYear: now.year,
      nowMonth: now.month,
      nowDay: now.day,
    );

    try {
      final bytes = await Isolate.run(() => _buildPayoffPlanPdf(params));
      if (!context.mounted) return;
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'loan_payoff_us_plan_${DateFormat('yyyyMMdd').format(now)}.pdf',
      );
      AnalyticsService.instance.logPdfExported();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.pdfExportedSuccess),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEs ? 'Error al exportar el PDF.' : 'Export failed.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(payoffResultProvider);
    ref.listen(loanInputProvider, (_, next) {
      final r = ref.read(payoffResultProvider);
      if (r != null) _scheduleAutoSave(r, next);
    });
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) => _buildContent(context, ref, result, isEs),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    PayoffResult? result,
    bool isEs,
  ) {
    final AppStrings s = isEs ? AppStringsES() : AppStringsEN();

    if (result == null) {
      return Column(
        children: [
          Expanded(child: Center(child: Text(s.enterLoan))),
          const CalcwiseAdFooter(),
        ],
      );
    }

    final schedule = result.schedule;
    final payoffDate = _debtFreeDate(result.extraMonths);

    // Group schedule into chunks of 12 months
    final groups = <List<AmortizationEntry>>[];
    for (int i = 0; i < schedule.length; i += 12) {
      groups.add(schedule.sublist(i, (i + 12).clamp(0, schedule.length)));
    }

    // ── Balance chart data (sampled every 6 months for performance) ──
    final normalSched = result.normalSchedule;
    final extraSched = result.schedule;
    final maxMonths = normalSched.length;
    const step = 6;

    List<FlSpot> normalSpots = [];
    List<FlSpot> extraSpots = [];
    for (int i = 0; i < maxMonths; i += step) {
      normalSpots.add(FlSpot(i.toDouble(), normalSched[i].balance));
    }
    normalSpots.add(FlSpot(maxMonths.toDouble(), 0));
    for (int i = 0; i < extraSched.length; i += step) {
      extraSpots.add(FlSpot(i.toDouble(), extraSched[i].balance));
    }
    extraSpots.add(FlSpot(extraSched.length.toDouble(), 0));

    final maxBalance = normalSched.isNotEmpty
        ? normalSched.first.balance + normalSched.first.principal
        : 1.0;

    return CalcwisePageEntrance(
        child: Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: groups.length + 6,
            itemBuilder: (ctx, i) {
              if (i == 0) {
                // ── Header stats ──
                return Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.primary, AppTheme.primaryDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _HeaderStat(s.months, '${result.extraMonths}', Colors.white),
                      _HeaderStat(
                        s.interest,
                        AmountFormatter.ui(result.interestExtra.roundToDouble(), 'USD'),
                        Colors.white70,
                      ),
                      _HeaderStat(
                        s.payoff,
                        DateFormat('MMM yyyy', isEs ? 'es' : 'en').format(payoffDate),
                        AppTheme.accentGood,
                      ),
                    ],
                  ),
                );
              } else if (i == 1) {
                return const StreakCard();
              } else if (i == 2) {
                // ── Next Victory ──
                return FutureBuilder<List<DebtItem>>(
                  future: DebtPersistence.instance.load(),
                  builder: (context, snap) {
                    final debts = snap.data ?? const [];
                    final debtMaps = debts
                        .map(
                          (d) => <String, dynamic>{
                            'id': d.id,
                            'name': d.name,
                            'balance': d.balance,
                            'monthlyPayment': d.minPayment,
                            'rate': d.annualRate,
                          },
                        )
                        .toList();
                    return NextVictoryCard(
                      nextVictory: StreakService.nextVictory(debtMaps),
                    );
                  },
                );
              } else if (i == 3) {
                // ── Balance over time chart ──
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.balanceChart,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextSize.body,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 180,
                        child: CalcwiseChartReveal(
                          child: LineChart(
                          LineChartData(
                            minY: 0,
                            maxY: maxBalance * 1.05,
                            gridData: const FlGridData(show: false),
                            borderData: FlBorderData(show: false),
                            lineTouchData: LineTouchData(
                              handleBuiltInTouches: true,
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipItems: (spots) => spots
                                    .map(
                                      (sp) => LineTooltipItem(
                                        '\$${(sp.y / 1000).toStringAsFixed(1)}k',
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
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 56,
                                  getTitlesWidget: (v, _) => Text(
                                    '\$${(v / 1000).toStringAsFixed(0)}k',
                                    style: const TextStyle(fontSize: AppTextSize.xs),
                                  ),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (v, _) {
                                    final yr = (v / 12).round();
                                    if (yr == 0 || v % 24 != 0) return const SizedBox();
                                    return Text(
                                      'Y$yr',
                                      style: const TextStyle(fontSize: AppTextSize.xs),
                                    );
                                  },
                                ),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                spots: normalSpots,
                                isCurved: true,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                barWidth: 2,
                                dashArray: CalcwiseChartTokens.secondarySeriesDash,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(show: false),
                              ),
                              if (result.monthsSaved > 0)
                                LineChartBarData(
                                  spots: extraSpots,
                                  isCurved: true,
                                  color: AppTheme.accentGood,
                                  barWidth: 2.5,
                                  dotData: const FlDotData(show: false),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: AppTheme.accentGood.withValues(alpha: 0.08),
                                  ),
                                ),
                            ],
                          ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          _LegendDot(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            label: s.normalLabel,
                          ),
                          const SizedBox(width: 16),
                          _LegendDot(
                            color: AppTheme.accentGood,
                            label: s.withExtraLabel,
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              } else if (i < groups.length + 4) {
                // ── Amortization groups ──
                final gi = i - 4;
                final group = groups[gi];
                final firstMo = group.first.month;
                final lastMo = group.last.month;
                final isLastGrp = gi == groups.length - 1;
                final yearNum = gi + 1;
                final totalPrinc = group.fold<double>(0, (sum, e) => sum + e.principal);
                final totalInt = group.fold<double>(0, (sum, e) => sum + e.interest);
                final totalPmt = group.fold<double>(0, (sum, e) => sum + e.payment);
                final endBal = group.last.balance;
                return _MonthGroup(
                  yearNum: yearNum,
                  firstMonth: firstMo,
                  lastMonth: lastMo,
                  totalPayment: totalPmt,
                  totalPrincipal: totalPrinc,
                  totalInterest: totalInt,
                  endBalance: endBal,
                  isLastGroup: isLastGrp,
                  entries: group,
                  s: s,
                );
              } else if (i == groups.length + 4) {
                // ── Save / Share / Export — bottom of list after full plan ──
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                  child: Column(
                    children: [
                      SaveScenarioButton(onSave: _saveScenario),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _share(context, result, isEs),
                              icon: const Icon(Icons.share_rounded, size: 16),
                              label: Text(
                                s.shareLabel,
                                style: const TextStyle(fontSize: AppTextSize.md),
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 44),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ValueListenableBuilder<bool>(
                              valueListenable: freemiumService.hasFullAccessNotifier,
                              builder: (_, isPremium, __) => OutlinedButton.icon(
                                onPressed: () => _exportPdf(context, result, isEs),
                                icon: isPremium
                                    ? const Icon(Icons.picture_as_pdf_rounded, size: 16)
                                    : const Icon(Icons.lock_outline, size: 16),
                                label: Text(
                                  s.exportPdf,
                                  style: const TextStyle(fontSize: AppTextSize.md),
                                ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 44),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              } else {
                return const SizedBox(height: AppSpacing.listBottomInset);
              }
            },
          ),
        ),
        const CalcwiseAdFooter(),
      ],
    ));
  }
}

// ── Expandable group of 12 months ────────────────────────────────────────────
class _MonthGroup extends StatefulWidget {
  final int yearNum, firstMonth, lastMonth;
  final double totalPayment, totalPrincipal, totalInterest, endBalance;
  final bool isLastGroup;
  final List<AmortizationEntry> entries;
  final AppStrings s;

  const _MonthGroup({
    required this.yearNum,
    required this.firstMonth,
    required this.lastMonth,
    required this.totalPayment,
    required this.totalPrincipal,
    required this.totalInterest,
    required this.endBalance,
    required this.isLastGroup,
    required this.entries,
    required this.s,
  });

  @override
  State<_MonthGroup> createState() => _MonthGroupState();
}

class _MonthGroupState extends State<_MonthGroup>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _rot;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _rot = Tween(
      begin: 0.0,
      end: 0.5,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final accentColor = widget.isLastGroup
        ? AppTheme.accentGood
        : AppTheme.primary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: _expanded ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(
          color: accentColor.withValues(alpha: _expanded ? 0.5 : 0.15),
          width: _expanded ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // ── Group header (tap to expand) ──
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Year badge
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Center(
                      child: Text(
                        'Y${widget.yearNum}',
                        style: TextStyle(
                          color: accentColor,
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextSize.sm,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Month range
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${s.monthLabel} ${widget.firstMonth} – ${widget.lastMonth}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: AppTextSize.md,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${s.balance}: ${AmountFormatter.ui(widget.endBalance, 'USD')}',
                          style: TextStyle(
                            fontSize: AppTextSize.xs,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Summary chips
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _MiniChip(
                        label: AmountFormatter.ui(widget.totalPayment.roundToDouble(), 'USD'),
                        color: AppTheme.primaryDark,
                      ),
                      const SizedBox(height: 3),
                      _MiniChip(
                        label:
                            '${AmountFormatter.ui(widget.totalInterest.roundToDouble(), 'USD')} int',
                        color: AppTheme.warning,
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  RotationTransition(
                    turns: _rot,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded rows ──
          if (_expanded) ...[
            const Divider(height: 1, indent: 14, endIndent: 14),
            // Column headers
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                children: [
                  _HCell(s.colMo, 1),
                  _HCell(s.payment, 2),
                  _HCell(s.principal, 2),
                  _HCell(s.interest, 2),
                  _HCell(s.balance, 2),
                ],
              ),
            ),
            ...widget.entries.asMap().entries.map((entry) {
              final i = entry.key;
              final e = entry.value;
              final last = i == widget.entries.length - 1 && widget.isLastGroup;
              final cs = Theme.of(context).colorScheme;
              final bg = last
                  ? AppTheme.accentGood.withValues(alpha: 0.08)
                  : i % 2 == 0
                  ? cs.surfaceContainerLow
                  : cs.surface;
              return Container(
                color: bg,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                child: Row(
                  children: [
                    _Cell('${e.month}', 1, bold: last),
                    _Cell(AmountFormatter.ui(e.payment.roundToDouble(), 'USD'), 2, bold: last),
                    _Cell(AmountFormatter.ui(e.principal.roundToDouble(), 'USD'), 2, bold: last),
                    _Cell(
                      AmountFormatter.ui(e.interest.roundToDouble(), 'USD'),
                      2,
                      color: AppTheme.warning,
                    ),
                    _Cell(
                      AmountFormatter.ui(e.balance.roundToDouble(), 'USD'),
                      2,
                      bold: last,
                      color: last ? AppTheme.accentGood : null,
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────
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
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(
          fontSize: AppTextSize.xs,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniChip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: AppTextSize.xs, fontWeight: FontWeight.w600),
    ),
  );
}

class _HeaderStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _HeaderStat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        label,
        style: const TextStyle(color: Colors.white60, fontSize: AppTextSize.xs),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: AppTextSize.bodyLg,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );
}

class _HCell extends StatelessWidget {
  final String text;
  final int flex;
  const _HCell(this.text, this.flex);
  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
        fontWeight: FontWeight.bold,
        fontSize: AppTextSize.xs,
      ),
      textAlign: TextAlign.right,
    ),
  );
}

class _Cell extends StatelessWidget {
  final String text;
  final int flex;
  final bool bold;
  final Color? color;
  const _Cell(this.text, this.flex, {this.bold = false, this.color});
  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(
      text,
      style: TextStyle(
        fontSize: AppTextSize.xs,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color,
      ),
      textAlign: TextAlign.right,
    ),
  );
}
