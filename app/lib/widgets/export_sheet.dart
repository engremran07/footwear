import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../core/utils/excel_export.dart';
import '../core/utils/pdf_export.dart';
import '../core/utils/share_helper.dart';
import '../core/l10n/app_locale.dart';

/// Shows a bottom sheet with export/share options: XLSX, PDF, Share, Print.
///
/// Usage:
/// ```dart
/// ExportSheet.show(context, ref,
///   title: 'Orders Report',
///   headers: ['ID', 'Customer', 'Total'],
///   rows: orders.map((o) => [o.id, o.customerName, o.total]).toList(),
///   fileName: 'orders',
/// );
/// ```
class ExportSheet {
  ExportSheet._();

  static void show(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required List<String> headers,
    required List<List<dynamic>> rows,
    required String fileName,
    String? subtitle,

    /// Optional override: when provided, used for PDF / Image / Print instead
    /// of the generic [buildPdfTable]. Useful for ledger-style exports.
    Future<Uint8List> Function()? pdfBytesBuilder,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: _ExportSheetContent(
              ref: ref,
              title: title,
              headers: headers,
              rows: rows,
              fileName: fileName,
              subtitle: subtitle,
              pdfBytesBuilder: pdfBytesBuilder,
            ),
          ),
        );
      },
    );
  }
}

class _ExportSheetContent extends StatelessWidget {
  final WidgetRef ref;
  final String title;
  final List<String> headers;
  final List<List<dynamic>> rows;
  final String fileName;
  final String? subtitle;
  final Future<Uint8List> Function()? pdfBytesBuilder;

  const _ExportSheetContent({
    required this.ref,
    required this.title,
    required this.headers,
    required this.rows,
    required this.fileName,
    this.subtitle,
    this.pdfBytesBuilder,
  });

  AppLocale get _locale => ref.read(appLocaleProvider);
  bool get _isRtl => _locale == AppLocale.ar || _locale == AppLocale.ur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            tr('export_share', ref),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${rows.length} ${tr('records', ref)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Option tiles
          _OptionTile(
            icon: Icons.table_chart_outlined,
            color: const Color(0xFF2E7D32),
            label: tr('download_excel', ref),
            sublabel: 'XLSX',
            onTap: () {
              Navigator.pop(context);
              exportToExcel(
                fileName: fileName,
                sheetName: title,
                headers: headers,
                rows: rows,
                isRtl: _isRtl,
              );
            },
          ),
          const SizedBox(height: 8),
          _OptionTile(
            icon: Icons.picture_as_pdf_outlined,
            color: const Color(0xFFD32F2F),
            label: tr('share_pdf', ref),
            sublabel: 'PDF',
            onTap: () async {
              Navigator.pop(context);
              final bytes = pdfBytesBuilder != null
                  ? await pdfBytesBuilder!()
                  : await buildPdfTable(
                      title: title,
                      headers: headers,
                      rows: rows,
                      subtitle: subtitle,
                      locale: _locale,
                    );
              await shareFile(
                bytes: bytes,
                fileName: '$fileName.pdf',
                mimeType: 'application/pdf',
              );
            },
          ),
          const SizedBox(height: 8),
          _OptionTile(
            icon: Icons.image_outlined,
            color: const Color(0xFFE65100),
            label: tr('share_image', ref),
            sublabel: 'PNG',
            onTap: () async {
              Navigator.pop(context);
              final pdfBytes = pdfBytesBuilder != null
                  ? await pdfBytesBuilder!()
                  : await buildPdfTable(
                      title: title,
                      headers: headers,
                      rows: rows,
                      subtitle: subtitle,
                      locale: _locale,
                    );
              // Rasterize first page of PDF to a high-res PNG
              final pages = Printing.raster(pdfBytes, dpi: 200);
              final firstPage = await pages.first;
              final pngBytes = await firstPage.toPng();
              await shareFile(
                bytes: pngBytes,
                fileName: '$fileName.png',
                mimeType: 'image/png',
              );
            },
          ),
          const SizedBox(height: 8),
          _OptionTile(
            icon: Icons.print_outlined,
            color: const Color(0xFF1565C0),
            label: tr('print_report', ref),
            sublabel: '',
            onTap: () async {
              Navigator.pop(context);
              final bytes = pdfBytesBuilder != null
                  ? await pdfBytesBuilder!()
                  : await buildPdfTable(
                      title: title,
                      headers: headers,
                      rows: rows,
                      subtitle: subtitle,
                      locale: _locale,
                    );
              await Printing.layoutPdf(
                  onLayout: (_) async => Uint8List.fromList(bytes));
            },
          ),
          const SizedBox(height: 8),
          _OptionTile(
            icon: Icons.share_outlined,
            color: const Color(0xFF6A1B9A),
            label: tr('share_excel', ref),
            sublabel: 'XLSX',
            onTap: () async {
              Navigator.pop(context);
              final excel = await _buildExcelBytes();
              if (excel == null) return;
              await shareFile(
                bytes: Uint8List.fromList(excel),
                fileName: '$fileName.xlsx',
                mimeType:
                    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              );
            },
          ),
        ],
      ),
    );
  }

  Future<List<int>?> _buildExcelBytes() async {
    return buildStyledExcelBytes(
      sheetName: title,
      headers: headers,
      rows: rows,
      isRtl: _isRtl,
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String sublabel;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.sublabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? color.withValues(alpha: 0.22)
                      : color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (sublabel.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark
                        ? color.withValues(alpha: 0.22)
                        : color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    sublabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
