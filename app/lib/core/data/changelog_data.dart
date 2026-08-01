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
    version: '3.9.25',
    date: 'August 2026',
    items: [
      ChangelogItem(
        emoji: '🛡️',
        text: {
          AppLocale.en:
              'Repeated write actions are now guarded so a single invoice or transaction submit is processed only once, preventing duplicate taps and accidental double-posts.',
          AppLocale.ar:
              'تمت حماية الإجراءات المتكررة الآن بحيث يتم تنفيذ إرسال فاتورة أو معاملة واحدة فقط مرة واحدة، مما يمنع النقرات المكررة والمنشورات المزدوجة عن طريق الخطأ.',
          AppLocale.ur:
              'بار بار دہرائے جانے والے write actions اب محفوظ ہو گئے ہیں تاکہ ایک ہی انوائس یا ٹرانزیکشن صرف ایک بار پروسیس ہو، دو بار ٹیپ اور accidental double-posts سے بچا جا سکے۔',
        },
      ),
      ChangelogItem(
        emoji: '📦',
        text: {
          AppLocale.en:
              'Release packaging and Android build metadata are aligned again so the APK version code safely exceeds the currently installed device build during handoff.',
          AppLocale.ar:
              'تمت محاذاة بيانات إصدار الحزمة وبناء Android مرة أخرى حتى يتجاوز رمز إصدار APK بشكل آمن الإصدار المثبت حاليًا على الجهاز أثناء التسليم.',
          AppLocale.ur:
              'ریلیز پیکیجنگ اور Android build metadata دوبارہ متوازن ہو گئے ہیں تاکہ APK version code ہینڈآف کے دوران موجودہ ڈیوائس build سے محفوظ طریقے سے زیادہ ہو۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.9.5',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '🧾',
        text: {
          AppLocale.en:
              'PDF exports now paginate consistently for large ledgers and account statements, so long reports are no longer truncated or cut off mid-page.',
          AppLocale.ar:
              'تُقسم صادرات PDF الآن بشكل متسق للقيود الكبيرة والبيانات المالية، لذلك لا يتم قطع التقارير الطويلة أو قطعها في منتصف الصفحة بعد الآن.',
          AppLocale.ur:
              'PDF ایکسپورٹس اب بڑے لیجرز اور اکاؤنٹ سٹیٹمنٹ کے لیے مستقل طور پر پیج بندی کرتے ہیں، اس لیے طویل رپورٹس اب نصف صفحے میں نہیں کٹے رہتے۔',
        },
      ),
      ChangelogItem(
        emoji: '🔐',
        text: {
          AppLocale.en:
              'Admin identity actions are now disabled by default in client builds unless a secure compile-time credential is provided, reducing the risk of accidental credential exposure.',
          AppLocale.ar:
              'تم تعطيل إجراءات الهوية الإدارية افتراضيًا في نسخ العميل ما لم يتم توفير بيانات اعتماد آمنة أثناء الترجمة، مما يقلل من خطر تسريب الاعتمادات عن طريق الخطأ.',
          AppLocale.ur:
              'ایڈمن آئیڈینٹی ایکشنز اب کلائنٹ builds میں ڈیفالٹ طور پر غیر فعال ہیں جب تک کہ کمپائل ٹائم پر محفوظ کریڈینشل فراہم نہ کیا جائے، جس سے accidental credential exposure کا خطرہ کم ہوتا ہے۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.9.4',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '🔍',
        text: {
          AppLocale.en:
              'Last transaction (In/Out + amount) now appears for all shops in both the Shops list and Route detail, even for older shops that did not previously show any activity.',
          AppLocale.ar:
              'تظهر الآن آخر معاملة (داخل/خارج + المبلغ) لجميع المتاجر في قائمة المتاجر وتفاصيل المسار، حتى للمتاجر القديمة التي لم تُظهر أي نشاط من قبل.',
          AppLocale.ur:
              'اب تمام شاپس کی آخری ٹرانزیکشن (اِن/آؤٹ + رقم) شاپس لسٹ اور روٹ ڈیٹیل دونوں میں نظر آتی ہے، پرانے شاپس کے لیے بھی جو پہلے کوئی ایکٹیویٹی نہیں دکھا رہے تھے۔',
        },
      ),
      ChangelogItem(
        emoji: '🗂️',
        text: {
          AppLocale.en:
              'Shops list tile no longer shows the route number in the subtitle — it now shows the last transaction details instead.',
          AppLocale.ar:
              'لا تُظهر بطاقة قائمة المتاجر رقم المسار في العنوان الفرعي بعد الآن — بل تُظهر تفاصيل آخر معاملة بدلاً من ذلك.',
          AppLocale.ur:
              'شاپس لسٹ ٹائل میں اب سب ٹائٹل میں روٹ نمبر نہیں دکھایا جاتا — اس کی جگہ آخری ٹرانزیکشن کی تفصیلات دکھائی جاتی ہیں۔',
        },
      ),
      ChangelogItem(
        emoji: '📅',
        text: {
          AppLocale.en:
              'Shops sort by most-recent activity now works correctly for all shops, including those created before the activity-tracking feature was introduced.',
          AppLocale.ar:
              'يعمل الآن ترتيب المتاجر حسب أحدث نشاط بشكل صحيح لجميع المتاجر، بما في ذلك تلك التي أُنشئت قبل تقديم ميزة تتبع النشاط.',
          AppLocale.ur:
              'شاپس کی ترتیب تازہ ترین ایکٹیویٹی کے مطابق اب تمام شاپس کے لیے درست طریقے سے کام کرتی ہے، بشمول وہ شاپس جو ایکٹیویٹی ٹریکنگ فیچر متعارف ہونے سے پہلے بنائی گئی تھیں۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.9.3',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '📊',
        text: {
          AppLocale.en:
              'Shop tiles now show only the last In/Out transaction without repeating the balance already visible in the tile.',
          AppLocale.ar:
              'تعرض بطاقات المتاجر الآن آخر معاملة (داخل/خارج) فقط دون تكرار الرصيد الظاهر بالفعل في البطاقة.',
          AppLocale.ur:
              'شاپ ٹائلز اب صرف آخری اِن/آؤٹ ٹرانزیکشن دکھاتی ہیں، بیلنس دوبارہ نہیں دکھایا جاتا کیونکہ وہ پہلے سے ٹائل میں نظر آتا ہے۔',
        },
      ),
      ChangelogItem(
        emoji: '🔄',
        text: {
          AppLocale.en:
              'Shops are sorted by most recent transaction activity at the top of the route and shops lists.',
          AppLocale.ar:
              'يتم الآن ترتيب المتاجر حسب آخر نشاط بالمعاملات في أعلى قوائم المسارات والمتاجر.',
          AppLocale.ur:
              'شاپس کو روٹ اور شاپس لسٹ میں سب سے حالیہ ٹرانزیکشن سرگرمی کے مطابق اوپر سے ترتیب دیا گیا ہے۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.9.2',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '🧾',
        text: {
          AppLocale.en:
              'Shop tiles on the Route and Shops screens now show the last transaction direction and amount at a glance.',
          AppLocale.ar:
              'تعرض بطاقات المتاجر في شاشتي المسار والمتاجر الآن اتجاه آخر معاملة ومبلغها بنظرة سريعة.',
          AppLocale.ur:
              'روٹ اور دکانوں کی اسکرین پر دکان کارڈز اب آخری ٹرانزیکشن کی سمت اور رقم ایک نظر میں دکھاتے ہیں۔',
        },
      ),
      ChangelogItem(
        emoji: '🔧',
        text: {
          AppLocale.en:
              'Fixed missing translation keys for "In", "Payment", and "Access Denied" labels shown in various screens.',
          AppLocale.ar:
              'تم إصلاح مفاتيح الترجمة المفقودة لتسميات "استلام" و"دفعة" و"لا صلاحية" التي تظهر في شاشات مختلفة.',
          AppLocale.ur:
              'مختلف اسکرینوں میں دکھائے جانے والے "موصول"، "ادائیگی" اور "رسائی نہیں" لیبلز کے گم ترجمہ کلیدیں ٹھیک کی گئیں۔',
        },
      ),
      ChangelogItem(
        emoji: '💡',
        text: {
          AppLocale.en:
              'Internal model improvements: InvoiceModel, TransactionModel, and NotificationModel now support copy-with-changes for more reliable state updates.',
          AppLocale.ar:
              'تحسينات داخلية في النماذج: تدعم InvoiceModel وTransactionModel وNotificationModel الآن النسخ مع التغييرات لتحديثات حالة أكثر موثوقية.',
          AppLocale.ur:
              'داخلی ماڈل بہتری: InvoiceModel، TransactionModel، اور NotificationModel اب کاپی ود چینجز کو سپورٹ کرتے ہیں تاکہ اسٹیٹ اپڈیٹس زیادہ قابل اعتماد ہوں۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.9.1',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '🧭',
        text: {
          AppLocale.en:
              'Route details now show the route name cleanly in the top breadcrumb with the normal back gesture flow.',
          AppLocale.ar:
              'تعرض تفاصيل المسار الآن اسم المسار فقط بشكل واضح في شريط التنقل العلوي مع سلوك الرجوع المعتاد.',
          AppLocale.ur:
              'روٹ کی تفصیلات میں اب اوپر کے بریڈ کرمب میں صرف روٹ کا نام صاف طور پر دکھتا ہے اور بیک جیسچر معمول کے مطابق کام کرتا ہے۔',
        },
      ),
      ChangelogItem(
        emoji: '⚡',
        text: {
          AppLocale.en:
              'Shops inside each route now auto-sort by latest live activity so the most recently updated shops appear first.',
          AppLocale.ar:
              'تُرتَّب المتاجر داخل كل مسار الآن تلقائيًا حسب أحدث نشاط مباشر بحيث تظهر المتاجر الأحدث تحديثًا أولاً.',
          AppLocale.ur:
              'ہر روٹ کے اندر دکانیں اب تازہ ترین لائیو سرگرمی کے مطابق خودکار طور پر ترتیب پاتی ہیں تاکہ سب سے حالیہ اپڈیٹ والی دکانیں پہلے آئیں۔',
        },
      ),
      ChangelogItem(
        emoji: '🧹',
        text: {
          AppLocale.en:
              'The temporary shops "Active Today" filter and its related UI were removed for a cleaner shops screen.',
          AppLocale.ar:
              'تمت إزالة فلتر المتاجر المؤقت "نشط اليوم" وكل الواجهة المرتبطة به لجعل شاشة المتاجر أبسط.',
          AppLocale.ur:
              'عارضی دکانوں کا "آج کی سرگرمی" فلٹر اور اس سے متعلقہ UI ہٹا دیا گیا ہے تاکہ دکانوں کی اسکرین زیادہ صاف رہے۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.9.0',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '📋',
        text: {
          AppLocale.en:
              'New History tab: view the last 7 days of transactions grouped by day, with tap-to-navigate to shop details.',
          AppLocale.ar:
              'تبويب السجل الجديد: عرض آخر 7 أيام من المعاملات مجمّعة حسب اليوم، مع النقر للانتقال إلى تفاصيل المتجر.',
          AppLocale.ur:
              'نیا تاریخ ٹیب: گزشتہ 7 دنوں کی ٹرانزیکشنز دن کے مطابق دیکھیں، دکان کی تفصیلات تک جانے کے لیے ٹیپ کریں۔',
        },
      ),
      ChangelogItem(
        emoji: '🔔',
        text: {
          AppLocale.en:
              'Admin notification bell: live badge in the top bar shows unread seller activity. Tap to open the Notification Center.',
          AppLocale.ar:
              'جرس إشعارات المسؤول: شارة حية في الشريط العلوي تعرض نشاط البائع غير المقروء. انقر لفتح مركز الإشعارات.',
          AppLocale.ur:
              'ایڈمن نوٹیفیکیشن بیل: اوپری بار میں لائیو بیج سیلر کی غیر پڑھی سرگرمی دکھاتا ہے۔ نوٹیفیکیشن سنٹر کھولنے کے لیے ٹیپ کریں۔',
        },
      ),
      ChangelogItem(
        emoji: '🏪',
        text: {
          AppLocale.en:
              'Shops list: "Active Today" filter highlights shops with same-day activity. Shops automatically sort by most recent transaction.',
          AppLocale.ar:
              'قائمة المتاجر: فلتر "نشط اليوم" يُبرز المتاجر النشطة اليوم. تُرتَّب المتاجر تلقائيًا حسب أحدث معاملة.',
          AppLocale.ur:
              'دکانوں کی فہرست: "آج کی سرگرمی" فلٹر آج کی سرگرمی والی دکانیں نمایاں کرتا ہے۔ دکانیں خودکار طور پر تازہ ترین ٹرانزیکشن کے مطابق ترتیب پاتی ہیں۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.8.5',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '🌐',
        text: {
          AppLocale.en:
              'Product details screen — labels (In Stock, Out, Quantity) now display correctly in Arabic and Urdu.',
          AppLocale.ar:
              'شاشة تفاصيل المنتج — التسميات (في المخزون، نافد، الكمية) تظهر الآن بشكل صحيح بالعربية والأردية.',
          AppLocale.ur:
              'پروڈکٹ تفصیلات اسکرین — لیبلز (اسٹاک میں، خالی، مقدار) اب عربی اور اردو میں درست ظاہر ہوتے ہیں۔',
        },
      ),
      ChangelogItem(
        emoji: '🔒',
        text: {
          AppLocale.en:
              'Security improvements: product image links are now validated, and transaction edit requests are checked for valid amounts.',
          AppLocale.ar:
              'تحسينات الأمان: روابط صور المنتج تُتحقق منها الآن، وطلبات تعديل المعاملات تُفحص للتأكد من صحة المبالغ.',
          AppLocale.ur:
              'سیکیورٹی بہتریاں: پروڈکٹ امیج لنکس کی اب توثیق کی جاتی ہے، اور ٹرانزیکشن ترمیم کی درخواستوں میں رقم کی جانچ ہوتی ہے۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.8.4',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '⚡',
        text: {
          AppLocale.en:
              'Seller dashboard now loads instantly without flickering — route cards and shop data appear together in one smooth render.',
          AppLocale.ar:
              'لوحة تحكم البائع تُحمّل الآن فورًا بدون وميض — بطاقات المسارات وبيانات المحلات تظهر معًا في عرض سلس.',
          AppLocale.ur:
              'سیلر ڈیش بورڈ اب فوری لوڈ ہوتا ہے بغیر جھلملاہٹ کے — روٹ کارڈز اور دکانوں کا ڈیٹا ایک ساتھ ظاہر ہوتا ہے۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.8.3',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '🧾',
        text: {
          AppLocale.en:
              'Reports now support a centralized bilingual column naming mode for English exports (Date, Description, Entry By, Credit, Debit, Balance).',
          AppLocale.ar:
              'التقارير تدعم الآن وضعًا مركزيًا لأسماء الأعمدة الثنائية في التصدير الإنجليزي (التاريخ، التفاصيل، بواسطة، فاتورة، واصل، الباقي).',
          AppLocale.ur:
              'رپورٹس میں اب انگریزی ایکسپورٹس کے لیے مرکزی بائی لنگول کالم نام موڈ شامل ہے (Date, Description, Entry By, Credit, Debit, Balance).',
        },
      ),
      ChangelogItem(
        emoji: '⚙️',
        text: {
          AppLocale.en:
              'Admin Settings now includes a toggle to enable or disable Arabic column names in English PDF, Excel, and image report outputs.',
          AppLocale.ar:
              'تتضمن إعدادات المشرف الآن مفتاحًا لتفعيل أو تعطيل أسماء الأعمدة العربية داخل تقارير PDF وExcel والصور باللغة الإنجليزية.',
          AppLocale.ur:
              'ایڈمن سیٹنگز میں اب ایک ٹوگل شامل ہے جس سے انگریزی PDF، Excel اور امیج رپورٹس میں عربی کالم نام آن یا آف کیے جا سکتے ہیں۔',
        },
      ),
      ChangelogItem(
        emoji: '🔗',
        text: {
          AppLocale.en:
              'Export naming behavior is now unified through one shared report-column utility, ensuring consistent output across all report screens.',
          AppLocale.ar:
              'سلوك تسمية الأعمدة في التصدير أصبح موحّدًا عبر أداة مشتركة واحدة لضمان الاتساق عبر جميع شاشات التقارير.',
          AppLocale.ur:
              'ایکسپورٹ کالم نامنگ اب ایک مشترکہ یوٹیلٹی کے ذریعے یکساں ہو گئی ہے، جس سے تمام رپورٹ اسکرینز میں آؤٹ پٹ مستقل رہتا ہے۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.8.2',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '🛡️',
        text: {
          AppLocale.en:
              'New fool-proof backup and restore flow with admin-only restore protection and recorded backup/restore timestamps.',
          AppLocale.ar:
              'تدفق نسخ احتياطي واستعادة جديد وآمن مع حماية الاستعادة للمشرف فقط وتسجيل وقت آخر نسخة احتياطية وآخر استعادة.',
          AppLocale.ur:
              'نیا محفوظ بیک اپ اور ریسٹور فلو: ریسٹور صرف ایڈمن کے لیے، اور آخری بیک اپ اور آخری ریسٹور کے وقت باقاعدہ ریکارڈ ہوتے ہیں۔',
        },
      ),
      ChangelogItem(
        emoji: '📱',
        text: {
          AppLocale.en:
              'Settings now opens dedicated Backup and Danger Zone screens for clearer, safer admin operations.',
          AppLocale.ar:
              'الإعدادات تفتح الآن شاشات مخصصة للنسخ الاحتياطي ومنطقة الخطر لتكون عمليات المشرف أوضح وأكثر أمانًا.',
          AppLocale.ur:
              'سیٹنگز میں اب بیک اپ اور ڈینجر زون کی الگ اسکرینز ہیں تاکہ ایڈمن آپریشنز زیادہ واضح اور محفوظ رہیں۔',
        },
      ),
      ChangelogItem(
        emoji: '🔧',
        text: {
          AppLocale.en:
              'Dependency cleanup: direct packages are up-to-date and deprecated API usage has been removed from app code.',
          AppLocale.ar:
              'تنظيف الاعتماديات: الحزم المباشرة أصبحت محدثة وتمت إزالة استخدامات الـ API المتقادمة من كود التطبيق.',
          AppLocale.ur:
              'ڈپینڈنسی کلین اپ: ڈائریکٹ پیکجز اپ ٹو ڈیٹ ہیں اور ایپ کوڈ سے deprecated API استعمالات ختم کر دی گئی ہیں۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.8.1',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '📋',
        text: {
          AppLocale.en:
              'Shops list: WhatsApp button now appears on every shop tile for quick contact.',
          AppLocale.ar:
              'قائمة المتاجر: زر واتساب يظهر الآن على كل بطاقة متجر للتواصل السريع.',
          AppLocale.ur:
              'شاپس لسٹ: اب ہر شاپ ٹائل پر واٹس ایپ بٹن دکھائی دیتا ہے — فوری رابطے کے لیے۔',
        },
      ),
      ChangelogItem(
        emoji: '📊',
        text: {
          AppLocale.en:
              'Reports: replaced the pie chart with a ranked top-10 debtors list — easier to see who owes the most.',
          AppLocale.ar:
              'التقارير: تم استبدال الرسم البياني الدائري بقائمة أفضل 10 مدينين — أسهل لمعرفة من يدين بالأكثر.',
          AppLocale.ur:
              'رپورٹس: پائی چارٹ کو ٹاپ 10 مقروضین کی رینکڈ لسٹ سے بدل دیا — دیکھیں کون سب سے زیادہ باقی ہے۔',
        },
      ),
      ChangelogItem(
        emoji: '🔧',
        text: {
          AppLocale.en:
              'Fixed: the Add Shop button no longer overlaps the shop list.',
          AppLocale.ar: 'إصلاح: زر إضافة متجر لم يعد يتداخل مع قائمة المتاجر.',
          AppLocale.ur: 'درستگی: ایڈ شاپ بٹن اب شاپ لسٹ کے اوپر نہیں آتا۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.8.0',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '💱',
        text: {
          AppLocale.en:
              'Multi-currency support: amounts now display in the correct currency (SAR or PKR) based on each route — no more mixed symbols.',
          AppLocale.ar:
              'دعم العملات المتعددة: تعرض المبالغ الآن العملة الصحيحة (ريال أو روبية) بناءً على كل مسار — لا مزيد من رموز مختلطة.',
          AppLocale.ur:
              'ملٹی کرنسی سپورٹ: رقومات اب ہر روٹ کے مطابق درست کرنسی (SAR یا PKR) میں دکھائی جاتی ہیں۔',
        },
      ),
      ChangelogItem(
        emoji: '💬',
        text: {
          AppLocale.en:
              'WhatsApp quick-connect: tap the WhatsApp button on any shop to open a chat instantly.',
          AppLocale.ar:
              'اتصال سريع عبر واتساب: اضغط على زر واتساب في أي متجر لفتح محادثة فوراً.',
          AppLocale.ur:
              'واٹس ایپ کوئیک کنیکٹ: کسی بھی شاپ پر واٹس ایپ بٹن دبائیں اور فوری چیٹ کھولیں۔',
        },
      ),
      ChangelogItem(
        emoji: '🧹',
        text: {
          AppLocale.en:
              'Cleaner charts: removed unused cash-flow and balance trend graphs to speed up screen loading.',
          AppLocale.ar:
              'رسوم بيانية أنظف: تمت إزالة الرسوم البيانية غير المستخدمة لتحسين سرعة تحميل الشاشات.',
          AppLocale.ur:
              'صاف چارٹس: غیر ضروری کیش فلو اور بیلنس ٹرینڈ گرافس ہٹا دیے — اسکرین لوڈنگ تیز ہو گئی۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.7.20',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '🔀',
        text: {
          AppLocale.en:
              'Multi-route seller assignment: sellers can now be assigned to multiple routes simultaneously.',
          AppLocale.ar:
              'تعيين البائعين لعدة مسارات: يمكن الآن تعيين البائعين لعدة مسارات في نفس الوقت.',
          AppLocale.ur:
              'ملٹی روٹ سیلر اسائنمنٹ: سیلرز کو اب ایک ساتھ کئی روٹس پر تعینات کیا جا سکتا ہے۔',
        },
      ),
      ChangelogItem(
        emoji: '🧹',
        text: {
          AppLocale.en:
              'Legacy single-route code removed — the app now uses arrays everywhere for route and seller assignments, improving reliability.',
          AppLocale.ar:
              'تم إزالة رمز المسار الواحد القديم — يستخدم التطبيق الآن المصفوفات في كل مكان لتعيينات المسارات والبائعين.',
          AppLocale.ur:
              'پرانا سنگل روٹ کوڈ ہٹا دیا گیا — ایپ اب ہر جگہ arrays استعمال کرتی ہے، جو مزید قابل اعتماد ہے۔',
        },
      ),
      ChangelogItem(
        emoji: '🔒',
        text: {
          AppLocale.en:
              'Firestore security rules updated for multi-route access control.',
          AppLocale.ar:
              'تم تحديث قواعد أمان Firestore للتحكم في الوصول متعدد المسارات.',
          AppLocale.ur:
              'ملٹی روٹ رسائی کنٹرول کے لیے Firestore سیکیورٹی رولز اپ ڈیٹ کیے گئے۔',
        },
      ),
    ],
  ),
  ChangelogEntry(
    version: '3.7.19',
    date: 'April 2026',
    items: [
      ChangelogItem(
        emoji: '📁',
        text: {
          AppLocale.en:
              'Export file names are now clean and consistent — every PDF, Excel, and image export uses a clear name like "ledger_shop-name_2026-04-18" instead of random codes.',
          AppLocale.ar:
              'أسماء ملفات التصدير أصبحت واضحة ومتسقة — كل PDF وExcel وصورة تستخدم اسمًا واضحًا مثل "ledger_shop-name_2026-04-18" بدلاً من رموز عشوائية.',
          AppLocale.ur:
              'ایکسپورٹ فائل نام اب صاف اور یکساں ہیں — ہر PDF، Excel، اور تصویر "ledger_shop-name_2026-04-18" جیسا واضح نام استعمال کرتی ہے، نہ کہ بے ترتیب کوڈ۔',
        },
      ),
      ChangelogItem(
        emoji: '🗂️',
        text: {
          AppLocale.en:
              'Multi-shop ledger PDF: route names now appear as section headers on the cover page, making it easy to jump to the right route at a glance.',
          AppLocale.ar:
              'PDF كشف حساب متعدد المتاجر: تظهر الآن أسماء المسارات كعناوين أقسام في صفحة الغلاف، مما يسهّل الوصول إلى المسار الصحيح بنظرة واحدة.',
          AppLocale.ur:
              'ملٹی شاپ لیجر PDF: روٹ کے نام اب کور پیج پر سیکشن ہیڈرز کے طور پر ظاہر ہوتے ہیں، جس سے صحیح روٹ تک ایک نظر میں پہنچنا آسان ہوتا ہے۔',
        },
      ),
      ChangelogItem(
        emoji: '📐',
        text: {
          AppLocale.en:
              'PDF layout improvements: stock summary cards and table cells are now properly centered for a cleaner, more professional look.',
          AppLocale.ar:
              'تحسينات تخطيط PDF: بطاقات ملخص المخزون وخلايا الجداول مركزة الآن بشكل صحيح لمظهر أنظف وأكثر احترافية.',
          AppLocale.ur:
              'PDF لے آؤٹ بہتری: اسٹاک سمری کارڈز اور ٹیبل سیلز اب صحیح طریقے سے سینٹر کیے گئے ہیں تاکہ ایک صاف اور زیادہ پیشہ ورانہ شکل ملے۔',
        },
      ),
    ],
  ),
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
          AppLocale.en: 'Removed unused code for a leaner, faster app.',
          AppLocale.ar: 'إزالة الأكواد غير المستخدمة لتطبيق أسرع وأخف.',
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
