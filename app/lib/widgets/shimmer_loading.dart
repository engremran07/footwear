import 'package:flutter/material.dart';

/// A shimmer placeholder widget for loading states.
/// Built with AnimationController — no external packages needed.
class ShimmerLoading extends StatefulWidget {
  final int itemCount;
  final bool showLeadingCircle;

  const ShimmerLoading({
    super.key,
    this.itemCount = 6,
    this.showLeadingCircle = true,
  });

  /// Card-style shimmer for dashboard KPI grid
  static Widget cards({int count = 6}) => _ShimmerCards(count: count);

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.itemCount,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemBuilder: (_, i) => _ShimmerTile(
            animation: _controller,
            showCircle: widget.showLeadingCircle,
          ),
        );
      },
    );
  }
}

class _ShimmerTile extends StatelessWidget {
  final Animation<double> animation;
  final bool showCircle;

  const _ShimmerTile({required this.animation, required this.showCircle});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final highlightColor = isDark ? Colors.grey.shade700 : Colors.grey.shade100;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (showCircle) ...[
            _ShimmerBox(
              width: 40,
              height: 40,
              borderRadius: 20,
              animation: animation,
              baseColor: baseColor,
              highlightColor: highlightColor,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ShimmerBox(
                  width: double.infinity,
                  height: 14,
                  borderRadius: 4,
                  animation: animation,
                  baseColor: baseColor,
                  highlightColor: highlightColor,
                ),
                const SizedBox(height: 8),
                _ShimmerBox(
                  width: 120,
                  height: 10,
                  borderRadius: 4,
                  animation: animation,
                  baseColor: baseColor,
                  highlightColor: highlightColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final Animation<double> animation;
  final Color baseColor;
  final Color highlightColor;

  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.animation,
    required this.baseColor,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment(-1.0 + 2.0 * animation.value, 0),
          end: Alignment(1.0 + 2.0 * animation.value, 0),
          colors: [baseColor, highlightColor, baseColor],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

class _ShimmerCards extends StatefulWidget {
  final int count;
  const _ShimmerCards({required this.count});

  @override
  State<_ShimmerCards> createState() => _ShimmerCardsState();
}

class _ShimmerCardsState extends State<_ShimmerCards>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final highlightColor = isDark ? Colors.grey.shade700 : Colors.grey.shade100;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List.generate(
            widget.count,
            (_) => SizedBox(
              width: 160,
              height: 100,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ShimmerBox(
                        width: 80,
                        height: 10,
                        borderRadius: 4,
                        animation: _controller,
                        baseColor: baseColor,
                        highlightColor: highlightColor,
                      ),
                      const SizedBox(height: 12),
                      _ShimmerBox(
                        width: 60,
                        height: 20,
                        borderRadius: 4,
                        animation: _controller,
                        baseColor: baseColor,
                        highlightColor: highlightColor,
                      ),
                      const Spacer(),
                      _ShimmerBox(
                        width: 100,
                        height: 8,
                        borderRadius: 4,
                        animation: _controller,
                        baseColor: baseColor,
                        highlightColor: highlightColor,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
