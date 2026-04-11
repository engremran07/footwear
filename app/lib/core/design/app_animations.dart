import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'app_tokens.dart';

/// Convenience animation presets using flutter_animate.
/// Use: `MyWidget().screenEntry()` or `item.listEntry(index)`.
extension AppAnimations on Widget {
  /// Standard screen entrance: fade + slight slide up.
  Widget screenEntry() => animate()
      .fadeIn(duration: AppTokens.durNormal, curve: AppTokens.curveEnter)
      .slideY(
        begin: 0.02,
        end: 0,
        duration: AppTokens.durNormal,
        curve: AppTokens.curveEnter,
      );

  /// Staggered list item entrance with index-based delay.
  Widget listEntry(int index) {
    final cappedIndex = index.clamp(0, 10);
    return animate()
        .fadeIn(
          duration: AppTokens.durNormal,
          delay: Duration(milliseconds: 50 * cappedIndex),
          curve: AppTokens.curveEnter,
        )
        .slideY(
          begin: 0.05,
          end: 0,
          duration: AppTokens.durNormal,
          delay: Duration(milliseconds: 50 * cappedIndex),
          curve: AppTokens.curveEnter,
        );
  }

  /// Wraps this widget with tap-reactive press scale feedback.
  /// Uses [PressableWidget] — NOT an infinite loop animation.
  Widget pressable({VoidCallback? onTap}) =>
      PressableWidget(onTap: onTap, child: this);

  /// Flash green on success.
  Widget successFlash() => animate().shimmer(
    duration: AppTokens.durSlow,
    color: const Color(0x3300C853),
  );

  /// Shake on error.
  Widget errorShake() =>
      animate().shakeX(hz: 4, amount: 6, duration: AppTokens.durSlow);

  // ─── Arctic / Glacial Animations ─────────────────────────────────────────

  /// Smooth slide-up entrance from bottom — used for sheets, cards, FABs.
  Widget frostedSlideUp({
    double beginY = 0.08,
    Duration? duration,
    Duration? delay,
  }) => animate()
      .slideY(
        begin: beginY,
        end: 0,
        duration: duration ?? AppTokens.durGlacial,
        delay: delay,
        curve: Curves.fastOutSlowIn,
      )
      .fadeIn(
        duration: duration ?? AppTokens.durGlacial,
        delay: delay,
        curve: Curves.easeOut,
      );

  /// Glacial slow fade-in — for hero images and splash overlays.
  Widget arcticFade({Duration? duration, Duration? delay}) => animate().fadeIn(
    duration: duration ?? AppTokens.durGlacial,
    delay: delay,
    curve: Curves.easeInOutCubic,
  );

  /// Elastic pop entrance — scale from 0 with bounce.
  Widget impactBounce({Duration? delay}) => animate()
      .scaleXY(
        begin: 0.6,
        end: 1.0,
        duration: AppTokens.durSlow,
        delay: delay,
        curve: Curves.elasticOut,
      )
      .fadeIn(
        duration: AppTokens.durNormal,
        delay: delay,
        curve: Curves.easeOut,
      );

  /// Spacious stagger — 80 ms per index. Ideal for dashboard tiles.
  Widget glacialStagger(int index, {double beginY = 0.04}) => animate()
      .fadeIn(
        duration: AppTokens.durSlow,
        delay: AppTokens.durStaggerStep * index,
        curve: AppTokens.curveEnter,
      )
      .slideY(
        begin: beginY,
        end: 0,
        duration: AppTokens.durSlow,
        delay: AppTokens.durStaggerStep * index,
        curve: AppTokens.curveEnter,
      );

  /// Quick pop-in: scale 0.85 → 1.0 with fade (dialog buttons, chips, badges).
  Widget popIn({Duration? delay}) => animate()
      .scaleXY(
        begin: 0.85,
        end: 1.0,
        duration: AppTokens.durNormal,
        delay: delay,
        curve: AppTokens.curveSpring,
      )
      .fadeIn(
        duration: AppTokens.durNormal,
        delay: delay,
        curve: Curves.easeOut,
      );

  /// Quick horizontal slide used when switching bottom nav tabs via swipe.
  Widget tabEntry({bool fromRight = true, Duration? delay}) => animate()
      .slideX(
        begin: fromRight ? 0.04 : -0.04,
        end: 0,
        duration: AppTokens.durNormal,
        delay: delay,
        curve: Curves.easeOutCubic,
      )
      .fadeIn(
        duration: AppTokens.durNormal,
        delay: delay,
        curve: Curves.easeOut,
      );
}

// ─── PressableWidget ──────────────────────────────────────────────────────────

/// Tap-reactive scale-down feedback widget.
/// Scale animates 1.0 → 0.96 on tap-down and reverses on tap-up.
/// Does NOT run an infinite loop — animation fires only on user interaction.
class PressableWidget extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const PressableWidget({super.key, required this.child, this.onTap});

  @override
  State<PressableWidget> createState() => _PressableWidgetState();
}

class _PressableWidgetState extends State<PressableWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 80),
    value: 0,
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 1.0,
    end: 0.96,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _ctrl.forward(),
    onTapUp: (_) {
      _ctrl.reverse();
      widget.onTap?.call();
    },
    onTapCancel: () => _ctrl.reverse(),
    child: AnimatedBuilder(
      animation: _scale,
      builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
      child: widget.child,
    ),
  );
}
