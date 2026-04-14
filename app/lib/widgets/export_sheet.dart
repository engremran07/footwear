import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../core/constants/app_brand.dart';
import '../core/utils/download_helper.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/excel_export.dart';
import '../core/utils/pdf_export.dart';
import '../core/utils/share_helper.dart';
import '../core/utils/snack_helper.dart';
import '../core/l10n/app_locale.dart';
import '../providers/settings_provider.dart';

/// Unified export/share bottom sheet — single centralised path for all formats.
///
/// All export logic lives HERE. Callers just pass data + open the sheet.
/// The sheet handles: loading state, error display, auto-close on success.
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

// ─── Sheet content — StatefulWidget for loading / error state ─────────────

class _ExportSheetContent extends StatefulWidget {
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

  @override
  State<_ExportSheetContent> createState() => _ExportSheetContentState();
}

class _ExportSheetContentState extends State<_ExportSheetContent> {
  /// Key of the option tile currently processing, null when idle.
  String? _activeKey;

  WidgetRef get ref => widget.ref;
  AppLocale get _locale => ref.read(appLocaleProvider);
  bool get _isRtl => _locale == AppLocale.ar || _locale == AppLocale.ur;

  // ── Centralised execute wrapper ───────────────────────────────────────
  // Runs [action] with loading indicator on the tapped tile.
  // Pops the sheet on success; shows error IN the still-open sheet on failure.
  Future<void> _execute(String key, Future<void> Function() action) async {
    if (_activeKey != null) return; // debounce while busy
    setState(() => _activeKey = key);
    try {
      await action();
      if (mounted) Navigator.pop(context);
    } catch (e, stack) {
      if (!mounted) return;
      debugPrint('[ExportSheet] $key failed: $e\n$stack');
      setState(() => _activeKey = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(errorSnackBar(tr(AppErrorMapper.key(e), ref)));
    }
  }

  // ── PDF bytes (lazy build) ────────────────────────────────────────────
  Future<Uint8List> _buildPdfBytes() async {
    if (widget.rows.isEmpty) throw Exception('no data to export');
    if (widget.pdfBytesBuilder != null) return widget.pdfBytesBuilder!();
    final logoBytes = ref.read(settingsProvider).value?.logoBytes;
    try {
      return await buildPdfTable(
        title: widget.title,
        headers: widget.headers,
        rows: widget.rows,
        subtitle: widget.subtitle,
        locale: _locale,
        logoBytes: logoBytes,
      );
    } catch (e, stack) {
      debugPrint('[ExportSheet] PDF build failed: $e\n$stack');
      throw Exception('pdf export failed');
    }
  }

  // ── Export actions (each runs inside _execute wrapper) ─────────────────

  Future<void> _sharePdf() async {
    final bytes = await _buildPdfBytes();
    await shareFile(
      bytes: bytes,
      fileName: '${widget.fileName}.pdf',
      mimeType: 'application/pdf',
    );
  }

  Future<void> _sharePng() async {
    final pdfBytes = await _buildPdfBytes();
    final firstPage = await Printing.raster(pdfBytes, dpi: 200).first;
    final rawPng = await firstPage.toPng();
    final pngBytes = await _withWhiteBackground(rawPng);
    await shareFile(
      bytes: pngBytes,
      fileName: '${widget.fileName}.png',
      mimeType: 'image/png',
    );
  }

  Future<void> _printPdf() async {
    final bytes = await _buildPdfBytes();
    await Printing.layoutPdf(
      name: '${widget.fileName}.pdf',
      onLayout: (_) async => Uint8List.fromList(bytes),
    );
  }

  Future<void> _downloadExcel() async {
    final bytes = buildStyledExcelBytes(
      sheetName: widget.title,
      headers: widget.headers,
      rows: widget.rows,
      isRtl: _isRtl,
    );
    if (bytes == null) throw Exception('format');
    await downloadBytes(bytes, '${widget.fileName}.xlsx');
  }

  Future<void> _shareExcel() async {
    final bytes = buildStyledExcelBytes(
      sheetName: widget.title,
      headers: widget.headers,
      rows: widget.rows,
      isRtl: _isRtl,
    );
    if (bytes == null) throw Exception('format');
    await shareFile(
      bytes: Uint8List.fromList(bytes),
      fileName: '${widget.fileName}.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
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

  // ── UI ─────────────────────────────────────────────────────────────────

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
            '${widget.rows.length} ${tr('records', ref)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Option tiles — all go through _execute (no premature pop)
          _OptionTile(
            icon: Icons.table_chart_outlined,
            color: AppBrand.successColor,
            label: tr('download_excel', ref),
            sublabel: 'XLSX',
            busy: _activeKey == 'excel_dl',
            enabled: _activeKey == null,
            onTap: () => _execute('excel_dl', _downloadExcel),
          ),
          const SizedBox(height: 8),
          _OptionTile(
            icon: Icons.picture_as_pdf_outlined,
            color: AppBrand.errorColor,
            label: tr('share_pdf', ref),
            sublabel: 'PDF',
            busy: _activeKey == 'pdf',
            enabled: _activeKey == null,
            onTap: () => _execute('pdf', _sharePdf),
          ),
          const SizedBox(height: 8),
          _OptionTile(
            icon: Icons.image_outlined,
            color: AppBrand.warningColor,
            label: tr('share_image', ref),
            sublabel: 'PNG',
            busy: _activeKey == 'png',
            enabled: _activeKey == null,
            onTap: () => _execute('png', _sharePng),
          ),
          const SizedBox(height: 8),
          _OptionTile(
            icon: Icons.print_outlined,
            color: AppBrand.primaryColor,
            label: tr('print_report', ref),
            sublabel: '',
            busy: _activeKey == 'print',
            enabled: _activeKey == null,
            onTap: () => _execute('print', _printPdf),
          ),
          const SizedBox(height: 8),
          _OptionTile(
            icon: Icons.share_outlined,
            color: AppBrand.adminRoleColor,
            label: tr('share_excel', ref),
            sublabel: 'XLSX',
            busy: _activeKey == 'excel_share',
            enabled: _activeKey == null,
            onTap: () => _execute('excel_share', _shareExcel),
          ),
        ],
      ),
    );
  }
}

// ─── Option tile with loading / disabled support ────────────────────────────

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String sublabel;
  final VoidCallback onTap;
  final bool busy;
  final bool enabled;

  const _OptionTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.sublabel,
    required this.onTap,
    this.busy = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = enabled || busy
        ? color
        : color.withValues(alpha: 0.4);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled && !busy ? onTap : null,
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
                      ? effectiveColor.withValues(alpha: 0.22)
                      : effectiveColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: busy
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: effectiveColor,
                        ),
                      )
                    : Icon(icon, color: effectiveColor, size: 22),
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
                        ? effectiveColor.withValues(alpha: 0.22)
                        : effectiveColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    sublabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: effectiveColor,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              if (busy)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Icon(
                  Icons.chevron_right,
                  color: enabled
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.3,
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
