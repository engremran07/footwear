import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_brand.dart';
import '../core/data/changelog_data.dart';
import '../core/l10n/app_locale.dart';
import '../providers/changelog_provider.dart';

/// Shows the "What's New" bottom sheet — WhatsApp-style, full-height.
///
/// Automatically shown once per version update (triggered by [AppShell]).
/// Also accessible via the About screen.
class WhatsNewSheet {
  WhatsNewSheet._();

  /// Show the sheet and immediately persist the current version as seen.
  ///
  /// Persisting before the modal opens means any dismiss gesture (swipe-down,
  /// tap-outside, or the Got-It button) all prevent the sheet from reappearing
  /// on the next launch — best-practice UX pattern for "new release" notices.
  static Future<void> show(BuildContext context, WidgetRef ref) async {
    await markChangelogSeen(AppBrand.appVersion);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _WhatsNewContent(ref: ref),
    );
  }
}

class _WhatsNewContent extends ConsumerWidget {
  final WidgetRef ref;
  const _WhatsNewContent({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final locale = widgetRef.watch(appLocaleProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isRtl =
        locale == AppLocale.ar || locale == AppLocale.ur;

    String t(String key) => _tr(key, locale);

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Image.asset(
                    AppBrand.logoAsset,
                    fit: BoxFit.contain,
                    scale: 1.5,
                    errorBuilder: (_, e, s) => Icon(
                      Icons.auto_awesome,
                      color: cs.primary,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: isRtl
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('whats_new'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        t('whats_new_subtitle'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1),

          // Changelog entries
          Expanded(
            child: Directionality(
              textDirection:
                  isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                itemCount: kChangelog.length,
                itemBuilder: (_, i) {
                  final entry = kChangelog[i];
                  return _EntrySection(
                    entry: entry,
                    locale: locale,
                    theme: theme,
                    cs: cs,
                    isFirst: i == 0,
                  );
                },
              ),
            ),
          ),

          // Got It button
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  t('got_it'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntrySection extends StatelessWidget {
  final ChangelogEntry entry;
  final AppLocale locale;
  final ThemeData theme;
  final ColorScheme cs;
  final bool isFirst;

  const _EntrySection({
    required this.entry,
    required this.locale,
    required this.theme,
    required this.cs,
    required this.isFirst,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Version badge + date
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: isFirst
                      ? cs.primaryContainer
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'v${entry.version}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isFirst ? cs.onPrimaryContainer : cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                entry.date,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (isFirst) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'NEW',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Bullet items
          ...entry.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.emoji,
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.textFor(locale),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal L10n lookup without WidgetRef (used inside non-Consumer widget).
String _tr(String key, AppLocale locale) {
  const Map<AppLocale, Map<String, String>> local = {
    AppLocale.en: {
      'whats_new': "What's New",
      'whats_new_subtitle': "Here's what changed in this update",
      'got_it': 'Got It',
    },
    AppLocale.ar: {
      'whats_new': 'الجديد',
      'whats_new_subtitle': 'إليك ما تغيّر في هذا التحديث',
      'got_it': 'حسناً',
    },
    AppLocale.ur: {
      'whats_new': 'نئی خصوصیات',
      'whats_new_subtitle': 'اس اپڈیٹ میں کیا تبدیل ہوا',
      'got_it': 'سمجھ گیا',
    },
  };
  return local[locale]?[key] ?? local[AppLocale.en]?[key] ?? key;
}
