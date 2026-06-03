import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../app/app_theme.dart';
import '../../core/auth/user_session.dart';
import '../../core/crypto/key_vault.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/membership/membership_service.dart';
import '../../core/membership/paywall.dart';
import '../../core/network/api_client.dart';

// ── 数据结构 ──────────────────────────────────────────────────

class _OcrIndicator {
  _OcrIndicator({
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
  final String status; // normal / high / low / unknown

  factory _OcrIndicator.fromJson(Map<String, dynamic> j) => _OcrIndicator(
        category: j['category'] as String? ?? '',
        name: j['name'] as String? ?? '',
        value: j['value'] as String? ?? '',
        unit: j['unit'] as String? ?? '',
        referenceRange: j['referenceRange'] as String? ?? '',
        status: j['status'] as String? ?? 'unknown',
      );
}

class _OcrResult {
  _OcrResult({
    required this.reportDate,
    required this.indicators,
    required this.summary,
    required this.rawText,
    required this.provider,
  });

  final String? reportDate;
  final List<_OcrIndicator> indicators;
  final String summary;
  final String rawText;
  final String provider;

  factory _OcrResult.fromJson(Map<String, dynamic> j) {
    final indList = (j['indicators'] as List? ?? [])
        .map((e) => _OcrIndicator.fromJson(e as Map<String, dynamic>))
        .toList();
    return _OcrResult(
      reportDate: j['reportDate'] as String?,
      indicators: indList,
      summary: j['summary'] as String? ?? '',
      rawText: j['rawText'] as String? ?? '',
      provider: j['provider'] as String? ?? 'oneapi',
    );
  }

  Map<String, dynamic> toJson() => {
        'reportDate': reportDate,
        'indicators': indicators
            .map((i) => {
                  'category': i.category,
                  'name': i.name,
                  'value': i.value,
                  'unit': i.unit,
                  'referenceRange': i.referenceRange,
                  'status': i.status,
                })
            .toList(),
        'summary': summary,
        'rawText': rawText,
      };
}

// ── 页面主体 ──────────────────────────────────────────────────

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final HealthRepository _repo = sl<HealthRepository>();
  final MembershipService _membership = sl<MembershipService>();
  final ApiClient _apiClient = sl<ApiClient>();
  final KeyVault _keyVault = sl<KeyVault>();
  final _picker = ImagePicker();

  bool _loading = true;
  bool _analyzing = false; // OCR 请求中
  bool _saving = false;    // 加密上传保存中

  XFile? _pickedImage;
  _OcrResult? _ocrResult;
  List<HealthIndicatorEntry> _recent = const [];

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
    if (!mounted) return;
    if (!silent) setState(() => _loading = true);
    final indicators = await _repo.loadIndicators(limit: 10);
    if (!mounted) return;
    setState(() {
      _recent = indicators;
      _loading = false;
    });
  }

  // ── 1. 选取图片 ───────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    // 会员校验
    final isMember = await _membership.isActive();
    if (!isMember && mounted) {
      await showPaywall(context, PaywallFeature.reportOcr);
      return;
    }

    XFile? file;
    try {
      file = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 88,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开相机/相册失败：$e')),
        );
      }
      return;
    }

    if (file == null) return; // 用户取消

    setState(() {
      _pickedImage = file;
      _ocrResult = null;
    });

    await _analyzeImage(file);
  }

  // ── 2. 发送 OCR 分析请求 ──────────────────────────────────────

  Future<void> _analyzeImage(XFile file) async {
    setState(() => _analyzing = true);

    try {
      final bytes = await file.readAsBytes();
      final mimeType = _mimeType(file.name);

      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: file.name,
          contentType: DioMediaType.parse(mimeType),
        ),
      });

      final resp = await _apiClient.dio.post('/reports/analyze', data: formData);
      final data = resp.data['data'] as Map<String, dynamic>;
      final result = _OcrResult.fromJson(data);

      if (!mounted) return;
      setState(() {
        _ocrResult = result;
        _analyzing = false;
      });

      // 弹出审核确认单
      if (mounted) _showReviewSheet(result, file);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _analyzing = false);
      final msg = _friendlyError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('识别失败：$msg'), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _analyzing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('识别异常：$e')));
    }
  }

  // ── 3. 审核确认底部弹窗 ────────────────────────────────────────

  void _showReviewSheet(_OcrResult result, XFile imageFile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OcrReviewSheet(
        result: result,
        imageFile: imageFile,
        onConfirm: () {
          Navigator.pop(context);
          _encryptAndSave(result, imageFile);
        },
        onDiscard: () => Navigator.pop(context),
      ),
    );
  }

  // ── 4. 加密 + 上传 + 保存 ─────────────────────────────────────

  Future<void> _encryptAndSave(_OcrResult result, XFile imageFile) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final clientId = const Uuid().v4().replaceAll('-', '');
      final imageBytes = await imageFile.readAsBytes();
      final now = DateTime.now();
      final deviceId = UserSession.instance.name;

      // ── 步骤 A：加密图片 ──────────────────────────────────────
      // 生成随机 DEK（每个文件独立）
      final dek = KeyVault.generateDek();

      // 用 DEK 加密图片字节
      final encImg = await KeyVault.encryptWithDek(imageBytes, dek);

      // ── 步骤 B：派生 K_file，包裹 DEK ────────────────────────
      String? imageOssKey;
      String? wrappedDek, wrapIv, wrapTag;

      final kFile = await _keyVault.deriveFileKey().catchError((_) => null as Uint8List?);

      if (kFile != null) {
        final wrapped = await KeyVault.wrapDek(dek, kFile);
        wrappedDek = wrapped['wrappedDek'];
        wrapIv = wrapped['iv'];
        wrapTag = wrapped['tag'];

        // ── 步骤 C：上传加密图片 ──────────────────────────────
        final encBytes = Uint8List.fromList([
          ...base64Decode(encImg['cipher']!),
        ]);
        // 上传格式：加密后的字节，文件名 clientId.enc
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(
            encBytes,
            filename: '$clientId.enc',
            contentType: DioMediaType('application', 'octet-stream'),
          ),
          'clientId': clientId,
        });
        final uploadResp =
            await _apiClient.dio.post('/files/upload', data: formData);
        imageOssKey =
            (uploadResp.data['data'] as Map<String, dynamic>)['ossKey'] as String?;
      }

      // ── 步骤 D：加密 OCR 文本 + 结构化 JSON ──────────────────
      final ocrTextBytes = utf8.encode(result.rawText);
      final structuredBytes = utf8.encode(jsonEncode(result.toJson()));

      final encOcr = await KeyVault.encryptWithDek(
          Uint8List.fromList(ocrTextBytes), dek);
      final encStructured = await KeyVault.encryptWithDek(
          Uint8List.fromList(structuredBytes), dek);
      final encSummary = await KeyVault.encryptWithDek(
          Uint8List.fromList(utf8.encode(result.summary)), dek);

      // ── 步骤 E：上报 ReportSaveRequest ────────────────────────
      final reportTime = result.reportDate != null
          ? '${result.reportDate}T00:00:00'
          : now.toIso8601String();

      await _apiClient.dio.post('/reports', data: {
        'clientId': clientId,
        'reportTime': reportTime,
        'deviceId': deviceId,
        'clientUpdatedAt': now.toIso8601String(),
        if (imageOssKey != null) 'imageOssKey': imageOssKey,
        if (wrappedDek != null) ...{
          'imageWrappedDek': wrappedDek,
          'imageDekIv': wrapIv,
          'imageDekTag': wrapTag,
        },
        'ocrTextCipher': encOcr['cipher'],
        'ocrTextIv': encOcr['iv'],
        'ocrTextTag': encOcr['tag'],
        'structuredCipher': encStructured['cipher'],
        'structuredIv': encStructured['iv'],
        'structuredTag': encStructured['tag'],
        'summaryCipher': encSummary['cipher'],
        'summaryIv': encSummary['iv'],
        'summaryTag': encSummary['tag'],
        'alg': 'aes-256-gcm:v1',
      });

      // ── 步骤 F：同步保存指标到本地 DB ────────────────────────
      await _saveIndicatorsLocally(result, now);

      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('报告已加密保存 ✓'),
          backgroundColor: Colors.green,
        ),
      );
      _load(silent: true);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('保存失败：${_friendlyError(e)}'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);

      // UMK 未就绪时降级：仅本地保存指标，不上传图片
      if (e is StateError && e.message.contains('UMK')) {
        await _saveIndicatorsLocally(result, DateTime.now());
        if (!mounted) return;
        setState(() => _saving = false);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('指标已保存（图片加密需先开通云同步）'),
          ),
        );
        _load(silent: true);
      } else {
        messenger.showSnackBar(
            SnackBar(content: Text('保存异常：$e')));
      }
    }
  }

  // ── 将 OCR 识别的指标存入本地健康库 ──────────────────────────

  Future<void> _saveIndicatorsLocally(
      _OcrResult result, DateTime measuredAt) async {
    // 尝试从识别结果中提取常见指标存入本地 DB
    String? systolicStr, diastolicStr, weightStr, glucoseStr, tcStr, ldlStr;

    for (final ind in result.indicators) {
      final name = ind.name.toLowerCase();
      final val = ind.value.trim();
      if (val.isEmpty) continue;
      if (name.contains('收缩') || name.contains('systolic')) {
        systolicStr = val;
      } else if (name.contains('舒张') || name.contains('diastolic')) {
        diastolicStr = val;
      } else if (name.contains('体重') || name.contains('weight')) {
        weightStr = val;
      } else if ((name.contains('血糖') || name.contains('glucose')) &&
          !name.contains('餐')) {
        glucoseStr = val;
      } else if (name.contains('总胆固醇') ||
          name == 'tc' ||
          name.contains('cholesterol')) {
        tcStr = val;
      } else if (name.contains('ldl') || name.contains('低密度')) {
        ldlStr = val;
      }
    }

    final tasks = <Future<void>>[];
    final sys = int.tryParse(systolicStr ?? '');
    final dia = int.tryParse(diastolicStr ?? '');
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
    final weight = double.tryParse(weightStr ?? '');
    if (weight != null) {
      tasks.add(_repo.addIndicator(
        type: 'weight',
        payload: {'weightKg': weight, 'summary': result.summary},
        source: 'report',
        measuredAt: measuredAt,
      ));
    }
    final glucose = double.tryParse(glucoseStr ?? '');
    if (glucose != null) {
      tasks.add(_repo.addIndicator(
        type: 'glucose',
        payload: {'glucoseMmol': glucose, 'summary': result.summary},
        source: 'report',
        measuredAt: measuredAt,
      ));
    }
    final tc = double.tryParse(tcStr ?? '');
    final ldl = double.tryParse(ldlStr ?? '');
    if (tc != null || ldl != null) {
      tasks.add(_repo.addIndicator(
        type: 'lipid',
        payload: {
          if (tc != null) 'tc': tc,
          if (ldl != null) 'ldl': ldl,
          'summary': result.summary,
        },
        source: 'report',
        measuredAt: measuredAt,
      ));
    }

    if (tasks.isNotEmpty) await Future.wait(tasks);
  }

  // ── 工具 ──────────────────────────────────────────────────────

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

  String _friendlyError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 40301) return '此功能需要会员权益';
    if (status == 429) return '请求过于频繁，请稍后重试';
    if (status == 401) return '登录已过期，请重新登录';
    if (e.type == DioExceptionType.receiveTimeout) return 'AI 识别超时，请重试';
    final msg = e.response?.data?['message'] as String?;
    return msg ?? '网络错误（${e.type.name}）';
  }

  // ── UI ────────────────────────────────────────────────────────

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
              onPickGallery: () => _pickImage(ImageSource.gallery),
              onPickCamera: () => _pickImage(ImageSource.camera),
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
            _CollapsibleRecentPanel(items: _recent),
          ],
        ),
      ),
    );
  }
}

// ── 选图卡片 ──────────────────────────────────────────────────

class _PickCard extends StatelessWidget {
  const _PickCard({
    required this.pickedImage,
    required this.analyzing,
    required this.saving,
    required this.onPickGallery,
    required this.onPickCamera,
  });

  final XFile? pickedImage;
  final bool analyzing;
  final bool saving;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;

  @override
  Widget build(BuildContext context) {
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
        const Text('报告识别',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          '上传体检报告图片，AI 自动提取所有指标并加密存储。',
          style: TextStyle(color: AppTheme.muted, height: 1.5),
        ),
        const SizedBox(height: 16),

        if (analyzing)
          const _StatusRow(
            icon: Icons.auto_awesome_outlined,
            text: 'AI 正在识别报告指标…',
            color: Color(0xFF0277BD),
          )
        else if (saving)
          const _StatusRow(
            icon: Icons.lock_outline,
            text: '正在加密上传…',
            color: Colors.green,
          )
        else
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton.icon(
              onPressed: onPickGallery,
              icon: const Icon(Icons.photo_library_outlined, size: 16),
              label: const Text('从相册选择'),
            ),
            OutlinedButton.icon(
              onPressed: onPickCamera,
              icon: const Icon(Icons.camera_alt_outlined, size: 16),
              label: const Text('拍照'),
            ),
          ]),

        if (pickedImage != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.image_outlined,
                size: 14, color: AppTheme.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                pickedImage!.name,
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

// ── 状态行 ────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: color),
      ),
      const SizedBox(width: 10),
      Text(text,
          style: TextStyle(
              fontSize: 13, color: color, fontWeight: FontWeight.w600)),
    ]);
  }
}

// ── OCR 结果摘要卡 ────────────────────────────────────────────

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
          Text('识别完成（${result.indicators.length} 项指标）',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.green.shade700)),
        ]),
        const SizedBox(height: 6),
        if (result.summary.isNotEmpty)
          Text(result.summary,
              style: const TextStyle(fontSize: 13, color: AppTheme.muted)),
      ]),
    );
  }
}

// ── 加密上传进度卡 ────────────────────────────────────────────

class _ProgressCard extends StatelessWidget {
  const _ProgressCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0277BD).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFF0277BD).withValues(alpha: 0.2)),
      ),
      child: const Row(children: [
        SizedBox(
          width: 18,
          height: 18,
          child:
              CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0277BD)),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'AES-256-GCM 加密 → 上传服务器 → 保存元数据…',
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

// ── OCR 审核底部弹窗 ──────────────────────────────────────────

class _OcrReviewSheet extends StatelessWidget {
  const _OcrReviewSheet({
    required this.result,
    required this.imageFile,
    required this.onConfirm,
    required this.onDiscard,
  });

  final _OcrResult result;
  final XFile imageFile;
  final VoidCallback onConfirm;
  final VoidCallback onDiscard;

  Color _statusColor(String status) => switch (status) {
        'high' => Colors.red.shade600,
        'low' => Colors.orange.shade700,
        'normal' => Colors.green.shade700,
        _ => AppTheme.muted,
      };

  String _statusLabel(String status) => switch (status) {
        'high' => '↑偏高',
        'low' => '↓偏低',
        'normal' => '正常',
        _ => '—',
      };

  @override
  Widget build(BuildContext context) {
    final byCategory = <String, List<_OcrIndicator>>{};
    for (final ind in result.indicators) {
      (byCategory[ind.category] ??= []).add(ind);
    }
    final bottomPad = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      margin: const EdgeInsets.only(top: 80),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPad),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // 把手
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

        // 标题行
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Icon(Icons.document_scanner_outlined,
                color: AppTheme.deepBlue),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('识别结果确认',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            Text(result.provider,
                style: const TextStyle(
                    color: AppTheme.muted, fontSize: 11)),
          ]),
        ),

        if (result.summary.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(result.summary,
                style: const TextStyle(
                    color: AppTheme.muted, fontSize: 13)),
          ),
        ],
        const Divider(height: 20),

        // 指标列表
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            children: [
              if (result.indicators.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('未识别到具体指标，请手动录入。',
                      style: TextStyle(color: AppTheme.muted)),
                )
              else
                for (final entry in byCategory.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 6),
                    child: Text(entry.key,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.muted)),
                  ),
                  for (final ind in entry.value)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Expanded(
                          child: Text(ind.name,
                              style: const TextStyle(fontSize: 13)),
                        ),
                        Text('${ind.value} ${ind.unit}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: _statusColor(ind.status)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(_statusLabel(ind.status),
                              style: TextStyle(
                                  fontSize: 10,
                                  color: _statusColor(ind.status),
                                  fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ),
                ],
              const SizedBox(height: 8),
            ],
          ),
        ),

        // 操作按钮
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onDiscard,
                child: const Text('放弃'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: onConfirm,
                icon: const Icon(Icons.lock_outline, size: 16),
                label: const Text('加密保存'),
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

// ── 通用面板 ──────────────────────────────────────────────────

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        const SizedBox(height: 16),
        child,
      ]),
    );
  }
}

// ── 最近记录列表 ──────────────────────────────────────────────

// ── 可收放的最近指标面板 ──────────────────────────────────────

class _CollapsibleRecentPanel extends StatefulWidget {
  const _CollapsibleRecentPanel({required this.items});
  final List<HealthIndicatorEntry> items;

  @override
  State<_CollapsibleRecentPanel> createState() =>
      _CollapsibleRecentPanelState();
}

class _CollapsibleRecentPanelState extends State<_CollapsibleRecentPanel> {
  static const _defaultShow = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final hasMore = items.length > _defaultShow;
    final visible = _expanded ? items : items.take(_defaultShow).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 标题行
        Row(children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('最近识别结果',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              SizedBox(height: 2),
              Text('已存入本地健康指标库',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12)),
            ]),
          ),
          if (items.isNotEmpty)
            Text('共 ${items.length} 条',
                style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        ]),
        const SizedBox(height: 14),

        // 指标列表
        if (items.isEmpty)
          const Text('暂无识别结果。', style: TextStyle(color: AppTheme.muted))
        else
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: Column(
              children: [
                for (final item in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _IndicatorRow(item: item),
                  ),
              ],
            ),
          ),

        // 展开/收起按钮
        if (hasMore) ...[
          const SizedBox(height: 4),
          GestureDetector(
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
                    _expanded
                        ? '收起'
                        : '展开全部 ${items.length} 条',
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.deepBlue,
                        fontWeight: FontWeight.w600),
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

class _IndicatorRow extends StatelessWidget {
  const _IndicatorRow({required this.item});
  final HealthIndicatorEntry item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.pageBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_iconFor(item.type), color: AppTheme.deepBlue, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.label,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13)),
            Text(item.displayValue,
                style: const TextStyle(
                    color: AppTheme.muted, fontSize: 12)),
          ]),
        ),
        Text(DateFormat('MM/dd').format(item.measuredTime),
            style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      ]),
    );
  }
}

IconData _iconFor(String type) => switch (type) {
      'bp' => Icons.favorite_outline,
      'weight' => Icons.scale_outlined,
      'glucose' => Icons.monitor_heart_outlined,
      'lipid' => Icons.science_outlined,
      _ => Icons.fiber_manual_record_outlined,
    };
