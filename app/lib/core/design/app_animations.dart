import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'app_tokens.dart';

class AppMotion {
  AppMotion._();

  static bool isEnabled(BuildContext context) =>
      !MediaQuery.of(context).disableAnimations;

  static Duration duration(BuildContext context, Duration duration) =>
      isEnabled(context) ? duration : Duration.zero;
}

Widget _withOptionalMotion(
  Widget child,
  Widget Function(Widget child) applyMotion,
) => Builder(
  builder: (context) =>
      AppMotion.isEnabled(context) ? applyMotion(child) : child,
);

/// Convenience animation presets using flutter_animate.
/// Use: `MyWidget().screenEntry()` or `item.listEntry(index)`.
extension AppAnimations on Widget {
  /// Standard screen entrance: fade + slight slide up.
  Widget screenEntry() => _withOptionalMotion(
    this,
    (child) => child
        .animate()
        .fadeIn(duration: AppTokens.durNormal, curve: AppTokens.curveEnter)
        .slideY(
          begin: 0.02,
          end: 0,
          duration: AppTokens.durNormal,
          curve: AppTokens.curveEnter,
        ),
  );

  /// Staggered list item entrance with index-based delay.
  Widget listEntry(int index) {
    final cappedIndex = index.clamp(0, 10);
    return _withOptionalMotion(
      this,
      (child) => child
          .animate()
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
          ),
    );
  }

  /// Wraps this widget with tap-reactive press scale feedback.
  /// Uses [PressableWidget] — NOT an infinite loop animation.
  Widget pressable({VoidCallback? onTap}) =>
      PressableWidget(onTap: onTap, child: this);

  /// Flash green on success.
  Widget successFlash() => _withOptionalMotion(
    this,
    (child) => child.animate().shimmer(
      duration: AppTokens.durSlow,
      color: const Color(0x3300C853),
    ),
  );

  /// Shake on error.
  Widget errorShake() => _withOptionalMotion(
    this,
    (child) =>
        child.animate().shakeX(hz: 4, amount: 6, duration: AppTokens.durSlow),
  );

  // ─── Arctic / Glacial Animations ─────────────────────────────────────────

  /// Smooth slide-up entrance from bottom — used for sheets, cards, FABs.
  Widget frostedSlideUp({
    double beginY = 0.08,
    Duration? duration,
    Duration? delay,
  }) => _withOptionalMotion(
    this,
    (child) => child
        .animate()
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
        ),
  );

  /// Glacial slow fade-in — for hero images and splash overlays.
  Widget arcticFade({Duration? duration, Duration? delay}) =>
      _withOptionalMotion(
        this,
        (child) => child.animate().fadeIn(
          duration: duration ?? AppTokens.durGlacial,
          delay: delay,
          curve: Curves.easeInOutCubic,
        ),
      );

  /// Elastic pop entrance — scale from 0 with bounce.
  Widget impactBounce({Duration? delay}) => _withOptionalMotion(
    this,
    (child) => child
        .animate()
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
        ),
  );

  /// Spacious stagger — 80 ms per index. Ideal for dashboard tiles.
  Widget glacialStagger(int index, {double beginY = 0.04}) =>
      _withOptionalMotion(
        this,
        (child) => child
            .animate()
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
            ),
      );

  /// Quick pop-in: scale 0.85 → 1.0 with fade (dialog buttons, chips, badges).
  Widget popIn({Duration? delay}) => _withOptionalMotion(
    this,
    (child) => child
        .animate()
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
        ),
  );

  /// Quick horizontal slide used when switching bottom nav tabs via swipe.
  Widget tabEntry({bool fromRight = true, Duration? delay}) =>
      _withOptionalMotion(
        this,
        (child) => child
            .animate()
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
            ),
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
    onTapDown: AppMotion.isEnabled(context) ? (_) => _ctrl.forward() : null,
    onTapUp: (_) {
      if (AppMotion.isEnabled(context)) _ctrl.reverse();
      widget.onTap?.call();
    },
    onTapCancel: AppMotion.isEnabled(context) ? () => _ctrl.reverse() : null,
    child: AnimatedBuilder(
      animation: _scale,
      builder: (_, child) => AppMotion.isEnabled(context)
          ? Transform.scale(scale: _scale.value, child: child)
          : child!,
      child: widget.child,
    ),
  );
}
