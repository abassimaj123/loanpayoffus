class AmortizationEntry {
  final int    month;
  final double payment;
  final double principal;
  final double interest;
  final double balance;
  final double extraPayment;

  const AmortizationEntry({
    required this.month,
    required this.payment,
    required this.principal,
    required this.interest,
    required this.balance,
    required this.extraPayment,
  });
}
