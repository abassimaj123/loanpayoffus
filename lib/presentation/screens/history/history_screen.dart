import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/ads/ad_footer.dart';
import '../../../core/db/database_helper.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/freemium/iap_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/language/language_notifier.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import 'history_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _rows = [];
  final _fmt = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);

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

  Future<void> _delete(int id) async {
    await DatabaseHelper.instance.deleteHistory(id);
    _load();
  }

  Future<void> _clearAll(dynamic s) async {
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.clearAll, style: const TextStyle(color: Colors.white)),
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
    final dynamic s = isEs ? AppStringsES() : AppStringsEN();

    return Column(children: [
      Expanded(child: _rows.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.history, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(s.historyEmpty,
              style: TextStyle(color: Colors.grey.shade500)),
          ]))
        : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _rows.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) return _buildHeader(s);
              final row = _rows[i - 1];
              return _buildCard(row, s);
            },
          ),
      ),
      const AdFooter(),
    ]);
  }

  Widget _buildHeader(dynamic s) {
    final isPremium = freemiumService.isPremium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: freemiumService.isPremiumNotifier,
            builder: (_, isPrem, __) => Text(
              isPrem
                ? '${_rows.length} saved'
                : '${_rows.length} / ${freemiumService.historyLimit} saved',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
          if (!isPremium)
            TextButton.icon(
              onPressed: () => IAPService.instance.buy(),
              icon: const Icon(Icons.star_outline, size: 14),
              label: Text(s.unlockUnlimited,
                  style: const TextStyle(fontSize: 12)),
            )
          else if (_rows.isNotEmpty)
            TextButton(
              onPressed: () => _clearAll(s),
              child: Text(s.clearAll,
                  style: const TextStyle(fontSize: 12, color: Colors.red)),
            ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> row, dynamic s) {
    final amount     = row['loan_amount'] as double;
    final rate       = row['interest_rate'] as double;
    final months     = row['normal_months'] as int;
    final saved      = row['interest_saved'] as double;
    final extra      = row['extra_payment'] as double;
    final loanType   = row['loan_type'] as String;
    final createdAt  = DateTime.tryParse(row['created_at'] as String);
    final dateStr    = createdAt != null
        ? DateFormat('MMM d, yyyy • h:mm a').format(createdAt)
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => HistoryDetailScreen(entry: row)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(loanType,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.chevron_right,
                    size: 18, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                  onPressed: () => _delete(row['id'] as int),
                ),
              ]),
            ]),
            const SizedBox(height: 4),
            Text(dateStr,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
            const SizedBox(height: 10),
            Row(children: [
              _chip('${_fmt.format(amount)}', Icons.attach_money),
              const SizedBox(width: 8),
              _chip('$rate%', Icons.percent),
              const SizedBox(width: 8),
              _chip('${(months / 12).toStringAsFixed(1)} yrs', Icons.schedule),
            ]),
            if (extra > 0 || saved > 0) ...[
              const SizedBox(height: 8),
              Text(
                extra > 0
                  ? '${s.extraSaved}: ${_fmt.format(extra)}/mo → saved ${_fmt.format(saved)}'
                  : '${s.interestLabel}: ${_fmt.format(saved)}',
                style: const TextStyle(
                    color: AppTheme.accentGood,
                    fontWeight: FontWeight.w600,
                    fontSize: 12),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _chip(String label, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppTheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: AppTheme.primary),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.primary)),
    ]),
  );
}
