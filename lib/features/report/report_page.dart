import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/membership/paywall.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/report_image_storage.dart';
import '../../core/sync/sync_service.dart';

const _aiDoctorDisclaimer = 'AI 不能代替医生诊断，只提供健康管理建议；如有异常结果、不适症状或用药调整需求，请及时咨询医生。';

String _withAiDoctorDisclaimer(String value) {
  final text = value.trim();
  if (text.isEmpty) return 'AI 已根据报告内容生成初步分析建议。$_aiDoctorDisclaimer';
  if (text.contains('不能代替医生') || text.contains('不代替医生')) {
    return text;
  }
  return '$text $_aiDoctorDisclaimer';
}

class _OcrIndicator {
  const _OcrIndicator({
    required this.category,
    required this.name,
    required this.value,
    required this.unit,
    required this.referenceRange,
    required this.status,
  });

  final String category;
  final String name;
  final String value;
  final String unit;
  final String referenceRange;
  final String status;

  factory _OcrIndicator.fromJson(Map<String, dynamic> json) => _OcrIndicator(
        category: json['category'] as String? ?? '其他',
        name: json['name'] as String? ?? '',
        value: json['value'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        referenceRange: json['referenceRange'] as String? ?? '',
        status: json['status'] as String? ?? 'unknown',
      );

  Map<String, dynamic> toJson() => {
        'category': category,
        'name': name,
        'value': value,
        'unit': unit,
        'referenceRange': referenceRange,
        'status': status,
      };
}

class _OcrResult {
  const _OcrResult({
    required this.reportDate,
    required this.indicators,
    required this.summary,
    required this.analysisAdvice,
    required this.rawText,
    required this.provider,
  });

  final String? reportDate;
  final List<_OcrIndicator> indicators;
  final String summary;
  final String analysisAdvice;
  final String rawText;
  final String provider;

  factory _OcrResult.fromJson(Map<String, dynamic> json) {
    final normalized = _normalizeOcrJson(json);
    final indicatorItems = normalized['indicators'];
    final indicators = (indicatorItems is List ? indicatorItems : const [])
        .whereType<Map>()
        .map((item) => _OcrIndicator.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.name.trim().isNotEmpty)
        .toList();

    return _OcrResult(
      reportDate: normalized['reportDate'] as String?,
      indicators: indicators,
      summary: normalized['summary'] as String? ?? '',
      analysisAdvice: normalized['analysisAdvice'] as String? ?? '',
      rawText: _displayRawText(normalized),
      provider: normalized['provider'] as String? ?? 'vision',
    );
  }

  Map<String, dynamic> toJson() => {
        'reportDate': reportDate,
        'indicators': indicators.map((item) => item.toJson()).toList(),
        'summary': summary,
        'analysisAdvice': _withAiDoctorDisclaimer(analysisAdvice),
        'rawText': rawText,
        'provider': provider,
      };
}

Map<String, dynamic> _normalizeOcrJson(Map<String, dynamic> json) {
  final rawText = json['rawText'];
  final indicators = json['indicators'];
  if ((indicators is List && indicators.isNotEmpty) || rawText is! String) {
    return json;
  }

  final parsed = _tryDecodeJsonObject(rawText);
  if (parsed == null) return json;

  return {
    ...parsed,
    if (json['provider'] != null) 'provider': json['provider'],
  };
}

Map<String, dynamic>? _tryDecodeJsonObject(String value) {
  var text = value.trim();
  if (text.startsWith('```')) {
    final start = text.indexOf('\n');
    final end = text.lastIndexOf('```');
    if (start > 0 && end > start) text = text.substring(start + 1, end).trim();
  }
  final first = text.indexOf('{');
  final last = text.lastIndexOf('}');
  if (first < 0 || last <= first) return null;

  try {
    final decoded = jsonDecode(text.substring(first, last + 1));
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value));
    }
  } catch (_) {}
  return null;
}

String _displayRawText(Map<String, dynamic> json) {
  final rawText = json['rawText'] as String? ?? '';
  if (_tryDecodeJsonObject(rawText) != null) return '';
  return rawText;
}

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final HealthRepository _repo = sl<HealthRepository>();
  final ApiClient _apiClient = sl<ApiClient>();
  final SyncService _syncService = sl<SyncService>();
  final ImagePicker _picker = ImagePicker();

  bool _loading = true;
  bool _analyzing = false;
  bool _saving = false;
  String _analyzeStage = '';
  XFile? _pickedImage;
  _OcrResult? _ocrResult;
  List<HealthReportRecord> _reports = const [];

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepoChanged);
    _load();
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    super.dispose();
  }

  void _onRepoChanged() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    final reports = await _repo.loadReportRecords(limit: 50);
    if (!mounted) return;
    setState(() {
      _reports = reports;
      _loading = false;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final ok = await requireAccountAndMember(context, PaywallFeature.reportOcr);
    if (!ok) return;

    XFile? file;
    try {
      file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 78,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开相机或相册失败：$e')),
      );
      return;
    }

    if (file == null) return;
    setState(() {
      _pickedImage = file;
      _ocrResult = null;
    });
    await _analyzeImage(file);
  }

  Future<void> _pickFile() async {
    final ok = await requireAccountAndMember(context, PaywallFeature.reportOcr);
    if (!ok) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif'],
        allowMultiple: false,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      if (kIsWeb && (file.bytes == null || file.bytes!.isEmpty)) {
        throw StateError('文件内容为空');
      }
      if (!kIsWeb && (file.path == null || file.path!.isEmpty)) {
        throw StateError('无法读取所选文件');
      }
      final picked = kIsWeb
          ? XFile.fromData(
              file.bytes!,
              name: file.name,
              mimeType: _mimeType(file.name),
            )
          : XFile(file.path!, name: file.name);

      if (!mounted) return;
      setState(() {
        _pickedImage = picked;
        _ocrResult = null;
      });
      await _analyzeImage(picked);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件失败：$e')),
      );
    }
  }

  Future<void> _analyzeImage(XFile file) async {
    setState(() {
      _analyzing = true;
      _analyzeStage = 'Preparing image...';
    });

    try {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _analyzeStage = 'Uploading report for AI recognition...');
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: file.name,
          contentType: DioMediaType.parse(_mimeType(file.name)),
        ),
      });

      final response = await _apiClient.dio.post(
        '/reports/analyze',
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      if (!mounted) return;
      setState(() => _analyzeStage = 'Extracting health indicators...');
      final result = _OcrResult.fromJson(_unwrapResponseData(response.data));

      if (!mounted) return;
      setState(() {
        _ocrResult = result;
        _analyzing = false;
        _analyzeStage = '';
      });
      _showReviewSheet(result);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _analyzeStage = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('识别失败：${_friendlyError(e)}'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _analyzeStage = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('识别异常：$e')),
      );
    }
  }

  void _showReviewSheet(_OcrResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OcrReviewSheet(
        result: result,
        onConfirm: () {
          Navigator.pop(context);
          _saveResult(result);
        },
        onDiscard: () => Navigator.pop(context),
      ),
    );
  }

  void _showReportDetail(HealthReportRecord record) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReportDetailSheet(record: record),
    );
  }

  Future<void> _deleteReport(HealthReportRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除报告'),
        content: const Text('删除后本地报告历史中将不再显示，已开启云同步时会同步删除云端记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.deleteReportRecord(record.clientId);
      await _deleteReportImage(record.imagePath);

      var syncMessage = '';
      if (await _syncService.isSyncEnabled()) {
        final syncResult = await _syncService.sync();
        if (syncResult.hasError) {
          syncMessage = '，云同步失败：${syncResult.error}';
        }
      }

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('报告已删除$syncMessage'),
          backgroundColor: syncMessage.isEmpty ? Colors.green : Colors.orange,
        ),
      );
      _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('删除失败：$e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveResult(_OcrResult result) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final reportTime = _parseReportDate(result.reportDate) ?? DateTime.now();
      final clientId = const Uuid().v4();
      final imagePath = await _persistReportImage(clientId);

      await _repo.saveReportRecord(
        clientId: clientId,
        imagePath: imagePath,
        reportTime: reportTime,
        summary: result.summary,
        rawText: result.rawText,
        structured: result.toJson(),
        provider: result.provider,
      );
      await _saveIndicatorsLocally(result, reportTime);

      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('报告已保存'), backgroundColor: Colors.green),
      );
      _load(silent: true);

      if (await _syncService.isSyncEnabled()) {
        unawaited(_syncAfterReportSave(messenger));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('保存失败：$e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _syncAfterReportSave(ScaffoldMessengerState messenger) async {
    try {
      final syncResult = await _syncService.sync();
      if (!mounted) return;
      if (syncResult.hasError) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('云同步失败：${syncResult.error}'),
            backgroundColor: Colors.orange,
          ),
        );
      } else if (syncResult.pushed + syncResult.pulled > 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('云同步完成：${syncResult.pushed + syncResult.pulled} 条'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('云同步失败：$e'), backgroundColor: Colors.orange),
      );
    }
  }

  Future<void> _saveIndicatorsLocally(
    _OcrResult result,
    DateTime measuredAt,
  ) async {
    double? systolic;
    double? diastolic;
    double? weight;
    double? glucose;
    double? totalCholesterol;
    double? lowDensityLipoprotein;
    double? highDensityLipoprotein;
    double? triglyceride;
    double? heartRate;
    double? waist;
    double? bodyFat;
    double? spo2;

    for (final indicator in result.indicators) {
      final name = _normalizeIndicatorName(indicator.name);
      final value = _firstNumber(indicator.value);
      if (value == null) continue;

      if (_containsAny(name, ['收缩压', '高压', 'systolic', 'sbp'])) {
        systolic = value;
      } else if (_containsAny(name, ['舒张压', '低压', 'diastolic', 'dbp'])) {
        diastolic = value;
      } else if (_containsAny(name, ['心率', '脉搏', 'heartrate', 'pulse'])) {
        heartRate = value;
      } else if (_containsAny(name, ['体重', 'weight'])) {
        weight = value;
      } else if (_containsAny(name, ['腰围', 'waist'])) {
        waist = value;
      } else if (_containsAny(name, ['体脂', 'bodyfat'])) {
        bodyFat = value;
      } else if (_containsAny(name, ['血氧', 'spo2', '氧饱和'])) {
        spo2 = value;
      } else if (_containsAny(name, ['血糖', '葡萄糖', 'glucose', 'glu', 'fpg']) &&
          !name.contains('尿')) {
        glucose = value;
      } else if (_containsAny(name, ['甘油三酯', 'triglyceride', 'tg'])) {
        triglyceride = value;
      } else if (_containsAny(name, ['低密度脂蛋白', 'ldlc', 'ldl'])) {
        lowDensityLipoprotein = value;
      } else if (_containsAny(name, ['高密度脂蛋白', 'hdlc', 'hdl'])) {
        highDensityLipoprotein = value;
      } else if (_containsAny(
          name, ['总胆固醇', 'totalcholesterol', 'cholesterol', 'tc'])) {
        totalCholesterol = value;
      }
    }

    final tasks = <Future<void>>[];
    final sys = systolic?.round();
    final dia = diastolic?.round();
    if (sys != null && dia != null) {
      tasks.add(_repo.addIndicator(
        type: 'bp',
        payload: {
          'systolic': sys,
          'diastolic': dia,
          'summary': result.summary,
        },
        source: 'report',
        measuredAt: measuredAt,
      ));
    }

    if (heartRate != null) {
      tasks.add(_repo.addIndicator(
        type: 'heart_rate',
        payload: {
          'bpm': heartRate.round(),
          'summary': result.summary,
        },
        source: 'report',
        measuredAt: measuredAt,
      ));
    }

    if (weight != null) {
      tasks.add(_repo.addIndicator(
        type: 'weight',
        payload: {'weightKg': weight, 'summary': result.summary},
        source: 'report',
        measuredAt: measuredAt,
      ));
    }

    if (glucose != null) {
      tasks.add(_repo.addIndicator(
        type: 'glucose',
        payload: {'glucoseMmol': glucose, 'summary': result.summary},
        source: 'report',
        measuredAt: measuredAt,
      ));
    }

    if (totalCholesterol != null ||
        lowDensityLipoprotein != null ||
        highDensityLipoprotein != null ||
        triglyceride != null) {
      tasks.add(_repo.addIndicator(
        type: 'lipid',
        payload: {
          if (totalCholesterol != null) 'tc': totalCholesterol,
          if (lowDensityLipoprotein != null) 'ldl': lowDensityLipoprotein,
          if (highDensityLipoprotein != null) 'hdl': highDensityLipoprotein,
          if (triglyceride != null) 'tg': triglyceride,
          'summary': result.summary,
        },
        source: 'report',
        measuredAt: measuredAt,
      ));
    }

    if (waist != null) {
      tasks.add(_repo.addIndicator(
        type: 'waist',
        payload: {'waistCm': waist, 'summary': result.summary},
        source: 'report',
        measuredAt: measuredAt,
      ));
    }

    if (bodyFat != null) {
      tasks.add(_repo.addIndicator(
        type: 'body_fat',
        payload: {'bodyFatPct': bodyFat, 'summary': result.summary},
        source: 'report',
        measuredAt: measuredAt,
      ));
    }

    if (spo2 != null) {
      tasks.add(_repo.addIndicator(
        type: 'spo2',
        payload: {'spo2Pct': spo2.round(), 'summary': result.summary},
        source: 'report',
        measuredAt: measuredAt,
      ));
    }

    if (tasks.isNotEmpty) await Future.wait(tasks);
  }

  Future<String> _persistReportImage(String clientId) async {
    final image = _pickedImage;
    if (image == null) return '';

    try {
      return await persistReportImage(image, clientId);
    } catch (_) {
      return '';
    }
  }

  Future<void> _deleteReportImage(String imagePath) async {
    if (imagePath.isBlank) return;

    try {
      await deleteReportImage(imagePath);
    } catch (_) {
      // 删除图片失败不影响报告记录删除。
    }
  }

  String _mimeType(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'application/octet-stream',
    };
  }

  DateTime? _parseReportDate(String? value) {
    if (value == null || value.isBlank || value == 'null') return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  double? _firstNumber(String value) {
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value);
    return double.tryParse(match?.group(0) ?? '');
  }

  String _normalizeIndicatorName(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_\-()/（）:：]'), '')
        .replaceAll('胆固醇', '胆固醇');
  }

  bool _containsAny(String value, List<String> keywords) {
    return keywords
        .any((keyword) => value.contains(_normalizeIndicatorName(keyword)));
  }

  String _friendlyError(DioException e) {
    final body = e.response?.data;
    if (body is Map) {
      final code = (body['code'] as num?)?.toInt() ?? 0;
      final message = (body['message'] ?? body['msg'])?.toString();
      if (code == 40101) return '视觉模型 Key 无效，请检查后端配置';
      if (code == 40301) return '该功能需要会员权益';
      if (message != null && message.isNotEmpty) return message;
    }
    final status = e.response?.statusCode;
    if (status == 429) return '请求过于频繁，请稍后重试';
    if (status == 401) return '登录已过期，请重新登录';
    if (e.type == DioExceptionType.receiveTimeout) return 'AI 识别超时，请重试';
    return '网络错误：${e.type.name}';
  }

  Map<String, dynamic> _unwrapResponseData(dynamic body) {
    if (body is! Map) {
      throw StateError('服务端响应格式异常');
    }
    final code = (body['code'] as num?)?.toInt() ?? 0;
    if (code != 0) {
      throw StateError(
        (body['message'] ?? body['msg'])?.toString() ?? '服务端处理失败',
      );
    }
    final data = body['data'];
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw StateError('报告识别未返回有效结果，请检查 AI 配置');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('报告识别')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _PickCard(
              pickedImage: _pickedImage,
              analyzing: _analyzing,
              saving: _saving,
              analyzeStage: _analyzeStage,
              onPickGallery: () => _pickImage(ImageSource.gallery),
              onPickCamera:
                  _canUseCamera ? () => _pickImage(ImageSource.camera) : null,
              onPickFile: _pickFile,
            ),
            if (_ocrResult != null) ...[
              const SizedBox(height: 16),
              _OcrSummaryCard(result: _ocrResult!),
            ],
            if (_saving) ...[
              const SizedBox(height: 16),
              const _ProgressCard(),
            ],
            const SizedBox(height: 16),
            _ReportHistoryPanel(
              records: _reports,
              onOpen: _showReportDetail,
              onDelete: _deleteReport,
            ),
          ],
        ),
      ),
    );
  }
}

class _PickCard extends StatelessWidget {
  const _PickCard({
    required this.pickedImage,
    required this.analyzing,
    required this.saving,
    required this.analyzeStage,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onPickFile,
  });

  final XFile? pickedImage;
  final bool analyzing;
  final bool saving;
  final String analyzeStage;
  final VoidCallback onPickGallery;
  final VoidCallback? onPickCamera;
  final VoidCallback onPickFile;

  @override
  Widget build(BuildContext context) {
    final pickedFile =
        pickedImage == null ? null : reportImageProvider(pickedImage!.path);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryBlue.withValues(alpha: 0.10), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          '报告识别',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          '上传体检或检验报告图片，AI 自动提取指标；确认后保存到本地，云同步开启时会自动加密同步。',
          style: TextStyle(color: AppTheme.muted, height: 1.5),
        ),
        const SizedBox(height: 16),
        if (analyzing && analyzeStage.isNotEmpty) ...[
          _StatusRow(
            text: analyzeStage,
            color: const Color(0xFF0277BD),
          ),
          const SizedBox(height: 8),
        ],
        if (analyzing)
          const _StatusRow(
            text: 'AI 正在识别报告指标...',
            color: Color(0xFF0277BD),
          )
        else if (saving)
          const _StatusRow(
            text: '正在保存识别结果...',
            color: Colors.green,
          )
        else
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton.icon(
              onPressed: onPickGallery,
              icon: const Icon(Icons.photo_library_outlined, size: 16),
              label: const Text('从相册选择'),
            ),
            if (onPickCamera != null)
              OutlinedButton.icon(
                onPressed: onPickCamera,
                icon: const Icon(Icons.camera_alt_outlined, size: 16),
                label: const Text('拍照'),
              ),
            OutlinedButton.icon(
              onPressed: onPickFile,
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: const Text('从文件选择'),
            ),
          ]),
        if (pickedImage != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.image_outlined, size: 14, color: AppTheme.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                pickedImage!.name,
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          if (pickedFile != null) ...[
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _showImagePreview(context, pickedFile),
              child: _ReportImagePreview(file: pickedFile, height: 220),
            ),
          ],
        ],
      ]),
    );
  }
}

bool get _canUseCamera =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
              fontSize: 13, color: color, fontWeight: FontWeight.w600),
        ),
      ),
    ]);
  }
}

class _OcrSummaryCard extends StatelessWidget {
  const _OcrSummaryCard({required this.result});

  final _OcrResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.check_circle_outline,
              size: 16, color: Colors.green.shade700),
          const SizedBox(width: 6),
          Text(
            '识别完成（${result.indicators.length} 项指标）',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: Colors.green.shade700),
          ),
        ]),
        if (result.summary.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(result.summary,
              style: const TextStyle(fontSize: 13, color: AppTheme.muted)),
        ],
        const SizedBox(height: 10),
        _AiAdviceCard(text: _withAiDoctorDisclaimer(result.analysisAdvice)),
      ]),
    );
  }
}

class _AiAdviceCard extends StatelessWidget {
  const _AiAdviceCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0277BD).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF0277BD).withValues(alpha: 0.18)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.psychology_outlined,
            size: 16, color: Color(0xFF0277BD)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppTheme.muted,
            ),
          ),
        ),
      ]),
    );
  }
}

class _ReportContentCard extends StatelessWidget {
  const _ReportContentCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.pageBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppTheme.muted, height: 1.45),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0277BD).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFF0277BD).withValues(alpha: 0.2)),
      ),
      child: const Row(children: [
        Icon(Icons.info_outline, size: 18, color: Color(0xFF0277BD)),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            '确认保存后会写入本地报告库和健康指标库',
            style: TextStyle(
                fontSize: 12,
                color: Color(0xFF0277BD),
                fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

class _OcrReviewSheet extends StatelessWidget {
  const _OcrReviewSheet({
    required this.result,
    required this.onConfirm,
    required this.onDiscard,
  });

  final _OcrResult result;
  final VoidCallback onConfirm;
  final VoidCallback onDiscard;

  Color _statusColor(String status) => switch (status) {
        'high' => Colors.red.shade600,
        'low' => Colors.orange.shade700,
        'normal' => Colors.green.shade700,
        _ => AppTheme.muted,
      };

  String _statusLabel(String status) => switch (status) {
        'high' => '偏高',
        'low' => '偏低',
        'normal' => '正常',
        _ => '待核对',
      };

  @override
  Widget build(BuildContext context) {
    final byCategory = <String, List<_OcrIndicator>>{};
    final rawText = result.rawText.trim();
    for (final indicator in result.indicators) {
      (byCategory[indicator.category.isEmpty ? '其他' : indicator.category] ??=
              [])
          .add(indicator);
    }

    return Container(
      margin: const EdgeInsets.only(top: 80),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Icon(Icons.document_scanner_outlined,
                color: AppTheme.deepBlue),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '识别结果确认',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            Text(result.provider,
                style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
          ]),
        ),
        if (result.summary.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(result.summary,
                style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
          ),
        ],
        const Divider(height: 20),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            children: [
              _AiAdviceCard(
                  text: _withAiDoctorDisclaimer(result.analysisAdvice)),
              const SizedBox(height: 14),
              if (result.indicators.isEmpty) ...[
                const Text(
                  '报告内容',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                _ReportContentCard(
                  text: rawText.isNotEmpty ? rawText : '未识别到具体指标，请人工核对报告图片。',
                ),
              ] else
                for (final entry in byCategory.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 6),
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.muted,
                      ),
                    ),
                  ),
                  for (final indicator in entry.value)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Expanded(
                            child: Text(indicator.name,
                                style: const TextStyle(fontSize: 13))),
                        Text(
                          '${indicator.value} ${indicator.unit}'.trim(),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: _statusColor(indicator.status)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _statusLabel(indicator.status),
                            style: TextStyle(
                              fontSize: 10,
                              color: _statusColor(indicator.status),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ]),
                    ),
                ],
              const SizedBox(height: 8),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Row(children: [
            Expanded(
              child:
                  OutlinedButton(onPressed: onDiscard, child: const Text('放弃')),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: onConfirm,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('保存结果'),
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0277BD)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ReportDetailSheet extends StatelessWidget {
  const _ReportDetailSheet({required this.record});

  final HealthReportRecord record;

  Color _statusColor(String status) => switch (status) {
        'high' => Colors.red.shade600,
        'low' => Colors.orange.shade700,
        'normal' => Colors.green.shade700,
        _ => AppTheme.muted,
      };

  String _statusLabel(String status) => switch (status) {
        'high' => '偏高',
        'low' => '偏低',
        'normal' => '正常',
        _ => '待核对',
      };

  @override
  Widget build(BuildContext context) {
    final structured = Map<String, dynamic>.from(record.structured);
    if ((structured['rawText'] as String? ?? '').trim().isEmpty &&
        record.rawText.trim().isNotEmpty) {
      structured['rawText'] = record.rawText;
    }
    final result = _OcrResult.fromJson(structured);
    final summary = record.summary.trim().isNotEmpty
        ? record.summary.trim()
        : result.summary.trim();
    final rawText = result.rawText.trim();
    final analysisAdvice = _withAiDoctorDisclaimer(result.analysisAdvice);
    final imageFile = reportImageProvider(record.imagePath);
    final imageHeight =
        (MediaQuery.sizeOf(context).height * 0.38).clamp(240.0, 380.0);

    final byCategory = <String, List<_OcrIndicator>>{};
    for (final indicator in result.indicators) {
      (byCategory[indicator.category.isEmpty ? '其他' : indicator.category] ??=
              [])
          .add(indicator);
    }

    return Container(
      margin: const EdgeInsets.only(top: 56),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(children: [
            const Icon(Icons.description_outlined, color: AppTheme.deepBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '报告详情',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormat('yyyy-MM-dd HH:mm').format(record.reportDateTime)} · ${record.provider.isBlank ? 'AI识别' : record.provider}',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ]),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              if (imageFile != null) ...[
                const Text(
                  '报告原图',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _showImagePreview(context, imageFile),
                  child: Stack(
                    children: [
                      _ReportImagePreview(
                        file: imageFile,
                        height: imageHeight.toDouble(),
                      ),
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.open_in_full,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (summary.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Text(
                    summary,
                    style: const TextStyle(color: AppTheme.muted, height: 1.5),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              _AiAdviceCard(text: analysisAdvice),
              const SizedBox(height: 14),
              Row(children: [
                const Expanded(
                  child: Text(
                    '识别指标',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${result.indicators.length} 项',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ]),
              const SizedBox(height: 8),
              if (result.indicators.isEmpty) ...[
                _ReportContentCard(
                  text:
                      rawText.isNotEmpty ? rawText : '这份报告未识别到具体指标，请人工核对报告原图。',
                ),
              ] else
                for (final entry in byCategory.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 6),
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.muted,
                      ),
                    ),
                  ),
                  for (final indicator in entry.value)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.pageBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(
                                indicator.name,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                            ),
                            Text(
                              '${indicator.value} ${indicator.unit}'.trim(),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: _statusColor(indicator.status)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _statusLabel(indicator.status),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _statusColor(indicator.status),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ]),
                          if (indicator.referenceRange.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '参考范围：${indicator.referenceRange}',
                              style: const TextStyle(
                                  color: AppTheme.muted, fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              if (rawText.isNotEmpty) ...[
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    '识别原文',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        rawText,
                        style: const TextStyle(
                            color: AppTheme.muted, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

class _ReportHistoryPanel extends StatefulWidget {
  const _ReportHistoryPanel({
    required this.records,
    required this.onOpen,
    required this.onDelete,
  });

  final List<HealthReportRecord> records;
  final ValueChanged<HealthReportRecord> onOpen;
  final ValueChanged<HealthReportRecord> onDelete;

  @override
  State<_ReportHistoryPanel> createState() => _ReportHistoryPanelState();
}

class _ReportHistoryPanelState extends State<_ReportHistoryPanel> {
  static const _defaultShow = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasMore = widget.records.length > _defaultShow;
    final visible =
        _expanded ? widget.records : widget.records.take(_defaultShow).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('最近识别结果',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              SizedBox(height: 2),
              Text('每次识别都会保存一条报告记录',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12)),
            ]),
          ),
          if (widget.records.isNotEmpty)
            Text('共 ${widget.records.length} 份',
                style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        ]),
        const SizedBox(height: 14),
        if (widget.records.isEmpty)
          const Text('暂无报告历史。保存一次识别结果后会显示在这里。',
              style: TextStyle(color: AppTheme.muted))
        else
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: Column(
              children: [
                for (final record in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ReportHistoryRow(
                      record: record,
                      onOpen: () => widget.onOpen(record),
                      onDelete: () => widget.onDelete(record),
                    ),
                  ),
              ],
            ),
          ),
        if (hasMore) ...[
          const SizedBox(height: 4),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.pageBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _expanded ? '收起' : '展开全部 ${widget.records.length} 份',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.deepBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: const Icon(Icons.keyboard_arrow_down,
                        size: 18, color: AppTheme.deepBlue),
                  ),
                ],
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _ReportHistoryRow extends StatelessWidget {
  const _ReportHistoryRow({
    required this.record,
    required this.onOpen,
    required this.onDelete,
  });

  final HealthReportRecord record;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final summary = record.summary.trim();
    final title = summary.isNotEmpty ? summary : '体检/检验报告';
    final provider = record.provider.isBlank ? 'AI识别' : record.provider;
    final imageFile = reportImageProvider(record.imagePath);

    return Material(
      color: AppTheme.pageBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            if (imageFile != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image(
                  image: imageFile,
                  width: 46,
                  height: 54,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                width: 46,
                height: 54,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: AppTheme.deepBlue,
                  size: 20,
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${DateFormat('MM/dd HH:mm').format(record.reportDateTime)} · ${record.indicatorCount} 项指标 · $provider',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                  ]),
            ),
            IconButton(
              tooltip: '删除报告',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ReportImagePreview extends StatelessWidget {
  const _ReportImagePreview({required this.file, required this.height});

  final ImageProvider<Object> file;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: height,
        width: double.infinity,
        color: AppTheme.pageBg,
        alignment: Alignment.center,
        child: Image(
          image: file,
          width: double.infinity,
          height: height,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _ImagePreviewPage extends StatelessWidget {
  const _ImagePreviewPage({required this.file});

  final ImageProvider<Object> file;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('报告原图'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: InteractiveViewer(
          minScale: 0.6,
          maxScale: 4,
          child: Center(
            child: Image(
              image: file,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

void _showImagePreview(BuildContext context, ImageProvider<Object> file) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => _ImagePreviewPage(file: file)),
  );
}

extension on String {
  bool get isBlank => trim().isEmpty;
}
