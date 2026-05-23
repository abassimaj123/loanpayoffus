import 'debt_category.dart';

class DebtItem {
  /// Stable id used to link payments. Generated when omitted.
  final String id;
  final String name;
  final double balance;

  /// Original balance — kept for progress tracking when balance is reduced.
  final double originalBalance;
  final double annualRate;
  final double minPayment;
  final DebtCategory category;

  /// User-defined sort priority for the Custom Order strategy (0 = first).
  final int priority;

  const DebtItem({
    required this.id,
    required this.name,
    required this.balance,
    required this.annualRate,
    required this.minPayment,
    this.category = DebtCategory.other,
    this.priority = 0,
    double? originalBalance,
  }) : originalBalance = originalBalance ?? balance;

  /// Convenience factory that auto-generates an id from current time.
  factory DebtItem.create({
    required String name,
    required double balance,
    required double annualRate,
    required double minPayment,
    DebtCategory category = DebtCategory.other,
    double? originalBalance,
    String? id,
  }) => DebtItem(
    id: id ?? DateTime.now().microsecondsSinceEpoch.toString(),
    name: name,
    balance: balance,
    annualRate: annualRate,
    minPayment: minPayment,
    category: category,
    originalBalance: originalBalance ?? balance,
  );

  DebtItem copyWith({
    String? id,
    String? name,
    double? balance,
    double? originalBalance,
    double? annualRate,
    double? minPayment,
    DebtCategory? category,
    int? priority,
  }) => DebtItem(
    id: id ?? this.id,
    name: name ?? this.name,
    balance: balance ?? this.balance,
    originalBalance: originalBalance ?? this.originalBalance,
    annualRate: annualRate ?? this.annualRate,
    minPayment: minPayment ?? this.minPayment,
    category: category ?? this.category,
    priority: priority ?? this.priority,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'balance': balance,
    'originalBalance': originalBalance,
    'annualRate': annualRate,
    'minPayment': minPayment,
    'category': category.id,
    'priority': priority,
  };

  factory DebtItem.fromJson(Map<String, dynamic> json) => DebtItem(
    id:
        (json['id'] as String?) ??
        DateTime.now().microsecondsSinceEpoch.toString(),
    name: json['name'] as String,
    balance: (json['balance'] as num).toDouble(),
    originalBalance:
        (json['originalBalance'] as num?)?.toDouble() ??
        (json['balance'] as num).toDouble(),
    annualRate: (json['annualRate'] as num).toDouble(),
    minPayment: (json['minPayment'] as num).toDouble(),
    category: DebtCategoryX.fromId(json['category'] as String?),
    priority: (json['priority'] as int?) ?? 0,
  );
}
