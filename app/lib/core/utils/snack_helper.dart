import 'package:flutter/material.dart';
import '../constants/app_brand.dart';

/// Convenience helpers for uniform snack bar messages across the app.

void showSuccess(BuildContext ctx, String msg) {
  if (!ctx.mounted) return;
  ScaffoldMessenger.of(ctx).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ],
      ),
      backgroundColor: AppBrand.successColor,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ),
  );
}

void showError(BuildContext ctx, String msg) {
  if (!ctx.mounted) return;
  ScaffoldMessenger.of(ctx).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.error, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ],
      ),
      backgroundColor: AppBrand.errorColor,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ),
  );
}

void showInfo(BuildContext ctx, String msg) {
  if (!ctx.mounted) return;
  ScaffoldMessenger.of(ctx).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.info, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ],
      ),
      backgroundColor: AppBrand.primaryColor,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ),
  );
}
