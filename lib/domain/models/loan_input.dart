import 'loan_type.dart';

class LoanInput {
  final LoanType loanType;
  final double loanAmount;
  final double interestRatePct;
  final double monthlyPayment;
  final double extraPayment;

  const LoanInput({
    required this.loanType,
    required this.loanAmount,
    required this.interestRatePct,
    required this.monthlyPayment,
    this.extraPayment = 0,
  });

  LoanInput copyWith({
    LoanType? loanType,
    double? loanAmount,
    double? interestRatePct,
    double? monthlyPayment,
    double? extraPayment,
  }) => LoanInput(
    loanType: loanType ?? this.loanType,
    loanAmount: loanAmount ?? this.loanAmount,
    interestRatePct: interestRatePct ?? this.interestRatePct,
    monthlyPayment: monthlyPayment ?? this.monthlyPayment,
    extraPayment: extraPayment ?? this.extraPayment,
  );
}
