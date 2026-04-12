import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants/app_brand.dart';
import '../core/design/app_tokens.dart';

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? color;
  final String? subtitle;
  final VoidCallback? onTap;
  final int staggerIndex;
  final double? trend; // positive = up, negative = down, null = no trend
  final bool isLoading;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.color,
    this.subtitle,
    this.onTap,
    this.staggerIndex = 0,
    this.trend,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = color ?? theme.colorScheme.primary;

    if (isLoading) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 12,
                width: 80,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: AppTokens.brXS,
                ),
              ),
              const Spacer(),
              Container(
                height: 24,
                width: 60,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: AppTokens.brXS,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
          label: '$title: $value',
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap != null
                  ? () {
                      HapticFeedback.lightImpact();
                      onTap!();
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.s12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: cardColor.withValues(alpha: 0.12),
                            borderRadius: AppTokens.brSM,
                          ),
                          child: Icon(
                            icon,
                            color: cardColor,
                            size: AppTokens.iconSizeSM,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: AppTokens.durNormal,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                value,
                                key: ValueKey(value),
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: cardColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (trend != null) ...[
                          const SizedBox(width: AppTokens.s4),
                          Icon(
                            trend! > 0
                                ? Icons.trending_up
                                : Icons.trending_down,
                            size: 16,
                            color: trend! > 0
                                ? AppBrand.successColor
                                : AppBrand.errorColor,
                          ),
                        ],
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(
          duration: AppTokens.durNormal,
          delay: Duration(milliseconds: 60 * staggerIndex),
          curve: AppTokens.curveEnter,
        )
        .slideY(
          begin: 0.1,
          end: 0,
          duration: AppTokens.durNormal,
          delay: Duration(milliseconds: 60 * staggerIndex),
          curve: AppTokens.curveEnter,
        );
  }
}
