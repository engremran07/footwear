import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../core/design/app_tokens.dart';

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
    final baseColor = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final highlightColor = isDark ? Colors.grey.shade700 : Colors.grey.shade100;

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
                horizontal: AppTokens.s16, vertical: AppTokens.s8),
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
                    color: Colors.white,
                    borderRadius: AppTokens.brXS,
                  ),
                ),
                const SizedBox(height: AppTokens.s8),
                Container(
                  width: 120,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.white,
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
          baseColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
          highlightColor: isDark ? Colors.grey.shade700 : Colors.grey.shade100,
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
            itemBuilder: (_, __) => Container(
              decoration: BoxDecoration(
                color: Colors.white,
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
          baseColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
          highlightColor: isDark ? Colors.grey.shade700 : Colors.grey.shade100,
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 24, width: 200, color: Colors.white),
                const SizedBox(height: AppTokens.s16),
                Container(height: 14, color: Colors.white),
                const SizedBox(height: AppTokens.s8),
                Container(height: 14, width: 250, color: Colors.white),
                const SizedBox(height: AppTokens.s24),
                Container(height: 120, color: Colors.white),
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
          baseColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
          highlightColor: isDark ? Colors.grey.shade700 : Colors.grey.shade100,
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
            itemBuilder: (_, __) => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppTokens.brMD,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
