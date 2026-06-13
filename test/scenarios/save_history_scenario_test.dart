import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calcwise_core/calcwise_core.dart';

class _MemoryAdapter implements DatabaseAdapter {
  final List<Map<String, dynamic>> _rows = [];
  int _nextId = 1;
  int get rowCount => _rows.length;

  @override
  Future<int> insertRow(Map<String, dynamic> row) async {
    final id = _nextId++;
    _rows.add({...row, 'id': id});
    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> getRows({
    required String appKey,
    String? screenId,
    bool? isPinned,
    int? limit,
  }) async {
    var result = _rows.where((r) {
      if (r['app_key'] != appKey) return false;
      if (screenId != null && r['screen_id'] != screenId) return false;
      if (isPinned != null) return ((r['is_pinned'] as int) == 1) == isPinned;
      return true;
    }).toList();
    result.sort((a, b) {
      final aPin = a['is_pinned'] as int;
      final bPin = b['is_pinned'] as int;
      if (aPin != bPin) return bPin.compareTo(aPin);
      return (b['saved_at'] as int).compareTo(a['saved_at'] as int);
    });
    if (limit != null && result.length > limit) result = result.sublist(0, limit);
    return result;
  }

  @override
  Future<Map<String, dynamic>?> getRowByHash({required String appKey, required String resultHash}) async {
    try { return _rows.firstWhere((r) => r['app_key'] == appKey && r['result_hash'] == resultHash); }
    catch (_) { return null; }
  }

  @override
  Future<int> updateRow(int id, Map<String, dynamic> values) async {
    final idx = _rows.indexWhere((r) => r['id'] == id);
    if (idx < 0) return 0;
    _rows[idx] = {..._rows[idx], ...values};
    return 1;
  }

  @override
  Future<int> deleteRow(int id) async {
    final before = _rows.length;
    _rows.removeWhere((r) => r['id'] == id);
    return before - _rows.length;
  }

  @override
  Future<int> countRows({required String appKey, bool? isPinned}) async =>
      _rows.where((r) {
        if (r['app_key'] != appKey) return false;
        if (isPinned != null) return ((r['is_pinned'] as int) == 1) == isPinned;
        return true;
      }).length;

  @override
  Future<List<Map<String, dynamic>>> getOldestAutoSaves({required String appKey, required int limit}) async {
    final rows = _rows.where((r) => r['app_key'] == appKey && (r['is_pinned'] as int) == 0).toList()
      ..sort((a, b) => (a['saved_at'] as int).compareTo(b['saved_at'] as int));
    return rows.take(limit).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getOldestPinned({required String appKey, required int limit}) async {
    final rows = _rows.where((r) => r['app_key'] == appKey && (r['is_pinned'] as int) == 1).toList()
      ..sort((a, b) => (a['saved_at'] as int).compareTo(b['saved_at'] as int));
    return rows.take(limit).toList();
  }
}

Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late _MemoryAdapter adapter;
  late CalcwiseFreemium freemium;
  late SmartHistoryService svc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    adapter = _MemoryAdapter();
    freemium = CalcwiseFreemium(appKey: 'loanpayoffus');
    await freemium.initialize();
    svc = SmartHistoryService(
      db: adapter,
      freemium: freemium,
      overrideSaveDebounce: Duration.zero,
    );
  });

  tearDown(() => svc.dispose());

  group('LoanPayoffUS — save → history scenarios', () {
    test('scenario: calculate loan payoff → entry appears in history', () async {
      // GIVEN: typical loan payoff inputs (mirrors _buildSnapshot in calculator_screen.dart)
      const loanAmount = 25000.0;
      const interestRate = 7.5;
      const monthlyPayment = 500.0;
      const extraPayment = 100.0;
      const normalMonths = 64;
      const interestSaved = 820.0;

      final inputHash = ResultHasher.hashMixed({
        'amount': ResultHasher.roundTo(loanAmount, 100),
        'rate': ResultHasher.roundTo(interestRate, 0.01),
        'payment': ResultHasher.roundTo(monthlyPayment, 10),
        'extra': ResultHasher.roundTo(extraPayment, 10),
        'type': 'personal',
      });

      // WHEN: auto-save triggered (mirrors _scheduleAutoSave in calculator_screen.dart)
      var savedCalled = false;
      svc.scheduleAutoSave(
        appKey: 'loanpayoffus',
        screenId: 'calculator',
        inputHash: inputHash,
        l1: {
          'loan_type': 'Personal',
          'loan_amount': loanAmount,
          'monthly_payment': monthlyPayment,
          'interest_rate': interestRate,
        },
        l2: {
          'loan_type': 'Personal',
          'loan_amount': loanAmount,
          'interest_rate': interestRate,
          'monthly_payment': monthlyPayment,
          'extra_payment': extraPayment,
          'normal_months': normalMonths,
          'interest_saved': interestSaved,
        },
        onSaved: () => savedCalled = true,
      );
      await _pump();

      // THEN
      final history = await svc.getHistory('loanpayoffus');
      expect(history, isNotEmpty,
          reason: 'History must contain the payoff entry');
      expect(history.first.l2['loan_amount'], loanAmount);
      expect(savedCalled, isTrue,
          reason: 'onSaved must fire — anti-regression for history refresh race condition');
    });

    test('scenario: two different loan amounts → both entries in history', () async {
      for (var i = 0; i < 2; i++) {
        final amount = 15000.0 + i * 10000;
        svc.scheduleAutoSave(
          appKey: 'loanpayoffus',
          screenId: 'calculator',
          inputHash: 'hash-payoff-$i',
          l1: {'loan_type': 'Auto', 'loan_amount': amount, 'interest_rate': 6.9},
          l2: {'loan_amount': amount, 'interest_rate': 6.9, 'monthly_payment': 350.0 + i * 50},
        );
        await _pump();
      }
      final history = await svc.getHistory('loanpayoffus');
      expect(history.length, 2);
    });

    test('scenario: same inputs twice → only one history entry', () async {
      const hash = 'same-hash-loanpayoffus';
      for (var i = 0; i < 3; i++) {
        svc.scheduleAutoSave(
          appKey: 'loanpayoffus',
          screenId: 'calculator',
          inputHash: hash,
          l1: {'loan_type': 'Mortgage', 'loan_amount': 20000.0, 'interest_rate': 5.0},
          l2: {'loan_amount': 20000.0, 'interest_rate': 5.0, 'extra_payment': 0.0},
        );
        await _pump();
      }
      expect(adapter.rowCount, 1,
          reason: 'Identical inputs must not create duplicates');
    });

    test('scenario: pinned payoff plan survives ring buffer eviction', () async {
      await svc.saveScenario(
        appKey: 'loanpayoffus',
        screenId: 'calculator',
        inputHash: 'pinned-payoff-scenario',
        l1: {'loan_type': 'Credit Card', 'loan_amount': 8000.0, 'interest_rate': 22.9},
        l2: {
          'loan_amount': 8000.0,
          'interest_rate': 22.9,
          'monthly_payment': 300.0,
          'extra_payment': 200.0,
          'normal_months': 36,
          'interest_saved': 1200.0,
        },
        label: 'Aggressive paydown plan',
      );
      for (var i = 0; i < MonetizationConfig.freeRingBufferSize + 2; i++) {
        svc.scheduleAutoSave(
          appKey: 'loanpayoffus',
          screenId: 'calculator',
          inputHash: 'auto-payoff-$i',
          l1: {'loan_type': 'Personal', 'loan_amount': i * 1000.0, 'interest_rate': 7.0},
          l2: {'loan_amount': i * 1000.0, 'extra_payment': 0.0},
        );
        await _pump();
      }
      final pinned = await svc.getPinned('loanpayoffus');
      expect(pinned, isNotEmpty,
          reason: 'Pinned payoff plan must survive ring buffer eviction');
      expect(pinned.first.l2['loan_amount'], 8000.0);
    });
  });
}
