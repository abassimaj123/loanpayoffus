import 'package:flutter_test/flutter_test.dart';
import 'package:loan_payoff_us/core/services/backup_service.dart';
import 'package:loan_payoff_us/domain/models/debt_category.dart';

/// Pure-parse coverage for [BackupService.parse]. No DB / SharedPreferences:
/// parsing is side-effect free, so these run without any platform mocking.
void main() {
  const validCsv = '#LOAN_PAYOFF_US_BACKUP,v1\n'
      '#DEBTS\n'
      'id,name,balance,original_balance,annual_rate,min_payment,category,priority\n'
      'd1,Credit Card,5000,6000,19.99,100,credit_card,0\n'
      'd2,Auto Loan,12000,15000,6.5,250,auto_loan,1\n'
      '#PAYMENTS\n'
      'debt_id,debt_name,amount,date_iso,note\n'
      'd1,Credit Card,200,2026-01-15T00:00:00.000,Jan payment\n'
      'd2,Auto Loan,250,2026-02-01T00:00:00.000,\n';

  test('parses a well-formed backup with debts and payments', () {
    final r = BackupService.instance.parse(validCsv);
    expect(r.isValid, isTrue);
    expect(r.errorCode, isNull);
    expect(r.skippedRows, 0);

    expect(r.debts.length, 2);
    final d1 = r.debts.first;
    expect(d1.id, 'd1');
    expect(d1.name, 'Credit Card');
    expect(d1.balance, 5000);
    expect(d1.originalBalance, 6000);
    expect(d1.annualRate, 19.99);
    expect(d1.minPayment, 100);
    expect(d1.category, DebtCategory.creditCard);
    expect(d1.priority, 0);

    expect(r.payments.length, 2);
    expect(r.payments.first.debtId, 'd1');
    expect(r.payments.first.amount, 200);
    expect(r.payments.first.note, 'Jan payment');
    // Empty note becomes null.
    expect(r.payments[1].note, isNull);
  });

  test('empty input -> empty', () {
    expect(BackupService.instance.parse('').errorCode, 'empty');
    expect(BackupService.instance.parse('   \n  ').errorCode, 'empty');
  });

  test('missing magic marker -> not_backup', () {
    final r = BackupService.instance.parse('foo,bar\n1,2\n');
    expect(r.isValid, isFalse);
    expect(r.errorCode, 'not_backup');
  });

  test('no debts section -> no_debts', () {
    final r = BackupService.instance.parse('#LOAN_PAYOFF_US_BACKUP,v1\n');
    expect(r.errorCode, 'no_debts');
  });

  test('wrong debt columns -> bad_debt_columns', () {
    const csv = '#LOAN_PAYOFF_US_BACKUP,v1\n'
        '#DEBTS\n'
        'id,name,WRONG\n'
        'd1,Credit Card,5000\n';
    expect(BackupService.instance.parse(csv).errorCode, 'bad_debt_columns');
  });

  test('invalid debt rows are skipped, not fatal', () {
    const csv = '#LOAN_PAYOFF_US_BACKUP,v1\n'
        '#DEBTS\n'
        'id,name,balance,original_balance,annual_rate,min_payment,category,priority\n'
        'd1,Credit Card,5000,6000,19.99,100,credit_card,0\n'
        'd2,,12000,15000,6.5,250,auto_loan,1\n' // empty name -> skipped
        'd3,Bad,-1,0,5,10,other,0\n'; // negative balance -> skipped
    final r = BackupService.instance.parse(csv);
    expect(r.isValid, isTrue);
    expect(r.debts.length, 1);
    expect(r.skippedRows, 2);
  });

  test('duplicate ids within the file are skipped', () {
    const csv = '#LOAN_PAYOFF_US_BACKUP,v1\n'
        '#DEBTS\n'
        'id,name,balance,original_balance,annual_rate,min_payment,category,priority\n'
        'd1,Credit Card,5000,6000,19.99,100,credit_card,0\n'
        'd1,Dup,1000,1000,5,50,other,0\n';
    final r = BackupService.instance.parse(csv);
    expect(r.debts.length, 1);
    expect(r.skippedRows, 1);
  });

  test('quoted fields with embedded commas round-trip through parse', () {
    const csv = '#LOAN_PAYOFF_US_BACKUP,v1\n'
        '#DEBTS\n'
        'id,name,balance,original_balance,annual_rate,min_payment,category,priority\n'
        'd1,"Visa, Gold",5000,5000,19.99,100,credit_card,0\n';
    final r = BackupService.instance.parse(csv);
    expect(r.isValid, isTrue);
    expect(r.debts.single.name, 'Visa, Gold');
  });

  test('debts without a payments section still parse', () {
    const csv = '#LOAN_PAYOFF_US_BACKUP,v1\n'
        '#DEBTS\n'
        'id,name,balance,original_balance,annual_rate,min_payment,category,priority\n'
        'd1,Credit Card,5000,6000,19.99,100,credit_card,0\n';
    final r = BackupService.instance.parse(csv);
    expect(r.isValid, isTrue);
    expect(r.debts.length, 1);
    expect(r.payments, isEmpty);
  });

  test('missing original_balance falls back to balance', () {
    const csv = '#LOAN_PAYOFF_US_BACKUP,v1\n'
        '#DEBTS\n'
        'id,name,balance,original_balance,annual_rate,min_payment,category,priority\n'
        'd1,Credit Card,5000,,19.99,100,credit_card,0\n';
    final r = BackupService.instance.parse(csv);
    expect(r.debts.single.originalBalance, 5000);
  });

  test('payment with non-positive amount is skipped', () {
    const csv = '#LOAN_PAYOFF_US_BACKUP,v1\n'
        '#DEBTS\n'
        'id,name,balance,original_balance,annual_rate,min_payment,category,priority\n'
        'd1,Credit Card,5000,6000,19.99,100,credit_card,0\n'
        '#PAYMENTS\n'
        'debt_id,debt_name,amount,date_iso,note\n'
        'd1,Credit Card,0,2026-01-15T00:00:00.000,\n';
    final r = BackupService.instance.parse(csv);
    expect(r.isValid, isTrue);
    expect(r.payments, isEmpty);
    expect(r.skippedRows, 1);
  });
}
