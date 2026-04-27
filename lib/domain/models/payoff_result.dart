import 'amortization_entry.dart';

class PayoffResult {
  final int    normalMonths;
  final int    extraMonths;
  final int    monthsSaved;
  final double interestNormal;
  final double interestExtra;
  final double interestSaved;
  final double totalPaidNormal;
  final double totalPaidExtra;
  final List<AmortizationEntry> schedule;
  final List<AmortizationEntry> normalSchedule;

  const PayoffResult({
    required this.normalMonths,
    required this.extraMonths,
    required this.monthsSaved,
    required this.interestNormal,
    required this.interestExtra,
    required this.interestSaved,
    required this.totalPaidNormal,
    required this.totalPaidExtra,
    required this.schedule,
    required this.normalSchedule,
  });

  int get yearsSaved     => monthsSaved ~/ 12;
  int get remMonthsSaved => monthsSaved % 12;
}
