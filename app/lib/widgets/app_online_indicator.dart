import 'package:flutter/material.dart';
import '../core/constants/app_brand.dart';

/// Small colored dot indicating online/offline status.
class AppOnlineIndicator extends StatelessWidget {
  final bool isOnline;
  final double size;

  const AppOnlineIndicator({super.key, required this.isOnline, this.size = 10});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: isOnline ? 'Online' : 'Offline',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isOnline ? AppBrand.successColor : AppBrand.stockColor,
          border: Border.all(
            color: Theme.of(context).colorScheme.surface,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
