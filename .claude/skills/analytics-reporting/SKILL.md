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
  rows: shops.map((s) => [s.name, 'R${s.routeNumber}', s.phone, s.balance]).toList(),
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
      child: Text('R${r.routeNumber} · ${r.name}'),
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

## Rules
1. All exports use `ExportSheet.show()` — no direct PDF generation in screens
2. PDF generation MUST run on `Isolate.run()` — never on main thread
3. Sanitize all user text with `_s()` before PDF interpolation
4. All data reads through providers — no direct Firestore in screens
5. Role-aware: admin sees all, seller sees own route only
6. Export file names: `{report_type}_{route_name}_{date}.xlsx`
