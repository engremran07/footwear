import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'app_tokens.dart';

/// Convenience animation presets using flutter_animate.
/// Use: `MyWidget().screenEntry()` or `item.listEntry(index)`.
extension AppAnimations on Widget {
  /// Standard screen entrance: fade + slight slide up.
  Widget screenEntry() => animate()
      .fadeIn(
        duration: AppTokens.durNormal,
        curve: AppTokens.curveEnter,
      )
      .slideY(
        begin: 0.02,
        end: 0,
        duration: AppTokens.durNormal,
        curve: AppTokens.curveEnter,
      );

  /// Staggered list item entrance with index-based delay.
  Widget listEntry(int index) => animate()
      .fadeIn(
        duration: AppTokens.durNormal,
        delay: Duration(milliseconds: 50 * index),
        curve: AppTokens.curveEnter,
      )
      .slideY(
        begin: 0.05,
        end: 0,
        duration: AppTokens.durNormal,
        delay: Duration(milliseconds: 50 * index),
        curve: AppTokens.curveEnter,
      );

  /// Pressable scale feedback for tappable widgets.
  Widget pressable() => animate(onPlay: (c) => c.repeat(reverse: true))
      .scaleXY(end: 0.97, duration: AppTokens.durFast);

  /// Flash green on success.
  Widget successFlash() => animate().shimmer(
        duration: AppTokens.durSlow,
        color: const Color(0x3300C853),
      );

  /// Shake on error.
  Widget errorShake() => animate().shakeX(
        hz: 4,
        amount: 6,
        duration: AppTokens.durSlow,
      );

  // ─── Arctic / Glacial Animations ─────────────────────────────────────────

  /// Smooth slide-up entrance from bottom — used for sheets, cards, FABs.
  Widget frostedSlideUp({
    double beginY = 0.08,
    Duration? duration,
    Duration? delay,
  }) =>
      animate()
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
  Widget arcticFade({Duration? duration, Duration? delay}) =>
      animate().fadeIn(
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
