import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSeenKey = 'whats_new_seen_version';

/// Returns the version string that the user last acknowledged in the
/// "What's New" sheet, or null if never seen.
final changelogSeenVersionProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kSeenKey);
});

/// Marks the given [version] as seen so the sheet won't be shown again for
/// that release.
Future<void> markChangelogSeen(String version) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kSeenKey, version);
}
