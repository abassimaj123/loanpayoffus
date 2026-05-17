class DebtPayment {
  final int? id;
  final String debtId;
  final String debtName;
  final double amount;
  final DateTime date;
  final String? note;

  const DebtPayment({
    this.id,
    required this.debtId,
    required this.debtName,
    required this.amount,
    required this.date,
    this.note,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'debt_id': debtId,
    'debt_name': debtName,
    'amount': amount,
    'date_iso': date.toIso8601String(),
    'note': note,
  };

  factory DebtPayment.fromMap(Map<String, dynamic> m) => DebtPayment(
    id: m['id'] as int?,
    debtId: m['debt_id'] as String,
    debtName: m['debt_name'] as String? ?? '',
    amount: (m['amount'] as num).toDouble(),
    date: DateTime.parse(m['date_iso'] as String),
    note: m['note'] as String?,
  );
}
