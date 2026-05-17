import 'package:flutter/material.dart';

enum DebtCategory {
  creditCard,
  studentLoan,
  autoLoan,
  medical,
  personal,
  mortgage,
  other,
}

extension DebtCategoryX on DebtCategory {
  String get id {
    switch (this) {
      case DebtCategory.creditCard:
        return 'credit_card';
      case DebtCategory.studentLoan:
        return 'student_loan';
      case DebtCategory.autoLoan:
        return 'auto_loan';
      case DebtCategory.medical:
        return 'medical';
      case DebtCategory.personal:
        return 'personal';
      case DebtCategory.mortgage:
        return 'mortgage';
      case DebtCategory.other:
        return 'other';
    }
  }

  IconData get icon {
    switch (this) {
      case DebtCategory.creditCard:
        return Icons.credit_card_rounded;
      case DebtCategory.studentLoan:
        return Icons.school_rounded;
      case DebtCategory.autoLoan:
        return Icons.directions_car_rounded;
      case DebtCategory.medical:
        return Icons.medical_services_rounded;
      case DebtCategory.personal:
        return Icons.person_rounded;
      case DebtCategory.mortgage:
        return Icons.house_rounded;
      case DebtCategory.other:
        return Icons.more_horiz_rounded;
    }
  }

  /// Default APR (%) when this category is picked.
  double get defaultApr {
    switch (this) {
      case DebtCategory.creditCard:
        return 22.0;
      case DebtCategory.studentLoan:
        return 6.0;
      case DebtCategory.autoLoan:
        return 7.0;
      case DebtCategory.medical:
        return 0.0;
      case DebtCategory.personal:
        return 10.0;
      case DebtCategory.mortgage:
        return 7.0;
      case DebtCategory.other:
        return 0.0;
    }
  }

  /// Chip color used in lists.
  Color get color {
    switch (this) {
      case DebtCategory.creditCard:
        return const Color(0xFFE53935); // red
      case DebtCategory.studentLoan:
        return const Color(0xFF1E88E5); // blue
      case DebtCategory.autoLoan:
        return const Color(0xFF6D4C41); // brown
      case DebtCategory.medical:
        return const Color(0xFFD81B60); // pink
      case DebtCategory.personal:
        return const Color(0xFF8E24AA); // purple
      case DebtCategory.mortgage:
        return const Color(0xFF00897B); // teal
      case DebtCategory.other:
        return const Color(0xFF607D8B); // blue grey
    }
  }

  String labelEn() {
    switch (this) {
      case DebtCategory.creditCard:
        return 'Credit Card';
      case DebtCategory.studentLoan:
        return 'Student Loan';
      case DebtCategory.autoLoan:
        return 'Auto Loan';
      case DebtCategory.medical:
        return 'Medical';
      case DebtCategory.personal:
        return 'Personal';
      case DebtCategory.mortgage:
        return 'Mortgage';
      case DebtCategory.other:
        return 'Other';
    }
  }

  String labelEs() {
    switch (this) {
      case DebtCategory.creditCard:
        return 'Tarjeta';
      case DebtCategory.studentLoan:
        return 'Estudiantil';
      case DebtCategory.autoLoan:
        return 'Auto';
      case DebtCategory.medical:
        return 'Médico';
      case DebtCategory.personal:
        return 'Personal';
      case DebtCategory.mortgage:
        return 'Hipoteca';
      case DebtCategory.other:
        return 'Otro';
    }
  }

  String label(bool isEs) => isEs ? labelEs() : labelEn();

  static DebtCategory fromId(String? raw) {
    switch (raw) {
      case 'credit_card':
        return DebtCategory.creditCard;
      case 'student_loan':
        return DebtCategory.studentLoan;
      case 'auto_loan':
        return DebtCategory.autoLoan;
      case 'medical':
        return DebtCategory.medical;
      case 'personal':
        return DebtCategory.personal;
      case 'mortgage':
        return DebtCategory.mortgage;
      default:
        return DebtCategory.other;
    }
  }
}
