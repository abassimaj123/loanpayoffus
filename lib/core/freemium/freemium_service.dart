/// Freemium service — re-exports CalcwiseFreemium from library.
import 'package:calcwise_core/calcwise_core.dart';

final freemiumService = CalcwiseFreemium(
  appKey: 'loanpayoffus',
  rewardedDurationMinutes: MonetizationConfig.rewardedDurationMinutes,
  maxRewardedPerDay: MonetizationConfig.maxRewardedPerDay,
  freeCalculationLimit: MonetizationConfig.freeCalculationLimit,
);
