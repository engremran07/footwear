import 'package:flutter/material.dart';
import '../core/constants/app_brand.dart';

/// Small colored dot indicating online/offline status.
class AppOnlineIndicator extends StatelessWidget {
  final bool isOnline;
  final String semanticLabel;
  final double size;

  const AppOnlineIndicator({
    super.key,
    required this.isOnline,
    required this.semanticLabel,
    this.size = 10,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isOnline ? AppBrand.successColor : colorScheme.error,
            border: Border.all(color: colorScheme.surface, width: 1.5),
          ),
        ),
      ),
    );
  }
}
