import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/design/app_tokens.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../providers/theme_preference_provider.dart';

enum StatusChipSize { sm, md, lg }

class StatusChip extends ConsumerWidget {
  final String status;
  final StatusChipSize size;

  const StatusChip({
    super.key,
    required this.status,
    this.size = StatusChipSize.md,
  });

  IconData _iconForStatus(String s) {
    return switch (s.toLowerCase()) {
      'active' ||
      'complete' ||
      'delivered' ||
      'paid' ||
      'qc_passed' => Icons.check_circle_outline,
      'pending' ||
      'draft' ||
      'qc_pending' ||
      'pending_approval' => Icons.schedule,
      'rejected' ||
      'cancelled' ||
      'qc_issues' ||
      'stock_issue' ||
      'void' => Icons.cancel_outlined,
      'processing' ||
      'in_production' ||
      'in_transit' ||
      'shipped' => Icons.local_shipping_outlined,
      'partial' => Icons.warning_amber_outlined,
      'issued' => Icons.send_outlined,
      'credit_note' => Icons.note_outlined,
      _ => Icons.circle_outlined,
    };
  }

  double _fontSize() => switch (size) {
    StatusChipSize.sm => 10,
    StatusChipSize.md => 11,
    StatusChipSize.lg => 13,
  };

  double _iconSize() => switch (size) {
    StatusChipSize.sm => 12,
    StatusChipSize.md => 14,
    StatusChipSize.lg => 16,
  };

  EdgeInsets _padding() => switch (size) {
    StatusChipSize.sm => const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    StatusChipSize.md => const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 4,
    ),
    StatusChipSize.lg => const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 6,
    ),
  };

  String _statusLabel(String value, WidgetRef ref) {
    final key = switch (value.toLowerCase()) {
      'complete' => 'completed',
      'pending_approval' => 'pending_admin_approval',
      'ready_for_shipment' => 'mark_ready_shipment',
      'received' => 'stock_received',
      'active' ||
      'approved' ||
      'cancelled' ||
      'credit_note' ||
      'delivered' ||
      'draft' ||
      'in_production' ||
      'in_transit' ||
      'issued' ||
      'paid' ||
      'partial' ||
      'pending' ||
      'processing' ||
      'qc_issues' ||
      'qc_passed' ||
      'qc_pending' ||
      'rejected' ||
      'reserved' ||
      'sent' ||
      'shipped' ||
      'stock_issue' ||
      'void' => value.toLowerCase(),
      _ => 'unknown_status_chip',
    };
    return tr(key, ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themePreferenceProvider);
    final color = AppTheme.statusColor(
      status,
      mode: mode,
      brightness: Theme.of(context).brightness,
    );
    final readable = _statusLabel(status, ref);
    return Semantics(
      label: '${tr('status', ref)}: $readable',
      child: AnimatedSwitcher(
        duration: AppTokens.durNormal,
        child: Container(
          key: ValueKey(status),
          padding: _padding(),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppTokens.rMD),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconForStatus(status), size: _iconSize(), color: color),
              const SizedBox(width: AppTokens.s4),
              Text(
                readable,
                style: TextStyle(
                  fontSize: _fontSize(),
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
