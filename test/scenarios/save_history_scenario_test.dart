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

    test(
        'scenario: consolidation save survives the history-screen purge check '
        '(regression for silent data-loss bug)', () async {
      // GIVEN: a consolidation scenario (mirrors _buildL1/_buildL2 in
      // consolidation_screen.dart) — note total_balance/consolidation_rate
      // are consolidation-specific keys, but the fix also mirrors them into
      // the generic loan_amount/interest_rate/normal_months keys so the
      // DB adapter (loan_payoff_us_database_adapter.dart) doesn't default
      // them to 0.
      const totalBalance = 32000.0;
      const consolidationRate = 11.5;
      const termMonths = 48;
      const consolidationPayment = 780.0;
      const monthlySavings = 120.0;

      await svc.saveScenario(
        appKey: 'loanpayoffus',
        screenId: 'consolidation',
        inputHash: 'consolidation-hash-1',
        l1: {
          'debt_count': 2,
          'total_balance': totalBalance,
          'consolidation_rate': consolidationRate,
          'monthly_savings': monthlySavings,
          'term_months': termMonths,
        },
        l2: {
          'loan_type': 'Consolidation',
          'loan_amount': totalBalance,
          'interest_rate': consolidationRate,
          'monthly_payment': consolidationPayment,
          'extra_payment': 0.0,
          'normal_months': termMonths,
          'interest_saved': monthlySavings * termMonths,
          'inputs': {
            'debts': [
              {'balance': 20000.0, 'rate': 18.0, 'payment': 500.0},
              {'balance': 12000.0, 'rate': 22.0, 'payment': 400.0},
            ],
            'consolidation_rate': consolidationRate,
            'term_months': termMonths,
          },
          'results': {
            'total_balance': totalBalance,
            'total_current_monthly': 900.0,
            'consolidation_payment': consolidationPayment,
            'total_consolidation_cost': consolidationPayment * termMonths,
            'total_consolidation_interest':
                consolidationPayment * termMonths - totalBalance,
            'monthly_savings': monthlySavings,
            'avg_current_rate': 19.5,
          },
        },
        label: 'Debt consolidation plan',
      );

      // WHEN: replaying the exact same shape the DatabaseAdapter.insertRow
      // uses to map l2_json → flat `history` columns (see
      // loan_payoff_us_database_adapter.dart lines 25-32).
      final saved = await svc.getPinned('loanpayoffus');
      expect(saved, isNotEmpty,
          reason: 'Consolidation scenario must be saved to history');
      final l2 = saved.first.l2;
      final mappedLoanAmount = (l2['loan_amount'] as num?)?.toDouble() ?? 0.0;
      final mappedInterestRate =
          (l2['interest_rate'] as num?)?.toDouble() ?? 0.0;
      final mappedNormalMonths = (l2['normal_months'] as num?)?.toInt() ?? 0;

      // THEN: replaying HistoryScreen._load()'s auto-purge condition
      // (amount == 0 && rate == 0) must NOT trigger for a consolidation row.
      final wouldBePurged = mappedLoanAmount == 0 && mappedInterestRate == 0;
      expect(wouldBePurged, isFalse,
          reason:
              'Consolidation entries must not look like corrupted zero-value '
              'auto-saves — this was the silent data-loss bug where '
              'HistoryScreen deleted every saved consolidation scenario');

      // AND: the mapped values are correct (not just non-zero) and safe for
      // the unchecked `as num` casts in HistoryScreen._buildCard and the
      // history-detail PDF export.
      expect(mappedLoanAmount, totalBalance);
      expect(mappedInterestRate, consolidationRate);
      expect(mappedNormalMonths, termMonths);

      // AND: the consolidation-specific results survive untouched for the
      // consolidation UI / PDF export to read back.
      final results = l2['results'] as Map<String, dynamic>;
      expect(results['total_balance'], totalBalance);
      expect(results['consolidation_payment'], consolidationPayment);
      expect(results['monthly_savings'], monthlySavings);
    });

    test(
        'scenario: one-time extra payment survives save/restore and hashes '
        'differently from an equivalent recurring extra '
        '(regression for silent data-loss bug)', () async {
      // GIVEN: two scenarios identical except for the one-time vs recurring
      // toggle (mirrors _buildSnapshot in calculator_screen.dart, which must
      // include extra_one_time in both the l2 payload and the input hash).
      const loanAmount = 25000.0;
      const interestRate = 7.5;
      const monthlyPayment = 500.0;
      const extraPayment = 200.0;
      const normalMonths = 64;
      const interestSaved = 900.0;

      Map<String, dynamic> buildL2(bool extraOneTime) => {
            'loan_type': 'Personal',
            'loan_amount': loanAmount,
            'interest_rate': interestRate,
            'monthly_payment': monthlyPayment,
            'extra_payment': extraPayment,
            'extra_one_time': extraOneTime,
            'normal_months': normalMonths,
            'interest_saved': interestSaved,
          };

      String buildHash(bool extraOneTime) => ResultHasher.hashMixed({
            'amount': ResultHasher.roundTo(loanAmount, 100),
            'rate': ResultHasher.roundTo(interestRate, 0.01),
            'payment': ResultHasher.roundTo(monthlyPayment, 10),
            'extra': ResultHasher.roundTo(extraPayment, 10),
            'extra_one_time': extraOneTime,
            'type': 'personal',
          });

      final oneTimeHash = buildHash(true);
      final recurringHash = buildHash(false);

      // THEN: one-time and recurring scenarios must NOT collide into the
      // same hash — otherwise SmartHistoryService's dedup would silently
      // discard one of them as a "duplicate".
      expect(oneTimeHash, isNot(equals(recurringHash)),
          reason: 'One-time and recurring extra-payment scenarios with '
              'identical amounts must produce different hashes, or dedup '
              'silently conflates them.');

      // WHEN: saving the one-time scenario (mirrors _saveScenario).
      await svc.saveScenario(
        appKey: 'loanpayoffus',
        screenId: 'calculator',
        inputHash: oneTimeHash,
        l1: {
          'loan_type': 'Personal',
          'loan_amount': loanAmount,
          'monthly_payment': monthlyPayment,
          'interest_rate': interestRate,
        },
        l2: buildL2(true),
        label: 'One-time lump sum plan',
      );

      // AND: saving the recurring scenario too — both must coexist.
      await svc.saveScenario(
        appKey: 'loanpayoffus',
        screenId: 'calculator',
        inputHash: recurringHash,
        l1: {
          'loan_type': 'Personal',
          'loan_amount': loanAmount,
          'monthly_payment': monthlyPayment,
          'interest_rate': interestRate,
        },
        l2: buildL2(false),
        label: 'Recurring monthly plan',
      );

      final pinned = await svc.getPinned('loanpayoffus');
      expect(pinned.length, 2,
          reason: 'One-time and recurring scenarios must both be saved, '
              'not collapsed into a single duplicate entry.');

      // THEN: restoring each entry (mirrors LoanPayoffUSDatabaseAdapter /
      // HistoryDetailScreen reading extra_one_time back from l2) correctly
      // reports which is which.
      final oneTimeEntry =
          pinned.firstWhere((e) => e.resultHash == oneTimeHash);
      final recurringEntry =
          pinned.firstWhere((e) => e.resultHash == recurringHash);

      final restoredOneTime =
          (oneTimeEntry.l2['extra_one_time'] as bool?) ?? false;
      final restoredRecurring =
          (recurringEntry.l2['extra_one_time'] as bool?) ?? false;

      expect(restoredOneTime, isTrue,
          reason: 'A one-time lump sum scenario must restore as one-time, '
              'not silently default to recurring monthly.');
      expect(restoredRecurring, isFalse,
          reason: 'A recurring monthly scenario must restore as recurring.');
    });

    test(
        'scenario: older saved snapshot without extra_one_time defaults to '
        'recurring monthly on restore (backward compatibility)', () async {
      // GIVEN: a legacy l2 payload saved before this fix existed — no
      // extra_one_time key at all.
      await svc.saveScenario(
        appKey: 'loanpayoffus',
        screenId: 'calculator',
        inputHash: 'legacy-hash-no-flag',
        l1: {'loan_type': 'Auto', 'loan_amount': 15000.0, 'interest_rate': 6.0},
        l2: {
          'loan_type': 'Auto',
          'loan_amount': 15000.0,
          'interest_rate': 6.0,
          'monthly_payment': 350.0,
          'extra_payment': 100.0,
          'normal_months': 48,
          'interest_saved': 300.0,
        },
        label: 'Legacy plan',
      );

      final pinned = await svc.getPinned('loanpayoffus');
      final legacyEntry =
          pinned.firstWhere((e) => e.resultHash == 'legacy-hash-no-flag');

      // THEN: missing the flag must default to false (recurring monthly),
      // not crash and not silently assume one-time.
      final restored = (legacyEntry.l2['extra_one_time'] as bool?) ?? false;
      expect(restored, isFalse,
          reason: 'Missing extra_one_time on legacy entries must default to '
              'recurring monthly for backward compatibility.');
    });
  });
}
