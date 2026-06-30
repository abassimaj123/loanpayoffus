import 'loan_type.dart';

class LoanInput {
  final LoanType loanType;
  final double loanAmount;
  final double interestRatePct;
  final double monthlyPayment;
  final double extraPayment;

  /// When true, [extraPayment] is a single lump sum applied at month 1
  /// (a "snowflake" payment) rather than a recurring monthly amount.
  final bool extraIsOneTime;

  const LoanInput({
    required this.loanType,
    required this.loanAmount,
    required this.interestRatePct,
    required this.monthlyPayment,
    this.extraPayment = 0,
    this.extraIsOneTime = false,
  });

  LoanInput copyWith({
    LoanType? loanType,
    double? loanAmount,
    double? interestRatePct,
    double? monthlyPayment,
    double? extraPayment,
    bool? extraIsOneTime,
  }) => LoanInput(
    loanType: loanType ?? this.loanType,
    loanAmount: loanAmount ?? this.loanAmount,
    interestRatePct: interestRatePct ?? this.interestRatePct,
    monthlyPayment: monthlyPayment ?? this.monthlyPayment,
    extraPayment: extraPayment ?? this.extraPayment,
    extraIsOneTime: extraIsOneTime ?? this.extraIsOneTime,
  );
}
