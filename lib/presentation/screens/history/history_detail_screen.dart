import 'dart:isolate';
import 'dart:math' show pow;
import 'dart:typed_data';

import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/firebase/analytics_service.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:intl/date_symbol_data_local.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/language/language_notifier.dart';
import '../../../main.dart' show paywallSession;
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../widgets/paywall_soft.dart';
import '../../widgets/paywall_hard.dart';
import '../../widgets/premium_badge.dart';

// ── Params + top-level builder for Isolate.run ────────────────────────────────

class _HistoryDetailPdfParams {
  final String loanType;
  final double loanAmount;
  final double interestRate;
  final double monthlyPayment;
  final double extraPayment;
  final int normalMonths;
  final double interestSaved;
  final String? createdAt;
  final bool isEs;

  const _HistoryDetailPdfParams({
    required this.loanType,
    required this.loanAmount,
    required this.interestRate,
    required this.monthlyPayment,
    required this.extraPayment,
    required this.normalMonths,
    required this.interestSaved,
    required this.createdAt,
    required this.isEs,
  });
}

Future<Uint8List> _buildHistoryDetailPdf(_HistoryDetailPdfParams p) async {
  await initializeDateFormatting(); // worker isolate: load locale date symbols
  final ts = p.createdAt != null ? DateTime.tryParse(p.createdAt!) : null;
  // Compute exact total interest by accounting for the smaller final payment.
  // Standard formula overstates when all N payments are assumed full-sized.
  // Instead: totalInterest = payment*(N-1) + finalPayment - principal
  // where finalPayment = remaining balance after N-1 periods + one period's interest.
  double totalInterest;
  final r = p.interestRate / 100 / 12;
  if (r > 0 && p.normalMonths > 0) {
    final n = p.normalMonths;
    // Balance after (n-1) payments: B * (1+r)^(n-1) - pmt * ((1+r)^(n-1) - 1) / r
    final factor = pow(1 + r, n - 1);
    final balanceBeforeLast = p.loanAmount * factor - p.monthlyPayment * (factor - 1) / r;
    final finalPayment = balanceBeforeLast * (1 + r); // balance + last period's interest
    totalInterest = (p.monthlyPayment * (n - 1) + finalPayment - p.loanAmount)
        .clamp(0.0, double.infinity);
  } else {
    // Zero-interest loan: no interest charged
    totalInterest = 0.0;
  }
  final payoffDate = ts?.add(Duration(days: p.normalMonths * 30));
  final payoffDateStr =
      payoffDate != null ? DateFormat('MMM yyyy', p.isEs ? 'es' : 'en').format(payoffDate) : '—';
  final yearsPayoff = p.normalMonths ~/ 12;
  final mosPayoff = p.normalMonths % 12;

  final s = p.isEs ? AppStringsES() : AppStringsEN();

  // Input rows
  final inputRows = <({String label, String value})>[
    (label: s.loanTypeLabel, value: p.loanType),
    (label: s.loanAmount, value: AmountFormatter.ui(p.loanAmount, 'USD')),
    (
      label: s.interestRate,
      value: '${p.interestRate.toStringAsFixed(2)}%',
    ),
    (label: s.monthlyPayment, value: AmountFormatter.ui(p.monthlyPayment, 'USD')),
    if (p.extraPayment > 0)
      (
        label: s.extraPayment,
        value: '${AmountFormatter.ui(p.extraPayment, 'USD')}/mo',
      ),
  ];

  // Result rows
  final resultRows = <({String label, String value})>[
    (label: s.payoff, value: '${yearsPayoff}y ${mosPayoff}m'),
    (label: s.interestLabel, value: AmountFormatter.ui(totalInterest, 'USD')),
    (label: s.payoffDate, value: payoffDateStr),
    if (p.interestSaved > 0)
      (label: s.interestSavedExtra, value: AmountFormatter.ui(p.interestSaved, 'USD')),
  ];

  pw.Widget pdfRow(String label, String value, {bool highlight = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800),
            ),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight:
                    highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: highlight ? PdfColors.blue800 : PdfColors.black,
              ),
            ),
          ],
        ),
      );

  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(AppSpacing.xxxl),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Loan Payoff US — ${s.historyDetail}',
            style: pw.TextStyle(
              fontSize: AppTextSize.title,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (ts != null)
            pw.Text(
              DateFormat('MMM d, yyyy', p.isEs ? 'es' : 'en').format(ts),
              style: const pw.TextStyle(
                fontSize: AppTextSize.xs,
                color: PdfColors.grey600,
              ),
            ),
          pw.SizedBox(height: 16),
          pw.Divider(),
          pw.SizedBox(height: 6),
          pw.Text(
            s.inputs,
            style: pw.TextStyle(
              fontSize: AppTextSize.md,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          ...inputRows.map((r) => pdfRow(r.label, r.value)),
          pw.SizedBox(height: 12),
          pw.Text(
            s.results,
            style: pw.TextStyle(
              fontSize: AppTextSize.md,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          ...resultRows.map((r) => pdfRow(r.label, r.value, highlight: true)),
          pw.SizedBox(height: 16),
          pw.Divider(),
          pw.SizedBox(height: 6),
          pw.Text(
            s.disclaimer,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            s.calculatedWith,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
          ),
        ],
      ),
    ),
  );
  return pdf.save();
}

class HistoryDetailScreen extends StatefulWidget {
  final Map<String, dynamic> entry;
  const HistoryDetailScreen({super.key, required this.entry});

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  final _fmtDate = DateFormat('MMM d, yyyy');
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('history_detail');
  }

  Map<String, dynamic> get _e => widget.entry;

  double _d(String key) {
    final v = _e[key];
    return v == null ? 0.0 : (v as num).toDouble();
  }

  int _i(String key) {
    final v = _e[key];
    return v == null ? 0 : (v as num).toInt();
  }

  List<({String label, String value})> _inputRows(AppStrings s) => [
    (label: s.loanTypeLabel, value: (_e['loan_type'] as String? ?? '—')),
    (label: s.loanAmount, value: AmountFormatter.ui(_d('loan_amount'), 'USD')),
    (
      label: s.interestRate,
      value: '${_d('interest_rate').toStringAsFixed(2)}%',
    ),
    (label: s.monthlyPayment, value: AmountFormatter.ui(_d('monthly_payment'), 'USD')),
    if (_d('extra_payment') > 0)
      (
        label: s.extraPayment,
        value: '${AmountFormatter.ui(_d('extra_payment'), 'USD')}/mo',
      ),
  ];

  List<({String label, String value})> _resultRows(AppStrings s) {
    final months = _i('normal_months');
    final saved = _d('interest_saved');
    final loanAmount = _d('loan_amount');
    final monthlyPayment = _d('monthly_payment');
    final rate = _d('interest_rate');
    // Exact total interest: accounts for the smaller final payment instead of
    // assuming all N payments are full-sized (which overstates interest).
    double totalInterest;
    final r2 = rate / 100 / 12;
    if (r2 > 0 && months > 0) {
      final factor = pow(1 + r2, months - 1);
      final balanceBeforeLast = loanAmount * factor - monthlyPayment * (factor - 1) / r2;
      final finalPayment = balanceBeforeLast * (1 + r2);
      totalInterest = (monthlyPayment * (months - 1) + finalPayment - loanAmount)
          .clamp(0.0, double.infinity);
    } else {
      totalInterest = 0.0;
    }
    final ts = DateTime.tryParse(_e['created_at'] as String? ?? '');
    final payoffDate = ts?.add(Duration(days: months * 30));
    final payoffDateStr =
        payoffDate != null ? DateFormat('MMM yyyy', isSpanishNotifier.value ? 'es' : 'en').format(payoffDate) : '—';
    return [
      (label: s.payoff, value: '${months ~/ 12}y ${months % 12}m'),
      (label: s.interestLabel, value: AmountFormatter.ui(totalInterest, 'USD')),
      (label: s.payoffDate, value: payoffDateStr),
      if (saved > 0)
        (label: s.interestSavedExtra, value: AmountFormatter.ui(saved, 'USD')),
    ];
  }

  String _buildShareText(AppStrings s) {
    final ts = DateTime.tryParse(_e['created_at'] as String? ?? '');
    const sep = '─────────────────────';
    final buf = StringBuffer();
    buf.writeln('Loan Payoff US — ${s.historyDetail}');
    if (ts != null) buf.writeln(_fmtDate.format(ts));
    buf.writeln(sep);
    buf.writeln(s.inputs);
    for (final r in _inputRows(s)) {
      final pad = ' ' * ((24 - r.label.length).clamp(1, 18));
      buf.writeln('${r.label}$pad${r.value}');
    }
    buf.writeln(sep);
    buf.writeln(s.results);
    for (final r in _resultRows(s)) {
      final pad = ' ' * ((24 - r.label.length).clamp(1, 18));
      buf.writeln('${r.label}$pad${r.value}');
    }
    buf.writeln(sep);
    buf.writeln(s.calculatedWith);
    buf.write(s is AppStringsES
        ? '\n📄 Exporta el reporte completo en PDF →'
        : '\n📄 Export the full PDF report in the app →');
    return buf.toString();
  }

  Future<void> _share(BuildContext context, AppStrings s) async {
    final text = _buildShareText(s);
    try {
      await Share.share(text, subject: 'Loan Payoff US Summary');
    } catch (_) {}
  }

  Future<void> _exportPdf(BuildContext context, AppStrings s) async {
    if (!freemiumService.hasFullAccess) {
      await PaywallHard.show(context);
      return;
    }
    setState(() => _isExporting = true);
    final ts = DateTime.tryParse(_e['created_at'] as String? ?? '');
    final tsStr = ts != null ? DateFormat('yyyyMMdd').format(ts) : 'export';
    try {
      final params = _HistoryDetailPdfParams(
        loanType: _e['loan_type'] as String? ?? '—',
        loanAmount: _d('loan_amount'),
        interestRate: _d('interest_rate'),
        monthlyPayment: _d('monthly_payment'),
        extraPayment: _d('extra_payment'),
        normalMonths: _i('normal_months'),
        interestSaved: _d('interest_saved'),
        createdAt: _e['created_at'] as String?,
        isEs: s is AppStringsES,
      );
      final bytes = await Isolate.run(() => _buildHistoryDetailPdf(params));
      if (!context.mounted) return;
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'loan_payoff_us_$tsStr.pdf',
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
              s is AppStringsES ? 'Error al exportar el PDF.' : 'Export failed.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Widget _detailRow(
    BuildContext context,
    String label,
    String value, {
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.55),
                fontSize: AppTextSize.body,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              fontSize: AppTextSize.body,
            ),
          ),
        ],
      ),
    );
  }

  // Icon map for input rows
  static const Map<String, IconData> _inputIcons = {
    'Loan Type': Icons.credit_card_rounded,
    'Type de prêt': Icons.credit_card_rounded,
    'Loan Amount': Icons.attach_money,
    'Montant': Icons.attach_money,
    'Interest Rate': Icons.percent,
    'Taux': Icons.percent,
    'Monthly Payment': Icons.calendar_month_rounded,
    'Paiement mensuel': Icons.calendar_month_rounded,
    'Extra Payment': Icons.add_circle_outline,
    'Paiement supplémentaire': Icons.add_circle_outline,
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final AppStrings s = isEs ? AppStringsES() : AppStringsEN();
        final ts = DateTime.tryParse(_e['created_at'] as String? ?? '');

        // Derived metrics
        final monthlyPayment = _d('monthly_payment');
        final loanAmount = _d('loan_amount');
        final rate = _d('interest_rate');
        // Exact total interest: accounts for the smaller final payment instead of
        // assuming all N payments are full-sized (which overstates interest).
        double totalInterest;
        final r3 = rate / 100 / 12;
        final nMonths = _i('normal_months');
        if (r3 > 0 && nMonths > 0) {
          final factor3 = pow(1 + r3, nMonths - 1);
          final balanceBeforeLast3 = loanAmount * factor3 - monthlyPayment * (factor3 - 1) / r3;
          final finalPayment3 = balanceBeforeLast3 * (1 + r3);
          totalInterest = (monthlyPayment * (nMonths - 1) + finalPayment3 - loanAmount)
              .clamp(0.0, double.infinity);
        } else {
          totalInterest = 0.0;
        }
        final payoffDate = ts?.add(Duration(days: _i('normal_months') * 30));
        final payoffDateStr =
            payoffDate != null ? DateFormat('MMM yyyy', isEs ? 'es' : 'en').format(payoffDate) : '—';
        final yearsPayoff = _i('normal_months') ~/ 12;
        final mosPayoff = _i('normal_months') % 12;

        return ValueListenableBuilder<bool>(
          valueListenable: freemiumService.hasFullAccessNotifier,
          builder: (context, isPremium, _) {
            return Scaffold(
              appBar: AppBar(
                title: Text(
                  ts != null
                      ? DateFormat('MMM d, yyyy', isEs ? 'es' : 'en').format(ts)
                      : s.historyDetail,
                ),
                centerTitle: false,
                actions: [
                  const PremiumBadge(),
                  IconButton(
                    icon: const Icon(Icons.share_rounded),
                    tooltip: s.shareLabel,
                    onPressed: () => _share(context, s),
                  ),
                ],
              ),
              body: CalcwisePageEntrance(
                  child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        // ── 1. HERO CARD ─────────────────────────────────────
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppTheme.primary, AppTheme.primaryDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.all(
                              Radius.circular(AppRadius.xxl),
                            ),
                          ),
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Loan type chip
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.xs,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: const BorderRadius.all(
                                      Radius.circular(AppRadius.xxl),
                                    ),
                                  ),
                                  child: Text(
                                    (_e['loan_type'] as String? ?? '—'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: AppTextSize.xs,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.mdPlus),
                              // Big loan amount
                              Text(
                                AmountFormatter.ui(loanAmount, 'USD'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: AppTextSize.display,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.5,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              // Payoff duration + debt-free date
                              Text(
                                '${s.payoffIn} ${yearsPayoff}${isEs ? 'a' : 'y'} ${mosPayoff}m  •  ${s.debtFreeBy} $payoffDateStr',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: AppTextSize.sm,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: AppSpacing.lg),

                        // ── 2. KPI ROW ────────────────────────────────────────
                        Row(
                          children: [
                            _MetricTile(
                              label: isEs ? 'Tasa de Interés' : 'Interest Rate',
                              value: '${rate.toStringAsFixed(2)}%',
                              icon: Icons.percent,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            _MetricTile(
                              label: isEs ? 'Pago Mensual' : 'Monthly Pmt',
                              value: AmountFormatter.ui(monthlyPayment, 'USD'),
                              icon: Icons.calendar_today_rounded,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            _MetricTile(
                              label: isEs ? 'Interés Total' : 'Total Interest',
                              value: AmountFormatter.ui(totalInterest, 'USD'),
                              icon: Icons.money_off_rounded,
                              color: AppTheme.warning,
                            ),
                          ],
                        ),

                        // ── 3. SAVINGS BANNER (extra payment only) ────────────
                        if (_d('extra_payment') > 0) ...[
                          const SizedBox(height: AppSpacing.md),
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.accentGood.withValues(alpha: 0.1),
                              border: Border.all(
                                color: AppTheme.accentGood.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                              borderRadius: const BorderRadius.all(
                                Radius.circular(AppRadius.lg),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.smPlus,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.bolt_rounded,
                                  color: AppTheme.accentGood,
                                  size: 20,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    isEs
                                        ? 'Extra +${AmountFormatter.ui(_d('extra_payment'), 'USD')}/mes → ahorrado ${AmountFormatter.ui(_d('interest_saved'), 'USD')}'
                                        : 'Extra +${AmountFormatter.ui(_d('extra_payment'), 'USD')}/mo → saved ${AmountFormatter.ui(_d('interest_saved'), 'USD')}',
                                    style: const TextStyle(
                                      color: AppTheme.accentGood,
                                      fontWeight: FontWeight.bold,
                                      fontSize: AppTextSize.sm,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: AppSpacing.lg),

                        // ── 4. INPUTS CARD ────────────────────────────────────
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.lg),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.inputs,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: AppTextSize.bodyMd,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                ..._inputRowsWithIcons(context, s),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: AppSpacing.lg),

                        // ── 5. ACTION BUTTONS ─────────────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  HapticFeedback.mediumImpact();
                                  _share(context, s);
                                },
                                icon: const Icon(Icons.share_rounded),
                                label: Text(s.shareLabel),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 52),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _isExporting
                                    ? null
                                    : () {
                                        HapticFeedback.mediumImpact();
                                        _exportPdf(context, s);
                                      },
                                icon: _isExporting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : isPremium
                                        ? const Icon(Icons.picture_as_pdf_rounded)
                                        : const Icon(Icons.lock_outline),
                                label: Text(s.exportPdf),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 52),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: AppSpacing.listBottomInset),
                      ],
                    ),
                  ),

                  // ── Banner ad — free only ─────────────────────────────────
                  if (!isPremium) const CalcwiseAdFooter(),
                ],
              )),
            );
          },
        );
      },
    );
  }

  List<Widget> _inputRowsWithIcons(BuildContext context, AppStrings s) {
    final rows = _inputRows(s);
    const iconFallback = Icons.info_outline_rounded;
    return rows.map((r) {
      final icon = _inputIcons.entries
              .where((e) =>
                  r.label.toLowerCase().contains(e.key.toLowerCase()))
              .map((e) => e.value)
              .firstOrNull ??
          iconFallback;
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.smPlus),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius:
                    const BorderRadius.all(Radius.circular(AppRadius.md)),
              ),
              child: Icon(icon, size: 16, color: AppTheme.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                r.label,
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                  fontSize: AppTextSize.body,
                ),
              ),
            ),
            Text(
              r.value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: AppTextSize.body,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI metric tile
// ─────────────────────────────────────────────────────────────────────────────
class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  const _MetricTile({
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
