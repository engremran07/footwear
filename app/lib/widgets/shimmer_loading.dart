import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../core/design/app_tokens.dart';

/// Returns a theme-aware placeholder color for shimmer shapes.
/// Light mode: white (classic shimmer look). Dark mode: dark grey.
Color _placeholderColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? Colors
          .grey
          .shade800 // shimmer
    : Colors.white; // shimmer

/// A shimmer placeholder widget for loading states.
/// Uses the shimmer package for smooth, consistent loading animations.
class ShimmerLoading extends StatelessWidget {
  final int itemCount;
  final bool showLeadingCircle;

  const ShimmerLoading({
    super.key,
    this.itemCount = 6,
    this.showLeadingCircle = true,
  });

  /// Card-style shimmer for dashboard KPI grid
  static Widget cards({int count = 6}) => _ShimmerCards(count: count);

  /// Detail page shimmer with header + sections
  static Widget detail() => const _ShimmerDetail();

  /// Grid shimmer for product cards
  static Widget grid({int count = 6}) => _ShimmerGrid(count: count);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? Colors.grey.shade800
        : Colors.grey.shade300; // shimmer
    final highlightColor = isDark
        ? Colors.grey.shade700
        : Colors.grey.shade100; // shimmer

    return Semantics(
      label: 'Loading data, please wait',
      child: ExcludeSemantics(
        child: Shimmer.fromColors(
          baseColor: baseColor,
          highlightColor: highlightColor,
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: itemCount,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s16,
              vertical: AppTokens.s8,
            ),
            itemBuilder: (_, i) => _ShimmerTile(showCircle: showLeadingCircle),
          ),
        ),
      ),
    );
  }
}

class _ShimmerTile extends StatelessWidget {
  final bool showCircle;
  const _ShimmerTile({required this.showCircle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (showCircle) ...[
            const CircleAvatar(radius: 20),
            const SizedBox(width: AppTokens.s12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: _placeholderColor(context),
                    borderRadius: AppTokens.brXS,
                  ),
                ),
                const SizedBox(height: AppTokens.s8),
                Container(
                  width: 120,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _placeholderColor(context),
                    borderRadius: AppTokens.brXS,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerCards extends StatelessWidget {
  final int count;
  const _ShimmerCards({required this.count});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: 'Loading statistics',
      child: ExcludeSemantics(
        child: Shimmer.fromColors(
          baseColor: isDark
              ? Colors.grey.shade800
              : Colors.grey.shade300, // shimmer
          highlightColor: isDark
              ? Colors.grey.shade700
              : Colors.grey.shade100, // shimmer
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            padding: const EdgeInsets.all(AppTokens.s16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppTokens.s12,
              crossAxisSpacing: AppTokens.s12,
              childAspectRatio: 1.6,
            ),
            itemCount: count,
            itemBuilder: (_, _) => Container(
              decoration: BoxDecoration(
                color: _placeholderColor(context),
                borderRadius: AppTokens.brMD,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShimmerDetail extends StatelessWidget {
  const _ShimmerDetail();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: 'Loading details',
      child: ExcludeSemantics(
        child: Shimmer.fromColors(
          baseColor: isDark
              ? Colors.grey.shade800
              : Colors.grey.shade300, // shimmer
          highlightColor: isDark
              ? Colors.grey.shade700
              : Colors.grey.shade100, // shimmer
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 24,
                  width: 200,
                  color: _placeholderColor(context),
                ),
                const SizedBox(height: AppTokens.s16),
                Container(height: 14, color: _placeholderColor(context)),
                const SizedBox(height: AppTokens.s8),
                Container(
                  height: 14,
                  width: 250,
                  color: _placeholderColor(context),
                ),
                const SizedBox(height: AppTokens.s24),
                Container(height: 120, color: _placeholderColor(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShimmerGrid extends StatelessWidget {
  final int count;
  const _ShimmerGrid({required this.count});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: 'Loading items',
      child: ExcludeSemantics(
        child: Shimmer.fromColors(
          baseColor: isDark
              ? Colors.grey.shade800
              : Colors.grey.shade300, // shimmer
          highlightColor: isDark
              ? Colors.grey.shade700
              : Colors.grey.shade100, // shimmer
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            padding: const EdgeInsets.all(AppTokens.s16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppTokens.s12,
              crossAxisSpacing: AppTokens.s12,
              childAspectRatio: 0.75,
            ),
            itemCount: count,
            itemBuilder: (_, _) => Container(
              decoration: BoxDecoration(
                color: _placeholderColor(context),
                borderRadius: AppTokens.brMD,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
