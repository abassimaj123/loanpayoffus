import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ads/ad_footer.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../main.dart' show paywallSession;
import '../../../core/language/language_notifier.dart';
import '../../../domain/models/amortization_entry.dart';
import '../../../domain/models/payoff_result.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../providers/loan_provider.dart';
import '../../widgets/paywall_soft.dart';
import '../../widgets/paywall_hard.dart';

class PayoffPlanScreen extends ConsumerWidget {
  const PayoffPlanScreen({super.key});

  Future<void> _share(BuildContext context, PayoffResult result, bool isEs) async {
    final dynamic s = isEs ? AppStringsES() : AppStringsEN();
    final fmt = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);

    if (!freemiumService.isPremium) {
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

    const sep = '─────────────────────';
    final buf = StringBuffer();
    buf.writeln('Loan Payoff US — ${s.navPayoffPlan}');
    buf.writeln(sep);
    buf.writeln('${s.withoutExtra}');
    buf.writeln('${s.payoff}: ${result.normalMonths ~/ 12}y ${result.normalMonths % 12}m');
    buf.writeln('${s.interest}: ${fmt.format(result.interestNormal)}');
    buf.writeln('${s.totalPaid}: ${fmt.format(result.totalPaidNormal)}');
    if (result.monthsSaved > 0) {
      buf.writeln(sep);
      buf.writeln('${s.withExtraLabel}');
      buf.writeln('${s.payoff}: ${result.extraMonths ~/ 12}y ${result.extraMonths % 12}m');
      buf.writeln('${s.interest}: ${fmt.format(result.interestExtra)}');
      buf.writeln('${s.totalPaid}: ${fmt.format(result.totalPaidExtra)}');
      buf.writeln('${s.saved}: ${fmt.format(result.interestSaved)}');
    }
    buf.writeln(sep);
    buf.write(s.calculatedWith);

    await Share.share(buf.toString(), subject: 'Loan Payoff US — Payoff Plan');
  }

  Future<void> _exportPdf(BuildContext context, PayoffResult result, bool isEs) async {
    final dynamic s = isEs ? AppStringsES() : AppStringsEN();

    if (!freemiumService.isPremium) {
      await PaywallHard.show(context);
      return;
    }

    final fmt     = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
    final fmtInt  = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
    final pdf     = pw.Document();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Loan Payoff US — ${s.navPayoffPlan}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text(DateFormat.yMMMMd().format(DateTime.now()),
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        ],
      ),
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        ],
      ),
      build: (context) => [
        pw.SizedBox(height: 8),

        // ── Summary ──────────────────────────────────────────────────────
        pw.Container(
          decoration: pw.BoxDecoration(
            color: PdfColors.blueGrey50,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          padding: const pw.EdgeInsets.all(12),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(s.withoutExtra,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              pw.SizedBox(height: 6),
              _pdfSummaryRow(s.payoff,     '${result.normalMonths ~/ 12}y ${result.normalMonths % 12}m'),
              _pdfSummaryRow(s.interest,   fmtInt.format(result.interestNormal)),
              _pdfSummaryRow(s.totalPaid,  fmtInt.format(result.totalPaidNormal)),
              if (result.monthsSaved > 0) ...[
                pw.Divider(color: PdfColors.grey400),
                pw.Text(s.withExtraLabel,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.SizedBox(height: 6),
                _pdfSummaryRow(s.payoff,    '${result.extraMonths ~/ 12}y ${result.extraMonths % 12}m'),
                _pdfSummaryRow(s.interest,  fmtInt.format(result.interestExtra)),
                _pdfSummaryRow(s.totalPaid, fmtInt.format(result.totalPaidExtra)),
                _pdfSummaryRow(s.saved,     fmtInt.format(result.interestSaved), highlight: true),
              ],
            ],
          ),
        ),

        pw.SizedBox(height: 16),

        // ── Amortization table ────────────────────────────────────────────
        pw.Text('${s.navPayoffPlan} — Schedule',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
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
              children: ['#', s.payment, s.principal, s.interest, s.balance]
                  .map((h) => _pdfCell(h, header: true))
                  .toList(),
            ),
            ...result.schedule.asMap().entries.map((entry) {
              final i  = entry.key;
              final r  = entry.value;
              final bg = i.isEven ? PdfColors.white : PdfColors.grey50;
              return pw.TableRow(
                decoration: pw.BoxDecoration(color: bg),
                children: [
                  _pdfCell('${r.month}'),
                  _pdfCell(fmt.format(r.payment)),
                  _pdfCell(fmt.format(r.principal)),
                  _pdfCell(fmt.format(r.interest)),
                  _pdfCell(fmtInt.format(r.balance), bold: r.balance < 0.01),
                ],
              );
            }),
          ],
        ),

        pw.SizedBox(height: 16),
        pw.Divider(),
        pw.SizedBox(height: 6),
        pw.Text(s.disclaimer,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        pw.Text(s.calculatedWith,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
      ],
    ));

    await Printing.sharePdf(
      bytes:    await pdf.save(),
      filename: 'loan_payoff_us_plan_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static pw.Widget _pdfSummaryRow(String label, String value,
      {bool highlight = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label,
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
            pw.Text(value,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: highlight ? PdfColors.blue800 : PdfColors.black,
                )),
          ],
        ),
      );

  static pw.Widget _pdfCell(String text, {bool header = false, bool bold = false}) =>
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(payoffResultProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) => _buildContent(context, ref, result, isEs),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, PayoffResult? result, bool isEs) {
    final dynamic s = isEs ? AppStringsES() : AppStringsEN();
    final fmt     = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
    final fmtFull = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);

    if (result == null) {
      return Column(children: [
        Expanded(child: Center(child: Text(s.enterLoan))),
        const AdFooter(),
      ]);
    }

    final schedule   = result.schedule;
    final payoffDate = DateTime.now().add(Duration(days: result.extraMonths * 30));

    // Group schedule into chunks of 12 months
    final groups = <List<AmortizationEntry>>[];
    for (int i = 0; i < schedule.length; i += 12) {
      groups.add(schedule.sublist(i, (i + 12).clamp(0, schedule.length)));
    }

    // ── Balance chart data (sampled every 6 months for performance) ──
    final normalSched = result.normalSchedule;
    final extraSched  = result.schedule;
    final maxMonths   = normalSched.length;
    const step = 6;

    List<FlSpot> normalSpots = [];
    List<FlSpot> extraSpots  = [];
    for (int i = 0; i < maxMonths; i += step) {
      normalSpots.add(FlSpot(i.toDouble(), normalSched[i].balance));
    }
    normalSpots.add(FlSpot(maxMonths.toDouble(), 0));
    for (int i = 0; i < extraSched.length; i += step) {
      extraSpots.add(FlSpot(i.toDouble(), extraSched[i].balance));
    }
    extraSpots.add(FlSpot(extraSched.length.toDouble(), 0));

    final maxBalance = normalSched.isNotEmpty ? normalSched.first.balance + normalSched.first.principal : 1.0;

    return Column(children: [
      // ── Header stats ──
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primary, AppTheme.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _HeaderStat(s.months,   '${result.extraMonths}',          Colors.white),
          _HeaderStat(s.interest, fmt.format(result.interestExtra), Colors.white70),
          _HeaderStat(s.payoff,
            DateFormat('MMM yyyy').format(payoffDate),              AppTheme.accentGood),
        ]),
      ),

      // ── Share / PDF actions ──
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _share(context, result, isEs),
              icon: const Icon(Icons.share_outlined, size: 16),
              label: Text(s.shareLabel, style: const TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 40),
                  padding: const EdgeInsets.symmetric(vertical: 8)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: freemiumService.isPremiumNotifier,
              builder: (_, isPremium, __) => FilledButton.icon(
                onPressed: () => _exportPdf(context, result, isEs),
                icon: isPremium
                    ? const Icon(Icons.picture_as_pdf_outlined, size: 16)
                    : const Icon(Icons.lock_outline, size: 16),
                label: Text(s.exportPdf, style: const TextStyle(fontSize: 13)),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40),
                    padding: const EdgeInsets.symmetric(vertical: 8)),
              ),
            ),
          ),
        ]),
      ),

      // ── Balance over time chart ──
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.balanceChart,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: LineChart(LineChartData(
              minY: 0,
              maxY: maxBalance * 1.05,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots.map((sp) => LineTooltipItem(
                    '\$${(sp.y / 1000).toStringAsFixed(1)}k',
                    const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  )).toList(),
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 56,
                  getTitlesWidget: (v, _) => Text(
                    '\$${(v / 1000).toStringAsFixed(0)}k',
                    style: const TextStyle(fontSize: 9)),
                )),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) {
                    final yr = (v / 12).round();
                    if (yr == 0 || v % 24 != 0) return const SizedBox();
                    return Text('Y$yr', style: const TextStyle(fontSize: 9));
                  },
                )),
                topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: [
                // Normal payoff line
                LineChartBarData(
                  spots: normalSpots,
                  isCurved: true,
                  color: const Color(0xFF94A3B8),
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                ),
                // Extra payment line
                if (extraSpots.length > 1)
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
            )),
          ),
          Row(children: [
            _LegendDot(color: const Color(0xFF94A3B8), label: s.normalLabel),
            const SizedBox(width: 16),
            _LegendDot(color: AppTheme.accentGood, label: s.withExtraLabel),
          ]),
        ]),
      ),

      // ── Accordion list ──
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: groups.length,
          itemBuilder: (context, gi) {
            final group     = groups[gi];
            final firstMo   = group.first.month;
            final lastMo    = group.last.month;
            final isLastGrp = gi == groups.length - 1;

            final yearNum    = gi + 1;
            final totalPrinc = group.fold<double>(0, (sum, e) => sum + e.principal);
            final totalInt   = group.fold<double>(0, (sum, e) => sum + e.interest);
            final totalPmt   = group.fold<double>(0, (sum, e) => sum + e.payment);
            final endBal     = group.last.balance;

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
              fmt: fmt,
              fmtFull: fmtFull,
              s: s,
            );
          },
        ),
      ),
      const AdFooter(),
    ]);
  }
}

// ── Expandable group of 12 months ────────────────────────────────────────────
class _MonthGroup extends StatefulWidget {
  final int    yearNum, firstMonth, lastMonth;
  final double totalPayment, totalPrincipal, totalInterest, endBalance;
  final bool   isLastGroup;
  final List<AmortizationEntry> entries;
  final NumberFormat fmt, fmtFull;
  final dynamic s;

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
    required this.fmt,
    required this.fmtFull,
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
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 220));
    _rot = Tween(begin: 0.0, end: 0.5).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final s           = widget.s;
    final accentColor = widget.isLastGroup ? AppTheme.accentGood : AppTheme.primary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: _expanded ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: accentColor.withValues(alpha: _expanded ? 0.5 : 0.15),
          width: _expanded ? 1.5 : 1,
        ),
      ),
      child: Column(children: [
        // ── Group header (tap to expand) ──
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              // Year badge
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Text(
                  'Y${widget.yearNum}',
                  style: TextStyle(color: accentColor,
                      fontWeight: FontWeight.bold, fontSize: 12),
                )),
              ),
              const SizedBox(width: 12),
              // Month range
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${s.monthLabel} ${widget.firstMonth} – ${widget.lastMonth}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  '${s.balance}: ${widget.fmt.format(widget.endBalance)}',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)),
                ),
              ])),
              // Summary chips
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                _MiniChip(
                  label: widget.fmtFull.format(widget.totalPayment),
                  color: AppTheme.primaryDark,
                ),
                const SizedBox(height: 3),
                _MiniChip(
                  label: '${widget.fmtFull.format(widget.totalInterest)} int',
                  color: AppTheme.warning,
                ),
              ]),
              const SizedBox(width: 6),
              RotationTransition(
                turns: _rot,
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
              ),
            ]),
          ),
        ),

        // ── Expanded rows ──
        if (_expanded) ...[
          const Divider(height: 1, indent: 14, endIndent: 14),
          // Column headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(children: [
              _HCell(s.colMo,      1),
              _HCell(s.payment,    2),
              _HCell(s.principal,  2),
              _HCell(s.interest,   2),
              _HCell(s.balance,    2),
            ]),
          ),
          ...widget.entries.asMap().entries.map((entry) {
            final i    = entry.key;
            final e    = entry.value;
            final last = i == widget.entries.length - 1 && widget.isLastGroup;
            final cs   = Theme.of(context).colorScheme;
            final bg   = last
                ? AppTheme.accentGood.withValues(alpha: 0.08)
                : i % 2 == 0 ? cs.surfaceContainerLow : cs.surface;
            return Container(
              color: bg,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Row(children: [
                _Cell('${e.month}', 1, bold: last),
                _Cell(widget.fmtFull.format(e.payment), 2, bold: last),
                _Cell(widget.fmtFull.format(e.principal), 2, bold: last),
                _Cell(widget.fmtFull.format(e.interest), 2,
                    color: AppTheme.warning),
                _Cell(widget.fmt.format(e.balance), 2, bold: last,
                    color: last ? AppTheme.accentGood : null),
              ]),
            );
          }),
          const SizedBox(height: 4),
        ],
      ]),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────
class _LegendDot extends StatelessWidget {
  final Color  color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: TextStyle(
        fontSize: 10,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        fontWeight: FontWeight.w600)),
  ]);
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color  color;
  const _MiniChip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
  );
}

class _HeaderStat extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _HeaderStat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
    const SizedBox(height: 4),
    Text(value,
      style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
  ]);
}

class _HCell extends StatelessWidget {
  final String text; final int flex;
  const _HCell(this.text, this.flex);
  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(text,
      style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
          fontWeight: FontWeight.bold, fontSize: 10),
      textAlign: TextAlign.right),
  );
}

class _Cell extends StatelessWidget {
  final String text; final int flex;
  final bool bold; final Color? color;
  const _Cell(this.text, this.flex, {this.bold = false, this.color});
  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        color: color),
      textAlign: TextAlign.right),
  );
}
