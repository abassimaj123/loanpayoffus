enum LoanType { mortgage, auto, student, creditCard, personal }

extension LoanTypeExt on LoanType {
  String get label => switch (this) {
    LoanType.mortgage => 'Mortgage',
    LoanType.auto => 'Auto Loan',
    LoanType.student => 'Student Loan',
    LoanType.creditCard => 'Credit Card',
    LoanType.personal => 'Personal Loan',
  };

  double get defaultRate => switch (this) {
    LoanType.mortgage => 6.2,
    LoanType.auto => 6.5,
    LoanType.student => 5.5,
    LoanType.creditCard => 18.5,
    LoanType.personal => 12.0,
  };

  double get defaultAmount => switch (this) {
    LoanType.mortgage => 400000,
    LoanType.auto => 35000,
    LoanType.student => 40000,
    LoanType.creditCard => 5000,
    LoanType.personal => 15000,
  };

  int get defaultTermMonths => switch (this) {
    LoanType.mortgage => 360,
    LoanType.auto => 60,
    LoanType.student => 180,
    LoanType.creditCard => 60,
    LoanType.personal => 84,
  };
}
