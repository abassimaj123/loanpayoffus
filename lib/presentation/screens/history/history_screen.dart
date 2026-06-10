import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../../../core/db/database_helper.dart';
import '../../../core/firebase/analytics_service.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/language/language_notifier.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../../main.dart' show smartHistoryService, historyRefreshNotifier;
import 'history_detail_screen.dart';
import '../../widgets/paywall_hard.dart';
import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard;

enum _CardAction { unpin, rename, delete }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('history');
    isSpanishNotifier.addListener(_onLangChange);
    historyRefreshNotifier.addListener(_silentRefresh);
    _load();
  }

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLangChange);
    historyRefreshNotifier.removeListener(_silentRefresh);
    super.dispose();
  }

  void _onLangChange() => setState(() {});
  void _silentRefresh() => _load();

  Future<void> _load() async {
    if (mounted && !_loading) setState(() => _loading = true);
    final rows = await DatabaseHelper.instance.getHistory();
    if (mounted) {
      setState(() {
        _rows = rows;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _pinned =>
      _rows.where((r) => (r['is_pinned'] as int? ?? 0) == 1).toList();

  List<Map<String, dynamic>> get _autoSaves =>
      _rows.where((r) => (r['is_pinned'] as int? ?? 0) == 0).toList();

  List<Map<String, dynamic>> get _visibleAutoSaves {
    if (freemiumService.hasFullAccess) return _autoSaves;
    return _autoSaves.take(MonetizationConfig.freeRingBufferSize).toList();
  }

  Future<void> _delete(int id, {bool confirm = true}) async {
    if (confirm) {
      final isEs = isSpanishNotifier.value;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(isEs ? 'Eliminar entrada' : 'Delete entry'),
          content: Text(
            isEs
                ? '¿Eliminar este cálculo del historial?'
                : 'Remove this calculation from history?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(isEs ? 'Cancelar' : 'Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                isEs ? 'Eliminar' : 'Delete',
                style: const TextStyle(color: AppTheme.dangerRed),
              ),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await smartHistoryService.delete(id);
    _load();
  }

  Future<void> _unpin(int id) async {
    await smartHistoryService.unpin(id);
    _load();
  }

  Future<void> _rename(Map<String, dynamic> row) async {
    final isEs = isSpanishNotifier.value;
    final ctrl = TextEditingController(
      text: (row['pin_label'] as String?) ?? '',
    );
    final label = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEs ? 'Renombrar escenario' : 'Rename scenario'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: isEs ? 'Nombre del escenario' : 'Scenario name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isEs ? 'Cancelar' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: Text(isEs ? 'Guardar' : 'Save'),
          ),
        ],
      ),
    );
    if (label == null) return;
    await smartHistoryService.rename(row['id'] as int, label.trim());
    _load();
  }

  Future<void> _clearAll(AppStrings s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.clearHistory),
        content: Text(s.clearHistoryMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerRed,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              s.clearAll,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseHelper.instance.clearHistory();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;
    final AppStrings s = isEs ? AppStringsES() : AppStringsEN();
    final pinned = _pinned;
    final autoSaves = _visibleAutoSaves;

    return CalcwisePageEntrance(
        child: Column(
      children: [
        Expanded(
          child: _loading
              ? const _HistorySkeleton()
              : _rows.isEmpty
              ? _buildEmpty(isEs, s)
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader(isEs, s)),
                    if (pinned.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: _sectionHeader(
                          isEs ? 'Escenarios guardados' : 'Saved Scenarios',
                          Icons.bookmark_rounded,
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              0,
                              AppSpacing.md,
                              AppSpacing.smPlus,
                            ),
                            child: _buildCard(pinned[i], s, pinned: true),
                          ),
                          childCount: pinned.length,
                        ),
                      ),
                    ],
                    if (autoSaves.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: _sectionHeader(
                          isEs ? 'Cálculos recientes' : 'Recent Calculations',
                          Icons.history_rounded,
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final row = autoSaves[i];
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.md,
                                0,
                                AppSpacing.md,
                                AppSpacing.smPlus,
                              ),
                              child: Dismissible(
                                key: ValueKey('hist_${row['id']}'),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(
                                    right: AppSpacing.xl,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.dangerRed.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.xl,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.delete_rounded,
                                    color: AppTheme.dangerRed,
                                  ),
                                ),
                                confirmDismiss: (_) => _delete(
                                  row['id'] as int,
                                  confirm: true,
                                ).then((_) => false),
                                child: _buildCard(row, s, pinned: false),
                              ),
                            );
                          },
                          childCount: autoSaves.length,
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.lg),
                    ),
                  ],
                ),
        ),
        const CalcwiseAdFooter(),
      ],
    ));
  }

  Widget _buildEmpty(bool isEs, AppStrings s) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_rounded,
            size: 72,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            s.historyEmpty,
            style: TextStyle(
              fontSize: AppTextSize.bodyMd,
              fontWeight: FontWeight.w500,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            isEs
                ? 'Calcula un préstamo para guardar aquí'
                : 'Calculate a loan to save it here',
            style: TextStyle(
              fontSize: AppTextSize.sm,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isEs, AppStrings s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: ValueListenableBuilder<bool>(
        valueListenable: freemiumService.hasFullAccessNotifier,
        builder: (_, isPremium, __) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isPremium
                  ? (isEs
                        ? '${_rows.length} guardados'
                        : '${_rows.length} saved')
                  : '${_autoSaves.length} / ${MonetizationConfig.freeRingBufferSize} ${isEs ? 'guardados' : 'saved'}',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.55),
                fontSize: AppTextSize.md,
              ),
            ),
            if (!isPremium)
              TextButton.icon(
                onPressed: () => PaywallHard.show(context),
                icon: const Icon(Icons.star_outline, size: 14),
                label: Text(
                  s.unlockUnlimited,
                  style: const TextStyle(fontSize: AppTextSize.sm),
                ),
              )
            else if (_rows.isNotEmpty)
              TextButton(
                onPressed: () => _clearAll(s),
                child: Text(
                  s.clearAll,
                  style: const TextStyle(
                    fontSize: AppTextSize.sm,
                    color: AppTheme.dangerRed,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.primary),
          const SizedBox(width: 5),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: AppTextSize.xs,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(
    Map<String, dynamic> row,
    AppStrings s, {
    required bool pinned,
  }) {
    final isEs = isSpanishNotifier.value;
    final amount = (row['loan_amount'] as num).toDouble();
    final rate = (row['interest_rate'] as num).toDouble();
    final months = (row['normal_months'] as num).toInt();
    final saved = (row['interest_saved'] as num).toDouble();
    final extra = (row['extra_payment'] as num).toDouble();
    final loanType = row['loan_type'] as String;
    final pinLabel = row['pin_label'] as String?;
    final createdAt = DateTime.tryParse(row['created_at'] as String);
    final dateStr = createdAt != null
        ? DateFormat('MMM d, yyyy').format(createdAt)
        : '';
    final id = row['id'] as int;
    final title = pinned && pinLabel != null && pinLabel.isNotEmpty
        ? pinLabel
        : loanType;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: pinned
            ? BorderSide(color: AppTheme.primary.withValues(alpha: 0.5), width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => HistoryDetailScreen(entry: row),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: AppDuration.base,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.mdPlus),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (pinned) ...[
                    const Icon(
                      Icons.bookmark_rounded,
                      size: 16,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextSize.bodyMd,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (pinned)
                    SizedBox(
                      height: 28,
                      width: 32,
                      child: PopupMenuButton<_CardAction>(
                        icon: Icon(
                          Icons.more_vert_rounded,
                          size: 18,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        padding: EdgeInsets.zero,
                        onSelected: (action) {
                          switch (action) {
                            case _CardAction.unpin:
                              _unpin(id);
                            case _CardAction.rename:
                              _rename(row);
                            case _CardAction.delete:
                              _delete(id);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: _CardAction.unpin,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.bookmark_remove_outlined,
                                  size: 18,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(isEs ? 'Desfijar' : 'Unpin'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: _CardAction.rename,
                            child: Row(
                              children: [
                                const Icon(Icons.edit_outlined, size: 18),
                                const SizedBox(width: AppSpacing.sm),
                                Text(isEs ? 'Renombrar' : 'Rename'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: _CardAction.delete,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: AppTheme.dangerRed,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  isEs ? 'Eliminar' : 'Delete',
                                  style: const TextStyle(
                                    color: AppTheme.dangerRed,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.35),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                dateStr,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.45),
                  fontSize: AppTextSize.xs,
                ),
              ),
              const SizedBox(height: AppSpacing.smPlus),
              Row(
                children: [
                  _chip(AmountFormatter.ui(amount, 'USD'), Icons.attach_money),
                  const SizedBox(width: AppSpacing.sm),
                  _chip('$rate%', Icons.percent),
                  const SizedBox(width: AppSpacing.sm),
                  _chip(
                    '${(months / 12).toStringAsFixed(1)} ${isEs ? 'años' : 'yrs'}',
                    Icons.schedule,
                  ),
                ],
              ),
              if (extra > 0 || saved > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  extra > 0
                      ? '${s.extraSaved}: ${AmountFormatter.ui(extra, 'USD')}/mo → ${isEs ? 'ahorro' : 'saved'} ${AmountFormatter.ui(saved, 'USD')}'
                      : '${s.interestLabel}: ${AmountFormatter.ui(saved, 'USD')}',
                  style: const TextStyle(
                    color: AppTheme.accentGood,
                    fontWeight: FontWeight.w600,
                    fontSize: AppTextSize.sm,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: AppTheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppRadius.xxl),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppTheme.primary),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: const TextStyle(
            fontSize: AppTextSize.sm,
            color: AppTheme.primary,
          ),
        ),
      ],
    ),
  );
}

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: List.generate(
          3,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.smPlus),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.mdPlus),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CalcwiseSkeleton.line(width: 100, height: 18),
                        const Spacer(),
                        CalcwiseSkeleton.line(width: 60, height: 14),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.smPlus),
                    CalcwiseSkeleton.line(width: 140, height: 12),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        CalcwiseSkeleton.line(width: 72, height: 24),
                        const SizedBox(width: AppSpacing.sm),
                        CalcwiseSkeleton.line(width: 52, height: 24),
                        const SizedBox(width: AppSpacing.sm),
                        CalcwiseSkeleton.line(width: 64, height: 24),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
