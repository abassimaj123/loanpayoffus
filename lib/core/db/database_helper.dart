import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final instance = DatabaseHelper._();
  static Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final p = join(await getDatabasesPath(), 'loan_payoff_us.db');
    return openDatabase(p, version: 1, onCreate: _onCreate);
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
  }

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
}
