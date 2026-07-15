import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final instance = DatabaseHelper._();
  static Database? _db;

  static const _dbVersion = 5;

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
        created_at TEXT NOT NULL,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        input_hash TEXT,
        pin_label TEXT,
        pin_order INTEGER NOT NULL DEFAULT 0,
        l1_json TEXT,
        extra_one_time INTEGER NOT NULL DEFAULT 0,
        screen_id TEXT NOT NULL DEFAULT 'calculator'
      )
    ''');
    await _createDebtPaymentsTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createDebtPaymentsTable(db);
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE history ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute('ALTER TABLE history ADD COLUMN input_hash TEXT');
      await db.execute('ALTER TABLE history ADD COLUMN pin_label TEXT');
      await db.execute(
        'ALTER TABLE history ADD COLUMN pin_order INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute('ALTER TABLE history ADD COLUMN l1_json TEXT');
    }
    if (oldVersion < 4) {
      // Distinguishes a one-time lump-sum extra payment from a recurring
      // monthly extra payment. Older rows predate this flag and default to
      // 0 (recurring monthly), matching their original save-time behavior.
      await db.execute(
        'ALTER TABLE history ADD COLUMN extra_one_time INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 5) {
      // Scopes history lookups by originating screen/tool. Without this,
      // saves from different screens (calculator, consolidation, refinance,
      // debt_strategy, goals, payoff_plan) whose rounded inputs hash to the
      // same value can silently merge via the pinned-promotion path.
      // Existing rows predate per-screen tracking; default to 'calculator'.
      await db.execute(
        "ALTER TABLE history ADD COLUMN screen_id TEXT NOT NULL DEFAULT 'calculator'",
      );
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

  Future<int> insertHistory(Map<String, dynamic> row) async {
    final db = await database;
    return db.insert('history', row);
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    final db = await database;
    return db.query(
      'history',
      orderBy: 'is_pinned DESC, pin_order DESC, created_at DESC',
    );
  }

  Future<Map<String, dynamic>?> getHistoryByHash(
    String hash, {
    required String screenId,
  }) async {
    final db = await database;
    final rows = await db.query(
      'history',
      where: 'input_hash = ? AND screen_id = ?',
      whereArgs: [hash, screenId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> updateHistoryEntry(int id, Map<String, dynamic> values) async {
    final db = await database;
    return db.update('history', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countHistory({bool? isPinned}) async {
    final db = await database;
    final String sql;
    if (isPinned == null) {
      sql = 'SELECT COUNT(*) FROM history';
    } else {
      sql =
          'SELECT COUNT(*) FROM history WHERE is_pinned = ${isPinned ? 1 : 0}';
    }
    final result = await db.rawQuery(sql);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getOldestAutoSaves(int limit) async {
    final db = await database;
    return db.query(
      'history',
      where: 'is_pinned = 0',
      orderBy: 'created_at ASC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getOldestPinnedEntries(int limit) async {
    final db = await database;
    return db.query(
      'history',
      where: 'is_pinned = 1',
      orderBy: 'pin_order ASC, created_at ASC',
      limit: limit,
    );
  }

  Future<void> deleteHistory(int id) async {
    final db = await database;
    await db.delete('history', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteOldestHistory() async {
    final db = await database;
    await db.rawDelete(
      'DELETE FROM history WHERE id = (SELECT id FROM history WHERE is_pinned = 0 ORDER BY created_at ASC LIMIT 1)',
    );
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

  Future<void> clearDebtPayments() async {
    final db = await database;
    await db.delete('debt_payments');
  }
}
