import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../language/language_notifier.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../theme/app_theme.dart';
import '../../main.dart';
import '../freemium/freemium_service.dart';
import '../../presentation/widgets/paywall_hard.dart';
import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard;
import '../firebase/analytics_service.dart';

const _purple = PdfColor(0.290, 0.196, 0.784); // LoanPayoff purple
const _navy = PdfColor(0.059, 0.137, 0.353);
const _light = PdfColor(0.949, 0.941, 0.996);

// ── Params classes (only sendable types: primitives + TypedData) ────────────

class _CalculatorPdfParams {
  final double loanBalance;
  final double interestRate;
  final double monthlyPayment;
  final double extraPayment;
  final int monthsWithout;
  final int monthsWith;
  final double interestWithout;
  final double interestWith;
  final double interestSaved;
  final int monthsSaved;
  final bool isEs;
  final int nowYear;
  final int nowMonth;

  const _CalculatorPdfParams({
    required this.loanBalance,
    required this.interestRate,
    required this.monthlyPayment,
    required this.extraPayment,
    required this.monthsWithout,
    required this.monthsWith,
    required this.interestWithout,
    required this.interestWith,
    required this.interestSaved,
    required this.monthsSaved,
    required this.isEs,
    required this.nowYear,
    required this.nowMonth,
  });
}

class _ConsolidationLoanEntry {
  final double balance;
  final double rate;
  final double payment;
  const _ConsolidationLoanEntry(this.balance, this.rate, this.payment);
}

class _ConsolidationPdfParams {
  final List<_ConsolidationLoanEntry> loans;
  final double consolidationRate;
  final int termMonths;
  final double currentTotalPayment;
  final double consolidationPayment;
  final double totalInterestCurrent;
  final double totalInterestConsolidated;
  final double netMonthlySavings;
  final bool isEs;

  const _ConsolidationPdfParams({
    required this.loans,
    required this.consolidationRate,
    required this.termMonths,
    required this.currentTotalPayment,
    required this.consolidationPayment,
    required this.totalInterestCurrent,
    required this.totalInterestConsolidated,
    required this.netMonthlySavings,
    required this.isEs,
  });
}

class _RefinancePdfParams {
  final double currentBalance;
  final double currentRate;
  final int remainingMonths;
  final double newRate;
  final int newTermMonths;
  final double closingCosts;
  final double currentPayment;
  final double newPayment;
  final double monthlySavings;
  final int breakEvenMonths;
  final double totalSavings;
  final bool isEs;

  const _RefinancePdfParams({
    required this.currentBalance,
    required this.currentRate,
    required this.remainingMonths,
    required this.newRate,
    required this.newTermMonths,
    required this.closingCosts,
    required this.currentPayment,
    required this.newPayment,
    required this.monthlySavings,
    required this.breakEvenMonths,
    required this.totalSavings,
    required this.isEs,
  });
}

class _DebtEntry {
  final String name;
  final double balance;
  final double rate;
  final double minPayment;
  const _DebtEntry(this.name, this.balance, this.rate, this.minPayment);
}

class _PayoffOrderEntry {
  final String name;
  final int monthPaidOff;
  final double interestPaid;
  const _PayoffOrderEntry(this.name, this.monthPaidOff, this.interestPaid);
}

class _DebtStrategyPdfParams {
  final List<_DebtEntry> debts;
  final double extraMonthly;
  final String strategy;
  final List<_PayoffOrderEntry> payoffOrder;
  final int totalMonthsStrategy;
  final double totalInterestStrategy;
  final int totalMonthsMinimum;
  final double totalInterestMinimum;
  final bool isEs;
  final int nowYear;
  final int nowMonth;

  const _DebtStrategyPdfParams({
    required this.debts,
    required this.extraMonthly,
    required this.strategy,
    required this.payoffOrder,
    required this.totalMonthsStrategy,
    required this.totalInterestStrategy,
    required this.totalMonthsMinimum,
    required this.totalInterestMinimum,
    required this.isEs,
    required this.nowYear,
    required this.nowMonth,
  });
}

class _GoalsPdfParams {
  final double loanAmount;
  final double interestRate;
  final double monthlyPayment;
  final double extraPayment;
  final int? targetDateYear;
  final int? targetDateMonth;
  final int? targetDateDay;
  final double? requiredExtra;
  final int currentPayoffMonths;
  final int monthsSaved;
  final double interestSaved;
  final bool isEs;
  final int nowYear;
  final int nowMonth;

  const _GoalsPdfParams({
    required this.loanAmount,
    required this.interestRate,
    required this.monthlyPayment,
    required this.extraPayment,
    required this.targetDateYear,
    required this.targetDateMonth,
    required this.targetDateDay,
    required this.requiredExtra,
    required this.currentPayoffMonths,
    required this.monthsSaved,
    required this.interestSaved,
    required this.isEs,
    required this.nowYear,
    required this.nowMonth,
  });
}

// ── Shared PDF helpers (top-level, isolate-safe) ─────────────────────────────

final _cur2Isolate = NumberFormat.currency(
  locale: 'en_US',
  symbol: '\$',
  decimalDigits: 2,
);
final _cur0Isolate = NumberFormat.currency(
  locale: 'en_US',
  symbol: '\$',
  decimalDigits: 0,
);
final _dateIsolate = DateFormat('MMMM d, yyyy');

pw.Widget _buildPayoffChartIsolate({
  required int monthsWithExtra,
  required int monthsWithoutExtra,
  required bool isEs,
}) {
  final maxMonths = monthsWithoutExtra.toDouble();
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
                _legendDotIsolate(
                  _navy,
                  '${isEs ? 'Sin extra' : 'No Extra'} · ${yrLabel(monthsWithoutExtra)}',
                ),
                pw.SizedBox(width: 18),
                _legendDotIsolate(
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

pw.Widget _legendDotIsolate(PdfColor color, String label) => pw.Row(
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

pw.Widget _sectionBoxIsolate(String title, List<pw.Widget> rows) => pw.Column(
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

pw.Widget _row2Isolate(
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

pw.Widget _headerIsolate(String title, String subtitle, bool isEs, int nowYear, int nowMonth) {
  final now = DateTime(nowYear, nowMonth);
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
            _dateIsolate.format(DateTime.now()),
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

pw.Widget _footerIsolate(bool isEs) => pw.Column(
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

// ── Top-level isolate build functions ────────────────────────────────────────

Future<Uint8List> _buildCalculatorPdf(_CalculatorPdfParams p) async {
  await initializeDateFormatting(); // worker isolate: load locale date symbols
  final now = DateTime(p.nowYear, p.nowMonth);
  final payoffDateWithout = DateTime(p.nowYear, p.nowMonth + p.monthsWithout);
  final payoffDateWith = p.extraPayment > 0
      ? DateTime(p.nowYear, p.nowMonth + p.monthsWith)
      : null;

  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _headerIsolate(
            'Loan Payoff US',
            p.isEs ? 'Informe de Pago del Préstamo' : 'Loan Payoff Report',
            p.isEs,
            p.nowYear,
            p.nowMonth,
          ),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _sectionBoxIsolate(
                  p.isEs ? 'DETALLES DEL PRÉSTAMO' : 'LOAN DETAILS',
                  [
                    _row2Isolate(
                      p.isEs ? 'Saldo del préstamo' : 'Loan balance',
                      _cur0Isolate.format(p.loanBalance),
                    ),
                    _row2Isolate(
                      p.isEs ? 'Tasa de interés' : 'Interest rate',
                      '${p.interestRate.toStringAsFixed(2)}%',
                    ),
                    _row2Isolate(
                      p.isEs ? 'Pago mensual' : 'Monthly payment',
                      _cur2Isolate.format(p.monthlyPayment),
                    ),
                    if (p.extraPayment > 0)
                      _row2Isolate(
                        p.isEs ? 'Pago extra' : 'Extra payment',
                        _cur2Isolate.format(p.extraPayment),
                        bold: true,
                        color: _purple,
                      ),
                  ],
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: _sectionBoxIsolate(
                  p.isEs ? 'RESULTADOS DE PAGO' : 'PAYOFF RESULTS',
                  [
                    _row2Isolate(
                      p.isEs ? 'Sin pago extra' : 'Without extra',
                      '${p.monthsWithout ~/ 12}y ${p.monthsWithout % 12}m  •  ${DateFormat('MMM yyyy', p.isEs ? 'es' : 'en').format(payoffDateWithout)}',
                    ),
                    _row2Isolate(
                      p.isEs ? 'Interés sin extra' : 'Interest (no extra)',
                      _cur0Isolate.format(p.interestWithout),
                    ),
                    if (p.extraPayment > 0 && payoffDateWith != null) ...[
                      pw.Divider(color: PdfColors.grey300, height: 6),
                      _row2Isolate(
                        p.isEs ? 'Con pago extra' : 'With extra payment',
                        '${p.monthsWith ~/ 12}y ${p.monthsWith % 12}m  •  ${DateFormat('MMM yyyy', p.isEs ? 'es' : 'en').format(payoffDateWith)}',
                        bold: true,
                        color: _purple,
                      ),
                      _row2Isolate(
                        p.isEs ? 'Interés con extra' : 'Interest (with extra)',
                        _cur0Isolate.format(p.interestWith),
                      ),
                      _row2Isolate(
                        p.isEs ? 'Interés ahorrado' : 'Interest saved',
                        _cur0Isolate.format(p.interestSaved),
                        bold: true,
                        color: _purple,
                      ),
                      _row2Isolate(
                        p.isEs ? 'Meses ahorrados' : 'Months saved',
                        '${p.monthsSaved} ${p.isEs ? "meses" : "months"}',
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
          if (p.extraPayment > 0)
            _buildPayoffChartIsolate(
              monthsWithExtra: p.monthsWith,
              monthsWithoutExtra: p.monthsWithout,
              isEs: p.isEs,
            ),
          pw.Spacer(),
          _footerIsolate(p.isEs),
        ],
      ),
    ),
  );
  return pdf.save();
}

Future<Uint8List> _buildConsolidationPdf(_ConsolidationPdfParams p) async {
  await initializeDateFormatting(); // worker isolate: load locale date symbols
  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _headerIsolate(
            'Loan Payoff US',
            p.isEs
                ? 'Informe de Consolidación de Deudas'
                : 'Debt Consolidation Report',
            p.isEs,
            DateTime.now().year,
            DateTime.now().month,
          ),

          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: _navy,
            child: pw.Text(
              p.isEs ? 'DEUDAS ACTUALES' : 'CURRENT DEBTS',
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
                        p.isEs ? 'Deuda' : 'Debt',
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
                        p.isEs ? 'Saldo' : 'Balance',
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
                        p.isEs ? 'Tasa' : 'Rate',
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
                        p.isEs ? 'Pago/mes' : 'Payment/mo',
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
                ...p.loans.asMap().entries.map(
                  (e) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Text(
                            '${p.isEs ? "Deuda" : "Debt"} ${e.key + 1}',
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                        ),
                        pw.SizedBox(
                          width: 80,
                          child: pw.Text(
                            _cur0Isolate.format(e.value.balance),
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
                            _cur2Isolate.format(e.value.payment),
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
                child: _sectionBoxIsolate(
                  p.isEs ? 'PRÉSTAMO CONSOLIDADO' : 'CONSOLIDATION LOAN',
                  [
                    _row2Isolate(
                      p.isEs ? 'Tasa de consolidación' : 'Consolidation rate',
                      '${p.consolidationRate.toStringAsFixed(2)}%',
                    ),
                    _row2Isolate(
                      p.isEs ? 'Plazo' : 'Term',
                      '${p.termMonths} ${p.isEs ? "meses" : "months"}',
                    ),
                    _row2Isolate(
                      p.isEs ? 'Nuevo pago mensual' : 'New monthly payment',
                      _cur2Isolate.format(p.consolidationPayment),
                      bold: true,
                      color: _purple,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: _sectionBoxIsolate(
                  p.isEs ? 'RESULTADOS' : 'RESULTS',
                  [
                    _row2Isolate(
                      p.isEs ? 'Pago total actual/mes' : 'Current total/month',
                      _cur2Isolate.format(p.currentTotalPayment),
                    ),
                    _row2Isolate(
                      p.isEs ? 'Interés total actual' : 'Total interest (current)',
                      _cur0Isolate.format(p.totalInterestCurrent),
                    ),
                    _row2Isolate(
                      p.isEs
                          ? 'Interés total consolidado'
                          : 'Total interest (consolidated)',
                      _cur0Isolate.format(p.totalInterestConsolidated),
                    ),
                    pw.Divider(color: PdfColors.grey300, height: 6),
                    _row2Isolate(
                      p.isEs ? 'Ahorro mensual neto' : 'Net monthly savings',
                      _cur2Isolate.format(p.netMonthlySavings),
                      bold: true,
                      color: p.netMonthlySavings >= 0 ? _purple : PdfColors.red,
                    ),
                  ],
                ),
              ),
            ],
          ),

          pw.Spacer(),
          _footerIsolate(p.isEs),
        ],
      ),
    ),
  );
  return pdf.save();
}

Future<Uint8List> _buildRefinancePdf(_RefinancePdfParams p) async {
  await initializeDateFormatting(); // worker isolate: load locale date symbols
  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _headerIsolate(
            'Loan Payoff US',
            p.isEs ? 'Informe de Refinanciamiento' : 'Refinance Report',
            p.isEs,
            DateTime.now().year,
            DateTime.now().month,
          ),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _sectionBoxIsolate(
                  p.isEs ? 'PRÉSTAMO ACTUAL' : 'CURRENT LOAN',
                  [
                    _row2Isolate(
                      p.isEs ? 'Saldo actual' : 'Current balance',
                      _cur0Isolate.format(p.currentBalance),
                    ),
                    _row2Isolate(
                      p.isEs ? 'Tasa actual' : 'Current rate',
                      '${p.currentRate.toStringAsFixed(2)}%',
                    ),
                    _row2Isolate(
                      p.isEs ? 'Meses restantes' : 'Remaining months',
                      '${p.remainingMonths} ${p.isEs ? "meses" : "months"}',
                    ),
                    _row2Isolate(
                      p.isEs ? 'Pago mensual actual' : 'Current monthly payment',
                      _cur2Isolate.format(p.currentPayment),
                    ),
                    if (p.closingCosts > 0)
                      _row2Isolate(
                        p.isEs ? 'Costos de cierre' : 'Closing costs',
                        _cur0Isolate.format(p.closingCosts),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: _sectionBoxIsolate(
                  p.isEs ? 'NUEVO PRÉSTAMO' : 'NEW LOAN',
                  [
                    _row2Isolate(
                      p.isEs ? 'Nueva tasa' : 'New rate',
                      '${p.newRate.toStringAsFixed(2)}%',
                    ),
                    _row2Isolate(
                      p.isEs ? 'Nuevo plazo' : 'New term',
                      '${p.newTermMonths} ${p.isEs ? "meses" : "months"}',
                    ),
                    _row2Isolate(
                      p.isEs ? 'Nuevo pago mensual' : 'New monthly payment',
                      _cur2Isolate.format(p.newPayment),
                      bold: true,
                      color: _purple,
                    ),
                    pw.Divider(color: PdfColors.grey300, height: 6),
                    _row2Isolate(
                      p.isEs ? 'Ahorro mensual' : 'Monthly savings',
                      _cur2Isolate.format(p.monthlySavings),
                      bold: true,
                      color: p.monthlySavings >= 0 ? _purple : PdfColors.red,
                    ),
                    _row2Isolate(
                      p.isEs ? 'Punto de equilibrio' : 'Break-even',
                      p.breakEvenMonths > 0
                          ? '${p.breakEvenMonths} ${p.isEs ? "meses" : "months"}'
                          : 'N/A',
                    ),
                    _row2Isolate(
                      p.isEs ? 'Ahorro total' : 'Total savings',
                      _cur0Isolate.format(p.totalSavings),
                      bold: true,
                      color: p.totalSavings >= 0 ? _purple : PdfColors.red,
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.Spacer(),
          _footerIsolate(p.isEs),
        ],
      ),
    ),
  );
  return pdf.save();
}

Future<Uint8List> _buildDebtStrategyPdf(_DebtStrategyPdfParams p) async {
  await initializeDateFormatting(); // worker isolate: load locale date symbols
  final now = DateTime(p.nowYear, p.nowMonth);
  final freeOnStrategy = DateTime(p.nowYear, p.nowMonth + p.totalMonthsStrategy);
  final interestSaved = (p.totalInterestMinimum - p.totalInterestStrategy)
      .clamp(0.0, double.infinity);

  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _headerIsolate(
            'Loan Payoff US',
            p.isEs ? 'Informe de Estrategia de Deuda' : 'Debt Strategy Report',
            p.isEs,
            p.nowYear,
            p.nowMonth,
          ),

          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: _navy,
            child: pw.Text(
              p.isEs ? 'MIS DEUDAS' : 'MY DEBTS',
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
                        p.isEs ? 'Nombre' : 'Name',
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
                        p.isEs ? 'Saldo' : 'Balance',
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
                        p.isEs ? 'Tasa' : 'Rate',
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
                        p.isEs ? 'Pago mín.' : 'Min. pmt',
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
                ...p.debts.map(
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
                            _cur0Isolate.format(d.balance),
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
                            _cur2Isolate.format(d.minPayment),
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
                child: _sectionBoxIsolate(
                  p.isEs ? 'CONFIGURACIÓN' : 'SETUP',
                  [
                    _row2Isolate(
                      p.isEs ? 'Estrategia' : 'Strategy',
                      p.strategy,
                    ),
                    _row2Isolate(
                      p.isEs ? 'Pago extra mensual' : 'Extra monthly payment',
                      _cur2Isolate.format(p.extraMonthly),
                      bold: p.extraMonthly > 0,
                      color: p.extraMonthly > 0 ? _purple : null,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: _sectionBoxIsolate(
                  p.isEs ? 'RESULTADOS' : 'RESULTS',
                  [
                    _row2Isolate(
                      p.isEs ? 'Libre de deudas en' : 'Debt-free in',
                      '${p.totalMonthsStrategy ~/ 12}y ${p.totalMonthsStrategy % 12}m  •  ${DateFormat('MMM yyyy', p.isEs ? 'es' : 'en').format(freeOnStrategy)}',
                      bold: true,
                      color: _purple,
                    ),
                    _row2Isolate(
                      p.isEs ? 'Interés total (estrategia)' : 'Total interest (strategy)',
                      _cur0Isolate.format(p.totalInterestStrategy),
                    ),
                    _row2Isolate(
                      p.isEs ? 'Interés total (mínimos)' : 'Total interest (minimums)',
                      _cur0Isolate.format(p.totalInterestMinimum),
                    ),
                    if (interestSaved > 0) ...[
                      pw.Divider(color: PdfColors.grey300, height: 6),
                      _row2Isolate(
                        p.isEs ? 'Interés ahorrado' : 'Interest saved',
                        _cur0Isolate.format(interestSaved),
                        bold: true,
                        color: _purple,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          if (p.payoffOrder.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _sectionBoxIsolate(
              p.isEs ? 'ORDEN DE PAGO' : 'PAYOFF ORDER',
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
                        p.isEs ? 'Deuda' : 'Debt',
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
                        p.isEs ? 'Fecha de pago' : 'Payoff date',
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
                        p.isEs ? 'Interés pagado' : 'Interest paid',
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
                ...p.payoffOrder.asMap().entries.map(
                  (e) {
                    final payoffDate = DateTime(p.nowYear, p.nowMonth + e.value.monthPaidOff);
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
                              DateFormat('MMM yyyy', p.isEs ? 'es' : 'en').format(payoffDate),
                              textAlign: pw.TextAlign.right,
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                          ),
                          pw.SizedBox(
                            width: 72,
                            child: pw.Text(
                              _cur0Isolate.format(e.value.interestPaid),
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
          _footerIsolate(p.isEs),
        ],
      ),
    ),
  );
  return pdf.save();
}

Future<Uint8List> _buildGoalsPdf(_GoalsPdfParams p) async {
  await initializeDateFormatting(); // worker isolate: load locale date symbols
  final payoffDate = DateTime(p.nowYear, p.nowMonth + p.currentPayoffMonths);
  final targetDate = (p.targetDateYear != null && p.targetDateMonth != null && p.targetDateDay != null)
      ? DateTime(p.targetDateYear!, p.targetDateMonth!, p.targetDateDay!)
      : null;

  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _headerIsolate(
            'Loan Payoff US',
            p.isEs ? 'Informe de Metas de Pago' : 'Payoff Goals Report',
            p.isEs,
            p.nowYear,
            p.nowMonth,
          ),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _sectionBoxIsolate(
                  p.isEs ? 'DETALLES DEL PRÉSTAMO' : 'LOAN DETAILS',
                  [
                    _row2Isolate(
                      p.isEs ? 'Saldo' : 'Loan balance',
                      _cur0Isolate.format(p.loanAmount),
                    ),
                    _row2Isolate(
                      p.isEs ? 'Tasa de interés' : 'Interest rate',
                      '${p.interestRate.toStringAsFixed(2)}%',
                    ),
                    _row2Isolate(
                      p.isEs ? 'Pago mensual' : 'Monthly payment',
                      _cur2Isolate.format(p.monthlyPayment),
                    ),
                    if (p.extraPayment > 0)
                      _row2Isolate(
                        p.isEs ? 'Pago extra mensual' : 'Extra monthly payment',
                        _cur2Isolate.format(p.extraPayment),
                        bold: true,
                        color: _purple,
                      ),
                  ],
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: _sectionBoxIsolate(
                  p.isEs ? 'FECHA DE PAGO ACTUAL' : 'CURRENT PAYOFF',
                  [
                    _row2Isolate(
                      p.isEs ? 'Fecha de liquidación' : 'Payoff date',
                      DateFormat('MMMM yyyy', p.isEs ? 'es' : 'en').format(payoffDate),
                      bold: true,
                      color: _purple,
                    ),
                    _row2Isolate(
                      p.isEs ? 'Duración' : 'Duration',
                      '${p.currentPayoffMonths ~/ 12}y ${p.currentPayoffMonths % 12}m',
                    ),
                    if (p.monthsSaved > 0) ...[
                      pw.Divider(color: PdfColors.grey300, height: 6),
                      _row2Isolate(
                        p.isEs ? 'Meses ahorrados' : 'Months saved',
                        '${p.monthsSaved} ${p.isEs ? "meses" : "months"}',
                        bold: true,
                        color: _purple,
                      ),
                      _row2Isolate(
                        p.isEs ? 'Interés ahorrado' : 'Interest saved',
                        _cur0Isolate.format(p.interestSaved),
                        bold: true,
                        color: _purple,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          if (targetDate != null || p.requiredExtra != null) ...[
            pw.SizedBox(height: 14),
            _sectionBoxIsolate(
              p.isEs ? 'META DE PAGO' : 'PAYOFF GOAL',
              [
                if (targetDate != null)
                  _row2Isolate(
                    p.isEs ? 'Fecha objetivo' : 'Target payoff date',
                    DateFormat('MMMM d, yyyy', p.isEs ? 'es' : 'en').format(targetDate),
                    bold: true,
                    color: _purple,
                  ),
                if (p.requiredExtra != null)
                  _row2Isolate(
                    p.isEs
                        ? 'Pago extra requerido/mes'
                        : 'Required extra payment/month',
                    _cur2Isolate.format(p.requiredExtra!),
                    bold: true,
                    color: p.requiredExtra! <= 0 ? _purple : PdfColors.orange800,
                  ),
              ],
            ),
          ],

          pw.Spacer(),
          _footerIsolate(p.isEs),
        ],
      ),
    ),
  );
  return pdf.save();
}

// ── PdfExportService ─────────────────────────────────────────────────────────

class PdfExportService {
  // ── Shared helpers ──────────────────────────────────────────────────────────

  static Future<void> _sharePdf(
    BuildContext context,
    Uint8List bytes,
    String filename,
    bool isEs,
  ) async {
    try {
      await Printing.sharePdf(bytes: bytes, filename: filename);
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
    final params = _CalculatorPdfParams(
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
      nowYear: now.year,
      nowMonth: now.month,
    );

    final bytes = await Isolate.run(() => _buildCalculatorPdf(params));
    if (context.mounted) {
      await _sharePdf(context, bytes, 'loan_payoff_calculator.pdf', isEs);
    }
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

    final params = _ConsolidationPdfParams(
      loans: loans.map((l) => _ConsolidationLoanEntry(l.balance, l.rate, l.payment)).toList(),
      consolidationRate: consolidationRate,
      termMonths: termMonths,
      currentTotalPayment: currentTotalPayment,
      consolidationPayment: consolidationPayment,
      totalInterestCurrent: totalInterestCurrent,
      totalInterestConsolidated: totalInterestConsolidated,
      netMonthlySavings: netMonthlySavings,
      isEs: isEs,
    );

    final bytes = await Isolate.run(() => _buildConsolidationPdf(params));
    if (context.mounted) {
      await _sharePdf(context, bytes, 'loan_payoff_consolidation.pdf', isEs);
    }
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

    final params = _RefinancePdfParams(
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
    );

    final bytes = await Isolate.run(() => _buildRefinancePdf(params));
    if (context.mounted) {
      await _sharePdf(context, bytes, 'loan_payoff_refinance.pdf', isEs);
    }
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
    final params = _DebtStrategyPdfParams(
      debts: debts.map((d) => _DebtEntry(d.name, d.balance, d.rate, d.minPayment)).toList(),
      extraMonthly: extraMonthly,
      strategy: strategy,
      payoffOrder: payoffOrder.map((e) => _PayoffOrderEntry(e.name, e.monthPaidOff, e.interestPaid)).toList(),
      totalMonthsStrategy: totalMonthsStrategy,
      totalInterestStrategy: totalInterestStrategy,
      totalMonthsMinimum: totalMonthsMinimum,
      totalInterestMinimum: totalInterestMinimum,
      isEs: isEs,
      nowYear: now.year,
      nowMonth: now.month,
    );

    final bytes = await Isolate.run(() => _buildDebtStrategyPdf(params));
    if (context.mounted) {
      await _sharePdf(context, bytes, 'loan_payoff_strategy.pdf', isEs);
    }
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
    final params = _GoalsPdfParams(
      loanAmount: loanAmount,
      interestRate: interestRate,
      monthlyPayment: monthlyPayment,
      extraPayment: extraPayment,
      targetDateYear: targetDate?.year,
      targetDateMonth: targetDate?.month,
      targetDateDay: targetDate?.day,
      requiredExtra: requiredExtra,
      currentPayoffMonths: currentPayoffMonths,
      monthsSaved: monthsSaved,
      interestSaved: interestSaved,
      isEs: isEs,
      nowYear: now.year,
      nowMonth: now.month,
    );

    final bytes = await Isolate.run(() => _buildGoalsPdf(params));
    if (context.mounted) {
      await _sharePdf(context, bytes, 'loan_payoff_goals.pdf', isEs);
    }
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
                AnalyticsService.instance.logPaywallShown('hard');
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
