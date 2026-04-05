import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/snack_helper.dart';

/// About screen — single source of truth for version / build info.
/// Reads from [AppBrand] which is synced by bump_version.dart on every release.
///
/// Accessible via:
///   - Settings → "About" tile
///   - Profile → info button
///   - Route: /about
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('about_us', ref)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          // ── Logo + Name ─────────────────────────────────────────────────
          Center(
            child: Column(
              children: [
                Image.asset(
                  AppBrand.logoAsset,
                  height: 88,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 12),
                Text(
                  AppBrand.appName,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                _VersionBadge(cs: cs),
                const SizedBox(height: 8),
                Text(
                  AppBrand.aboutDescription,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 8),

          // ── Version Details ──────────────────────────────────────────────
          _SectionHeader(label: tr('version_info', ref), cs: cs),
          _InfoTile(
            icon: Icons.info_outline,
            label: tr('app_version', ref),
            value: AppBrand.versionDisplay,
            onTap: () =>
                _copyToClipboard(context, AppBrand.versionDisplay, ref),
          ),
          _InfoTile(
            icon: Icons.build_outlined,
            label: tr('build_number', ref),
            value: AppBrand.buildNumber,
            onTap: () => _copyToClipboard(context, AppBrand.buildNumber, ref),
          ),
          _InfoTile(
            icon: Icons.calendar_today_outlined,
            label: tr('release_date', ref),
            value: 'April 5, 2026',
          ),
          _InfoTile(
            icon: Icons.cloud_outlined,
            label: tr('platform', ref),
            value: 'Firebase Spark — Firestore + Auth',
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // ── Contact ──────────────────────────────────────────────────────
          _SectionHeader(label: tr('contact', ref), cs: cs),
          _InfoTile(
            icon: Icons.email_outlined,
            label: tr('email', ref),
            value: AppBrand.contactEmail,
            onTap: () => _launchUrl('mailto:${AppBrand.contactEmail}', context),
          ),
          _InfoTile(
            icon: Icons.phone_outlined,
            label: tr('phone', ref),
            value: AppBrand.contactPhone,
            onTap: () => _launchUrl(
                'tel:${AppBrand.contactPhone.replaceAll(' ', '')}', context),
          ),
          _InfoTile(
            icon: Icons.language_outlined,
            label: tr('website', ref),
            value: AppBrand.websiteUrl,
            onTap: () => _launchUrl(AppBrand.websiteUrl, context),
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // ── Legal ────────────────────────────────────────────────────────
          _SectionHeader(label: tr('legal', ref), cs: cs),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.article_outlined),
            title: Text(tr('open_source_licenses', ref)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: AppBrand.appName,
              applicationVersion: AppBrand.versionDisplay,
              applicationIcon: Padding(
                padding: const EdgeInsets.all(8),
                child: Image.asset(AppBrand.logoAsset, height: 48),
              ),
            ),
          ),

          const SizedBox(height: 32),
          Center(
            child: Text(
              '© 2026 ${AppBrand.companyName}. All rights reserved.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text, WidgetRef ref) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
        .showSnackBar(successSnackBar(tr('copied', ref)));
  }

  Future<void> _launchUrl(String url, BuildContext context) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(errorSnackBar('Could not open $url'));
      }
    }
  }
}

// ─── Version Badge ────────────────────────────────────────────────────────────

class _VersionBadge extends StatelessWidget {
  final ColorScheme cs;
  const _VersionBadge({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppBrand.primaryColor.withAlpha(20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppBrand.primaryColor.withAlpha(60)),
      ),
      child: const Text(
        AppBrand.versionDisplay,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppBrand.primaryColor,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ─── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final ColorScheme cs;
  const _SectionHeader({required this.label, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: cs.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ─── Info Tile ─────────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: cs.onSurfaceVariant, size: 20),
      title: Text(label,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      subtitle: Text(
        value,
        style: TextStyle(
          fontSize: 14,
          color: cs.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: onTap != null
          ? Icon(Icons.copy_outlined, size: 16, color: cs.onSurfaceVariant)
          : null,
      onTap: onTap,
      mouseCursor: onTap != null ? SystemMouseCursors.click : null,
    );
  }
}
