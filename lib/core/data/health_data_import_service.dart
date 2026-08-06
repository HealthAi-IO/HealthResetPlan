import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'health_repository.dart';

class HealthImportRow {
  const HealthImportRow({
    required this.rowNumber,
    required this.measuredAt,
    required this.type,
    required this.payload,
  });

  final int rowNumber;
  final DateTime measuredAt;
  final String type;
  final Map<String, dynamic> payload;
}

class HealthImportPreview {
  const HealthImportPreview({
    required this.validRows,
    required this.errors,
    required this.duplicateCount,
  });

  final List<HealthImportRow> validRows;
  final List<String> errors;
  final int duplicateCount;

  int get importCount => validRows.length - duplicateCount;
}

class HealthDataImportService {
  HealthDataImportService(this.repository);

  final HealthRepository repository;

  static const headers = [
    '测量时间',
    '指标类型',
    '收缩压',
    '舒张压',
    '体重kg',
    '血糖mmol/L',
    '测量时段',
    '总胆固醇',
    'LDL',
    '血氧%',
    '睡眠小时',
  ];

  Uint8List buildTemplate() {
    final workbook = Excel.createExcel();
    final sheet = workbook['健康数据'];
    workbook.delete('Sheet1');
    sheet.appendRow(headers.map(TextCellValue.new).toList());
    sheet.appendRow([
      TextCellValue('2026-08-05 08:30'),
      TextCellValue('血压'),
      IntCellValue(120),
      IntCellValue(80),
      for (var i = 0; i < headers.length - 4; i++) TextCellValue(''),
    ]);
    sheet.appendRow([
      TextCellValue('2026-08-05 09:00'),
      TextCellValue('血糖'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      DoubleCellValue(5.6),
      TextCellValue('空腹'),
      for (var i = 0; i < headers.length - 7; i++) TextCellValue(''),
    ]);
    return Uint8List.fromList(workbook.encode()!);
  }

  Future<HealthImportPreview> preview(Uint8List bytes, String extension) async {
    final matrix = extension.toLowerCase() == 'csv'
        ? _decodeCsv(bytes)
        : _decodeXlsx(bytes);
    if (matrix.isEmpty || !_matchesTemplate(matrix.first)) {
      return const HealthImportPreview(
        validRows: [],
        errors: ['文件不是本 APP 导入模板，请先下载模板后填写。'],
        duplicateCount: 0,
      );
    }

    final existing = await repository.loadIndicators(limit: 100000);
    final existingKeys =
        existing.map((item) => '${item.type}:${item.measuredAt}').toSet();
    final seen = <String>{};
    final valid = <HealthImportRow>[];
    final errors = <String>[];
    var duplicates = 0;
    for (var index = 1; index < matrix.length; index++) {
      final values = matrix[index];
      if (values.every((value) => value.trim().isEmpty)) continue;
      try {
        final row = _parseRow(index + 1, values);
        final key = '${row.type}:${row.measuredAt.millisecondsSinceEpoch}';
        if (existingKeys.contains(key) || !seen.add(key)) duplicates++;
        valid.add(row);
      } on FormatException catch (error) {
        errors.add('第 ${index + 1} 行：${error.message}');
      }
    }
    return HealthImportPreview(
      validRows: valid,
      errors: errors,
      duplicateCount: duplicates,
    );
  }

  Future<int> commit(HealthImportPreview preview) async {
    final existing = await repository.loadIndicators(limit: 100000);
    final keys =
        existing.map((item) => '${item.type}:${item.measuredAt}').toSet();
    var count = 0;
    for (final row in preview.validRows) {
      final key = '${row.type}:${row.measuredAt.millisecondsSinceEpoch}';
      if (!keys.add(key)) continue;
      await repository.addIndicator(
        type: row.type,
        payload: row.payload,
        source: 'template-import',
        measuredAt: row.measuredAt,
      );
      count++;
    }
    return count;
  }

  List<List<String>> _decodeXlsx(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) return const [];
    final sheet = workbook.tables.values.first;
    return sheet.rows
        .map((row) =>
            row.map((cell) => cell?.value?.toString().trim() ?? '').toList())
        .toList();
  }

  List<List<String>> _decodeCsv(Uint8List bytes) {
    final text =
        utf8.decode(bytes, allowMalformed: false).replaceFirst('\ufeff', '');
    return const LineSplitter()
        .convert(text)
        .map(_splitCsvLine)
        .toList(growable: false);
  }

  List<String> _splitCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        result.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    result.add(buffer.toString().trim());
    return result;
  }

  bool _matchesTemplate(List<String> row) {
    if (row.length < headers.length) return false;
    for (var i = 0; i < headers.length; i++) {
      if (row[i].trim() != headers[i]) return false;
    }
    return true;
  }

  HealthImportRow _parseRow(int rowNumber, List<String> row) {
    String cell(int index) => index < row.length ? row[index].trim() : '';
    final measuredAt = DateTime.tryParse(cell(0).replaceFirst(' ', 'T'));
    if (measuredAt == null) {
      throw const FormatException('测量时间格式应为 YYYY-MM-DD HH:mm');
    }
    if (measuredAt.isAfter(DateTime.now())) {
      throw const FormatException('测量时间不能晚于当前时间');
    }

    final type = switch (cell(1)) {
      '体重' => 'weight',
      '血压' => 'bp',
      '血糖' => 'glucose',
      '血脂' => 'lipid',
      '血氧' => 'spo2',
      '睡眠' => 'sleep',
      _ => throw const FormatException('指标类型仅支持体重、血压、血糖、血脂、血氧、睡眠'),
    };
    double requiredNumber(int index, String name) {
      final value = double.tryParse(cell(index));
      if (value == null) {
        throw FormatException('$name 必须填写数字');
      }
      return value;
    }

    final payload = switch (type) {
      'weight' => {'weightKg': requiredNumber(4, '体重')},
      'bp' => {
          'systolic': requiredNumber(2, '收缩压').round(),
          'diastolic': requiredNumber(3, '舒张压').round(),
        },
      'glucose' => {
          'glucoseMmol': requiredNumber(5, '血糖'),
          'mealType': cell(6) == '餐后' ? 'postmeal' : 'fasting',
        },
      'lipid' => {
          'tc': requiredNumber(7, '总胆固醇'),
          'ldl': requiredNumber(8, 'LDL'),
        },
      'spo2' => {'spo2Pct': requiredNumber(9, '血氧').round()},
      'sleep' => {'sleepHours': requiredNumber(10, '睡眠小时')},
      _ => <String, dynamic>{},
    };
    return HealthImportRow(
      rowNumber: rowNumber,
      measuredAt: measuredAt,
      type: type,
      payload: payload,
    );
  }
}
