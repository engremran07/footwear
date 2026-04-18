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
    version: '3.7.18',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '📄',
        text: {
          AppLocale.en:
              'PDF sharing fixed: multi-shop ledger and invoice PDF exports now use a more reliable sharing method that works on all Android versions.',
          AppLocale.ar:
              'إصلاح مشاركة PDF: تصدير كشف حساب المتاجر والفواتير يستخدم الآن طريقة مشاركة أكثر موثوقية تعمل على جميع إصدارات أندرويد.',
          AppLocale.ur:
              'PDF شیئرنگ ٹھیک: ملٹی شاپ لیجر اور انوائس PDF ایکسپورٹ اب ایک زیادہ قابل اعتماد شیئرنگ طریقہ استعمال کرتے ہیں جو تمام اینڈرائیڈ ورژنز پر کام کرتا ہے۔',
        },
      ),
      ChangelogItem(
        emoji: '🔍',
        text: {
          AppLocale.en:
              'Better error diagnostics: PDF export errors are now logged to Crashlytics for faster troubleshooting.',
          AppLocale.ar:
              'تشخيص أفضل للأخطاء: أخطاء تصدير PDF تُسجَّل الآن في Crashlytics لتسريع استكشاف الأخطاء.',
          AppLocale.ur:
              'بہتر ایرر تشخیص: PDF ایکسپورٹ ایررز اب Crashlytics میں لاگ ہوتے ہیں تاکہ مسائل تیزی سے حل ہوں۔',
        },
      ),
      ChangelogItem(
        emoji: '🖨️',
        text: {
          AppLocale.en:
              'Unified export pipeline: invoices and multi-shop ledgers now offer Excel, PDF, PNG, and Print options from a single export sheet.',
          AppLocale.ar:
              'خط تصدير موحّد: الفواتير وكشوف حسابات المتاجر تقدم الآن خيارات Excel وPDF وPNG والطباعة من ورقة تصدير واحدة.',
          AppLocale.ur:
              'متحد ایکسپورٹ پائپ لائن: انوائسز اور ملٹی شاپ لیجرز اب ایک ایکسپورٹ شیٹ سے Excel، PDF، PNG، اور پرنٹ کے آپشنز پیش کرتے ہیں۔',
        },
      ),
      ChangelogItem(
        emoji: '🌍',
        text: {
          AppLocale.en:
              'Invoice PDF fully localized: all labels now display in your chosen language (Arabic, Urdu, or English).',
          AppLocale.ar:
              'فاتورة PDF مترجمة بالكامل: جميع التسميات تظهر الآن بلغتك المختارة (العربية، الأردية، أو الإنجليزية).',
          AppLocale.ur:
              'انوائس PDF مکمل طور پر مقامی: تمام لیبلز اب آپ کی منتخب زبان (عربی، اردو، یا انگریزی) میں ظاہر ہوتے ہیں۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.7.17',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '🛡️',
        text: {
          AppLocale.en:
              'Export & save reliability: all screens now wait for your user data to fully load before exporting or saving — no more blank reports or silent failures.',
          AppLocale.ar:
              'موثوقية التصدير والحفظ: جميع الشاشات تنتظر الآن تحميل بيانات المستخدم بالكامل قبل التصدير أو الحفظ — لا مزيد من التقارير الفارغة أو الأخطاء الصامتة.',
          AppLocale.ur:
              'ایکسپورٹ اور محفوظ کرنے کی قابل اعتمادی: تمام اسکرینز اب ایکسپورٹ یا محفوظ کرنے سے پہلے آپ کے صارف ڈیٹا کے مکمل لوڈ ہونے کا انتظار کرتی ہیں — مزید خالی رپورٹس یا خاموش ناکامیاں نہیں۔',
        },
      ),
      ChangelogItem(
        emoji: '🧹',
        text: {
          AppLocale.en:
              'Removed unused code for a leaner, faster app.',
          AppLocale.ar:
              'إزالة الأكواد غير المستخدمة لتطبيق أسرع وأخف.',
          AppLocale.ur:
              'غیر استعمال شدہ کوڈ ہٹایا گیا تاکہ ایپ ہلکی اور تیز ہو۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.7.15',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '📊',
        text: {
          AppLocale.en:
              'Seller report PDF now loads fresh data reliably — no more "PDF generation failed" on first tap.',
          AppLocale.ar:
              'تقرير البائع PDF يحمّل البيانات الحديثة بموثوقية — لا مزيد من رسالة "فشل إنشاء PDF" عند أول ضغطة.',
          AppLocale.ur:
              'سیلر رپورٹ PDF اب قابل اعتماد طریقے سے تازہ ڈیٹا لوڈ کرتی ہے — پہلی ٹیپ پر "PDF ناکام" کی خطا نہیں آئے گی۔',
        },
      ),
      ChangelogItem(
        emoji: '📄',
        text: {
          AppLocale.en:
              'Shop account-statement PDF now always reads latest company settings before generating.',
          AppLocale.ar:
              'تقرير حساب المتجر يقرأ الآن أحدث إعدادات الشركة قبل الإنشاء.',
          AppLocale.ur:
              'دکان اکاؤنٹ سٹیٹمنٹ PDF بنانے سے پہلے کمپنی کی تازہ ترین ترتیبات پڑھتا ہے۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.7.14',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '📄',
        text: {
          AppLocale.en:
              'Fixed PDF export crash — export providers no longer self-destruct during Firestore queries.',
          AppLocale.ar:
              'تم إصلاح تعطل تصدير PDF — مزودات التصدير لم تعد تتلف أثناء استعلامات Firestore.',
          AppLocale.ur:
              'PDF ایکسپورٹ کریش درست کی گئی — ایکسپورٹ پرووائیڈرز Firestore کوئریز کے دوران ختم نہیں ہوتے۔',
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
          AppLocale.en:
              'Fixed PDF ledger export (all-shops / per-route) — was crashing during Firebase token refresh mid-export.',
          AppLocale.ar:
              'تم إصلاح تصدير PDF للدفتر (جميع المتاجر / لكل خط) — كان يتعطل أثناء تجديد دخول Firebase.',
          AppLocale.ur:
              'PDF لیجر ایکسپورٹ درست کی گئی — Firebase ٹوکن ریفریش کے دوران کریش ہوتا تھا۔',
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
