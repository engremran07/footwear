---
name: analytics-reporting
description: "Use when: building analytics dashboards, adding export features, generating per-route/per-shop/per-seller reports, integrating ExportSheet, adding filter dropdowns, or implementing consolidated report generation."
---

# Skill: Analytics & Reporting for ShoesERP

## Purpose
Generate production-quality reports from Firestore data using ExportSheet, PDF
export, and role-aware data scoping. Support per-route, per-seller, per-shop
and consolidated all-data reporting.

## Architecture

### Data Flow
```
Provider (StreamProvider) → Screen (ConsumerStatefulWidget) → ExportSheet.show()
                                                               ↓
                                                    buildPdfTable() / pdfBytesBuilder
                                                               ↓
                                                    Isolate.run() → PDF bytes
```

### Report Scoping
| Role | Scope |
|------|-------|
| Admin | All routes, all shops, all transactions |
| Seller | Own route only, own transactions only |

### Export Formats
- XLSX (Excel) — `exportToExcel()`
- PDF — `buildPdfTable()` + custom `pdfBytesBuilder`
- PNG (Image) — via `Printing.printPdf()`
- Print — system dialog
- Share — via `SharePlus`

## ExportSheet API
```dart
ExportSheet.show(
  context, ref,
  title: tr('shops_report', ref),
  headers: ['Name', 'Route', 'Phone', 'Balance'],
  rows: shops.map((s) => [s.name, s.routeNumber, s.phone, s.balance]).toList(),
  fileName: 'shops_report',
  subtitle: 'Route 5 — Generated ${DateTime.now()}',
  pdfBytesBuilder: () => buildPdfTable(...), // optional custom PDF
);
```

## Per-Route Report Pattern
```dart
// Group shops by routeId, generate one report per route
final routes = ref.read(routesProvider).valueOrNull ?? [];
for (final route in routes) {
  final routeShops = allShops.where((s) => s.routeId == route.id).toList();
  // Build per-route export data
}
```

## Dropdown Filter Pattern
```dart
// Route dropdown for admin filtering
DropdownButton<String?>(
  value: _selectedRouteId,
  items: [
    DropdownMenuItem(value: null, child: Text(tr('all_routes', ref))),
    ...routes.map((r) => DropdownMenuItem(
      value: r.id,
      child: Text('${r.routeNumber} · ${r.name}'),
    )),
  ],
  onChanged: (v) => setState(() => _selectedRouteId = v),
)
```

## L10n Keys Required
- `filter_by_route` — "Filter by Route"
- `all_routes` — "All Routes"
- `export_report` — "Export Report"
- `export_all_shops` — "Export All Shops"
- `export_per_route` — "Export Per Route"
- `route_report` — "Route Report"
- `generating_report` — "Generating report..."

## Name Resolution (Single Source of Truth)

All export paths MUST use `NameResolver` from
`app/lib/core/utils/name_resolver.dart` to resolve user UIDs to display names.
Never build ad-hoc `entryByMap` maps. Never fall back to a raw Firestore UID.

```dart
import '../core/utils/name_resolver.dart';

final names = NameResolver(
  users: allUsers,
  extra: {if (user != null) user.id: user.displayName},
  unknownLabel: trRead('unknown_user', locale),
);

// Pass to PDF/Excel builders:
entryByMap: names.map,
```

`ExportContext` (`app/lib/core/utils/export_context.dart`) carries the
`NameResolver`, locale, company branding, and pre-resolved labels as a single
object. Use it when building new export paths.

## Export I18n Keys

All string literals in export output (PDF, Excel, images) MUST use localized
keys from `app_locale.dart`. Key export-specific keys:

| Key | EN | AR | UR |
| --- | --- | --- | --- |
| `page_x_of_y` | Page %1 of %2 | صفحة %1 من %2 | صفحہ %1 از %2 |
| `others` | Others | أخرى | دیگر |
| `excel_generated` | Generated | تم الإنشاء | بنایا گیا |
| `unknown_user` | Unknown | غير معروف | نامعلوم |

## Rules

1. All exports use `ExportSheet.show()` — no direct PDF generation in screens
2. PDF generation MUST run on `Isolate.run()` — never on main thread
3. Sanitize all user text with `_s()` before PDF interpolation
4. All data reads through providers — no direct Firestore in screens
5. Role-aware: admin sees all, seller sees own route only
6. Export file names: `{report_type}_{route_name}_{date}.xlsx`
7. Never show raw Firestore UIDs in any export — use `NameResolver.resolve()`
8. Never hardcode English strings in PDF/Excel output — use `trRead()` with locale
9. Route labels use `'${route.routeNumber} · ${route.name}'` — no `'R'` prefix
