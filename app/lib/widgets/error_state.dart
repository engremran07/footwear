import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/design/app_tokens.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';

enum ErrorType { network, permission, unknown }

Widget mappedErrorState({
  required Object error,
  required WidgetRef ref,
  VoidCallback? onRetry,
}) {
  final key = AppErrorMapper.key(error);
  final errorType = AppErrorMapper.isPermissionOrAuthError(error)
      ? ErrorType.permission
      : (key == 'err_network' ||
            key == 'err_service_unavailable' ||
            key == 'err_timeout')
      ? ErrorType.network
      : ErrorType.unknown;

  return ErrorState(
    message: tr(key, ref),
    errorType: errorType,
    onRetry: onRetry,
    retryLabel: tr('retry', ref),
  );
}

class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final ErrorType errorType;

  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.errorType = ErrorType.unknown,
  });

  IconData get _icon => switch (errorType) {
    ErrorType.network => Icons.wifi_off_rounded,
    ErrorType.permission => Icons.lock_outline_rounded,
    ErrorType.unknown => Icons.error_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _icon,
              size: 64,
              color: theme.colorScheme.error,
            ).animate().shakeX(hz: 3, amount: 5, duration: AppTokens.durSlow),
            const SizedBox(height: AppTokens.s16),
            Text(
              message,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppTokens.s24),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(retryLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
