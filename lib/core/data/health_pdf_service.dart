import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'health_models.dart';
import 'health_repository.dart';

class HealthPdfService {
  HealthPdfService(this.repository);

  final HealthRepository repository;

  Future<Uint8List> build(int days) async {
    final now = DateTime.now();
    final since = now.subtract(Duration(days: days));
    final results = await Future.wait<Object?>([
      repository.loadProfile(),
      repository.loadIndicatorsSince(since),
      repository.loadReminders(),
      repository.loadClockRecords(limit: 5000),
      repository.loadReportRecords(limit: 100),
    ]);
    final profile = results[0] as UserProfileData?;
    final indicators = results[1] as List<HealthIndicatorEntry>;
    final medicines = (results[2] as List<ReminderData>)
        .where((item) => item.type == 'medicine' && !item.isArchived)
        .toList();
    final clockRecords = (results[3] as List<ClockRecordData>)
        .where((item) => !item.clockTime.isBefore(since))
        .toList();
    final reports = (results[4] as List<HealthReportRecord>)
        .where((item) => !item.reportDateTime.isBefore(since))
        .toList();

    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansSC-Variable-1.0.12.ttf'),
    );
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        theme: pw.ThemeData.withFont(base: regular, bold: regular),
        header: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('健康摘要',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text('$days天',
                style: const pw.TextStyle(color: PdfColors.grey700)),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('第 ${context.pageNumber} 页',
              style: const pw.TextStyle(fontSize: 9)),
        ),
        build: (context) => [
          pw.SizedBox(height: 18),
          pw.Text(
            profile?.nickname.trim().isNotEmpty == true
                ? profile!.nickname
                : '健康用户',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
              '统计区间：${DateFormat('yyyy-MM-dd').format(since)} 至 ${DateFormat('yyyy-MM-dd').format(now)}'),
          pw.SizedBox(height: 16),
          _section('健康档案', [
            if (profile == null) '尚未完善档案',
            if (profile != null)
              '年龄 ${profile.age == 0 ? '--' : profile.age} 岁　身高 ${profile.heightCm.toStringAsFixed(1)} cm　体重 ${profile.weightKg.toStringAsFixed(1)} kg',
            if (profile != null && profile.medicalHistory.trim().isNotEmpty)
              '既往史：${profile.medicalHistory}',
          ]),
          _section(
              '当前用药',
              medicines.isEmpty
                  ? ['暂无有效用药提醒']
                  : medicines.map((item) {
                      final strength =
                          item.payload['strength']?.toString() ?? '';
                      final dose = item.payload['dose']?.toString() ?? '';
                      final instructions =
                          item.payload['instructions']?.toString() ?? '';
                      final times = item.dailyTimes
                          .map((time) =>
                              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}')
                          .join('、');
                      return '${item.displayLabel}${strength.isEmpty ? '' : ' $strength'}　$dose　$times${instructions.isEmpty ? '' : '　$instructions'}';
                    }).toList()),
          _section('关键趋势', _trendLines(indicators)),
          _section('异常记录', _abnormalLines(indicators, profile)),
          _section('用药执行', [_adherenceLine(clockRecords)]),
          _section(
              '报告摘要',
              reports.isEmpty
                  ? ['本周期暂无报告']
                  : reports
                      .take(10)
                      .map((item) =>
                          '${DateFormat('MM-dd').format(item.reportDateTime)}　${item.summary.trim().isEmpty ? '已保存健康报告' : item.summary.trim()}')
                      .toList()),
          pw.SizedBox(height: 12),
          pw.Text('生成时间：${DateFormat('yyyy-MM-dd HH:mm').format(now)}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.Text('本摘要仅用于日常健康管理参考，不能替代医生诊断。',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ),
    );
    return document.save();
  }

  pw.Widget _section(String title, List<String> lines) => pw.Inseparable(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              ...lines.map((line) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 3),
                    child: pw.Text(line.isEmpty ? '--' : line),
                  )),
            ],
          ),
        ),
      );

  List<String> _trendLines(List<HealthIndicatorEntry> entries) {
    const types = ['bp', 'glucose', 'weight', 'lipid', 'spo2', 'sleep'];
    final lines = <String>[];
    for (final type in types) {
      final values = entries.where((item) => item.type == type).toList();
      if (values.isEmpty) continue;
      final latest = values.first;
      final oldest = values.last;
      lines.add(
          '${latest.label}：最新 ${latest.displayValue}（${DateFormat('MM-dd HH:mm').format(latest.measuredTime)}），周期首条 ${oldest.displayValue}');
    }
    return lines.isEmpty ? ['本周期暂无指标记录'] : lines;
  }

  List<String> _abnormalLines(
      List<HealthIndicatorEntry> entries, UserProfileData? profile) {
    bool abnormal(HealthIndicatorEntry item) => switch (item.type) {
          'bp' => ((item.payload['systolic'] as num?) ?? 0) >= 130 ||
              ((item.payload['diastolic'] as num?) ?? 0) >= 80,
          'glucose' => ((item.payload['glucoseMmol'] as num?) ?? 0) >=
              (item.payload['mealType'] == 'postmeal' ? 7.8 : 5.6),
          'spo2' => ((item.payload['spo2Pct'] as num?) ?? 100) < 95,
          'lipid' => ((item.payload['tc'] as num?) ?? 0) >= 5.18 ||
              ((item.payload['ldl'] as num?) ?? 0) >= 3.37,
          'sleep' => ((item.payload['sleepHours'] as num?) ?? 8) < 7,
          _ => false,
        };
    final values = entries
        .where(abnormal)
        .take(20)
        .map((item) =>
            '${DateFormat('MM-dd HH:mm').format(item.measuredTime)}　${item.label} ${item.displayValue}')
        .toList();
    return values.isEmpty ? ['本周期未发现超出参考范围的记录'] : values;
  }

  String _adherenceLine(List<ClockRecordData> records) {
    final medicines = records.where((item) => item.type == 'medicine').toList();
    if (medicines.isEmpty) return '本周期暂无用药确认记录';
    final taken = medicines.where((item) => item.status == 'done').length;
    return '已服 $taken 次 / 已确认 ${medicines.length} 次，执行率 ${(taken * 100 / medicines.length).round()}%';
  }
}
