import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../core/constants/app_brand.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/excel_export.dart';
import '../core/utils/pdf_export.dart';
import '../core/utils/share_helper.dart';
import '../core/utils/snack_helper.dart';
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

  Future<Uint8List?> _buildPdfBytes(BuildContext context) async {
    if (rows.isEmpty) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(infoSnackBar(tr('no_data', ref)));
      return null;
    }
    try {
      return pdfBytesBuilder != null
          ? await pdfBytesBuilder!()
          : await buildPdfTable(
              title: title,
              headers: headers,
              rows: rows,
              subtitle: subtitle,
              locale: _locale,
            );
    } catch (e) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(errorSnackBar(tr(AppErrorMapper.key(e), ref)));
      return null;
    }
  }

  Future<void> _sharePdf(BuildContext context) async {
    final bytes = await _buildPdfBytes(context);
    if (bytes == null) return;
    try {
      await shareFile(
        bytes: bytes,
        fileName: '$fileName.pdf',
        mimeType: 'application/pdf',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(errorSnackBar(tr(AppErrorMapper.key(e), ref)));
    }
  }

  Future<void> _sharePng(BuildContext context) async {
    final pdfBytes = await _buildPdfBytes(context);
    if (pdfBytes == null) return;
    try {
      final firstPage = await Printing.raster(pdfBytes, dpi: 200).first;
      final rawPng = await firstPage.toPng();
      // Composite onto white canvas so transparent/dark PDF backgrounds
      // do not appear black when shared to apps like WhatsApp / Gallery.
      final pngBytes = await _withWhiteBackground(rawPng);
      await shareFile(
        bytes: pngBytes,
        fileName: '$fileName.png',
        mimeType: 'image/png',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(errorSnackBar(tr(AppErrorMapper.key(e), ref)));
    }
  }

  /// Returns a white-background PNG from the given [pngBytes].
  Future<Uint8List> _withWhiteBackground(Uint8List pngBytes) async {
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
    );
    canvas.drawColor(Colors.white, ui.BlendMode.src);
    canvas.drawImage(src, Offset.zero, Paint());
    final picture = recorder.endRecording();
    final result = await picture.toImage(src.width, src.height);
    final data = await result.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<void> _printPdf(BuildContext context) async {
    final bytes = await _buildPdfBytes(context);
    if (bytes == null) return;
    try {
      await Printing.layoutPdf(
        name: '$fileName.pdf',
        onLayout: (_) async => Uint8List.fromList(bytes),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(errorSnackBar(tr(AppErrorMapper.key(e), ref)));
    }
  }

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
            color: AppBrand.successColor,
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
            color: AppBrand.errorColor,
            label: tr('share_pdf', ref),
            sublabel: 'PDF',
            onTap: () async {
              Navigator.pop(context);
              await _sharePdf(context);
            },
          ),
          const SizedBox(height: 8),
          _OptionTile(
            icon: Icons.image_outlined,
            color: AppBrand.warningColor,
            label: tr('share_image', ref),
            sublabel: 'PNG',
            onTap: () async {
              Navigator.pop(context);
              await _sharePng(context);
            },
          ),
          const SizedBox(height: 8),
          _OptionTile(
            icon: Icons.print_outlined,
            color: AppBrand.primaryColor,
            label: tr('print_report', ref),
            sublabel: '',
            onTap: () async {
              Navigator.pop(context);
              await _printPdf(context);
            },
          ),
          const SizedBox(height: 8),
          _OptionTile(
            icon: Icons.share_outlined,
            color: AppBrand.adminRoleColor,
            label: tr('share_excel', ref),
            sublabel: 'XLSX',
            onTap: () async {
              Navigator.pop(context);
              try {
                final excel = await _buildExcelBytes();
                if (excel == null) return;
                await shareFile(
                  bytes: Uint8List.fromList(excel),
                  fileName: '$fileName.xlsx',
                  mimeType:
                      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.maybeOf(
                  context,
                )?.showSnackBar(errorSnackBar(tr(AppErrorMapper.key(e), ref)));
              }
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
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
                      color: color,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
