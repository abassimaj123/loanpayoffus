// Backup / restore for the Debt Strategy data.
//
// Exports every debt (SharedPreferences via DebtPersistence) plus the full
// payment history (SQLite via DebtPaymentPersistence) into a single CSV file,
// and restores them back with validation. The round-trip is exact: export then
// import yields the same debts (incl. ids) and payments.
//
// CSV layout — one file, two labelled sections:
//
//   #LOAN_PAYOFF_US_BACKUP,v1
//   #DEBTS
//   id,name,balance,original_balance,annual_rate,min_payment,category,priority
//   ...rows...
//   #PAYMENTS
//   debt_id,debt_name,amount,date_iso,note
//   ...rows...
//
// No external file-picker dependency: export shares a temp .csv via share_plus;
// import accepts pasted CSV text (see BackupScreen).

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/models/debt_item.dart';
import '../../domain/models/debt_category.dart';
import '../../domain/models/debt_payment.dart';
import '../db/debt_persistence.dart';
import '../db/debt_payment_persistence.dart';
import '../language/language_notifier.dart';

/// File-format marker written as the very first cell of the backup.
const _magic = '#LOAN_PAYOFF_US_BACKUP';
const _formatVersion = 'v1';
const _debtsMarker = '#DEBTS';
const _paymentsMarker = '#PAYMENTS';

const _debtHeader = [
  'id',
  'name',
  'balance',
  'original_balance',
  'annual_rate',
  'min_payment',
  'category',
  'priority',
];

const _paymentHeader = [
  'debt_id',
  'debt_name',
  'amount',
  'date_iso',
  'note',
];

/// Outcome of parsing a CSV backup. Either [isValid] with data, or an error
/// message key describing what went wrong. Parsing never throws.
class BackupParseResult {
  final bool isValid;
  final List<DebtItem> debts;
  final List<DebtPayment> payments;

  /// Non-null when [isValid] is false — a stable error code the UI maps to a
  /// localized message. One of: 'empty', 'not_backup', 'no_debts',
  /// 'bad_debt_columns', 'bad_payment_columns', 'invalid_values'.
  final String? errorCode;

  /// Count of rows that were skipped because individual values were invalid
  /// (parsed best-effort). Zero on a clean import.
  final int skippedRows;

  const BackupParseResult._({
    required this.isValid,
    this.debts = const [],
    this.payments = const [],
    this.errorCode,
    this.skippedRows = 0,
  });

  factory BackupParseResult.error(String code) =>
      BackupParseResult._(isValid: false, errorCode: code);

  factory BackupParseResult.ok(
    List<DebtItem> debts,
    List<DebtPayment> payments, {
    int skipped = 0,
  }) => BackupParseResult._(
    isValid: true,
    debts: debts,
    payments: payments,
    skippedRows: skipped,
  );
}

class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  // ── Export ─────────────────────────────────────────────────────────────────

  /// Builds the full CSV text for the current debts + payments.
  Future<String> buildCsv() async {
    final debts = await DebtPersistence.instance.load();
    final payments = await DebtPaymentPersistence.instance.listAll();
    return _serialize(debts, payments);
  }

  /// Writes the backup to a temp .csv file and opens the system share sheet.
  /// Returns true if the share sheet was presented.
  Future<bool> exportAndShare() async {
    final csv = await buildCsv();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().split('T').first;
    final file = File('${dir.path}/loan_payoff_backup_$stamp.csv');
    await file.writeAsString(csv);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: isSpanishNotifier.value
          ? 'Loan Payoff US — Copia de seguridad'
          : 'Loan Payoff US — Backup',
    );
    return true;
  }

  String _serialize(List<DebtItem> debts, List<DebtPayment> payments) {
    final buf = StringBuffer();
    buf.writeln(_csvRow([_magic, _formatVersion]));
    buf.writeln(_csvRow([_debtsMarker]));
    buf.writeln(_csvRow(_debtHeader));
    for (final d in debts) {
      buf.writeln(_csvRow([
        d.id,
        d.name,
        _num(d.balance),
        _num(d.originalBalance),
        _num(d.annualRate),
        _num(d.minPayment),
        d.category.id,
        d.priority.toString(),
      ]));
    }
    buf.writeln(_csvRow([_paymentsMarker]));
    buf.writeln(_csvRow(_paymentHeader));
    for (final p in payments) {
      buf.writeln(_csvRow([
        p.debtId,
        p.debtName,
        _num(p.amount),
        p.date.toIso8601String(),
        p.note ?? '',
      ]));
    }
    return buf.toString();
  }

  /// Trims trailing zeros so a round-trip stays stable but readable.
  String _num(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toString();
  }

  // ── Parse ────────────────────────────────────────────────────────────────────

  /// Parses raw CSV text into debts + payments. Never throws — malformed input
  /// produces a [BackupParseResult.error] with a stable [errorCode], and the
  /// existing database is never touched here (parsing is side-effect free).
  BackupParseResult parse(String raw) {
    if (raw.trim().isEmpty) return BackupParseResult.error('empty');

    final List<List<String>> rows;
    try {
      rows = _parseCsv(raw);
    } catch (_) {
      return BackupParseResult.error('not_backup');
    }
    if (rows.isEmpty) return BackupParseResult.error('empty');

    // First non-empty row must be the magic marker.
    final first = rows.firstWhere(
      (r) => r.any((c) => c.trim().isNotEmpty),
      orElse: () => const [],
    );
    if (first.isEmpty || first.first.trim() != _magic) {
      return BackupParseResult.error('not_backup');
    }

    // Locate section markers.
    int debtsIdx = -1;
    int paymentsIdx = -1;
    for (var i = 0; i < rows.length; i++) {
      final cell = rows[i].isEmpty ? '' : rows[i].first.trim();
      if (cell == _debtsMarker) debtsIdx = i;
      if (cell == _paymentsMarker) paymentsIdx = i;
    }
    if (debtsIdx < 0) return BackupParseResult.error('no_debts');

    final debtEnd = paymentsIdx > debtsIdx ? paymentsIdx : rows.length;

    // ── Debts ──
    // Row debtsIdx+1 is the header; validate column names.
    if (debtsIdx + 1 >= rows.length) {
      return BackupParseResult.error('bad_debt_columns');
    }
    final debtHeaderRow = rows[debtsIdx + 1].map((c) => c.trim()).toList();
    if (!_headerMatches(debtHeaderRow, _debtHeader)) {
      return BackupParseResult.error('bad_debt_columns');
    }

    final debts = <DebtItem>[];
    var skipped = 0;
    final seenIds = <String>{};
    for (var i = debtsIdx + 2; i < debtEnd; i++) {
      final r = rows[i];
      if (r.every((c) => c.trim().isEmpty)) continue;
      final debt = _parseDebtRow(r);
      if (debt == null) {
        skipped++;
        continue;
      }
      // Guard against duplicate ids within the file.
      if (seenIds.contains(debt.id)) {
        skipped++;
        continue;
      }
      seenIds.add(debt.id);
      debts.add(debt);
    }

    if (debts.isEmpty) return BackupParseResult.error('no_debts');

    // ── Payments (optional section) ──
    final payments = <DebtPayment>[];
    if (paymentsIdx >= 0) {
      if (paymentsIdx + 1 >= rows.length) {
        return BackupParseResult.error('bad_payment_columns');
      }
      final payHeaderRow =
          rows[paymentsIdx + 1].map((c) => c.trim()).toList();
      if (!_headerMatches(payHeaderRow, _paymentHeader)) {
        return BackupParseResult.error('bad_payment_columns');
      }
      for (var i = paymentsIdx + 2; i < rows.length; i++) {
        final r = rows[i];
        if (r.every((c) => c.trim().isEmpty)) continue;
        if (r.isNotEmpty && r.first.trim().startsWith('#')) continue;
        final pay = _parsePaymentRow(r);
        if (pay == null) {
          skipped++;
          continue;
        }
        payments.add(pay);
      }
    }

    return BackupParseResult.ok(debts, payments, skipped: skipped);
  }

  DebtItem? _parseDebtRow(List<String> r) {
    if (r.length < _debtHeader.length) return null;
    final id = r[0].trim();
    final name = r[1].trim();
    final balance = double.tryParse(r[2].trim());
    final originalBalance = double.tryParse(r[3].trim());
    final rate = double.tryParse(r[4].trim());
    final minPayment = double.tryParse(r[5].trim());
    final categoryId = r[6].trim();
    final priority = int.tryParse(r[7].trim());

    if (id.isEmpty || name.isEmpty) return null;
    if (balance == null || balance < 0) return null;
    if (rate == null || rate < 0) return null;
    if (minPayment == null || minPayment < 0) return null;

    return DebtItem(
      id: id,
      name: name,
      balance: balance,
      originalBalance:
          (originalBalance != null && originalBalance >= 0) ? originalBalance : balance,
      annualRate: rate,
      minPayment: minPayment,
      category: DebtCategoryX.fromId(categoryId),
      priority: priority ?? 0,
    );
  }

  DebtPayment? _parsePaymentRow(List<String> r) {
    if (r.length < _paymentHeader.length) return null;
    final debtId = r[0].trim();
    final debtName = r[1].trim();
    final amount = double.tryParse(r[2].trim());
    final date = DateTime.tryParse(r[3].trim());
    final note = r[4].trim();

    if (debtId.isEmpty) return null;
    if (amount == null || amount <= 0) return null;
    if (date == null) return null;

    return DebtPayment(
      debtId: debtId,
      debtName: debtName,
      amount: amount,
      date: date,
      note: note.isEmpty ? null : note,
    );
  }

  bool _headerMatches(List<String> got, List<String> expected) {
    if (got.length < expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (got[i].toLowerCase() != expected[i]) return false;
    }
    return true;
  }

  // ── Apply (writes to storage) ───────────────────────────────────────────────

  /// Replaces all debts and payments with the parsed set. Caller must confirm
  /// first (this wipes existing data). Returns once persistence completes.
  Future<void> applyReplace(BackupParseResult data) async {
    await DebtPersistence.instance.save(data.debts);
    await DebtPaymentPersistence.instance.clearAll();
    for (final p in data.payments) {
      await DebtPaymentPersistence.instance.add(p);
    }
  }

  /// Merges the parsed set into existing data: debts with a new id are added,
  /// existing ids are kept as-is; all imported payments are appended.
  Future<void> applyMerge(BackupParseResult data) async {
    final existing = await DebtPersistence.instance.load();
    final existingIds = existing.map((d) => d.id).toSet();
    final merged = [...existing];
    for (final d in data.debts) {
      if (!existingIds.contains(d.id)) merged.add(d);
    }
    await DebtPersistence.instance.save(merged);
    for (final p in data.payments) {
      await DebtPaymentPersistence.instance.add(p);
    }
  }

  // ── Minimal RFC-4180 CSV codec ──────────────────────────────────────────────

  String _csvRow(List<String> cells) => cells.map(_escape).join(',');

  String _escape(String v) {
    final needsQuote =
        v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r');
    if (!needsQuote) return v;
    return '"${v.replaceAll('"', '""')}"';
  }

  /// Parses CSV text into a list of rows (each a list of cells). Handles quoted
  /// fields, escaped quotes (""), and embedded commas/newlines.
  List<List<String>> _parseCsv(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    final s = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    void endField() {
      row.add(field.toString());
      field.clear();
    }

    void endRow() {
      endField();
      rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < s.length && s[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
      } else {
        if (ch == '"') {
          inQuotes = true;
        } else if (ch == ',') {
          endField();
        } else if (ch == '\n') {
          endRow();
        } else {
          field.write(ch);
        }
      }
    }
    // Flush trailing field/row if any content remains.
    if (field.isNotEmpty || row.isNotEmpty) {
      endRow();
    }
    return rows;
  }
}
