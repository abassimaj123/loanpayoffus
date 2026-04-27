import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/loan_input.dart';
import '../../domain/models/loan_type.dart';
import '../../domain/models/payoff_result.dart';
import '../../domain/usecases/loan_calculator.dart';

final loanInputProvider =
    StateNotifierProvider<LoanInputNotifier, LoanInput>(
  (ref) => LoanInputNotifier(),
);

class LoanInputNotifier extends StateNotifier<LoanInput> {
  LoanInputNotifier()
      : super(LoanInput(
          loanType:        LoanType.mortgage,
          loanAmount:      400000,
          interestRatePct: 6.2,
          monthlyPayment:  LoanCalculator.computeMonthlyPayment(400000, 6.2, 360),
          extraPayment:    0,
        ));

  void update(LoanInput input) => state = input;
}

final payoffResultProvider = Provider<PayoffResult?>((ref) {
  final input = ref.watch(loanInputProvider);
  if (input.loanAmount <= 0 || input.monthlyPayment <= 0) return null;
  try {
    return LoanCalculator.calculate(input);
  } catch (_) {
    return null;
  }
});
