import 'package:flutter/material.dart';
import '../language/language_notifier.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../theme/app_theme.dart';
import '../../main.dart';
import '../freemium/freemium_service.dart';
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

  // ── Shared helpers ──────────────────────────────────────────────────────────

  static Future<void> _sharePdf(
    BuildContext context,
    pw.Document pdf,
    String filename,
    bool isEs,
  ) async {
    try {
      await Printing.sharePdf(bytes: await pdf.save(), filename: filename);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEs ? 'PDF exportado' : 'PDF exported'),
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

  static pw.Document _newDoc() => pw.Document();

  static pw.Widget _header(String title, String subtitle, bool isEs) {
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
                  title,
                  style: pw.TextStyle(
                    fontSize: AppTextSize.title,
                    fontWeight: pw.FontWeight.bold,
                    color: _purple,
                  ),
                ),
                pw.Text(
                  subtitle,
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
      ],
    );
  }

  static pw.Widget _footer(bool isEs) => pw.Column(
    children: [
      pw.Divider(color: PdfColors.grey300, height: 12),
      pw.Text(
        isEs
            ? 'Generado por Loan Payoff US · Solo fines informativos. No es asesoramiento financiero.'
            : 'Generated by Loan Payoff US · For illustration purposes only. Not financial advice.',
        style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
      ),
    ],
  );

  // ── 1. Calculator — Main loan payoff ────────────────────────────────────────

  static Future<void> exportCalculator(
    BuildContext context, {
    required double loanBalance,
    required double interestRate,
    required double monthlyPayment,
    required double extraPayment,
    required int monthsWithout,
    required int monthsWith,
    required double interestWithout,
    required double interestWith,
    required double interestSaved,
    required int monthsSaved,
    bool isEs = false,
  }) async {
    if (!freemiumService.hasFullAccess) {
      await showUnlockOrPay(
        context,
        () => exportCalculator(
          context,
          loanBalance: loanBalance,
          interestRate: interestRate,
          monthlyPayment: monthlyPayment,
          extraPayment: extraPayment,
          monthsWithout: monthsWithout,
          monthsWith: monthsWith,
          interestWithout: interestWithout,
          interestWith: interestWith,
          interestSaved: interestSaved,
          monthsSaved: monthsSaved,
          isEs: isEs,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final payoffDateWithout = DateTime(now.year, now.month + monthsWithout);
    final payoffDateWith = extraPayment > 0
        ? DateTime(now.year, now.month + monthsWith)
        : null;

    final pdf = _newDoc();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header(
              'Loan Payoff US',
              isEs ? 'Informe de Pago del Préstamo' : 'Loan Payoff Report',
              isEs,
            ),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _sectionBox(
                    isEs ? 'DETALLES DEL PRÉSTAMO' : 'LOAN DETAILS',
                    [
                      _row2(
                        isEs ? 'Saldo del préstamo' : 'Loan balance',
                        _cur0.format(loanBalance),
                      ),
                      _row2(
                        isEs ? 'Tasa de interés' : 'Interest rate',
                        '${interestRate.toStringAsFixed(2)}%',
                      ),
                      _row2(
                        isEs ? 'Pago mensual' : 'Monthly payment',
                        _cur2.format(monthlyPayment),
                      ),
                      if (extraPayment > 0)
                        _row2(
                          isEs ? 'Pago extra' : 'Extra payment',
                          _cur2.format(extraPayment),
                          bold: true,
                          color: _purple,
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 14),
                pw.Expanded(
                  child: _sectionBox(
                    isEs ? 'RESULTADOS DE PAGO' : 'PAYOFF RESULTS',
                    [
                      _row2(
                        isEs ? 'Sin pago extra' : 'Without extra',
                        '${monthsWithout ~/ 12}y ${monthsWithout % 12}m  •  ${DateFormat('MMM yyyy').format(payoffDateWithout)}',
                      ),
                      _row2(
                        isEs ? 'Interés sin extra' : 'Interest (no extra)',
                        _cur0.format(interestWithout),
                      ),
                      if (extraPayment > 0 && payoffDateWith != null) ...[
                        pw.Divider(color: PdfColors.grey300, height: 6),
                        _row2(
                          isEs ? 'Con pago extra' : 'With extra payment',
                          '${monthsWith ~/ 12}y ${monthsWith % 12}m  •  ${DateFormat('MMM yyyy').format(payoffDateWith)}',
                          bold: true,
                          color: _purple,
                        ),
                        _row2(
                          isEs ? 'Interés con extra' : 'Interest (with extra)',
                          _cur0.format(interestWith),
                        ),
                        _row2(
                          isEs ? 'Interés ahorrado' : 'Interest saved',
                          _cur0.format(interestSaved),
                          bold: true,
                          color: _purple,
                        ),
                        _row2(
                          isEs ? 'Meses ahorrados' : 'Months saved',
                          '$monthsSaved ${isEs ? "meses" : "months"}',
                          bold: true,
                          color: _purple,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            if (extraPayment > 0)
              _buildPayoffChart(
                monthsWithExtra: monthsWith,
                monthsWithoutExtra: monthsWithout,
              ),
            pw.Spacer(),
            _footer(isEs),
          ],
        ),
      ),
    );

    await _sharePdf(context, pdf, 'loan_payoff_calculator.pdf', isEs);
  }

  // ── 2. Consolidation ────────────────────────────────────────────────────────

  static Future<void> exportConsolidation(
    BuildContext context, {
    required List<({double balance, double rate, double payment})> loans,
    required double consolidationRate,
    required int termMonths,
    required double currentTotalPayment,
    required double consolidationPayment,
    required double totalInterestCurrent,
    required double totalInterestConsolidated,
    required double netMonthlySavings,
    bool isEs = false,
  }) async {
    if (!freemiumService.hasFullAccess) {
      await showUnlockOrPay(
        context,
        () => exportConsolidation(
          context,
          loans: loans,
          consolidationRate: consolidationRate,
          termMonths: termMonths,
          currentTotalPayment: currentTotalPayment,
          consolidationPayment: consolidationPayment,
          totalInterestCurrent: totalInterestCurrent,
          totalInterestConsolidated: totalInterestConsolidated,
          netMonthlySavings: netMonthlySavings,
          isEs: isEs,
        ),
      );
      return;
    }

    final pdf = _newDoc();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header(
              'Loan Payoff US',
              isEs
                  ? 'Informe de Consolidación de Deudas'
                  : 'Debt Consolidation Report',
              isEs,
            ),

            // Loan list
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: _navy,
              child: pw.Text(
                isEs ? 'DEUDAS ACTUALES' : 'CURRENT DEBTS',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
              ),
              child: pw.Column(
                children: [
                  // Header row
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          isEs ? 'Deuda' : 'Debt',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                      pw.SizedBox(
                        width: 80,
                        child: pw.Text(
                          isEs ? 'Saldo' : 'Balance',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                      pw.SizedBox(
                        width: 60,
                        child: pw.Text(
                          isEs ? 'Tasa' : 'Rate',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                      pw.SizedBox(
                        width: 80,
                        child: pw.Text(
                          isEs ? 'Pago/mes' : 'Payment/mo',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.Divider(color: PdfColors.grey300, height: 4),
                  ...loans.asMap().entries.map(
                    (e) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      child: pw.Row(
                        children: [
                          pw.Expanded(
                            child: pw.Text(
                              '${isEs ? "Deuda" : "Debt"} ${e.key + 1}',
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                          ),
                          pw.SizedBox(
                            width: 80,
                            child: pw.Text(
                              _cur0.format(e.value.balance),
                              textAlign: pw.TextAlign.right,
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                          ),
                          pw.SizedBox(
                            width: 60,
                            child: pw.Text(
                              '${e.value.rate.toStringAsFixed(2)}%',
                              textAlign: pw.TextAlign.right,
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                          ),
                          pw.SizedBox(
                            width: 80,
                            child: pw.Text(
                              _cur2.format(e.value.payment),
                              textAlign: pw.TextAlign.right,
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 14),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _sectionBox(
                    isEs ? 'PRÉSTAMO CONSOLIDADO' : 'CONSOLIDATION LOAN',
                    [
                      _row2(
                        isEs ? 'Tasa de consolidación' : 'Consolidation rate',
                        '${consolidationRate.toStringAsFixed(2)}%',
                      ),
                      _row2(
                        isEs ? 'Plazo' : 'Term',
                        '$termMonths ${isEs ? "meses" : "months"}',
                      ),
                      _row2(
                        isEs ? 'Nuevo pago mensual' : 'New monthly payment',
                        _cur2.format(consolidationPayment),
                        bold: true,
                        color: _purple,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 14),
                pw.Expanded(
                  child: _sectionBox(
                    isEs ? 'RESULTADOS' : 'RESULTS',
                    [
                      _row2(
                        isEs ? 'Pago total actual/mes' : 'Current total/month',
                        _cur2.format(currentTotalPayment),
                      ),
                      _row2(
                        isEs ? 'Interés total actual' : 'Total interest (current)',
                        _cur0.format(totalInterestCurrent),
                      ),
                      _row2(
                        isEs
                            ? 'Interés total consolidado'
                            : 'Total interest (consolidated)',
                        _cur0.format(totalInterestConsolidated),
                      ),
                      pw.Divider(color: PdfColors.grey300, height: 6),
                      _row2(
                        isEs ? 'Ahorro mensual neto' : 'Net monthly savings',
                        _cur2.format(netMonthlySavings),
                        bold: true,
                        color: netMonthlySavings >= 0 ? _purple : PdfColors.red,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            pw.Spacer(),
            _footer(isEs),
          ],
        ),
      ),
    );

    await _sharePdf(context, pdf, 'loan_payoff_consolidation.pdf', isEs);
  }

  // ── 3. Refinance ────────────────────────────────────────────────────────────

  static Future<void> exportRefinance(
    BuildContext context, {
    required double currentBalance,
    required double currentRate,
    required int remainingMonths,
    required double newRate,
    required int newTermMonths,
    required double closingCosts,
    required double currentPayment,
    required double newPayment,
    required double monthlySavings,
    required int breakEvenMonths,
    required double totalSavings,
    bool isEs = false,
  }) async {
    if (!freemiumService.hasFullAccess) {
      await showUnlockOrPay(
        context,
        () => exportRefinance(
          context,
          currentBalance: currentBalance,
          currentRate: currentRate,
          remainingMonths: remainingMonths,
          newRate: newRate,
          newTermMonths: newTermMonths,
          closingCosts: closingCosts,
          currentPayment: currentPayment,
          newPayment: newPayment,
          monthlySavings: monthlySavings,
          breakEvenMonths: breakEvenMonths,
          totalSavings: totalSavings,
          isEs: isEs,
        ),
      );
      return;
    }

    final pdf = _newDoc();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header(
              'Loan Payoff US',
              isEs ? 'Informe de Refinanciamiento' : 'Refinance Report',
              isEs,
            ),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _sectionBox(
                    isEs ? 'PRÉSTAMO ACTUAL' : 'CURRENT LOAN',
                    [
                      _row2(
                        isEs ? 'Saldo actual' : 'Current balance',
                        _cur0.format(currentBalance),
                      ),
                      _row2(
                        isEs ? 'Tasa actual' : 'Current rate',
                        '${currentRate.toStringAsFixed(2)}%',
                      ),
                      _row2(
                        isEs ? 'Meses restantes' : 'Remaining months',
                        '$remainingMonths ${isEs ? "meses" : "months"}',
                      ),
                      _row2(
                        isEs ? 'Pago mensual actual' : 'Current monthly payment',
                        _cur2.format(currentPayment),
                      ),
                      if (closingCosts > 0)
                        _row2(
                          isEs ? 'Costos de cierre' : 'Closing costs',
                          _cur0.format(closingCosts),
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 14),
                pw.Expanded(
                  child: _sectionBox(
                    isEs ? 'NUEVO PRÉSTAMO' : 'NEW LOAN',
                    [
                      _row2(
                        isEs ? 'Nueva tasa' : 'New rate',
                        '${newRate.toStringAsFixed(2)}%',
                      ),
                      _row2(
                        isEs ? 'Nuevo plazo' : 'New term',
                        '$newTermMonths ${isEs ? "meses" : "months"}',
                      ),
                      _row2(
                        isEs ? 'Nuevo pago mensual' : 'New monthly payment',
                        _cur2.format(newPayment),
                        bold: true,
                        color: _purple,
                      ),
                      pw.Divider(color: PdfColors.grey300, height: 6),
                      _row2(
                        isEs ? 'Ahorro mensual' : 'Monthly savings',
                        _cur2.format(monthlySavings),
                        bold: true,
                        color: monthlySavings >= 0 ? _purple : PdfColors.red,
                      ),
                      _row2(
                        isEs ? 'Punto de equilibrio' : 'Break-even',
                        breakEvenMonths > 0
                            ? '$breakEvenMonths ${isEs ? "meses" : "months"}'
                            : 'N/A',
                      ),
                      _row2(
                        isEs ? 'Ahorro total' : 'Total savings',
                        _cur0.format(totalSavings),
                        bold: true,
                        color: totalSavings >= 0 ? _purple : PdfColors.red,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.Spacer(),
            _footer(isEs),
          ],
        ),
      ),
    );

    await _sharePdf(context, pdf, 'loan_payoff_refinance.pdf', isEs);
  }

  // ── 4. Debt Strategy ────────────────────────────────────────────────────────

  static Future<void> exportDebtStrategy(
    BuildContext context, {
    required List<({String name, double balance, double rate, double minPayment})> debts,
    required double extraMonthly,
    required String strategy,
    required List<({String name, int monthPaidOff, double interestPaid})> payoffOrder,
    required int totalMonthsStrategy,
    required double totalInterestStrategy,
    required int totalMonthsMinimum,
    required double totalInterestMinimum,
    bool isEs = false,
  }) async {
    if (!freemiumService.hasFullAccess) {
      await showUnlockOrPay(
        context,
        () => exportDebtStrategy(
          context,
          debts: debts,
          extraMonthly: extraMonthly,
          strategy: strategy,
          payoffOrder: payoffOrder,
          totalMonthsStrategy: totalMonthsStrategy,
          totalInterestStrategy: totalInterestStrategy,
          totalMonthsMinimum: totalMonthsMinimum,
          totalInterestMinimum: totalInterestMinimum,
          isEs: isEs,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final freeOnStrategy = DateTime(now.year, now.month + totalMonthsStrategy);
    final interestSaved = (totalInterestMinimum - totalInterestStrategy)
        .clamp(0.0, double.infinity);

    final pdf = _newDoc();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header(
              'Loan Payoff US',
              isEs ? 'Informe de Estrategia de Deuda' : 'Debt Strategy Report',
              isEs,
            ),

            // Debt list table
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: _navy,
              child: pw.Text(
                isEs ? 'MIS DEUDAS' : 'MY DEBTS',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
              ),
              child: pw.Column(
                children: [
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          isEs ? 'Nombre' : 'Name',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                      pw.SizedBox(
                        width: 72,
                        child: pw.Text(
                          isEs ? 'Saldo' : 'Balance',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                      pw.SizedBox(
                        width: 50,
                        child: pw.Text(
                          isEs ? 'Tasa' : 'Rate',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                      pw.SizedBox(
                        width: 72,
                        child: pw.Text(
                          isEs ? 'Pago mín.' : 'Min. pmt',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.Divider(color: PdfColors.grey300, height: 4),
                  ...debts.map(
                    (d) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      child: pw.Row(
                        children: [
                          pw.Expanded(
                            child: pw.Text(
                              d.name,
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                          ),
                          pw.SizedBox(
                            width: 72,
                            child: pw.Text(
                              _cur0.format(d.balance),
                              textAlign: pw.TextAlign.right,
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                          ),
                          pw.SizedBox(
                            width: 50,
                            child: pw.Text(
                              '${d.rate.toStringAsFixed(2)}%',
                              textAlign: pw.TextAlign.right,
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                          ),
                          pw.SizedBox(
                            width: 72,
                            child: pw.Text(
                              _cur2.format(d.minPayment),
                              textAlign: pw.TextAlign.right,
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 14),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _sectionBox(
                    isEs ? 'CONFIGURACIÓN' : 'SETUP',
                    [
                      _row2(
                        isEs ? 'Estrategia' : 'Strategy',
                        strategy,
                      ),
                      _row2(
                        isEs ? 'Pago extra mensual' : 'Extra monthly payment',
                        _cur2.format(extraMonthly),
                        bold: extraMonthly > 0,
                        color: extraMonthly > 0 ? _purple : null,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 14),
                pw.Expanded(
                  child: _sectionBox(
                    isEs ? 'RESULTADOS' : 'RESULTS',
                    [
                      _row2(
                        isEs ? 'Libre de deudas en' : 'Debt-free in',
                        '${totalMonthsStrategy ~/ 12}y ${totalMonthsStrategy % 12}m  •  ${DateFormat('MMM yyyy').format(freeOnStrategy)}',
                        bold: true,
                        color: _purple,
                      ),
                      _row2(
                        isEs ? 'Interés total (estrategia)' : 'Total interest (strategy)',
                        _cur0.format(totalInterestStrategy),
                      ),
                      _row2(
                        isEs ? 'Interés total (mínimos)' : 'Total interest (minimums)',
                        _cur0.format(totalInterestMinimum),
                      ),
                      if (interestSaved > 0) ...[
                        pw.Divider(color: PdfColors.grey300, height: 6),
                        _row2(
                          isEs ? 'Interés ahorrado' : 'Interest saved',
                          _cur0.format(interestSaved),
                          bold: true,
                          color: _purple,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            if (payoffOrder.isNotEmpty) ...[
              pw.SizedBox(height: 14),
              _sectionBox(
                isEs ? 'ORDEN DE PAGO' : 'PAYOFF ORDER',
                [
                  pw.Row(
                    children: [
                      pw.SizedBox(
                        width: 28,
                        child: pw.Text(
                          '#',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          isEs ? 'Deuda' : 'Debt',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                      pw.SizedBox(
                        width: 80,
                        child: pw.Text(
                          isEs ? 'Fecha de pago' : 'Payoff date',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                      pw.SizedBox(
                        width: 72,
                        child: pw.Text(
                          isEs ? 'Interés pagado' : 'Interest paid',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.Divider(color: PdfColors.grey300, height: 4),
                  ...payoffOrder.asMap().entries.map(
                    (e) {
                      final payoffDate = DateTime(now.year, now.month + e.value.monthPaidOff);
                      return pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 2),
                        child: pw.Row(
                          children: [
                            pw.SizedBox(
                              width: 28,
                              child: pw.Text(
                                '${e.key + 1}',
                                style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold,
                                  color: _purple,
                                ),
                              ),
                            ),
                            pw.Expanded(
                              child: pw.Text(
                                e.value.name,
                                style: const pw.TextStyle(fontSize: 9),
                              ),
                            ),
                            pw.SizedBox(
                              width: 80,
                              child: pw.Text(
                                DateFormat('MMM yyyy').format(payoffDate),
                                textAlign: pw.TextAlign.right,
                                style: const pw.TextStyle(fontSize: 9),
                              ),
                            ),
                            pw.SizedBox(
                              width: 72,
                              child: pw.Text(
                                _cur0.format(e.value.interestPaid),
                                textAlign: pw.TextAlign.right,
                                style: const pw.TextStyle(
                                  fontSize: 9,
                                  color: PdfColors.orange800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],

            pw.Spacer(),
            _footer(isEs),
          ],
        ),
      ),
    );

    await _sharePdf(context, pdf, 'loan_payoff_strategy.pdf', isEs);
  }

  // ── 5. Goals ────────────────────────────────────────────────────────────────

  static Future<void> exportGoals(
    BuildContext context, {
    required double loanAmount,
    required double interestRate,
    required double monthlyPayment,
    required double extraPayment,
    required DateTime? targetDate,
    required double? requiredExtra,
    required int currentPayoffMonths,
    required int monthsSaved,
    required double interestSaved,
    bool isEs = false,
  }) async {
    if (!freemiumService.hasFullAccess) {
      await showUnlockOrPay(
        context,
        () => exportGoals(
          context,
          loanAmount: loanAmount,
          interestRate: interestRate,
          monthlyPayment: monthlyPayment,
          extraPayment: extraPayment,
          targetDate: targetDate,
          requiredExtra: requiredExtra,
          currentPayoffMonths: currentPayoffMonths,
          monthsSaved: monthsSaved,
          interestSaved: interestSaved,
          isEs: isEs,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final payoffDate = DateTime(now.year, now.month + currentPayoffMonths);

    final pdf = _newDoc();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header(
              'Loan Payoff US',
              isEs ? 'Informe de Metas de Pago' : 'Payoff Goals Report',
              isEs,
            ),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _sectionBox(
                    isEs ? 'DETALLES DEL PRÉSTAMO' : 'LOAN DETAILS',
                    [
                      _row2(
                        isEs ? 'Saldo' : 'Loan balance',
                        _cur0.format(loanAmount),
                      ),
                      _row2(
                        isEs ? 'Tasa de interés' : 'Interest rate',
                        '${interestRate.toStringAsFixed(2)}%',
                      ),
                      _row2(
                        isEs ? 'Pago mensual' : 'Monthly payment',
                        _cur2.format(monthlyPayment),
                      ),
                      if (extraPayment > 0)
                        _row2(
                          isEs ? 'Pago extra mensual' : 'Extra monthly payment',
                          _cur2.format(extraPayment),
                          bold: true,
                          color: _purple,
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 14),
                pw.Expanded(
                  child: _sectionBox(
                    isEs ? 'FECHA DE PAGO ACTUAL' : 'CURRENT PAYOFF',
                    [
                      _row2(
                        isEs ? 'Fecha de liquidación' : 'Payoff date',
                        DateFormat('MMMM yyyy').format(payoffDate),
                        bold: true,
                        color: _purple,
                      ),
                      _row2(
                        isEs ? 'Duración' : 'Duration',
                        '${currentPayoffMonths ~/ 12}y ${currentPayoffMonths % 12}m',
                      ),
                      if (monthsSaved > 0) ...[
                        pw.Divider(color: PdfColors.grey300, height: 6),
                        _row2(
                          isEs ? 'Meses ahorrados' : 'Months saved',
                          '$monthsSaved ${isEs ? "meses" : "months"}',
                          bold: true,
                          color: _purple,
                        ),
                        _row2(
                          isEs ? 'Interés ahorrado' : 'Interest saved',
                          _cur0.format(interestSaved),
                          bold: true,
                          color: _purple,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            if (targetDate != null || requiredExtra != null) ...[
              pw.SizedBox(height: 14),
              _sectionBox(
                isEs ? 'META DE PAGO' : 'PAYOFF GOAL',
                [
                  if (targetDate != null)
                    _row2(
                      isEs ? 'Fecha objetivo' : 'Target payoff date',
                      DateFormat('MMMM d, yyyy').format(targetDate),
                      bold: true,
                      color: _purple,
                    ),
                  if (requiredExtra != null)
                    _row2(
                      isEs
                          ? 'Pago extra requerido/mes'
                          : 'Required extra payment/month',
                      _cur2.format(requiredExtra),
                      bold: true,
                      color: requiredExtra <= 0 ? _purple : PdfColors.orange800,
                    ),
                ],
              ),
            ],

            pw.Spacer(),
            _footer(isEs),
          ],
        ),
      ),
    );

    await _sharePdf(context, pdf, 'loan_payoff_goals.pdf', isEs);
  }

  // ── Original entry point (kept for history_detail_screen) ───────────────────

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
