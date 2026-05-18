import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/language/language_notifier.dart';
import '../../../core/db/debt_payment_persistence.dart';
import '../../../domain/models/debt_payment.dart';
import 'package:calcwise_core/calcwise_core.dart';

class PaymentsHistoryScreen extends StatefulWidget {
  const PaymentsHistoryScreen({super.key});

  @override
  State<PaymentsHistoryScreen> createState() => _PaymentsHistoryScreenState();
}

class _PaymentsHistoryScreenState extends State<PaymentsHistoryScreen> {
  final _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: '\$',
    decimalDigits: 2,
  );
  final _date = DateFormat.yMMMd();

  late Future<List<DebtPayment>> _future;

  @override
  void initState() {
    super.initState();
    isSpanishNotifier.addListener(_onLang);
    _future = DebtPaymentPersistence.instance.listAll();
  }

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLang);
    super.dispose();
  }

  void _onLang() => setState(() {});

  Future<void> _refresh() async {
    setState(() {
      _future = DebtPaymentPersistence.instance.listAll();
    });
  }

  Future<void> _delete(int id) async {
    await DebtPaymentPersistence.instance.delete(id);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEs ? 'Historial de Pagos' : 'Payments History'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<DebtPayment>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const <DebtPayment>[];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.payments_rounded,
                      size: 56,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      isEs
                          ? 'Aún no hay pagos registrados.'
                          : 'No payments logged yet.',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) {
                final p = items[i];
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  elevation: 0,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.accentGood.withValues(
                        alpha: 0.15,
                      ),
                      child: const Icon(
                        Icons.payments_rounded,
                        color: AppTheme.accentGood,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      p.debtName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextSize.body,
                      ),
                    ),
                    subtitle: Text(
                      '${_date.format(p.date)}'
                      '${(p.note ?? '').isNotEmpty ? "  •  ${p.note}" : ''}',
                      style: const TextStyle(fontSize: AppTextSize.sm),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _money.format(p.amount),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accentGood,
                            fontSize: AppTextSize.body,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                          color: AppTheme.dangerRed,
                          onPressed: p.id == null ? null : () => _delete(p.id!),
                          tooltip: isEs ? 'Eliminar' : 'Delete',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
