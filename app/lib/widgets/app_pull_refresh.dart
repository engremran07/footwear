import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants/app_brand.dart';

/// Styled RefreshIndicator with brand color + haptic feedback.
class AppPullRefresh extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onRefresh;

  const AppPullRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppBrand.primaryColor,
      onRefresh: () async {
        HapticFeedback.selectionClick();
        await onRefresh();
      },
      child: child,
    );
  }
}
