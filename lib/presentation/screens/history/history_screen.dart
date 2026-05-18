import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/db/database_helper.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/freemium/iap_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/language/language_notifier.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import 'history_detail_screen.dart';
import 'package:calcwise_core/calcwise_core.dart' show CalcwiseAdFooter;
import 'package:calcwise_core/calcwise_core.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _rows = [];
  final _fmt = NumberFormat.currency(
    locale: 'en_US',
    symbol: '\$',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    isSpanishNotifier.addListener(_onLangChange);
    _load();
  }

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLangChange);
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.getHistory();
    if (mounted) setState(() => _rows = rows);
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
    await DatabaseHelper.instance.deleteHistory(id);
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

    return Column(
      children: [
        Expanded(
          child: _rows.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 72,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.15),
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
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: _rows.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) return _buildHeader(s);
                    final row = _rows[i - 1];
                    return _buildCard(row, s);
                  },
                ),
        ),
        const CalcwiseAdFooter(),
      ],
    );
  }

  Widget _buildHeader(AppStrings s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ValueListenableBuilder<bool>(
        valueListenable: freemiumService.isPremiumNotifier,
        builder: (_, isPremium, __) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isPremium
                  ? '${_rows.length} saved'
                  : '${_rows.length} / ${freemiumService.historyLimit} saved',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.55),
                fontSize: AppTextSize.md,
              ),
            ),
            if (!isPremium)
              TextButton.icon(
                onPressed: () => IAPService.instance.buy(),
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

  Widget _buildCard(Map<String, dynamic> row, AppStrings s) {
    final amount = row['loan_amount'] as double;
    final rate = row['interest_rate'] as double;
    final months = row['normal_months'] as int;
    final saved = row['interest_saved'] as double;
    final extra = row['extra_payment'] as double;
    final loanType = row['loan_type'] as String;
    final createdAt = DateTime.tryParse(row['created_at'] as String);
    final dateStr = createdAt != null
        ? DateFormat('MMM d, yyyy • h:mm a').format(createdAt)
        : '';

    return Dismissible(
      key: ValueKey(row['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        margin: const EdgeInsets.only(bottom: AppSpacing.smPlus),
        decoration: BoxDecoration(
          color: AppTheme.dangerRed.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: const Icon(Icons.delete_rounded, color: AppTheme.dangerRed),
      ),
      confirmDismiss: (_) =>
          _delete(row['id'] as int, confirm: true).then((_) => false),
      child: Card(
        margin: const EdgeInsets.only(bottom: AppSpacing.smPlus),
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      loanType,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextSize.bodyMd,
                      ),
                    ),
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
                    _chip('${_fmt.format(amount)}', Icons.attach_money),
                    const SizedBox(width: AppSpacing.sm),
                    _chip('$rate%', Icons.percent),
                    const SizedBox(width: AppSpacing.sm),
                    _chip(
                      '${(months / 12).toStringAsFixed(1)} yrs',
                      Icons.schedule,
                    ),
                  ],
                ),
                if (extra > 0 || saved > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    extra > 0
                        ? '${s.extraSaved}: ${_fmt.format(extra)}/mo → saved ${_fmt.format(saved)}'
                        : '${s.interestLabel}: ${_fmt.format(saved)}',
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
      ),
    );
  }

  Widget _chip(String label, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
    decoration: BoxDecoration(
      color: AppTheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
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
