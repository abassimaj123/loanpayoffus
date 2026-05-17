import 'package:calcwise_core/calcwise_core.dart'
    show PaywallTrigger, CalcwiseAdFooter;
import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

class HistoryDetailScreen extends StatefulWidget {
  final Map<String, dynamic> entry;
  const HistoryDetailScreen({super.key, required this.entry});

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  final _fmtCur = NumberFormat.currency(
    locale: 'en_US',
    symbol: '\$',
    decimalDigits: 2,
  );
  final _fmtInt = NumberFormat.currency(
    locale: 'en_US',
    symbol: '\$',
    decimalDigits: 0,
  );
  final _fmtDate = DateFormat('MMM d, yyyy · h:mm a');

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
    (label: s.loanAmount, value: _fmtInt.format(_d('loan_amount'))),
    (
      label: s.interestRate,
      value: '${_d('interest_rate').toStringAsFixed(2)}%',
    ),
    (label: s.monthlyPayment, value: _fmtCur.format(_d('monthly_payment'))),
    if (_d('extra_payment') > 0)
      (
        label: s.extraPayment,
        value: '${_fmtCur.format(_d('extra_payment'))}/mo',
      ),
  ];

  List<({String label, String value})> _resultRows(AppStrings s) {
    final months = _i('normal_months');
    final saved = _d('interest_saved');
    return [
      (label: s.payoff, value: '${months ~/ 12}y ${months % 12}m'),
      (
        label: s.interestLabel,
        value: _fmtCur.format(
          _d('interest_rate') > 0
              ? _d('loan_amount') * _d('interest_rate') / 100 * months / 12
              : 0,
        ),
      ),
      if (saved > 0)
        (label: s.interestSavedExtra, value: _fmtInt.format(saved)),
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
    buf.write(s.calculatedWith);
    return buf.toString();
  }

  Future<void> _share(BuildContext context, AppStrings s) async {
    if (!freemiumService.hasFullAccess) {
      final gate = await paywallSession.recordAction();
      if (!context.mounted) return;
      if (gate == PaywallTrigger.hard) {
        await PaywallHard.show(context);
        return;
      } else if (gate == PaywallTrigger.soft) {
        await PaywallSoft.show(context);
        if (!context.mounted) return;
      }
    }
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
    final ts = DateTime.tryParse(_e['created_at'] as String? ?? '');
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
                DateFormat('MMM d, yyyy').format(ts),
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
            ..._inputRows(s).map((r) => _pdfRow(r.label, r.value)),

            pw.SizedBox(height: 12),
            pw.Text(
              s.results,
              style: pw.TextStyle(
                fontSize: AppTextSize.md,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            ..._resultRows(
              s,
            ).map((r) => _pdfRow(r.label, r.value, highlight: true)),

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

    final tsStr = ts != null ? DateFormat('yyyyMMdd').format(ts) : 'export';
    try {
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'loan_payoff_us_$tsStr.pdf',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF exported'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Export failed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  pw.Widget _pdfRow(String label, String value, {bool highlight = false}) =>
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
                fontWeight: highlight
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
                color: highlight ? PdfColors.blue800 : PdfColors.black,
              ),
            ),
          ],
        ),
      );

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
          Text(
            label,
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.55),
              fontSize: AppTextSize.body,
            ),
          ),
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final AppStrings s = isEs ? AppStringsES() : AppStringsEN();
        final ts = DateTime.tryParse(_e['created_at'] as String? ?? '');

        return ValueListenableBuilder<bool>(
          valueListenable: freemiumService.isPremiumNotifier,
          builder: (context, isPremium, _) {
            return Scaffold(
              appBar: AppBar(
                title: Text(
                  ts != null
                      ? DateFormat('MMM d, yyyy').format(ts)
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
                  IconButton(
                    icon: isPremium
                        ? const Icon(Icons.picture_as_pdf_rounded)
                        : const Icon(Icons.lock_outline),
                    tooltip: s.exportPdf,
                    onPressed: () => _exportPdf(context, s),
                  ),
                ],
              ),
              body: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        // ── Date ─────────────────────────────────────────────
                        if (ts != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              _fmtDate.format(ts),
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.45),
                                fontSize: AppTextSize.md,
                              ),
                            ),
                          ),

                        // ── Inputs card ───────────────────────────────────────
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
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
                                const SizedBox(height: 12),
                                ..._inputRows(s).map(
                                  (r) => _detailRow(context, r.label, r.value),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // ── Results card ──────────────────────────────────────
                        Card(
                          color: AppTheme.primary.withValues(alpha: 0.04),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            side: BorderSide(
                              color: AppTheme.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          elevation: 0,
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.results,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: AppTextSize.bodyMd,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ..._resultRows(s).map(
                                  (r) => _detailRow(
                                    context,
                                    r.label,
                                    r.value,
                                    bold: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // ── Action buttons ────────────────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _share(context, s),
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
                                onPressed: () => _exportPdf(context, s),
                                icon: isPremium
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

                        const SizedBox(height: 80),
                      ],
                    ),
                  ),

                  // ── Banner ad — free only ─────────────────────────────────
                  if (!isPremium) const CalcwiseAdFooter(),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
