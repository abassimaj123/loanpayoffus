import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which partial-payoff milestones have already been shown to the user
/// so they are only displayed once per loan session.
///
/// Milestone keys: 'milestone_shown_25', 'milestone_shown_50', 'milestone_shown_75'
class MilestoneTracker {
  MilestoneTracker._();
  static final instance = MilestoneTracker._();

  /// Returns true if [pct] milestone (25, 50, or 75) has not been shown yet,
  /// then marks it as shown so subsequent calls return false.
  Future<bool> claimIfNew(int pct) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'milestone_shown_$pct';
    if (prefs.getBool(key) == true) return false;
    await prefs.setBool(key, true);
    return true;
  }

  /// Resets all milestone flags — useful when the user starts a new loan.
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove('milestone_shown_25'),
      prefs.remove('milestone_shown_50'),
      prefs.remove('milestone_shown_75'),
    ]);
  }
}
