import 'package:flutter/material.dart';
import '../language/language_notifier.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../../main.dart';
import '../../presentation/widgets/paywall_hard.dart';
import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard;

const _purple = PdfColor(0.290, 0.196, 0.784); // LoanPayoff purple
const _navy = PdfColor(0.059, 0.137, 0.353);
const _light = PdfColor(0.949, 0.941, 0.996);

class PdfExportService {
  static final _cur2 = NumberFormat.currency(
    locale: 'en_US',
    symbol: '\$',
    decimalDigits: 2,
  );
  static final _cur0 = NumberFormat.currency(
    locale: 'en_US',
    symbol: '\$',
    decimalDigits: 0,
  );
  static final _date = DateFormat('MMMM d, yyyy');

  static Future<void> exportPayoff({
    required BuildContext context,
    required double balance,
    required double rate,
    required double monthlyPayment,
    required double extraPayment,
    required int monthsToPayoff,
    required double totalInterest,
    required double interestSaved,
    required int monthsSaved,
    required String strategy,
  }) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
        build: (_) => _buildPage(
          balance: balance,
          rate: rate,
          monthlyPayment: monthlyPayment,
          extraPayment: extraPayment,
          monthsToPayoff: monthsToPayoff,
          totalInterest: totalInterest,
          interestSaved: interestSaved,
          monthsSaved: monthsSaved,
          strategy: strategy,
        ),
      ),
    );
    final pdfBytes = await pdf.save();
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/LoanPayoff_${balance.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.Widget _buildPage({
    required double balance,
    required double rate,
    required double monthlyPayment,
    required double extraPayment,
    required int monthsToPayoff,
    required double totalInterest,
    required double interestSaved,
    required int monthsSaved,
    required String strategy,
  }) {
    final now = DateTime.now();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Loan Payoff Calculator',
                  style: pw.TextStyle(
                    fontSize: AppTextSize.title,
                    fontWeight: pw.FontWeight.bold,
                    color: _purple,
                  ),
                ),
                pw.Text(
                  'Debt Payoff Strategy Report',
                  style: const pw.TextStyle(
                    fontSize: AppTextSize.xs,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.Text(
              _date.format(now),
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ],
        ),
        pw.Container(
          height: 2,
          color: _purple,
          margin: const pw.EdgeInsets.only(top: 6, bottom: 14),
        ),

        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                children: [
                  _sectionBox('LOAN DETAILS', [
                    _row2('Current Balance', _cur0.format(balance)),
                    _row2('Interest Rate', '${rate.toStringAsFixed(2)}%'),
                    _row2('Monthly Payment', _cur2.format(monthlyPayment)),
                    if (extraPayment > 0)
                      _row2(
                        'Extra Payment',
                        _cur2.format(extraPayment),
                        bold: true,
                        color: _purple,
                      ),
                    _row2('Strategy', strategy),
                  ]),
                ],
              ),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: pw.Column(
                children: [
                  _sectionBox('PAYOFF RESULTS', [
                    _row2(
                      'Months to Pay Off',
                      '$monthsToPayoff mo (${(monthsToPayoff / 12.0).toStringAsFixed(1)} yr)',
                    ),
                    _row2('Total Interest', _cur0.format(totalInterest)),
                    pw.Divider(color: PdfColors.grey300, height: 6),
                    _row2(
                      'Interest Saved',
                      _cur0.format(interestSaved),
                      bold: true,
                      color: _purple,
                    ),
                    _row2('Time Saved', '$monthsSaved months'),
                  ]),
                ],
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 16),
        _buildPayoffChart(
          monthsWithExtra: monthsToPayoff,
          monthsWithoutExtra: monthsToPayoff + monthsSaved,
        ),

        pw.Spacer(),
        pw.Column(
          children: [
            pw.Divider(color: PdfColors.grey300, height: 12),
            pw.Text(
              'Generated by Loan Payoff Calculator · For illustration purposes only. Not financial advice.',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildPayoffChart({
    required int monthsWithExtra,
    required int monthsWithoutExtra,
  }) {
    final isEs = isSpanishNotifier.value;
    final maxMonths = monthsWithoutExtra.toDouble();
    // Round the y-axis top up to a clean value (multiple of 12).
    final axisTop = ((maxMonths / 12).ceil() * 12).toDouble().clamp(12, 1e9);
    final ticks = <double>[];
    final step = (axisTop / 4).ceilToDouble();
    for (var v = 0.0; v <= axisTop + 0.5; v += step) {
      ticks.add(v);
    }

    String yrLabel(int months) => isEs
        ? '${(months / 12.0).toStringAsFixed(1)} años'
        : '${(months / 12.0).toStringAsFixed(1)} yr';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: _navy,
          child: pw.Text(
            isEs ? 'COMPARACIÓN DE PLAZO' : 'PAYOFF TIME COMPARISON',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        ),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.fromLTRB(8, 10, 8, 6),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                height: 150,
                child: pw.Chart(
                  grid: pw.CartesianGrid(
                    xAxis: pw.FixedAxis.fromStrings(
                      [
                        isEs ? 'Sin extra' : 'No Extra',
                        isEs ? 'Con extra' : 'With Extra',
                      ],
                      marginStart: 40,
                      marginEnd: 40,
                      textStyle: const pw.TextStyle(fontSize: 8),
                    ),
                    yAxis: pw.FixedAxis(
                      ticks,
                      format: (v) => '${v.toInt()}',
                      divisions: true,
                      textStyle: const pw.TextStyle(
                        fontSize: 7,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ),
                  datasets: [
                    pw.BarDataSet(
                      width: 48,
                      borderColor: _navy,
                      color: _navy,
                      data: [
                        pw.PointChartValue(0, monthsWithoutExtra.toDouble()),
                      ],
                    ),
                    pw.BarDataSet(
                      width: 48,
                      borderColor: _purple,
                      color: _purple,
                      data: [
                        pw.PointChartValue(1, monthsWithExtra.toDouble()),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  _legendDot(
                    _navy,
                    '${isEs ? 'Sin extra' : 'No Extra'} · ${yrLabel(monthsWithoutExtra)}',
                  ),
                  pw.SizedBox(width: 18),
                  _legendDot(
                    _purple,
                    '${isEs ? 'Con extra' : 'With Extra'} · ${yrLabel(monthsWithExtra)}',
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(
                  isEs
                      ? 'Eje Y: meses para liquidar'
                      : 'Y-axis: months to pay off',
                  style: const pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.grey500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _legendDot(PdfColor color, String label) => pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Container(
        width: 9,
        height: 9,
        decoration: pw.BoxDecoration(
          color: color,
          shape: pw.BoxShape.circle,
        ),
      ),
      pw.SizedBox(width: 5),
      pw.Text(
        label,
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
      ),
    ],
  );

  static pw.Widget _sectionBox(String title, List<pw.Widget> rows) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: _navy,
        child: pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
        ),
      ),
      pw.Container(
        padding: const pw.EdgeInsets.all(AppSpacing.sm),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        ),
        child: pw.Column(children: rows),
      ),
    ],
  );

  static pw.Widget _row2(
    String label,
    String value, {
    bool bold = false,
    PdfColor? color,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color ?? PdfColors.black,
          ),
        ),
      ],
    ),
  );

  static Future<void> showUnlockOrPay(
    BuildContext context,
    Future<void> Function() onExport,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PdfUnlockSheet(onExport: onExport),
    );
  }
}

class _PdfUnlockSheet extends StatefulWidget {
  final Future<void> Function() onExport;
  const _PdfUnlockSheet({required this.onExport});
  @override
  State<_PdfUnlockSheet> createState() => _PdfUnlockSheetState();
}

class _PdfUnlockSheetState extends State<_PdfUnlockSheet> {
  bool _loading = false;
  Future<void> _watchAd() async {
    setState(() => _loading = true);
    final earned = await adService.showRewarded();
    if (!mounted) return;
    setState(() => _loading = false);
    if (earned) {
      Navigator.pop(context);
      await widget.onExport();
    } else
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isSpanishNotifier.value
                ? 'Anuncio no disponible. Inténtalo más tarde.'
                : 'Ad not available. Try again later.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final adReady = adService.isRewardedReady;
    final isEs = isSpanishNotifier.value;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Icon(
            Icons.picture_as_pdf_rounded,
            size: 36,
            color: AppTheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            isEs ? 'Exportar PDF' : 'Export PDF',
            style: const TextStyle(
              fontSize: AppTextSize.subtitle,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isEs
                ? 'Elige cómo desbloquear la exportación'
                : 'Choose how to unlock PDF export',
            style: TextStyle(
              fontSize: AppTextSize.md,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 24),
          Opacity(
            opacity: adReady ? 1.0 : 0.45,
            child: InkWell(
              onTap: (adReady && !_loading) ? _watchAd : null,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_circle_outline,
                        color: AppTheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEs ? 'Ver un video corto' : 'Watch a short video',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: AppTextSize.bodyMd,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isEs
                                ? 'Exportar una vez — gratis'
                                : 'Export once — free',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.65),
                              fontSize: AppTextSize.md,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_loading)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF94A3B8),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                PaywallHard.show(context);
              },
              icon: const Icon(Icons.workspace_premium, size: 18),
              label: Text(
                isEs
                    ? 'Premium (ilimitado)'
                    : 'Premium (unlimited)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentGood,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              isEs ? 'Ahora no' : 'Not now',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.65)),
            ),
          ),
        ],
      ),
    );
  }
}
