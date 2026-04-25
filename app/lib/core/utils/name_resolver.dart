import '../../models/user_model.dart';

/// Single source of truth for resolving user IDs → display names in exports.
///
/// All export/report code paths MUST use this resolver instead of building
/// ad-hoc `entryByMap` maps. This ensures:
///   1. No raw UIDs ever leak into PDFs, Excel, images, or prints.
///   2. Consistent fallback to [unknownLabel] (never a Firestore doc ID).
///   3. One cache shared across the entire export pipeline.
class NameResolver {
  final Map<String, String> _cache;
  final String unknownLabel;

  /// Creates a resolver from a list of [UserModel].
  /// Optionally merge [extra] entries (e.g. current user if not in admin list).
  NameResolver({
    required List<UserModel> users,
    Map<String, String> extra = const {},
    this.unknownLabel = '—',
  }) : assert(unknownLabel.isNotEmpty, 'unknownLabel must not be empty'),
       _cache = {for (final u in users) u.id: u.displayName, ...extra};

  /// Resolves [uid] to a display name. Returns [unknownLabel] for unknown IDs.
  String resolve(String uid) => _cache[uid] ?? unknownLabel;

  /// Returns the full uid→name map (for passing to PDF/Excel builders).
  Map<String, String> get map => Map.unmodifiable(_cache);
}
