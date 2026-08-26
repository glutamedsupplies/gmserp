import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:photo_view/photo_view.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/png_export.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/time_card_table.dart';
import '../../models/time_card_salary.dart';
import '../../models/time_entry.dart';

/// GMS ERP export palette — matches [AppColors.light] for readable PNG reports.
abstract final class PngReportColors {
  static const page = Color(0xFFFFFFFF);
  static const header = Color(0xFFE6F3B8);
  static const card = Color(0xFFF7FBEA);
  static const border = Color(0xFFD4E4A8);
  static const borderStrong = Color(0xFFB8D080);
  static const textPrimary = AppColors.onPrimary;
  static const textSecondary = Color(0xFF6B7280);
  static const textHint = Color(0xFFB0B7C3);
  static const rowHighlight = Color(0xFFF7FBEA);
  static const late = Color(0xFFD97706);
  static const leave = AppColors.primaryDark;
  /// Complementary to GMS green — used for salary amounts on light backgrounds.
  static const salary = Color(0xFF7C3AED);
  static const salaryDark = Color(0xFF6D28D9);
  /// Lighter purple for salary text on the dark total-salary card.
  static const salaryOnDark = Color(0xFFE9D5FF);
}

/// Portrait export canvas width in logical pixels (readable A4-like page).
const double _kPortraitWidth = 900;

class TimeCardPngPreviewScreen extends StatefulWidget {
  const TimeCardPngPreviewScreen({
    super.key,
    required this.employeeName,
    required this.employeeEmail,
    required this.companyName,
    required this.companyId,
    required this.filter,
    required this.rows,
    required this.totalHours,
    required this.generatedAt,
    DateTime? periodDate,
    this.salaryBreakdowns = const [],
  }) : periodDate = periodDate ?? generatedAt;

  final String employeeName;
  final String employeeEmail;
  final String companyName;
  final String companyId;
  final TimeCardPeriodFilter filter;
  final List<TimeCardTableRow> rows;
  final String totalHours;
  final DateTime generatedAt;
  final DateTime periodDate;
  final List<EmployeeSalaryBreakdown> salaryBreakdowns;

  @override
  State<TimeCardPngPreviewScreen> createState() =>
      _TimeCardPngPreviewScreenState();
}

class _TimeCardPngPreviewScreenState extends State<TimeCardPngPreviewScreen> {
  final _captureKey = GlobalKey();
  final _photoController = PhotoViewController();
  int _previewGeneration = 0;
  Uint8List? _pngBytes;
  bool _capturing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  @override
  void dispose() {
    _photoController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _photoController.reset();
  }

  Future<void> _capture() async {
    if (_capturing) return;
    setState(() {
      _capturing = true;
      _pngBytes = null;
    });
    _resetZoom();

    // Let the offscreen portrait card lay out fully before capture.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await WidgetsBinding.instance.endOfFrame;

    try {
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null || !boundary.hasSize) return;

      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted || byteData == null) return;
      setState(() {
        _pngBytes = byteData.buffer.asUint8List();
        _previewGeneration++;
      });
      _resetZoom();
    } catch (_) {
      if (mounted) {
        SnackBarHelper.showError(context, 'Could not generate PNG preview.');
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _savePng() async {
    if (_pngBytes == null) {
      await _capture();
    }
    final bytes = _pngBytes;
    if (bytes == null || !mounted) return;

    setState(() => _saving = true);
    try {
      final fileName =
          'time_card_${formatWorkDate(widget.generatedAt)}_${widget.filter.name}.png';
      final path = await savePngBytes(bytes, fileName);
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        path == null
            ? 'PNG downloaded to your device.'
            : 'Saved to your device: $path',
      );
    } catch (_) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          'Could not save PNG. Allow Photos access and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatGeneratedAt(DateTime value) {
    return '${formatWorkDate(value)} ${formatClockTime(value)}';
  }

  Widget _buildPortraitReport() {
    return _PortraitReportCard(
      employeeName: widget.employeeName,
      employeeEmail: widget.employeeEmail,
      companyName: widget.companyName,
      companyId: widget.companyId,
      filter: widget.filter,
      rows: widget.rows,
      totalHours: widget.totalHours,
      generatedAt: widget.generatedAt,
      generatedAtLabel: _formatGeneratedAt(widget.generatedAt),
      periodDate: widget.periodDate,
      salaryBreakdowns: widget.salaryBreakdowns,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.88),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Time card preview'),
        actions: [
          TextButton.icon(
            onPressed: _capturing ? null : _capture,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            label: const Text('Refresh', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Offscreen full-size portrait card — never clipped by screen width.
          Positioned(
            left: -_kPortraitWidth - 100,
            top: 0,
            child: Material(
              color: Colors.transparent,
              child: RepaintBoundary(
                key: _captureKey,
                child: SizedBox(
                  width: _kPortraitWidth,
                  child: _buildPortraitReport(),
                ),
              ),
            ),
          ),
          Column(
            children: [
              Expanded(
                child: _capturing && _pngBytes == null
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 12),
                            Text(
                              'Building portrait preview…',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      )
                    : _pngBytes == null
                        ? const Center(
                            child: Text(
                              'Preview unavailable',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      'Pinch / scroll to zoom · drag to pan',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton(
                                      onPressed: _resetZoom,
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white70,
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                      ),
                                      child: const Text('Reset'),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: PhotoView(
                                  key: ValueKey(_previewGeneration),
                                  controller: _photoController,
                                  imageProvider: MemoryImage(_pngBytes!),
                                  backgroundDecoration: const BoxDecoration(
                                    color: Colors.transparent,
                                  ),
                                  initialScale:
                                      PhotoViewComputedScale.contained,
                                  minScale:
                                      PhotoViewComputedScale.contained * 0.6,
                                  maxScale:
                                      PhotoViewComputedScale.covered * 4.5,
                                  basePosition: Alignment.center,
                                  tightMode: false,
                                  filterQuality: FilterQuality.high,
                                  enablePanAlways: true,
                                  gestureDetectorBehavior:
                                      HitTestBehavior.opaque,
                                ),
                              ),
                            ],
                          ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Close'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving || _capturing ? null : _savePng,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.download_rounded),
                          label: Text(_saving ? 'Saving…' : 'Save PNG'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PortraitReportCard extends StatelessWidget {
  const _PortraitReportCard({
    required this.employeeName,
    required this.employeeEmail,
    required this.companyName,
    required this.companyId,
    required this.filter,
    required this.rows,
    required this.totalHours,
    required this.generatedAt,
    required this.generatedAtLabel,
    required this.periodDate,
    this.salaryBreakdowns = const [],
  });

  final String employeeName;
  final String employeeEmail;
  final String companyName;
  final String companyId;
  final TimeCardPeriodFilter filter;
  final List<TimeCardTableRow> rows;
  final String totalHours;
  final String generatedAtLabel;
  final DateTime generatedAt;
  final DateTime periodDate;
  final List<EmployeeSalaryBreakdown> salaryBreakdowns;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kPortraitWidth,
      color: PngReportColors.page,
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(
            filter: filter,
            periodDate: periodDate,
            totalHours: totalHours,
          ),
          const SizedBox(height: 18),
          _MetaGrid(
            employeeName: employeeName,
            employeeEmail: employeeEmail,
            companyName: companyName,
            companyId: companyId,
            generatedAtLabel: generatedAtLabel,
            rowCount: rows.length,
            daysWithData: rows.where((r) => r.hasData).length,
          ),
          if (salaryBreakdowns.isNotEmpty) ...[
            const SizedBox(height: 18),
            _SalarySection(
              filter: filter,
              breakdowns: salaryBreakdowns,
              periodDate: periodDate,
              employeeName: employeeName,
            ),
          ],
          const SizedBox(height: 18),
          _ExportTable(rows: rows),
          const SizedBox(height: 16),
          Text(
            'Generated by GMSERP · Portrait time card report · For internal attendance records',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: PngReportColors.textHint,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.filter,
    required this.periodDate,
    required this.totalHours,
  });

  final TimeCardPeriodFilter filter;
  final DateTime periodDate;
  final String totalHours;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: PngReportColors.border),
          ),
          child: const Icon(
            Icons.schedule_rounded,
            color: AppColors.primaryDark,
            size: 30,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'GMSERP Time Card Report',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: PngReportColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${filter.label} · ${periodSubtitle(filter, periodDate)}',
                style: const TextStyle(
                  fontSize: 17,
                  color: PngReportColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: PngReportColors.header,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: PngReportColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                totalHours,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                ),
              ),
              const Text(
                'Total hours',
                style: TextStyle(
                  fontSize: 15,
                  color: PngReportColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SalarySection extends StatelessWidget {
  const _SalarySection({
    required this.filter,
    required this.breakdowns,
    required this.periodDate,
    required this.employeeName,
  });

  final TimeCardPeriodFilter filter;
  final List<EmployeeSalaryBreakdown> breakdowns;
  final DateTime periodDate;
  final String employeeName;

  @override
  Widget build(BuildContext context) {
    final multi = breakdowns.length > 1;
    final grandNet = totalNetSalary(breakdowns);
    final periodLabel = '${filter.label} · ${periodSubtitle(filter, periodDate)}';
    final single = !multi && breakdowns.length == 1 ? breakdowns.first : null;
    final displayTotal = multi ? grandNet : (single?.netPay ?? grandNet);
    final hasAnyRate = breakdowns.any((item) => item.hasRate);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _TotalSalaryHero(
              amount: displayTotal,
              periodLabel: periodLabel,
              employeeLabel:
                  multi ? '${breakdowns.length} employees' : employeeName,
              hasRate: hasAnyRate,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _SalaryBreakdownPanel(
              breakdowns: breakdowns,
              multi: multi,
            ),
          ),
        ],
      ),
    );
  }
}

class _SalaryBreakdownPanel extends StatelessWidget {
  const _SalaryBreakdownPanel({
    required this.breakdowns,
    required this.multi,
  });

  final List<EmployeeSalaryBreakdown> breakdowns;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        color: PngReportColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PngReportColors.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Row(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                color: AppColors.primaryDark,
                size: 22,
              ),
              SizedBox(width: 8),
              Text(
                'Salary breakdown',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: PngReportColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < breakdowns.length; i++) ...[
            if (i > 0) Divider(height: 20, color: PngReportColors.border),
            _SalaryBreakdownCard(
              breakdown: breakdowns[i],
              showEmployeeName: multi,
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Basic Pay = Daily Rate × Payable Days\n'
            'Late / Early Out Deduction = Minutes × (Daily Rate ÷ paid work minutes)\n'
            'Net Pay = Basic Pay − Late − Early Out (− other + additions). '
            'Lunch break is not counted as late or early-out time.',
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: PngReportColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalSalaryHero extends StatelessWidget {
  const _TotalSalaryHero({
    required this.amount,
    required this.periodLabel,
    required this.employeeLabel,
    required this.hasRate,
  });

  final double amount;
  final String periodLabel;
  final String employeeLabel;
  final bool hasRate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PngReportColors.borderStrong, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(99),
            ),
            child: const Text(
              'TOTAL NET',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: PngReportColors.salaryOnDark,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            employeeLabel,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            periodLabel,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasRate
                ? EmployeeSalaryBreakdown.formatMoney(amount)
                : '—',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 42,
              height: 1.05,
              fontWeight: FontWeight.w900,
              color: PngReportColors.salary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasRate ? 'Total net for this period' : 'Set daily rate in Time card settings',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
}

class _SalaryBreakdownCard extends StatelessWidget {
  const _SalaryBreakdownCard({
    required this.breakdown,
    required this.showEmployeeName,
  });

  final EmployeeSalaryBreakdown breakdown;
  final bool showEmployeeName;

  @override
  Widget build(BuildContext context) {
    if (!breakdown.hasRate) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showEmployeeName)
            Text(
              breakdown.employeeName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: PngReportColors.textPrimary,
              ),
            ),
          if (showEmployeeName) const SizedBox(height: 4),
          const Text(
            'No daily rate set — configure in Time card settings.',
            style: TextStyle(
              fontSize: 15,
              color: PngReportColors.textSecondary,
            ),
          ),
        ],
      );
    }

    final lines = <_SalaryLine>[
      _SalaryLine(
        'Daily Rate',
        EmployeeSalaryBreakdown.formatMoney(breakdown.dailyRate),
        valueColor: _SalaryValueColor.green,
      ),
      _SalaryLine(
        'Payable Days',
        '${breakdown.payableDays}',
        valueColor: _SalaryValueColor.neutral,
      ),
      _SalaryLine(
        'Basic Pay',
        EmployeeSalaryBreakdown.formatMoney(breakdown.basicPay),
        valueColor: _SalaryValueColor.green,
      ),
      if (breakdown.totalLateMinutes > 0 || breakdown.lateDays > 0)
        _SalaryLine(
          'Total Late',
          '${breakdown.totalLateMinutes} minute${breakdown.totalLateMinutes == 1 ? '' : 's'}',
          valueColor: _SalaryValueColor.orange,
        ),
      if (breakdown.lateDeduction > 0 || breakdown.totalLateMinutes > 0)
        _SalaryLine(
          'Late Deduction',
          EmployeeSalaryBreakdown.formatMoney(
            breakdown.lateDeduction,
            showMinus: true,
          ),
          valueColor: _SalaryValueColor.orange,
        ),
      if (breakdown.totalEarlyOutMinutes > 0)
        _SalaryLine(
          'Total Early Out',
          '${breakdown.totalEarlyOutMinutes} minute${breakdown.totalEarlyOutMinutes == 1 ? '' : 's'}',
          valueColor: _SalaryValueColor.orange,
        ),
      if (breakdown.earlyOutDeduction > 0 || breakdown.totalEarlyOutMinutes > 0)
        _SalaryLine(
          'Early Out Deduction',
          EmployeeSalaryBreakdown.formatMoney(
            breakdown.earlyOutDeduction,
            showMinus: true,
          ),
          valueColor: _SalaryValueColor.orange,
        ),
      if (breakdown.otherDeductions > 0)
        _SalaryLine(
          'Other Deductions',
          EmployeeSalaryBreakdown.formatMoney(
            breakdown.otherDeductions,
            showMinus: true,
          ),
          valueColor: _SalaryValueColor.red,
        ),
      if (breakdown.additions > 0)
        _SalaryLine(
          'Additions',
          EmployeeSalaryBreakdown.formatMoney(breakdown.additions),
          valueColor: _SalaryValueColor.green,
        ),
      if (breakdown.absentDays > 0)
        _SalaryLine(
          'Absent (${breakdown.absentDays} day${breakdown.absentDays == 1 ? '' : 's'})',
          EmployeeSalaryBreakdown.formatMoney(0),
          valueColor: _SalaryValueColor.red,
        ),
      if (breakdown.excuseDays > 0)
        _SalaryLine(
          'On leave (${breakdown.excuseDays} day${breakdown.excuseDays == 1 ? '' : 's'})',
          EmployeeSalaryBreakdown.formatMoney(0),
          valueColor: _SalaryValueColor.red,
        ),
      _SalaryLine(
        'Net Pay',
        EmployeeSalaryBreakdown.formatMoney(breakdown.netPay),
        valueColor: _SalaryValueColor.green,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showEmployeeName)
          Text(
            breakdown.employeeName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: PngReportColors.textPrimary,
            ),
          ),
        if (showEmployeeName) const SizedBox(height: 8),
        for (final line in lines) ...[
          _SalaryLineRow(line: line),
          const SizedBox(height: 5),
        ],
        if (showEmployeeName) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: PngReportColors.page,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: PngReportColors.border),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Employee net',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: PngReportColors.textSecondary,
                    ),
                  ),
                ),
                Text(
                  EmployeeSalaryBreakdown.formatMoney(breakdown.netPay),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: PngReportColors.salary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

enum _SalaryValueColor { green, orange, red, neutral }

class _SalaryLine {
  const _SalaryLine(
    this.label,
    this.value, {
    this.valueColor = _SalaryValueColor.neutral,
  });

  final String label;
  final String value;
  final _SalaryValueColor valueColor;
}

class _SalaryLineRow extends StatelessWidget {
  const _SalaryLineRow({required this.line});

  final _SalaryLine line;

  @override
  Widget build(BuildContext context) {
    Color color = switch (line.valueColor) {
      _SalaryValueColor.green => AppColors.success,
      _SalaryValueColor.orange => PngReportColors.late,
      _SalaryValueColor.red => AppColors.error,
      _SalaryValueColor.neutral => PngReportColors.textPrimary,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            line.label,
            style: const TextStyle(
              fontSize: 16,
              color: PngReportColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          line.value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _MetaGrid extends StatelessWidget {
  const _MetaGrid({
    required this.employeeName,
    required this.employeeEmail,
    required this.companyName,
    required this.companyId,
    required this.generatedAtLabel,
    required this.rowCount,
    required this.daysWithData,
  });

  final String employeeName;
  final String employeeEmail;
  final String companyName;
  final String companyId;
  final String generatedAtLabel;
  final int rowCount;
  final int daysWithData;

  @override
  Widget build(BuildContext context) {
    final items = [
      _MetaItem('Employee', employeeName),
      _MetaItem('Email', employeeEmail),
      _MetaItem('Company', companyName),
      _MetaItem('Company ID', companyId),
      _MetaItem('Generated', generatedAtLabel),
      _MetaItem('Records', '$daysWithData / $rowCount days'),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: PngReportColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PngReportColors.border, width: 1.5),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: items[i]),
                const SizedBox(width: 16),
                Expanded(
                  child: i + 1 < items.length ? items[i + 1] : const SizedBox(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            color: PngReportColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            color: PngReportColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ExportTable extends StatelessWidget {
  const _ExportTable({required this.rows});

  final List<TimeCardTableRow> rows;

  static const _header = PngReportColors.header;
  static const _border = PngReportColors.border;
  static const _highlight = PngReportColors.rowHighlight;

  @override
  Widget build(BuildContext context) {
    const columnWidths = <int, TableColumnWidth>{
      0: FlexColumnWidth(1.35),
      1: FlexColumnWidth(0.6),
      2: FlexColumnWidth(1.6),
      3: FlexColumnWidth(1.6),
      4: FlexColumnWidth(0.9),
      5: FlexColumnWidth(0.85),
    };

    return Table(
      columnWidths: columnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder.all(color: _border, width: 1.4),
      children: [
        TableRow(
          decoration: const BoxDecoration(color: _header),
          children: [
            const _Cell('Date', header: true),
            const _Cell('Day', header: true),
            const _Cell('Time in', header: true),
            const _Cell('Time out', header: true),
            const _Cell('Hours', header: true),
            const _Cell('Status', header: true),
          ],
        ),
        for (final row in rows)
          TableRow(
            decoration: BoxDecoration(
              color: row.isToday ? _highlight : null,
            ),
            children: [
              _Cell(row.workDate, bold: row.isToday || row.hasData),
              _Cell(row.weekday, muted: true),
              _Cell(row.timeIn),
              _Cell(row.timeOut, accent: row.timeOut == 'Active'),
              _Cell(row.duration, bold: row.hasData, accent: row.hasData),
              _Cell(
                row.status,
                accent: row.status == 'Late',
                leave: row.status == 'On Leave',
                success: row.status == 'Present',
                danger: row.status == 'Absent',
                muted: row.status == 'Off' || row.status == '—',
              ),
            ],
          ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(
    this.value, {
    this.header = false,
    this.bold = false,
    this.muted = false,
    this.accent = false,
    this.success = false,
    this.danger = false,
    this.leave = false,
  });

  final String value;
  final bool header;
  final bool bold;
  final bool muted;
  final bool accent;
  final bool success;
  final bool danger;
  final bool leave;

  @override
  Widget build(BuildContext context) {
    Color color = PngReportColors.textPrimary;
    if (header) {
      color = AppColors.primaryDark;
    } else if (danger) {
      color = AppColors.error;
    } else if (success) {
      color = AppColors.success;
    } else if (leave) {
      color = PngReportColors.leave;
    } else if (accent) {
      color = PngReportColors.late;
    } else if (muted) {
      color = PngReportColors.textSecondary;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Text(
        value,
        style: TextStyle(
          fontSize: header ? 17.5 : 16.5,
          height: 1.3,
          fontWeight: header || bold ? FontWeight.w800 : FontWeight.w600,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
