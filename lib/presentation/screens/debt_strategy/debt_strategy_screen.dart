import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/ads/ad_footer.dart';
import '../../../core/engine/debt_strategy_engine.dart';
import '../../../core/db/debt_persistence.dart';
import '../../../domain/models/debt_item.dart';
import '../../../core/language/language_notifier.dart';
import '../../widgets/paywall_soft.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
double _parseNum(String v) {
  if (v.isEmpty) return 0.0;
  final s = (v.contains('.') && v.contains(','))
      ? v.replaceAll(',', '')
      : v.replaceAll(',', '.');
  return double.tryParse(s.trim()) ?? 0.0;
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class DebtStrategyScreen extends StatefulWidget {
  const DebtStrategyScreen({super.key});

  @override
  State<DebtStrategyScreen> createState() => _DebtStrategyScreenState();
}

class _DebtStrategyScreenState extends State<DebtStrategyScreen> {
  final _fmt = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  final _extraCtrl = TextEditingController(text: '0');

  List<DebtItem> _debts = [];

  PayoffStrategy _strategy    = PayoffStrategy.avalanche;
  double         _extra       = 0;
  double         _extraSlider = 0;

  EngineResult? _strategyResult;
  EngineResult? _minimumResult;

  bool _loaded = false;

  static const int _freeDebtLimit = 5;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    isSpanishNotifier.addListener(_onLangChange);
    _loadDebts();
  }

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLangChange);
    _extraCtrl.dispose();
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  Future<void> _loadDebts() async {
    final saved = await DebtPersistence.instance.load();
    if (!mounted) return;
    setState(() {
      _debts  = saved.isNotEmpty
          ? saved
          : [
              const DebtItem(name: 'Credit Card', balance: 5000,  annualRate: 19.99, minPayment: 100),
              const DebtItem(name: 'Auto Loan',   balance: 12000, annualRate: 6.5,   minPayment: 250),
            ];
      _loaded = true;
    });
    _runCalc();
  }

  void _persist() => DebtPersistence.instance.save(_debts);

  void _runCalc() {
    if (_debts.isEmpty) {
      setState(() {
        _strategyResult = null;
        _minimumResult  = null;
      });
      return;
    }
    setState(() {
      _strategyResult = DebtStrategyEngine.run(
        debts:        _debts,
        extraMonthly: _extra,
        strategy:     _strategy,
      );
      _minimumResult = DebtStrategyEngine.runMinimumOnly(_debts);
    });
  }

  // ── Add / Edit debt dialog ─────────────────────────────────────────────────

  Future<void> _showDebtDialog({DebtItem? existing, int? index}) async {
    if (!freemiumService.isPremium &&
        _debts.length >= _freeDebtLimit &&
        existing == null) {
      await PaywallSoft.show(context);
      return;
    }

    final isEs      = isSpanishNotifier.value;
    final nameCtrl  = TextEditingController(text: existing?.name ?? '');
    final balCtrl   = TextEditingController(
        text: existing != null ? existing.balance.toStringAsFixed(0) : '');
    final rateCtrl  = TextEditingController(
        text: existing != null ? existing.annualRate.toStringAsFixed(2) : '');
    final minCtrl   = TextEditingController(
        text: existing != null ? existing.minPayment.toStringAsFixed(0) : '');

    final result = await showModalBottomSheet<DebtItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          top: 20,
          left: 20,
          right: 20,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            existing == null
                ? (isEs ? 'Agregar Deuda'   : 'Add Debt')
                : (isEs ? 'Editar Deuda'    : 'Edit Debt'),
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: AppTheme.primaryDark),
          ),
          const SizedBox(height: 16),
          _field(isEs ? 'Nombre' : 'Name', nameCtrl),
          _field(isEs ? 'Saldo (\$)'      : 'Balance (\$)',     balCtrl,  numeric: true),
          _field(isEs ? 'Tasa Anual (%)' : 'Annual Rate (%)',  rateCtrl, numeric: true),
          _field(isEs ? 'Pago Mínimo (\$)': 'Min Payment (\$)', minCtrl,  numeric: true),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(isEs ? 'Cancelar' : 'Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  final name   = nameCtrl.text.trim();
                  final bal    = _parseNum(balCtrl.text);
                  final rate   = _parseNum(rateCtrl.text);
                  final minPmt = _parseNum(minCtrl.text);
                  if (name.isEmpty || bal <= 0 || minPmt <= 0) return;
                  Navigator.pop(
                    context,
                    DebtItem(
                      name:       name,
                      balance:    bal,
                      annualRate: rate,
                      minPayment: minPmt,
                    ),
                  );
                },
                child: Text(isEs ? 'Guardar' : 'Save'),
              ),
            ),
          ]),
        ]),
      ),
    );

    if (result == null) return;
    setState(() {
      if (index != null) {
        _debts[index] = result;
      } else {
        _debts.add(result);
      }
    });
    _persist();
    _runCalc();
  }

  Widget _field(String label, TextEditingController ctrl,
      {bool numeric = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctrl,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters: numeric
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
              : null,
          textCapitalization: numeric
              ? TextCapitalization.none
              : TextCapitalization.words,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      );

  void _deleteDebt(int index) {
    setState(() => _debts.removeAt(index));
    _persist();
    _runCalc();
  }

  // ── Payoff schedule bottom-sheet (premium-gated) ───────────────────────────

  Future<void> _showSchedule() async {
    if (!freemiumService.isPremium) {
      await PaywallSoft.show(context);
      return;
    }
    if (_strategyResult == null) return;

    final isEs = isSpanishNotifier.value;
    final allocs = _strategyResult!.monthlyAllocations;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => Column(children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(children: [
              const Icon(Icons.calendar_month_rounded, color: AppTheme.primary, size: 18),
              const SizedBox(width: 6),
              Text(
                isEs ? 'Calendario de Pagos' : 'Payment Schedule',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppTheme.primaryDark),
              ),
            ]),
          ),
          const Divider(height: 1),
          // Header row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              _schedHdr(isEs ? 'Mo.' : 'Mo.',   48),
              _schedHdr(isEs ? 'Deuda'   : 'Debt',     0,  flex: true),
              _schedHdr(isEs ? 'Interés' : 'Interest', 70),
              _schedHdr(isEs ? 'Capital' : 'Principal',70),
              _schedHdr(isEs ? 'Saldo'   : 'Balance',  72),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: allocs.length,
              itemBuilder: (_, k) {
                final a    = allocs[k];
                final even = k.isEven;
                return Container(
                  color: even
                      ? Colors.transparent
                      : Theme.of(context).colorScheme.surfaceContainerLowest,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                  child: Row(children: [
                    SizedBox(width: 48,
                        child: Text('${a.month}',
                            style: const TextStyle(fontSize: 11))),
                    Expanded(
                        child: Text(a.debtName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w500))),
                    SizedBox(width: 70,
                        child: Text(_fmt.format(a.interest),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.warning))),
                    SizedBox(width: 70,
                        child: Text(_fmt.format(a.principal),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.accentGood))),
                    SizedBox(width: 72,
                        child: Text(
                            a.endingBalance < 1
                                ? (isEs ? '¡Pagado!' : 'Paid off!')
                                : _fmt.format(a.endingBalance),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: a.endingBalance < 1
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: a.endingBalance < 1
                                    ? AppTheme.accentGood
                                    : null))),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _schedHdr(String t, double w, {bool flex = false}) {
    final child = Text(t,
        textAlign: TextAlign.right,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryDark));
    if (flex) return Expanded(child: child);
    return SizedBox(width: w, child: child);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;

    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final interestSaved = (_minimumResult != null && _strategyResult != null)
        ? (_minimumResult!.totalInterest - _strategyResult!.totalInterest)
            .clamp(0.0, double.infinity)
        : 0.0;

    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Strategy toggle ───────────────────────────────────────────
              _SectionHeader(
                icon:  Icons.account_balance_wallet_rounded,
                title: isEs ? 'Estrategia de Pago' : 'Payoff Strategy',
              ),
              const SizedBox(height: 10),
              SegmentedButton<PayoffStrategy>(
                segments: [
                  ButtonSegment(
                    value: PayoffStrategy.avalanche,
                    label: Text(isEs ? 'Avalancha' : 'Avalanche'),
                    icon: const Icon(Icons.trending_down_rounded),
                  ),
                  ButtonSegment(
                    value: PayoffStrategy.snowball,
                    label: Text(isEs ? 'Bola de Nieve' : 'Snowball'),
                    icon: const Icon(Icons.ac_unit_rounded),
                  ),
                ],
                selected: {_strategy},
                onSelectionChanged: (v) {
                  setState(() => _strategy = v.first);
                  _runCalc();
                },
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppTheme.primary;
                    }
                    return null;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return null;
                  }),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _strategy == PayoffStrategy.avalanche
                    ? (isEs
                        ? 'Paga primero la deuda con la tasa más alta. Ahorra más en intereses.'
                        : 'Pay highest-rate debt first. Saves the most interest.')
                    : (isEs
                        ? 'Paga primero la deuda con el saldo más bajo. Victorias rápidas.'
                        : 'Pay lowest-balance debt first. Quick wins.'),
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55)),
              ),

              const SizedBox(height: 22),

              // ── Debt list ─────────────────────────────────────────────────
              Row(children: [
                _SectionHeader(
                  icon:  Icons.list_alt_rounded,
                  title: isEs ? 'Mis Deudas' : 'My Debts',
                ),
                const Spacer(),
                if (!freemiumService.isPremium)
                  Text(
                    '${_debts.length}/$_freeDebtLimit',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.45)),
                  ),
              ]),
              const SizedBox(height: 8),

              ..._debts.asMap().entries.map((e) => Dismissible(
                    key: ValueKey('${e.value.name}-${e.key}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: AppTheme.dangerRed),
                    ),
                    onDismissed: (_) => _deleteDebt(e.key),
                    child: _DebtTile(
                      debt:     e.value,
                      fmt:      _fmt,
                      onEdit:   () => _showDebtDialog(existing: e.value, index: e.key),
                      onDelete: () => _deleteDebt(e.key),
                    ),
                  )),

              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _showDebtDialog(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(isEs ? 'Agregar Deuda' : 'Add Debt'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  minimumSize: const Size.fromHeight(44),
                ),
              ),

              const SizedBox(height: 22),

              // ── Extra payment ─────────────────────────────────────────────
              Row(children: [
                const Icon(Icons.add_circle_outline,
                    size: 18, color: AppTheme.primary),
                const SizedBox(width: 6),
                Text(
                  isEs ? 'Pago Extra Mensual' : 'Monthly Extra Payment',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppTheme.primaryDark),
                ),
                const Spacer(),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _extraCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                    ],
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      prefixText: '\$',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (v) {
                      final val = _parseNum(v);
                      setState(() {
                        _extra       = val;
                        _extraSlider = val.clamp(0, 1000);
                      });
                      _runCalc();
                    },
                  ),
                ),
              ]),
              Slider(
                value: _extraSlider,
                min: 0, max: 1000,
                divisions: 100,
                label: _fmt.format(_extraSlider),
                activeColor: AppTheme.primary,
                onChanged: (v) {
                  setState(() {
                    _extra       = v;
                    _extraSlider = v;
                    _extraCtrl.text = v.toInt().toString();
                  });
                  _runCalc();
                },
              ),

              const SizedBox(height: 16),

              // ── Results ───────────────────────────────────────────────────
              if (_strategyResult != null && _debts.isNotEmpty) ...[
                _SectionHeader(
                  icon:  Icons.emoji_events_rounded,
                  title: isEs ? 'Resultados' : 'Results',
                ),
                const SizedBox(height: 12),

                // Hero card — debt-free date
                _HeroCard(
                  result:        _strategyResult!,
                  minimumResult: _minimumResult,
                  fmt:           _fmt,
                  isEs:          isEs,
                  interestSaved: interestSaved,
                  extra:         _extra,
                ),
                const SizedBox(height: 14),

                // Bar chart: minimum interest vs strategy interest
                if (_minimumResult != null)
                  _InterestBarChart(
                    minimumInterest:  _minimumResult!.totalInterest,
                    strategyInterest: _strategyResult!.totalInterest,
                    fmt:              _fmt,
                    isEs:             isEs,
                    strategy:         _strategy,
                  ),
                const SizedBox(height: 16),

                // Payoff order
                _SectionHeader(
                  icon:  Icons.sort_rounded,
                  title: isEs ? 'Orden de Pago' : 'Payoff Order',
                ),
                const SizedBox(height: 8),
                ..._strategyResult!.payoffOrder.asMap().entries.map((e) =>
                    _PayoffOrderTile(
                      rank:          e.key + 1,
                      summary:       e.value,
                      fmt:           _fmt,
                      isEs:          isEs,
                    )),

                const SizedBox(height: 16),

                // View schedule button (premium-gated)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _showSchedule,
                    icon: freemiumService.isPremium
                        ? const Icon(Icons.calendar_month_rounded, size: 18)
                        : const Icon(Icons.lock_outline_rounded, size: 18),
                    label: Text(
                      isEs
                          ? (freemiumService.isPremium
                              ? 'Ver Calendario de Pagos'
                              : 'Calendario de Pagos — Premium')
                          : (freemiumService.isPremium
                              ? 'View Payment Schedule'
                              : 'Payment Schedule — Premium'),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: BorderSide(
                          color: freemiumService.isPremium
                              ? AppTheme.primary
                              : AppTheme.primary.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      const AdFooter(),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Hero card
// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  final EngineResult  result;
  final EngineResult? minimumResult;
  final NumberFormat  fmt;
  final bool          isEs;
  final double        interestSaved;
  final double        extra;

  const _HeroCard({
    required this.result,
    required this.minimumResult,
    required this.fmt,
    required this.isEs,
    required this.interestSaved,
    required this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final months   = result.totalMonths;
    final interest = result.totalInterest;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
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
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(children: [
        Text(
          isEs ? 'LIBRE DE DEUDAS EN' : 'DEBT-FREE IN',
          style: const TextStyle(
              color: Colors.white70, fontSize: 12, letterSpacing: 1.2),
        ),
        const SizedBox(height: 6),
        Text(
          '${months ~/ 12}y ${months % 12}m',
          style: const TextStyle(
              color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '${isEs ? "Interés total" : "Total interest"}: ${fmt.format(interest)}',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        if (interestSaved > 0 && extra > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.accentGood.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${isEs ? "Ahorras" : "You save"} ${fmt.format(interestSaved)} '
              '${isEs ? "vs solo mínimos" : "vs minimum-only"}',
              style: const TextStyle(
                  color: AppTheme.accentGood,
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
            ),
          ),
        ],
        if (minimumResult != null &&
            minimumResult!.totalMonths > result.totalMonths) ...[
          const SizedBox(height: 6),
          Text(
            '${result.totalMonths < minimumResult!.totalMonths ? (minimumResult!.totalMonths - result.totalMonths) : 0} '
            '${isEs ? "meses antes que el mínimo" : "months faster than minimum-only"}',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Bar chart — minimum interest vs strategy interest
// ---------------------------------------------------------------------------

class _InterestBarChart extends StatelessWidget {
  final double       minimumInterest;
  final double       strategyInterest;
  final NumberFormat fmt;
  final bool         isEs;
  final PayoffStrategy strategy;

  const _InterestBarChart({
    required this.minimumInterest,
    required this.strategyInterest,
    required this.fmt,
    required this.isEs,
    required this.strategy,
  });

  @override
  Widget build(BuildContext context) {
    final strategyLabel = strategy == PayoffStrategy.avalanche
        ? (isEs ? 'Avalancha' : 'Avalanche')
        : (isEs ? 'Bola de Nieve' : 'Snowball');
    final minLabel = isEs ? 'Solo Mínimos' : 'Minimum Only';
    final saved    = (minimumInterest - strategyInterest).clamp(0.0, double.infinity);
    final maxVal   = minimumInterest * 1.1;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.bar_chart_rounded,
                color: AppTheme.primary, size: 18),
            const SizedBox(width: 6),
            Text(
              isEs ? 'Interés Total: Comparación' : 'Total Interest Comparison',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.primaryDark),
            ),
          ]),
          if (saved > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 24),
              child: Text(
                '${isEs ? "Ahorras" : "You save"} ${fmt.format(saved)}',
                style: const TextStyle(
                    color: AppTheme.accentGood,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                maxY: maxVal,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxVal / 4,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.08),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      getTitlesWidget: (v, _) => Text(
                        fmt.format(v),
                        style: TextStyle(
                            fontSize: 9,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.55)),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (v, _) {
                        final labels = [minLabel, strategyLabel];
                        final i = v.toInt();
                        if (i < 0 || i >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            labels[i],
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.7)),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  BarChartGroupData(x: 0, barRods: [
                    BarChartRodData(
                      toY:   minimumInterest,
                      color: AppTheme.warning.withValues(alpha: 0.8),
                      width: 48,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6)),
                      backDrawRodData: BackgroundBarChartRodData(
                        show:  true,
                        toY:   maxVal,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.04),
                      ),
                    ),
                  ]),
                  BarChartGroupData(x: 1, barRods: [
                    BarChartRodData(
                      toY:   strategyInterest,
                      color: AppTheme.accentGood.withValues(alpha: 0.85),
                      width: 48,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6)),
                      backDrawRodData: BackgroundBarChartRodData(
                        show:  true,
                        toY:   maxVal,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.04),
                      ),
                    ),
                  ]),
                ],
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) =>
                        Theme.of(context).colorScheme.inverseSurface,
                    getTooltipItem: (group, _, rod, __) {
                      final label = group.x == 0 ? minLabel : strategyLabel;
                      return BarTooltipItem(
                        '$label\n${fmt.format(rod.toY)}',
                        TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onInverseSurface,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String   title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 6),
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppTheme.primaryDark)),
      ]);
}

class _DebtTile extends StatelessWidget {
  final DebtItem     debt;
  final NumberFormat fmt;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DebtTile({
    required this.debt,
    required this.fmt,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 1,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.credit_card_rounded,
                color: AppTheme.primary, size: 20),
          ),
          title: Text(debt.name,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Text(
            '${fmt.format(debt.balance)}  •  '
            '${debt.annualRate.toStringAsFixed(2)}%  •  '
            '${fmt.format(debt.minPayment)}/mo',
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55)),
          ),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: AppTheme.primary,
              onPressed: onEdit,
              tooltip: 'Edit',
              constraints:
                  const BoxConstraints(minWidth: 40, minHeight: 40),
              padding: const EdgeInsets.all(8),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              color: AppTheme.dangerRed,
              onPressed: onDelete,
              tooltip: 'Delete',
              constraints:
                  const BoxConstraints(minWidth: 40, minHeight: 40),
              padding: const EdgeInsets.all(8),
            ),
          ]),
        ),
      );
}

class _PayoffOrderTile extends StatelessWidget {
  final int               rank;
  final DebtPayoffSummary summary;
  final NumberFormat      fmt;
  final bool              isEs;

  const _PayoffOrderTile({
    required this.rank,
    required this.summary,
    required this.fmt,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    final colors = [
      AppTheme.accentGood,
      AppTheme.primary,
      AppTheme.warning,
      Colors.teal,
      Colors.indigo,
    ];
    final color = colors[(rank - 1).clamp(0, colors.length - 1)];
    final months = summary.monthPaidOff;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(children: [
        Container(
          width: 26, height: 26,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Center(
            child: Text('$rank',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(summary.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              Text(
                '${isEs ? "Interés" : "Interest"}: ${fmt.format(summary.interestPaid)}',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55)),
              ),
            ],
          ),
        ),
        Text(
          '${months ~/ 12}y ${months % 12}m',
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.bold),
        ),
      ]),
    );
  }
}
