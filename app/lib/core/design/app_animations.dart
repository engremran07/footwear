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
}
