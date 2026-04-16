import '../l10n/app_locale.dart';

/// A single bullet point inside a changelog entry.
class ChangelogItem {
  final String emoji;
  final Map<AppLocale, String> text;

  const ChangelogItem({required this.emoji, required this.text});

  String textFor(AppLocale locale) =>
      text[locale] ?? text[AppLocale.en] ?? '';
}

/// One release version shown in the "What's New" sheet.
class ChangelogEntry {
  final String version;
  final String date;
  final List<ChangelogItem> items;

  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.items,
  });
}

/// Human-friendly changelog shown to users on first launch after an update.
/// Add a new [ChangelogEntry] at the TOP of this list for every release.
/// Keep language simple — no tech jargon, no internal codes.
const List<ChangelogEntry> kChangelog = [
  ChangelogEntry(
    version: '3.7.6',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '📄',
        text: {
          AppLocale.en: 'Shop account-statement PDF now works reliably for '
              'all users — fixed the "something went wrong" error.',
          AppLocale.ar: 'كشف حساب المتجر بصيغة PDF يعمل الآن بشكل موثوق لجميع '
              'المستخدمين — تم إصلاح خطأ "حدث خطأ ما".',
          AppLocale.ur: 'دکان کا اکاؤنٹ اسٹیٹمنٹ PDF اب سب کے لیے درست '
              'کام کرتا ہے — "کچھ غلط ہو گیا" والی خطا ٹھیک کر دی گئی۔',
        },
      ),
      ChangelogItem(
        emoji: '📊',
        text: {
          AppLocale.en: 'Multi-shop route ledger PDF works for both admin '
              'and sellers — each seller only sees their own route.',
          AppLocale.ar: 'كشف حساب المسار متعدد المتاجر يعمل للمدير والبائعين — '
              'كل بائع يرى مساره فقط.',
          AppLocale.ur: 'ملٹی شاپ روٹ لیجر PDF ایڈمن اور سیلرز دونوں کے '
              'لیے کام کرتا ہے — ہر سیلر صرف اپنا روٹ دیکھتا ہے۔',
        },
      ),
      ChangelogItem(
        emoji: '🔔',
        text: {
          AppLocale.en:
              'New "What\'s New" screen — app now tells you what changed '
              'every time it updates.',
          AppLocale.ar: 'شاشة "الجديد" الجديدة — يخبرك التطبيق الآن بما '
              'تغيّر في كل تحديث.',
          AppLocale.ur: 'نئی "نئی خصوصیات" اسکرین — اب ایپ ہر اپڈیٹ میں '
              'نئی تبدیلیاں بتاتی ہے۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.7.5',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '🛡️',
        text: {
          AppLocale.en: 'Stability improvements — better error messages when '
              'something goes wrong.',
          AppLocale.ar: 'تحسينات الاستقرار — رسائل خطأ أوضح عند حدوث مشاكل.',
          AppLocale.ur: 'استحکام میں بہتری — کچھ غلط ہونے پر واضح پیغامات۔',
        },
      ),
      ChangelogItem(
        emoji: '⚡',
        text: {
          AppLocale.en: 'Faster data export — transaction exports now load '
              'up to 2,000 records.',
          AppLocale.ar: 'تصدير بيانات أسرع — تصدير المعاملات يدعم الآن '
              'حتى 2000 سجل.',
          AppLocale.ur: 'تیز ڈیٹا ایکسپورٹ — ٹرانزیکشن ایکسپورٹ اب '
              '2,000 ریکارڈ تک لوڈ کرتا ہے۔',
        },
      ),
      ChangelogItem(
        emoji: '🎨',
        text: {
          AppLocale.en: 'Cleaner offline indicator and shimmer loading cards.',
          AppLocale.ar: 'مؤشر اتصال أنظف وبطاقات تحميل أجمل.',
          AppLocale.ur: 'بہتر آف لائن اشارہ اور خوبصورت لوڈنگ کارڈز۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.7.0',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '🔄',
        text: {
          AppLocale.en: 'Upgraded libraries for better performance and '
              'compatibility with the latest devices.',
          AppLocale.ar: 'مكتبات محدّثة لأداء أفضل وتوافق مع أحدث الأجهزة.',
          AppLocale.ur: 'بہتر کارکردگی اور نئے آلات کے ساتھ مطابقت کے لیے '
              'لائبریریاں اپ گریڈ کی گئیں۔',
        },
      ),
      ChangelogItem(
        emoji: '🔙',
        text: {
          AppLocale.en: 'WhatsApp-style back navigation — swipe from any '
              'screen to go back.',
          AppLocale.ar: 'تنقل خلفي بأسلوب واتساب — اسحب من أي شاشة للعودة.',
          AppLocale.ur: 'واٹس ایپ طرز کی پیچھے نیویگیشن — کسی بھی اسکرین '
              'سے سوائپ کر کے واپس جائیں۔',
        },
      ),
    ],
  ),
];
