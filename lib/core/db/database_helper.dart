import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final instance = DatabaseHelper._();
  static Database? _db;

  static const _dbVersion = 2;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final p = join(await getDatabasesPath(), 'loan_payoff_us.db');
    return openDatabase(
      p,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        loan_type TEXT NOT NULL,
        loan_amount REAL NOT NULL,
        interest_rate REAL NOT NULL,
        monthly_payment REAL NOT NULL,
        extra_payment REAL NOT NULL DEFAULT 0,
        normal_months INTEGER NOT NULL,
        interest_saved REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await _createDebtPaymentsTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createDebtPaymentsTable(db);
    }
  }

  Future<void> _createDebtPaymentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS debt_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        debt_id TEXT NOT NULL,
        debt_name TEXT NOT NULL,
        amount REAL NOT NULL,
        date_iso TEXT NOT NULL,
        note TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_debt_payments_debt_id ON debt_payments(debt_id)',
    );
  }

  // ── History ────────────────────────────────────────────────────────────────

  Future<void> insertHistory(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert('history', row);
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    final db = await database;
    return db.query('history', orderBy: 'created_at DESC');
  }

  Future<int> countHistory() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM history');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> deleteHistory(int id) async {
    final db = await database;
    await db.delete('history', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearHistory() async {
    final db = await database;
    await db.delete('history');
  }

  // ── Debt payments ──────────────────────────────────────────────────────────

  Future<int> insertDebtPayment(Map<String, dynamic> row) async {
    final db = await database;
    return db.insert('debt_payments', row);
  }

  Future<List<Map<String, dynamic>>> getDebtPayments({String? debtId}) async {
    final db = await database;
    if (debtId != null) {
      return db.query(
        'debt_payments',
        where: 'debt_id = ?',
        whereArgs: [debtId],
        orderBy: 'date_iso DESC',
      );
    }
    return db.query('debt_payments', orderBy: 'date_iso DESC');
  }

  Future<double> sumDebtPayments(String debtId) async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(amount),0) AS total FROM debt_payments WHERE debt_id = ?',
      [debtId],
    );
    return (r.first['total'] as num).toDouble();
  }

  Future<DateTime?> latestPaymentDate(String debtId) async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT MAX(date_iso) AS d FROM debt_payments WHERE debt_id = ?',
      [debtId],
    );
    final s = r.first['d'] as String?;
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> deleteDebtPayment(int id) async {
    final db = await database;
    await db.delete('debt_payments', where: 'id = ?', whereArgs: [id]);
  }
}
