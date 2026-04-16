import '../l10n/app_locale.dart';

/// A single bullet point inside a changelog entry.
class ChangelogItem {
  final String emoji;
  final Map<AppLocale, String> text;

  const ChangelogItem({required this.emoji, required this.text});

  String textFor(AppLocale locale) => text[locale] ?? text[AppLocale.en] ?? '';
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
    version: '3.7.14',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '📄',
        text: {
          AppLocale.en: 'Fixed PDF export crash — export providers no longer self-destruct during Firestore queries.',
          AppLocale.ar: 'تم إصلاح تعطل تصدير PDF — مزودات التصدير لم تعد تتلف أثناء استعلامات Firestore.',
          AppLocale.ur: 'PDF ایکسپورٹ کریش درست کی گئی — ایکسپورٹ پرووائیڈرز Firestore کوئریز کے دوران ختم نہیں ہوتے۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.7.13',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '📄',
        text: {
          AppLocale.en: 'Fixed PDF ledger export (all-shops / per-route) — was crashing during Firebase token refresh mid-export.',
          AppLocale.ar: 'تم إصلاح تصدير PDF للدفتر (جميع المتاجر / لكل خط) — كان يتعطل أثناء تجديد دخول Firebase.',
          AppLocale.ur: 'PDF لیجر ایکسپورٹ درست کی گئی — Firebase ٹوکن ریفریش کے دوران کریش ہوتا تھا۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.7.12',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '🔒',
        text: {
          AppLocale.en:
              'Session lock overlay no longer appears on the login screen when left unattended.',
          AppLocale.ar:
              'لم تعد شاشة قفل الجلسة تظهر على شاشة تسجيل الدخول عند عدم النشاط.',
          AppLocale.ur:
              'لاگن سکرین پر بیکار وقت سیشن لاک والی اسکرین اب ظاھر نہیں ہوگی۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.7.11',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '👤',
        text: {
          AppLocale.en:
              '"Entry By" column in exports now correctly shows '
              'seller names — including for inactive and past sellers.',
          AppLocale.ar:
              'عمود "أدخل بواسطة" في التصديرات يُظهر الآن أسماء '
              'البائعين بشكل صحيح — بما فيهم البائعون غير النشطين.',
          AppLocale.ur:
              'ایکسپورٹس میں "داخل کردہ" کالم اب درست سیلر نام '
              'دکھاتا ہے — غیر فعال اور سابق سیلرز سمیت۔',
        },
      ),
      ChangelogItem(
        emoji: '📁',
        text: {
          AppLocale.en:
              'Exported files now have clear, dated names: '
              'type_subject_YYYY-MM-DD for easy filing.',
          AppLocale.ar:
              'الملفات المُصدَّرة لها الآن أسماء واضحة ومؤرخة: '
              'النوع_الموضوع_YYYY-MM-DD لسهولة الأرشفة.',
          AppLocale.ur:
              'ایکسپورٹ فائلوں کے نام اب واضح اور تاریخ کے ساتھ '
              'ہیں: قسم_موضوع_YYYY-MM-DD آسان فائلنگ کے لیے۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.7.10',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '🏪',
        text: {
          AppLocale.en:
              'All "Customer" labels renamed to "Shop" throughout '
              'reports, PDFs, and exports for consistency.',
          AppLocale.ar:
              'تم تغيير جميع تسميات "العميل" إلى "المتجر" في '
              'التقارير وملفات PDF وعمليات التصدير.',
          AppLocale.ur:
              'تمام "گاہک" لیبلز کو "دکان" میں تبدیل کر دیا گیا '
              'رپورٹس، PDFs اور ایکسپورٹس میں۔',
        },
      ),
      ChangelogItem(
        emoji: '✅',
        text: {
          AppLocale.en:
              'Documentation and governance files updated — '
              'zero markdown lint issues across all project files.',
          AppLocale.ar:
              'تحديث ملفات التوثيق والحوكمة — '
              'صفر مشاكل في تدقيق Markdown عبر جميع الملفات.',
          AppLocale.ur:
              'دستاویزات اور گورننس فائلیں اپ ڈیٹ ہوئیں — '
              'تمام پراجیکٹ فائلوں میں صفر مارک ڈاؤن مسائل۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.7.9',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '📄',
        text: {
          AppLocale.en:
              'Shop account-statement PDF export now works from '
              'every shop — fixed "failed to export" error.',
          AppLocale.ar:
              'تصدير كشف حساب المتجر بصيغة PDF يعمل الآن من كل '
              'متجر — تم إصلاح خطأ "فشل التصدير".',
          AppLocale.ur:
              'دکان کا اکاؤنٹ اسٹیٹمنٹ PDF ایکسپورٹ اب ہر دکان '
              'سے کام کرتا ہے — "ایکسپورٹ ناکام" خطا ٹھیک ہو گئی۔',
        },
      ),
      ChangelogItem(
        emoji: '📋',
        text: {
          AppLocale.en:
              'Export governance — all reports now consistently '
              'show proper ledger format with names and balances.',
          AppLocale.ar:
              'حوكمة التصدير — جميع التقارير تعرض الآن تنسيق '
              'دفتر أستاذ متسق مع الأسماء والأرصدة.',
          AppLocale.ur:
              'ایکسپورٹ گورننس — تمام رپورٹیں اب مستقل لیجر '
              'فارمیٹ میں نام اور بیلنس دکھاتی ہیں۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.7.8',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '👤',
        text: {
          AppLocale.en:
              'Reports now show seller names instead of internal '
              'codes — all exports use proper name resolution.',
          AppLocale.ar:
              'التقارير تعرض الآن أسماء البائعين بدلاً من الرموز '
              'الداخلية — جميع التصديرات تستخدم حل الأسماء الصحيح.',
          AppLocale.ur:
              'رپورٹیں اب اندرونی کوڈز کی بجائے سیلر کے نام '
              'دکھاتی ہیں — تمام ایکسپورٹس صحیح نام استعمال کرتے ہیں۔',
        },
      ),
      ChangelogItem(
        emoji: '🌍',
        text: {
          AppLocale.en:
              'PDF exports now fully support Arabic, Urdu, and '
              'English labels — no more English-only headers.',
          AppLocale.ar:
              'تصدير PDF يدعم الآن العربية والأردية والإنجليزية '
              'بالكامل — لا مزيد من العناوين الإنجليزية فقط.',
          AppLocale.ur:
              'PDF ایکسپورٹس اب عربی، اردو اور انگریزی لیبلز '
              'کی مکمل حمایت کرتے ہیں — صرف انگریزی ہیڈرز نہیں رہے۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.7.7',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '⚡',
        text: {
          AppLocale.en:
              'Faster app startup — optimized provider '
              'initialization and reduced cold-start time.',
          AppLocale.ar:
              'بدء تشغيل أسرع — تحسين تهيئة المزودات وتقليل '
              'وقت البدء البارد.',
          AppLocale.ur:
              'تیز ایپ سٹارٹ اپ — پرووائیڈر شروعات کو بہتر '
              'بنایا اور کولڈ سٹارٹ ٹائم کم کیا۔',
        },
      ),
      ChangelogItem(
        emoji: '📊',
        text: {
          AppLocale.en:
              'Shop ledger PDF export from shop detail screen '
              'now generates proper account statement.',
          AppLocale.ar:
              'تصدير دفتر أستاذ المتجر بصيغة PDF من شاشة تفاصيل '
              'المتجر ينشئ الآن كشف حساب صحيح.',
          AppLocale.ur:
              'شاپ ڈیٹیل اسکرین سے دکان لیجر PDF ایکسپورٹ اب '
              'صحیح اکاؤنٹ اسٹیٹمنٹ بناتا ہے۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.7.6',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '📄',
        text: {
          AppLocale.en:
              'Shop account-statement PDF now works reliably for '
              'all users — fixed the "something went wrong" error.',
          AppLocale.ar:
              'كشف حساب المتجر بصيغة PDF يعمل الآن بشكل موثوق لجميع '
              'المستخدمين — تم إصلاح خطأ "حدث خطأ ما".',
          AppLocale.ur:
              'دکان کا اکاؤنٹ اسٹیٹمنٹ PDF اب سب کے لیے درست '
              'کام کرتا ہے — "کچھ غلط ہو گیا" والی خطا ٹھیک کر دی گئی۔',
        },
      ),
      ChangelogItem(
        emoji: '📊',
        text: {
          AppLocale.en:
              'Multi-shop route ledger PDF works for both admin '
              'and sellers — each seller only sees their own route.',
          AppLocale.ar:
              'كشف حساب المسار متعدد المتاجر يعمل للمدير والبائعين — '
              'كل بائع يرى مساره فقط.',
          AppLocale.ur:
              'ملٹی شاپ روٹ لیجر PDF ایڈمن اور سیلرز دونوں کے '
              'لیے کام کرتا ہے — ہر سیلر صرف اپنا روٹ دیکھتا ہے۔',
        },
      ),
      ChangelogItem(
        emoji: '🔔',
        text: {
          AppLocale.en:
              'New "What\'s New" screen — app now tells you what changed '
              'every time it updates.',
          AppLocale.ar:
              'شاشة "الجديد" الجديدة — يخبرك التطبيق الآن بما '
              'تغيّر في كل تحديث.',
          AppLocale.ur:
              'نئی "نئی خصوصیات" اسکرین — اب ایپ ہر اپڈیٹ میں '
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
          AppLocale.en:
              'Stability improvements — better error messages when '
              'something goes wrong.',
          AppLocale.ar: 'تحسينات الاستقرار — رسائل خطأ أوضح عند حدوث مشاكل.',
          AppLocale.ur: 'استحکام میں بہتری — کچھ غلط ہونے پر واضح پیغامات۔',
        },
      ),
      ChangelogItem(
        emoji: '⚡',
        text: {
          AppLocale.en:
              'Faster data export — transaction exports now load '
              'up to 2,000 records.',
          AppLocale.ar:
              'تصدير بيانات أسرع — تصدير المعاملات يدعم الآن '
              'حتى 2000 سجل.',
          AppLocale.ur:
              'تیز ڈیٹا ایکسپورٹ — ٹرانزیکشن ایکسپورٹ اب '
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
          AppLocale.en:
              'Upgraded libraries for better performance and '
              'compatibility with the latest devices.',
          AppLocale.ar: 'مكتبات محدّثة لأداء أفضل وتوافق مع أحدث الأجهزة.',
          AppLocale.ur:
              'بہتر کارکردگی اور نئے آلات کے ساتھ مطابقت کے لیے '
              'لائبریریاں اپ گریڈ کی گئیں۔',
        },
      ),
      ChangelogItem(
        emoji: '🔙',
        text: {
          AppLocale.en:
              'WhatsApp-style back navigation — swipe from any '
              'screen to go back.',
          AppLocale.ar: 'تنقل خلفي بأسلوب واتساب — اسحب من أي شاشة للعودة.',
          AppLocale.ur:
              'واٹس ایپ طرز کی پیچھے نیویگیشن — کسی بھی اسکرین '
              'سے سوائپ کر کے واپس جائیں۔',
        },
      ),
    ],
  ),
];
