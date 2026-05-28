import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../core/engine/debt_strategy_engine.dart';
import '../../../core/db/debt_persistence.dart';
import '../../../core/db/debt_payment_persistence.dart';
import '../../../domain/models/debt_item.dart';
import '../../../domain/models/debt_category.dart';
import '../../../domain/models/debt_payment.dart';
import '../../../core/language/language_notifier.dart';
import '../../widgets/paywall_soft.dart';
import 'payments_history_screen.dart';
import 'package:calcwise_core/calcwise_core.dart';

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
  final _extraCtrl = TextEditingController(text: '0');

  // ── Snowflake (one-time windfall) ─────────────────────────────────────────
  final _snowflakeCtrl = TextEditingController();
  final _snowflakeMonthCtrl = TextEditingController(text: '1');
  bool _snowflakeEnabled = false;
  double _snowflakeAmount = 0;
  int _snowflakeMonth = 1;
  EngineResult? _snowflakeResult; // result with snowflake applied

  // ── What-If extra monthly ─────────────────────────────────────────────────
  double _whatIfExtra = 0;
  double _whatIfSlider = 0;
  final _whatIfCtrl = TextEditingController(text: '0');
  EngineResult? _whatIfResult;

  List<DebtItem> _debts = [];

  /// Per-debt-id aggregates loaded from sqlite.
  Map<String, double> _totalPaid = {};
  Map<String, DateTime?> _lastPaid = {};

  // Custom priority reorder
  List<String> _customOrder = []; // debt ids in user-defined order

  PayoffStrategy _strategy = PayoffStrategy.avalanche;
  double _extra = 0;
  double _extraSlider = 0;

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
    _snowflakeCtrl.dispose();
    _snowflakeMonthCtrl.dispose();
    _whatIfCtrl.dispose();
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  Future<void> _loadDebts() async {
    final saved = await DebtPersistence.instance.load();
    if (!mounted) return;
    final initial = saved.isNotEmpty
        ? saved
        : [
            DebtItem.create(
              name: 'Credit Card',
              balance: 5000,
              annualRate: 19.99,
              minPayment: 100,
              category: DebtCategory.creditCard,
            ),
            DebtItem.create(
              name: 'Auto Loan',
              balance: 12000,
              annualRate: 6.5,
              minPayment: 250,
              category: DebtCategory.autoLoan,
            ),
          ];
    setState(() {
      _debts = initial;
      // Restore priority order from saved data
      _customOrder = initial.map((d) => d.id).toList();
      _loaded = true;
    });
    await _refreshPaymentAggregates();
    _runCalc();
  }

  Future<void> _refreshPaymentAggregates() async {
    final paid = <String, double>{};
    final last = <String, DateTime?>{};
    for (final d in _debts) {
      paid[d.id] = await DebtPaymentPersistence.instance.totalForDebt(d.id);
      last[d.id] = await DebtPaymentPersistence.instance.lastPaymentDate(d.id);
    }
    if (!mounted) return;
    setState(() {
      _totalPaid = paid;
      _lastPaid = last;
    });
  }

  void _persist() => DebtPersistence.instance.save(_debts);

  /// Returns debts with `priority` field set according to `_customOrder`.
  List<DebtItem> get _debtsWithPriority {
    if (_strategy != PayoffStrategy.customPriority) return _debts;
    return _debts.map((d) {
      final idx = _customOrder.indexOf(d.id);
      return d.copyWith(priority: idx < 0 ? 999 : idx);
    }).toList();
  }

  void _runCalc() {
    if (_debts.isEmpty) {
      setState(() {
        _strategyResult = null;
        _minimumResult = null;
        _snowflakeResult = null;
        _whatIfResult = null;
      });
      return;
    }

    final debtsForCalc = _debtsWithPriority;

    final snowflake = _snowflakeEnabled && _snowflakeAmount > 0
        ? SnowflakePayment(
            amount: _snowflakeAmount,
            month: _snowflakeMonth.clamp(1, 1200),
          )
        : null;

    setState(() {
      _strategyResult = DebtStrategyEngine.run(
        debts: debtsForCalc,
        extraMonthly: _extra,
        strategy: _strategy,
      );
      _minimumResult = DebtStrategyEngine.runMinimumOnly(debtsForCalc);
      _snowflakeResult = snowflake != null
          ? DebtStrategyEngine.run(
              debts: debtsForCalc,
              extraMonthly: _extra,
              strategy: _strategy,
              snowflake: snowflake,
            )
          : null;
      _whatIfResult = _whatIfExtra > 0
          ? DebtStrategyEngine.run(
              debts: debtsForCalc,
              extraMonthly: _extra + _whatIfExtra,
              strategy: _strategy,
            )
          : null;
    });
  }

  // ── Add / Edit debt dialog ─────────────────────────────────────────────────

  Future<void> _showDebtDialog({DebtItem? existing, int? index}) async {
    if (!freemiumService.hasFullAccess &&
        _debts.length >= _freeDebtLimit &&
        existing == null) {
      await PaywallSoft.show(context);
      return;
    }

    final isEs = isSpanishNotifier.value;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final balCtrl = TextEditingController(
      text: existing != null ? existing.balance.toStringAsFixed(0) : '',
    );
    final rateCtrl = TextEditingController(
      text: existing != null ? existing.annualRate.toStringAsFixed(2) : '',
    );
    final minCtrl = TextEditingController(
      text: existing != null ? existing.minPayment.toStringAsFixed(0) : '',
    );
    DebtCategory selectedCat = existing?.category ?? DebtCategory.creditCard;

    final result = await showModalBottomSheet<DebtItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      sheetCtx,
                    ).colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  existing == null
                      ? (isEs ? 'Agregar Deuda' : 'Add Debt')
                      : (isEs ? 'Editar Deuda' : 'Edit Debt'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextSize.bodyXl,
                    color: AppTheme.primaryDark,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Category chips
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    isEs ? 'Categoría' : 'Category',
                    style: const TextStyle(
                      fontSize: AppTextSize.sm,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: DebtCategory.values.map((c) {
                    final selected = c == selectedCat;
                    return ChoiceChip(
                      avatar: Icon(
                        c.icon,
                        size: 16,
                        color: selected ? Colors.white : c.color,
                      ),
                      label: Text(c.label(isEs)),
                      selected: selected,
                      selectedColor: c.color,
                      backgroundColor: c.color.withValues(alpha: 0.08),
                      labelStyle: TextStyle(
                        fontSize: AppTextSize.sm,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : c.color,
                      ),
                      side: BorderSide(color: c.color.withValues(alpha: 0.4)),
                      onSelected: (v) {
                        if (!v) return;
                        setSheet(() {
                          selectedCat = c;
                          // Auto-fill APR if the field is empty (new debt only).
                          if (existing == null &&
                              rateCtrl.text.trim().isEmpty) {
                            rateCtrl.text = c.defaultApr.toStringAsFixed(2);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.mdPlus),
                _field(isEs ? 'Nombre' : 'Name', nameCtrl),
                _field(
                  isEs ? 'Saldo (\$)' : 'Balance (\$)',
                  balCtrl,
                  numeric: true,
                ),
                _field(
                  isEs ? 'Tasa Anual (%)' : 'Annual Rate (%)',
                  rateCtrl,
                  numeric: true,
                ),
                _field(
                  isEs ? 'Pago Mínimo (\$)' : 'Min Payment (\$)',
                  minCtrl,
                  numeric: true,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        child: Text(isEs ? 'Cancelar' : 'Cancel'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final name = nameCtrl.text.trim();
                          final bal = _parseNum(balCtrl.text);
                          final rate = _parseNum(rateCtrl.text);
                          final minPmt = _parseNum(minCtrl.text);
                          if (name.isEmpty || bal <= 0 || minPmt <= 0) return;
                          Navigator.pop(
                            sheetCtx,
                            existing == null
                                ? DebtItem.create(
                                    name: name,
                                    balance: bal,
                                    annualRate: rate,
                                    minPayment: minPmt,
                                    category: selectedCat,
                                  )
                                : existing.copyWith(
                                    name: name,
                                    balance: bal,
                                    annualRate: rate,
                                    minPayment: minPmt,
                                    category: selectedCat,
                                  ),
                          );
                        },
                        child: Text(isEs ? 'Guardar' : 'Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == null) return;
    final bool isNewDebt = index == null;
    setState(() {
      if (index != null) {
        _debts[index] = result;
      } else {
        _debts.add(result);
        if (!_customOrder.contains(result.id)) {
          _customOrder.add(result.id);
        }
      }
    });
    if (isNewDebt) {
      AnalyticsService.instance.logDebtAdded(
        balance: result.balance,
        rate: result.annualRate,
      );
    }
    _persist();
    await _refreshPaymentAggregates();
    _runCalc();
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
    ),
  );

  void _deleteDebt(int index) {
    setState(() {
      final id = _debts[index].id;
      _debts.removeAt(index);
      _customOrder.remove(id);
    });
    _persist();
    _runCalc();
  }

  // ── Log payment bottom sheet ───────────────────────────────────────────────

  Future<void> _logPayment(DebtItem debt) async {
    final isEs = isSpanishNotifier.value;
    final amountCtrl = TextEditingController(
      text: debt.minPayment > 0 ? debt.minPayment.toStringAsFixed(2) : '',
    );
    final noteCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();

    final saved = await showModalBottomSheet<DebtPayment>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: Theme.of(
                    sheetCtx,
                  ).colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  Icon(
                    debt.category.icon,
                    color: debt.category.color,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      isEs
                          ? 'Registrar Pago — ${debt.name}'
                          : 'Log Payment — ${debt.name}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextSize.bodyLg,
                        color: AppTheme.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _field(
                isEs ? 'Monto (\$)' : 'Amount (\$)',
                amountCtrl,
                numeric: true,
              ),
              // Date picker row
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: sheetCtx,
                    initialDate: selectedDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) setSheet(() => selectedDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.mdPlus,
                    vertical: AppSpacing.mdPlus,
                  ),
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(
                        sheetCtx,
                      ).colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 18,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.smPlus),
                      Text(
                        DateFormat.yMMMd().format(selectedDate),
                        style: const TextStyle(fontSize: AppTextSize.body),
                      ),
                      const Spacer(),
                      Text(
                        isEs ? 'Cambiar' : 'Change',
                        style: const TextStyle(
                          fontSize: AppTextSize.sm,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _field(isEs ? 'Nota (opcional)' : 'Note (optional)', noteCtrl),
              const SizedBox(height: AppSpacing.sm),
              AnimatedSwitcher(
                duration: AppDuration.base,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        child: Text(isEs ? 'Cancelar' : 'Cancel'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(isEs ? 'Guardar' : 'Save'),
                        onPressed: () {
                          final amt = _parseNum(amountCtrl.text);
                          if (amt <= 0) return;
                          Navigator.pop(
                            sheetCtx,
                            DebtPayment(
                              debtId: debt.id,
                              debtName: debt.name,
                              amount: amt,
                              date: selectedDate,
                              note: noteCtrl.text.trim().isEmpty
                                  ? null
                                  : noteCtrl.text.trim(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == null) return;
    await DebtPaymentPersistence.instance.add(saved);
    AnalyticsService.instance.logPaymentLogged(amount: saved.amount);
    await _refreshPaymentAggregates();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isSpanishNotifier.value
              ? 'Pago registrado: ${AmountFormatter.format(saved.amount, 'USD')}'
              : 'Payment logged: ${AmountFormatter.format(saved.amount, 'USD')}',
        ),
        backgroundColor: AppTheme.accentGood,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Payoff schedule bottom-sheet (premium-gated) ───────────────────────────

  Future<void> _showSchedule() async {
    if (!freemiumService.hasFullAccess) {
      AnalyticsService.instance.logPaywallViewed('payment_schedule');
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
        builder: (_, controller) => Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_month_rounded,
                    color: AppTheme.primary,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    isEs ? 'Calendario de Pagos' : 'Payment Schedule',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextSize.bodyLg,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Header row
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  _schedHdr(isEs ? 'Mo.' : 'Mo.', 48),
                  _schedHdr(isEs ? 'Deuda' : 'Debt', 0, flex: true),
                  _schedHdr(isEs ? 'Interés' : 'Interest', 70),
                  _schedHdr(isEs ? 'Capital' : 'Principal', 70),
                  _schedHdr(isEs ? 'Saldo' : 'Balance', 72),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: allocs.length,
                itemBuilder: (_, k) {
                  final a = allocs[k];
                  final even = k.isEven;
                  return Container(
                    color: even
                        ? Colors.transparent
                        : Theme.of(context).colorScheme.surfaceContainerLowest,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: 5,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          child: Text(
                            '${a.month}',
                            style: const TextStyle(fontSize: AppTextSize.xs),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            a.debtName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: AppTextSize.xs,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 70,
                          child: Text(
                            AmountFormatter.format(a.interest, 'USD'),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: AppTextSize.xs,
                              color: AppTheme.warning,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 70,
                          child: Text(
                            AmountFormatter.format(a.principal, 'USD'),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: AppTextSize.xs,
                              color: AppTheme.accentGood,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 72,
                          child: Text(
                            a.endingBalance < 1
                                ? (isEs ? '¡Pagado!' : 'Paid off!')
                                : AmountFormatter.format(a.endingBalance, 'USD'),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: AppTextSize.xs,
                              fontWeight: a.endingBalance < 1
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: a.endingBalance < 1
                                  ? AppTheme.accentGood
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _schedHdr(String t, double w, {bool flex = false}) {
    final child = Text(
      t,
      textAlign: TextAlign.right,
      style: const TextStyle(
        fontSize: AppTextSize.xs,
        fontWeight: FontWeight.bold,
        color: AppTheme.primaryDark,
      ),
    );
    if (flex) return Expanded(child: child);
    return SizedBox(width: w, child: child);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;

    if (!_loaded) {
      return const _DebtStrategySkeleton();
    }

    final interestSaved = (_minimumResult != null && _strategyResult != null)
        ? (_minimumResult!.totalInterest - _strategyResult!.totalInterest)
              .clamp(0.0, double.infinity)
        : 0.0;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Strategy toggle ───────────────────────────────────────────
                _SectionHeader(
                  icon: Icons.account_balance_wallet_rounded,
                  title: isEs ? 'Estrategia de Pago' : 'Payoff Strategy',
                ),
                const SizedBox(height: AppSpacing.smPlus),
                _StrategySelector(
                  selected: _strategy,
                  isEs: isEs,
                  onChanged: (s) {
                    setState(() => _strategy = s);
                    AnalyticsService.instance.logStrategySelected(
                      strategy: s.name,
                    );
                    _runCalc();
                  },
                ),

                const SizedBox(height: AppSpacing.xxl),

                // ── Debt list ─────────────────────────────────────────────────
                Row(
                  children: [
                    _SectionHeader(
                      icon: Icons.list_alt_rounded,
                      title: isEs ? 'Mis Deudas' : 'My Debts',
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: isEs ? 'Historial de Pagos' : 'Payments History',
                      icon: const Icon(Icons.receipt_long_rounded, size: 20),
                      color: AppTheme.primary,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PaymentsHistoryScreen(),
                        ),
                      ),
                    ),
                    if (!freemiumService.hasFullAccess)
                      Text(
                        '${_debts.length}/$_freeDebtLimit',
                        style: TextStyle(
                          fontSize: AppTextSize.sm,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                ..._debts.asMap().entries.map(
                  (e) => Dismissible(
                    key: ValueKey('${e.value.id}-${e.key}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: AppSpacing.lg),
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppTheme.dangerRed,
                      ),
                    ),
                    onDismissed: (_) => _deleteDebt(e.key),
                    child: _DebtTile(
                      debt: e.value,
                      totalPaid: _totalPaid[e.value.id] ?? 0,
                      lastPaid: _lastPaid[e.value.id],
                      isEs: isEs,
                      onEdit: () =>
                          _showDebtDialog(existing: e.value, index: e.key),
                      onDelete: () => _deleteDebt(e.key),
                      onLogPayment: () => _logPayment(e.value),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: () => _showDebtDialog(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(isEs ? 'Agregar Deuda' : 'Add Debt'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.mdPlus),
                    ),
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),

                // ── Custom order drag list ─────────────────────────────────────
                if (_strategy == PayoffStrategy.customPriority &&
                    _debts.length > 1) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      const Icon(
                        Icons.drag_indicator_rounded,
                        size: 16,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        isEs
                            ? 'Arrastra para ordenar prioridad'
                            : 'Drag to set payoff priority',
                        style: const TextStyle(
                          fontSize: AppTextSize.sm,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: (oldIdx, newIdx) {
                      setState(() {
                        // Ensure customOrder has all current debt ids
                        for (final d in _debts) {
                          if (!_customOrder.contains(d.id)) {
                            _customOrder.add(d.id);
                          }
                        }
                        if (newIdx > oldIdx) newIdx--;
                        final id = _customOrder.removeAt(oldIdx);
                        _customOrder.insert(newIdx, id);
                      });
                      _runCalc();
                    },
                    children: [
                      for (final id in _customOrder.where(
                        (id) => _debts.any((d) => d.id == id),
                      ))
                        Builder(
                          key: ValueKey(id),
                          builder: (ctx) {
                            final debt = _debts.firstWhere((d) => d.id == id);
                            final rank =
                                _customOrder
                                    .where((i) => _debts.any((d) => d.id == i))
                                    .toList()
                                    .indexOf(id) +
                                1;
                            return Container(
                              margin: const EdgeInsets.only(
                                bottom: AppSpacing.xs,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.mdPlus,
                                vertical: AppSpacing.smPlus,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.lg,
                                ),
                                border: Border.all(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '$rank',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: AppTextSize.xs,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.smPlus),
                                  Icon(
                                    debt.category.icon,
                                    size: 16,
                                    color: debt.category.color,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      debt.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: AppTextSize.body,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.drag_handle_rounded,
                                    size: 20,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ],

                const SizedBox(height: AppSpacing.xxl),

                // ── Extra payment ─────────────────────────────────────────────
                Row(
                  children: [
                    const Icon(
                      Icons.add_circle_outline,
                      size: 18,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      isEs ? 'Pago Extra Mensual' : 'Monthly Extra Payment',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextSize.bodyMd,
                        color: AppTheme.primaryDark,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _extraCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        textAlign: TextAlign.right,
                        decoration: InputDecoration(
                          prefixText: '\$',
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.mdPlus,
                            ),
                          ),
                        ),
                        onChanged: (v) {
                          final val = _parseNum(v);
                          setState(() {
                            _extra = val;
                            _extraSlider = val.clamp(0, 1000);
                          });
                          _runCalc();
                        },
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _extraSlider,
                  min: 0,
                  max: 1000,
                  divisions: 100,
                  label: AmountFormatter.format(_extraSlider, 'USD'),
                  activeColor: AppTheme.primary,
                  onChanged: (v) {
                    setState(() {
                      _extra = v;
                      _extraSlider = v;
                      _extraCtrl.text = v.toInt().toString();
                    });
                    _runCalc();
                  },
                ),

                const SizedBox(height: AppSpacing.xxl),

                // ── Snowflake (one-time windfall payment) ─────────────────────
                _SectionHeader(
                  icon: Icons.auto_awesome_rounded,
                  title: isEs
                      ? 'Pago Único (Windfall)'
                      : 'Windfall Payment (one-time)',
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  isEs
                      ? 'Aplica un bono, reembolso de impuestos o fondos extra'
                      : 'Apply a bonus, tax refund, or any extra funds',
                  style: TextStyle(
                    fontSize: AppTextSize.sm,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: AppSpacing.smPlus),
                Row(
                  children: [
                    Switch(
                      value: _snowflakeEnabled,
                      activeColor: AppTheme.primary,
                      onChanged: (v) {
                        setState(() => _snowflakeEnabled = v);
                        _runCalc();
                      },
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      isEs ? 'Activar pago único' : 'Enable windfall payment',
                      style: const TextStyle(fontSize: AppTextSize.body),
                    ),
                  ],
                ),
                if (_snowflakeEnabled) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          isEs ? 'Monto (\$)' : 'Windfall Amount (\$)',
                          _snowflakeCtrl,
                          numeric: true,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      SizedBox(
                        width: 110,
                        child: _field(
                          isEs ? 'En el mes' : 'Apply in month',
                          _snowflakeMonthCtrl,
                          numeric: true,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final amt = _parseNum(_snowflakeCtrl.text);
                            final mo =
                                int.tryParse(_snowflakeMonthCtrl.text.trim()) ??
                                1;
                            setState(() {
                              _snowflakeAmount = amt;
                              _snowflakeMonth = mo < 1 ? 1 : mo;
                            });
                            _runCalc();
                          },
                          icon: const Icon(Icons.bolt_rounded, size: 16),
                          label: Text(
                            isEs ? 'Aplicar pago único' : 'Apply Windfall',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: const BorderSide(color: AppTheme.primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.mdPlus,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_snowflakeResult != null && _strategyResult != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _SnowflakeResultBanner(
                      baseline: _strategyResult!,
                      withSnowflake: _snowflakeResult!,
                      snowflakeAmount: _snowflakeAmount,
                      snowflakeMonth: _snowflakeMonth,
                      isEs: isEs,
                    ),
                  ],
                ],

                const SizedBox(height: AppSpacing.xxl),

                // ── What-If extra monthly payment ────────────────────────────
                _SectionHeader(
                  icon: Icons.help_outline_rounded,
                  title: isEs
                      ? '¿Qué pasa si pago más?'
                      : 'What-If Extra Payment',
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  isEs
                      ? '¿Cuánto ahorrarías pagando más cada mes?'
                      : 'How much would you save paying more each month?',
                  style: TextStyle(
                    fontSize: AppTextSize.sm,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: AppSpacing.smPlus),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isEs
                            ? 'Extra por mes adicional'
                            : 'Additional monthly payment',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: AppTextSize.body,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _whatIfCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        textAlign: TextAlign.right,
                        decoration: InputDecoration(
                          prefixText: '\$',
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.mdPlus,
                            ),
                          ),
                        ),
                        onChanged: (v) {
                          final val = _parseNum(v);
                          setState(() {
                            _whatIfExtra = val;
                            _whatIfSlider = val.clamp(0, 500);
                          });
                          _runCalc();
                        },
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _whatIfSlider,
                  min: 0,
                  max: 500,
                  divisions: 50,
                  label: '+${AmountFormatter.format(_whatIfSlider, 'USD')}/mo',
                  activeColor: AppTheme.accentGood,
                  onChanged: (v) {
                    setState(() {
                      _whatIfExtra = v;
                      _whatIfSlider = v;
                      _whatIfCtrl.text = v.toInt().toString();
                    });
                    _runCalc();
                  },
                ),
                if (_whatIfResult != null &&
                    _strategyResult != null &&
                    _whatIfExtra > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _WhatIfComparisonCard(
                    baseline: _strategyResult!,
                    withExtra: _whatIfResult!,
                    extraAmount: _whatIfExtra,
                    isEs: isEs,
                  ),
                ],

                const SizedBox(height: AppSpacing.lg),

                // ── Results ───────────────────────────────────────────────────
                if (_strategyResult != null && _debts.isNotEmpty) ...[
                  _SectionHeader(
                    icon: Icons.emoji_events_rounded,
                    title: isEs ? 'Resultados' : 'Results',
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Hero card — debt-free date
                  AnimatedSwitcher(
                    duration: AppDuration.base,
                    child: Builder(
                      key: ValueKey(_strategyResult!.totalMonths),
                      builder: (context) {
                        final months = _strategyResult!.totalMonths;
                        final interest = _strategyResult!.totalInterest;
                        final now = DateTime.now();
                        final freeOn = DateTime(
                          now.year,
                          now.month + months,
                          now.day,
                        );
                        final dateLabel = DateFormat.yMMM(
                          isEs ? 'es' : 'en',
                        ).format(freeOn);
                        final timeLabel = '${months ~/ 12}y ${months % 12}m';
                        final secondaryLabel = isEs
                            ? 'Libre de deudas: $dateLabel'
                            : 'Debt-free: $dateLabel';
                        return Semantics(
                          label:
                              '${isEs ? "Libre de deudas en" : "Debt-free in"} $timeLabel. ${isEs ? "Interés total" : "Total interest"}: ${AmountFormatter.format(interest, 'USD')}${interestSaved > 0 && _extra > 0 ? ". ${isEs ? "Ahorras" : "You save"} ${AmountFormatter.format(interestSaved, 'USD')}" : ""}',
                          child: CalcwiseHeroCard(
                            label: isEs ? 'LIBRE DE DEUDAS EN' : 'DEBT-FREE IN',
                            value: timeLabel,
                            secondary: secondaryLabel,
                            stats: [
                              (
                                label: isEs
                                    ? 'Interés total'
                                    : 'Total interest',
                                value: AmountFormatter.format(interest, 'USD'),
                              ),
                              if (interestSaved > 0 && _extra > 0)
                                (
                                  label: isEs
                                      ? 'Ahorro vs mínimos'
                                      : 'Saved vs minimum',
                                  value: AmountFormatter.format(interestSaved, 'USD'),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.mdPlus),

                  // Bar chart: minimum interest vs strategy interest
                  if (_minimumResult != null)
                    _InterestBarChart(
                      minimumInterest: _minimumResult!.totalInterest,
                      strategyInterest: _strategyResult!.totalInterest,
                      isEs: isEs,
                      strategy: _strategy,
                    ),
                  const SizedBox(height: AppSpacing.lg),

                  // Payoff order
                  _SectionHeader(
                    icon: Icons.sort_rounded,
                    title: isEs ? 'Orden de Pago' : 'Payoff Order',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ..._strategyResult!.payoffOrder.asMap().entries.map(
                    (e) => _PayoffOrderTile(
                      rank: e.key + 1,
                      summary: e.value,
                      isEs: isEs,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // View schedule button (premium-gated)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _showSchedule,
                      icon: freemiumService.hasFullAccess
                          ? const Icon(Icons.calendar_month_rounded, size: 18)
                          : const Icon(Icons.lock_outline_rounded, size: 18),
                      label: Text(
                        isEs
                            ? (freemiumService.hasFullAccess
                                  ? 'Ver Calendario de Pagos'
                                  : 'Calendario de Pagos — Premium')
                            : (freemiumService.hasFullAccess
                                  ? 'View Payment Schedule'
                                  : 'Payment Schedule — Premium'),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: BorderSide(
                          color: freemiumService.hasFullAccess
                              ? AppTheme.primary
                              : AppTheme.primary.withValues(alpha: 0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.mdPlus),
                        ),
                        minimumSize: const Size.fromHeight(44),
                      ),
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

// ---------------------------------------------------------------------------
// Bar chart — minimum interest vs strategy interest  [_HeroCard removed — replaced by CalcwiseHeroCard]
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Bar chart — minimum interest vs strategy interest
// ---------------------------------------------------------------------------

class _InterestBarChart extends StatelessWidget {
  final double minimumInterest;
  final double strategyInterest;
  final bool isEs;
  final PayoffStrategy strategy;

  const _InterestBarChart({
    required this.minimumInterest,
    required this.strategyInterest,
    required this.isEs,
    required this.strategy,
  });

  @override
  Widget build(BuildContext context) {
    final strategyLabel = _strategyLabel(strategy, isEs);
    final minLabel = isEs ? 'Solo Mínimos' : 'Minimum Only';
    final saved = (minimumInterest - strategyInterest).clamp(
      0.0,
      double.infinity,
    );
    final maxVal = minimumInterest * 1.1;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.bar_chart_rounded,
                  color: AppTheme.primary,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  isEs
                      ? 'Interés Total: Comparación'
                      : 'Total Interest Comparison',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextSize.body,
                    color: AppTheme.primaryDark,
                  ),
                ),
              ],
            ),
            if (saved > 0)
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.xs,
                  left: AppSpacing.xxl,
                ),
                child: Text(
                  '${isEs ? "Ahorras" : "You save"} ${AmountFormatter.format(saved, 'USD')}',
                  style: const TextStyle(
                    color: AppTheme.accentGood,
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextSize.sm,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
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
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.08),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        getTitlesWidget: (v, _) => Text(
                          AmountFormatter.format(v, 'USD'),
                          style: TextStyle(
                            fontSize: AppTextSize.xxs,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.55),
                          ),
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
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Text(
                              labels[i],
                              style: TextStyle(
                                fontSize: AppTextSize.xs,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: minimumInterest,
                          color: AppTheme.warning.withValues(alpha: 0.8),
                          width: 48,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxVal,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.04),
                          ),
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: strategyInterest,
                          color: AppTheme.accentGood.withValues(alpha: 0.85),
                          width: 48,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxVal,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.04),
                          ),
                        ),
                      ],
                    ),
                  ],
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) =>
                          Theme.of(context).colorScheme.inverseSurface,
                      getTooltipItem: (group, _, rod, __) {
                        final label = group.x == 0 ? minLabel : strategyLabel;
                        return BarTooltipItem(
                          '$label\n${AmountFormatter.format(rod.toY, 'USD')}',
                          TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onInverseSurface,
                            fontSize: AppTextSize.xs,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: AppTheme.primary),
      const SizedBox(width: AppSpacing.xs),
      Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: AppTextSize.bodyMd,
          color: AppTheme.primaryDark,
        ),
      ),
    ],
  );
}

class _DebtTile extends StatelessWidget {
  final DebtItem debt;
  final double totalPaid;
  final DateTime? lastPaid;
  final bool isEs;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onLogPayment;

  const _DebtTile({
    required this.debt,
    required this.totalPaid,
    required this.lastPaid,
    required this.isEs,
    required this.onEdit,
    required this.onDelete,
    required this.onLogPayment,
  });

  String _relativeDays(DateTime when) {
    final d = DateTime.now().difference(when).inDays;
    if (d <= 0) return isEs ? 'hoy' : 'today';
    if (d == 1) return isEs ? 'ayer' : 'yesterday';
    return isEs ? 'hace $d días' : '$d days ago';
  }

  @override
  Widget build(BuildContext context) {
    final cat = debt.category;
    final orig = debt.originalBalance <= 0
        ? debt.balance
        : debt.originalBalance;
    final progress = orig <= 0 ? 0.0 : (totalPaid / orig).clamp(0.0, 1.0);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.mdPlus,
          AppSpacing.smPlus,
          AppSpacing.sm,
          AppSpacing.smPlus,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cat.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.mdPlus),
                  ),
                  child: Icon(cat.icon, color: cat.color, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              debt.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: AppTextSize.body,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          // Category chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xxs,
                            ),
                            decoration: BoxDecoration(
                              color: cat.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                AppRadius.mdPlus,
                              ),
                              border: Border.all(
                                color: cat.color.withValues(alpha: 0.4),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              cat.label(isEs),
                              style: TextStyle(
                                fontSize: AppTextSize.xs,
                                fontWeight: FontWeight.w600,
                                color: cat.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        '${AmountFormatter.format(debt.balance, 'USD')}  •  '
                        '${debt.annualRate.toStringAsFixed(2)}%  •  '
                        '${AmountFormatter.format(debt.minPayment, 'USD')}/mo',
                        style: TextStyle(
                          fontSize: AppTextSize.xs,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  color: AppTheme.primary,
                  onPressed: onEdit,
                  tooltip: isEs ? 'Editar' : 'Edit',
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: const EdgeInsets.all(6),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  color: AppTheme.dangerRed,
                  onPressed: onDelete,
                  tooltip: isEs ? 'Eliminar' : 'Delete',
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: const EdgeInsets.all(6),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: cat.color.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(cat.color),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    totalPaid > 0
                        ? '${isEs ? "Pagado" : "Paid"}: ${AmountFormatter.format(totalPaid, 'USD')} / ${AmountFormatter.format(orig, 'USD')}'
                        : (isEs
                              ? 'Sin pagos registrados'
                              : 'No payments logged'),
                    style: TextStyle(
                      fontSize: AppTextSize.xs,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                ),
                if (lastPaid != null)
                  Text(
                    '${isEs ? "Último" : "Last"}: ${_relativeDays(lastPaid!)}',
                    style: TextStyle(
                      fontSize: AppTextSize.xs,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onLogPayment,
                icon: const Icon(Icons.payments_rounded, size: 16),
                label: Text(
                  isEs ? 'Registrar Pago' : 'Log Payment',
                  style: const TextStyle(fontSize: AppTextSize.sm),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accentGood,
                  side: BorderSide(
                    color: AppTheme.accentGood.withValues(alpha: 0.6),
                  ),
                  minimumSize: const Size.fromHeight(34),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayoffOrderTile extends StatelessWidget {
  final int rank;
  final DebtPayoffSummary summary;
  final bool isEs;

  const _PayoffOrderTile({
    required this.rank,
    required this.summary,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    final colors = [
      AppTheme.accentGood,
      AppTheme.primary,
      AppTheme.warning,
      const Color(0xFF009688), // teal — chart accent, no semantic token
      Colors.indigo,
    ];
    final color = colors[(rank - 1).clamp(0, colors.length - 1)];
    final months = summary.monthPaidOff;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.mdPlus,
        vertical: AppSpacing.smPlus,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Center(
              child: Text(
                '$rank',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: AppTextSize.sm,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.smPlus),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: AppTextSize.md,
                  ),
                ),
                Text(
                  '${isEs ? "Interés" : "Interest"}: ${AmountFormatter.format(summary.interestPaid, 'USD')}',
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
          Text(
            '${months ~/ 12}y ${months % 12}m',
            style: TextStyle(
              fontSize: AppTextSize.sm,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Snowflake result banner
// ---------------------------------------------------------------------------

class _SnowflakeResultBanner extends StatelessWidget {
  final EngineResult baseline;
  final EngineResult withSnowflake;
  final double snowflakeAmount;
  final int snowflakeMonth;
  final bool isEs;

  const _SnowflakeResultBanner({
    required this.baseline,
    required this.withSnowflake,
    required this.snowflakeAmount,
    required this.snowflakeMonth,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    DateTime _payoffDate(int months) =>
        DateTime(now.year, now.month + months, now.day);

    final baseDateLabel = DateFormat.yMMM(
      isEs ? 'es' : 'en',
    ).format(_payoffDate(baseline.totalMonths));
    final sfDateLabel = DateFormat.yMMM(
      isEs ? 'es' : 'en',
    ).format(_payoffDate(withSnowflake.totalMonths));
    final monthsSaved = baseline.totalMonths - withSnowflake.totalMonths;
    final interestSaved = (baseline.totalInterest - withSnowflake.totalInterest)
        .clamp(0.0, double.infinity);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppTheme.accentGood.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppTheme.accentGood.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: AppTheme.accentGood,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  isEs
                      ? 'Con ${AmountFormatter.format(snowflakeAmount, 'USD')} en el mes $snowflakeMonth:'
                      : 'With ${AmountFormatter.format(snowflakeAmount, 'USD')} windfall in month $snowflakeMonth:',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextSize.body,
                    color: AppTheme.accentGood,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEs ? 'Sin windfall' : 'Without windfall',
                      style: TextStyle(
                        fontSize: AppTextSize.xs,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                    Text(
                      baseDateLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: AppTextSize.body,
                      ),
                    ),
                    Text(
                      AmountFormatter.format(baseline.totalInterest, 'USD'),
                      style: const TextStyle(
                        fontSize: AppTextSize.sm,
                        color: AppTheme.warning,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: AppTheme.accentGood,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isEs ? 'Con windfall' : 'With windfall',
                      style: const TextStyle(
                        fontSize: AppTextSize.xs,
                        color: AppTheme.accentGood,
                      ),
                    ),
                    Text(
                      sfDateLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextSize.body,
                        color: AppTheme.accentGood,
                      ),
                    ),
                    Text(
                      AmountFormatter.format(withSnowflake.totalInterest, 'USD'),
                      style: const TextStyle(
                        fontSize: AppTextSize.sm,
                        color: AppTheme.accentGood,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (interestSaved > 0 || monthsSaved > 0) ...[
            const Divider(height: AppSpacing.lg),
            Text(
              isEs
                  ? 'Ahorro: ${AmountFormatter.format(interestSaved, 'USD')} en intereses${monthsSaved > 0 ? " · $monthsSaved meses antes" : ""}'
                  : 'Savings: ${AmountFormatter.format(interestSaved, 'USD')} in interest${monthsSaved > 0 ? " · $monthsSaved months sooner" : ""}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.accentGood,
                fontSize: AppTextSize.sm,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// What-If comparison card
// ---------------------------------------------------------------------------

class _WhatIfComparisonCard extends StatelessWidget {
  final EngineResult baseline;
  final EngineResult withExtra;
  final double extraAmount;
  final bool isEs;

  const _WhatIfComparisonCard({
    required this.baseline,
    required this.withExtra,
    required this.extraAmount,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    DateTime _payoffDate(int months) =>
        DateTime(now.year, now.month + months, now.day);

    final baseDateLabel = DateFormat.yMMM(
      isEs ? 'es' : 'en',
    ).format(_payoffDate(baseline.totalMonths));
    final extraDateLabel = DateFormat.yMMM(
      isEs ? 'es' : 'en',
    ).format(_payoffDate(withExtra.totalMonths));
    final interestSaved = (baseline.totalInterest - withExtra.totalInterest)
        .clamp(0.0, double.infinity);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.35)),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.compare_arrows_rounded,
                  color: AppTheme.primary,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    isEs
                        ? '¿Qué pasa si pago +${AmountFormatter.format(extraAmount, 'USD')}/mes?'
                        : 'What if I paid +${AmountFormatter.format(extraAmount, 'USD')}/mo?',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextSize.body,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Side-by-side table
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Current plan column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEs ? 'Plan actual' : 'Current plan',
                        style: TextStyle(
                          fontSize: AppTextSize.xs,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        isEs ? 'Pago libre:' : 'Payoff:',
                        style: const TextStyle(fontSize: AppTextSize.xs),
                      ),
                      Text(
                        baseDateLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: AppTextSize.body,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        isEs ? 'Interés:' : 'Interest:',
                        style: const TextStyle(fontSize: AppTextSize.xs),
                      ),
                      Text(
                        AmountFormatter.format(baseline.totalInterest, 'USD'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: AppTextSize.body,
                          color: AppTheme.warning,
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: AppSpacing.lg),
                // With extra payment column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEs
                            ? 'Con +${AmountFormatter.format(extraAmount, 'USD')}/mes'
                            : 'With +${AmountFormatter.format(extraAmount, 'USD')}/mo',
                        style: const TextStyle(
                          fontSize: AppTextSize.xs,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accentGood,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        isEs ? 'Pago libre:' : 'Payoff:',
                        style: const TextStyle(fontSize: AppTextSize.xs),
                      ),
                      Text(
                        extraDateLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextSize.body,
                          color: AppTheme.accentGood,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        isEs ? 'Interés:' : 'Interest:',
                        style: const TextStyle(fontSize: AppTextSize.xs),
                      ),
                      Text(
                        AmountFormatter.format(withExtra.totalInterest, 'USD'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextSize.body,
                          color: AppTheme.accentGood,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (interestSaved > 0) ...[
              const Divider(height: AppSpacing.lg),
              Row(
                children: [
                  const Icon(
                    Icons.savings_rounded,
                    color: AppTheme.accentGood,
                    size: 16,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      isEs
                          ? 'Ahorros: ${AmountFormatter.format(interestSaved, 'USD')}'
                          : 'Savings: ${AmountFormatter.format(interestSaved, 'USD')}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentGood,
                        fontSize: AppTextSize.body,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Strategy helpers
// ---------------------------------------------------------------------------

String _strategyLabel(PayoffStrategy s, bool isEs) {
  switch (s) {
    case PayoffStrategy.avalanche:
      return isEs ? 'Avalancha' : 'Avalanche';
    case PayoffStrategy.snowball:
      return isEs ? 'Bola de Nieve' : 'Snowball';
    case PayoffStrategy.highestPayment:
      return isEs ? 'Pago Más Alto Primero' : 'Highest Payment First';
    case PayoffStrategy.highestBalance:
      return isEs ? 'Deuda Más Grande Primero' : 'Largest Debt First';
    case PayoffStrategy.customPriority:
      return isEs ? 'Orden Personalizado' : 'Custom Order';
  }
}

String _strategyDesc(PayoffStrategy s, bool isEs) {
  switch (s) {
    case PayoffStrategy.avalanche:
      return isEs
          ? 'Paga primero la deuda con la tasa más alta. Ahorra más en intereses.'
          : 'Pay highest-rate debt first. Saves the most interest.';
    case PayoffStrategy.snowball:
      return isEs
          ? 'Paga primero la deuda con el saldo más bajo. Victorias rápidas.'
          : 'Pay lowest-balance debt first. Quick wins.';
    case PayoffStrategy.highestPayment:
      return isEs
          ? 'Libera flujo de efectivo más rápido.'
          : 'Free up cash flow faster.';
    case PayoffStrategy.highestBalance:
      return isEs
          ? 'Enfócate en tu deuda más grande.'
          : 'Focus on your biggest debt.';
    case PayoffStrategy.customPriority:
      return isEs
          ? 'Tú decides la prioridad. Arrastra las deudas para ordenarlas.'
          : 'You decide the priority. Drag debts to reorder.';
  }
}

IconData _strategyIcon(PayoffStrategy s) {
  switch (s) {
    case PayoffStrategy.avalanche:
      return Icons.trending_down_rounded;
    case PayoffStrategy.snowball:
      return Icons.ac_unit_rounded;
    case PayoffStrategy.highestPayment:
      return Icons.payments_rounded;
    case PayoffStrategy.highestBalance:
      return Icons.account_balance_rounded;
    case PayoffStrategy.customPriority:
      return Icons.drag_indicator_rounded;
  }
}

class _StrategySelector extends StatelessWidget {
  final PayoffStrategy selected;
  final bool isEs;
  final ValueChanged<PayoffStrategy> onChanged;

  const _StrategySelector({
    required this.selected,
    required this.isEs,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Compact dropdown card
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () async {
            final picked = await showModalBottomSheet<PayoffStrategy>(
              context: context,
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    for (final s in PayoffStrategy.values)
                      ListTile(
                        leading: Icon(
                          _strategyIcon(s),
                          color: s == selected
                              ? AppTheme.primary
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        title: Text(
                          _strategyLabel(s, isEs),
                          style: TextStyle(
                            fontWeight: s == selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: s == selected ? AppTheme.primary : null,
                          ),
                        ),
                        subtitle: Text(
                          _strategyDesc(s, isEs),
                          style: TextStyle(
                            fontSize: AppTextSize.xs,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                        trailing: s == selected
                            ? const Icon(
                                Icons.check_rounded,
                                color: AppTheme.primary,
                              )
                            : null,
                        onTap: () => Navigator.pop(context, s),
                      ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            );
            if (picked != null) onChanged(picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.mdPlus,
              vertical: AppSpacing.smPlus,
            ),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _strategyIcon(selected),
                  size: 20,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: AppSpacing.smPlus),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _strategyLabel(selected, isEs),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextSize.body,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                      Text(
                        _strategyDesc(selected, isEs),
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
                const Icon(Icons.expand_more_rounded, color: AppTheme.primary),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton loading placeholder for DebtStrategyScreen
// ---------------------------------------------------------------------------
class _DebtStrategySkeleton extends StatefulWidget {
  const _DebtStrategySkeleton();
  @override
  State<_DebtStrategySkeleton> createState() => _DebtStrategySkeletonState();
}

class _DebtStrategySkeletonState extends State<_DebtStrategySkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _shimmer({double? width, required double height}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE8E8E8);
    final shine = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5);
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Color.lerp(base, shine, _anim.value),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero card placeholder
          _shimmer(height: 100),
          const SizedBox(height: AppSpacing.xxl),
          // Section title placeholder
          _shimmer(width: 140, height: 14),
          const SizedBox(height: AppSpacing.lg),
          // Debt tiles
          for (int i = 0; i < 3; i++) ...[
            _shimmer(height: 72),
            const SizedBox(height: AppSpacing.md),
          ],
          // Extra payment row placeholder
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _shimmer(width: 160, height: 14),
              _shimmer(width: 80, height: 14),
            ],
          ),
        ],
      ),
    );
  }
}
