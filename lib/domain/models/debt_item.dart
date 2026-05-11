class DebtItem {
  final String name;
  final double balance;
  final double annualRate;
  final double minPayment;

  const DebtItem({
    required this.name,
    required this.balance,
    required this.annualRate,
    required this.minPayment,
  });

  DebtItem copyWith({
    String? name,
    double? balance,
    double? annualRate,
    double? minPayment,
  }) =>
      DebtItem(
        name:       name       ?? this.name,
        balance:    balance    ?? this.balance,
        annualRate: annualRate ?? this.annualRate,
        minPayment: minPayment ?? this.minPayment,
      );

  Map<String, dynamic> toJson() => {
        'name':        name,
        'balance':     balance,
        'annualRate':  annualRate,
        'minPayment':  minPayment,
      };

  factory DebtItem.fromJson(Map<String, dynamic> json) => DebtItem(
        name:       json['name']       as String,
        balance:    (json['balance']   as num).toDouble(),
        annualRate: (json['annualRate'] as num).toDouble(),
        minPayment: (json['minPayment'] as num).toDouble(),
      );
}
