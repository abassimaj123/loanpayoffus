// Wrapper over DatabaseHelper for the debt_payments table.

import '../../domain/models/debt_payment.dart';
import 'database_helper.dart';

class DebtPaymentPersistence {
  DebtPaymentPersistence._();
  static final DebtPaymentPersistence instance = DebtPaymentPersistence._();

  Future<int> add(DebtPayment p) =>
      DatabaseHelper.instance.insertDebtPayment(p.toMap());

  Future<List<DebtPayment>> listAll() async {
    final rows = await DatabaseHelper.instance.getDebtPayments();
    return rows.map(DebtPayment.fromMap).toList();
  }

  Future<List<DebtPayment>> listForDebt(String debtId) async {
    final rows = await DatabaseHelper.instance.getDebtPayments(debtId: debtId);
    return rows.map(DebtPayment.fromMap).toList();
  }

  Future<double> totalForDebt(String debtId) =>
      DatabaseHelper.instance.sumDebtPayments(debtId);

  Future<DateTime?> lastPaymentDate(String debtId) =>
      DatabaseHelper.instance.latestPaymentDate(debtId);

  Future<void> delete(int id) => DatabaseHelper.instance.deleteDebtPayment(id);

  Future<void> clearAll() => DatabaseHelper.instance.clearDebtPayments();
}
