import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_theme.dart';
import '../../core/di/service_locator.dart';
import '../../core/membership/paywall.dart';
import '../../core/network/ai_api.dart';

class SelfCheckPage extends StatefulWidget {
  const SelfCheckPage({super.key});

  @override
  State<SelfCheckPage> createState() => _SelfCheckPageState();
}

class _SelfCheckPageState extends State<SelfCheckPage> {
  final _picker = ImagePicker();
  final _api = sl<AiApi>();

  _CheckType _type = _CheckType.skin;
  XFile? _image;
  AiVisionResult? _result;
  bool _loading = false;
  bool _skinStarted = false;
  bool _privacyAgreed = false;
  String? _error;

  Future<void> _pick(ImageSource source) async {
    final ok = await requireAccountAndMember(context, PaywallFeature.reportOcr);
    if (!ok) return;

    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
      );
      if (image == null) return;
      setState(() {
        _image = image;
        _result = null;
        _error = null;
      });
      await _analyze(image);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '打开图片失败：$e');
    }
  }

  Future<void> _analyze(XFile image) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.analyzeVision(image: image, type: _type.value);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyDioError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _selectType(_CheckType type) {
    setState(() {
      _type = type;
      _image = null;
      _result = null;
      _error = null;
      _skinStarted = type != _CheckType.skin;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canUseCamera = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    return Scaffold(
      appBar: AppBar(title: Text(_type.appBarTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final type in _CheckType.values)
                ChoiceChip(
                  label: Text(type.label),
                  selected: _type == type,
                  onSelected: _loading ? null : (_) => _selectType(type),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_type == _CheckType.skin && !_skinStarted)
            _SkinIntroCard(
              agreed: _privacyAgreed,
              onAgreedChanged: (value) =>
                  setState(() => _privacyAgreed = value ?? false),
              onStart: _privacyAgreed
                  ? () => setState(() => _skinStarted = true)
                  : null,
            )
          else
            _UploadCard(
              type: _type,
              imageName: _image?.name,
              loading: _loading,
              canUseCamera: canUseCamera,
              onPickCamera: () => _pick(ImageSource.camera),
              onPickGallery: () => _pick(ImageSource.gallery),
            ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            _ErrorCard(message: _error!)
          else if (_result != null)
            _ResultCard(result: _result!),
        ],
      ),
    );
  }

  String _friendlyDioError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      return (data['message'] ?? data['msg'])?.toString() ?? 'AI 分析失败';
    }
    return e.message ?? '网络异常，请稍后重试';
  }
}

class _SkinIntroCard extends StatelessWidget {
  const _SkinIntroCard({
    required this.agreed,
    required this.onAgreedChanged,
    required this.onStart,
  });

  final bool agreed;
  final ValueChanged<bool?> onAgreedChanged;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEFF6FF), Color(0xFFFDF2F8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI 测肤质',
            style: TextStyle(
              color: AppTheme.deepBlue,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '检测肤质、肤色、痘痘、毛孔、纹理、泛红等信息',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          const _SkinFeatureRow(text: '请在光线充足的环境中正脸居中拍摄'),
          const _SkinFeatureRow(text: '尽量素颜，避免强滤镜、强美颜和过暗环境'),
          const _SkinFeatureRow(text: '结果仅用于智能测肤及面部特征分析'),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onStart,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('开始检测 →', style: TextStyle(fontSize: 18)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          CheckboxListTile(
            value: agreed,
            onChanged: onAgreedChanged,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              '仅收集必要脸部照片用于智能测肤及面部特征分析，我已阅读并同意隐私说明。',
              style: TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkinFeatureRow extends StatelessWidget {
  const _SkinFeatureRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.face_retouching_natural_outlined,
              size: 18, color: AppTheme.deepBlue),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  const _UploadCard({
    required this.type,
    required this.imageName,
    required this.loading,
    required this.canUseCamera,
    required this.onPickCamera,
    required this.onPickGallery,
  });

  final _CheckType type;
  final String? imageName;
  final bool loading;
  final bool canUseCamera;
  final VoidCallback onPickCamera;
  final VoidCallback onPickGallery;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            type.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(type.hint, style: const TextStyle(color: AppTheme.muted)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (canUseCamera)
                FilledButton.icon(
                  onPressed: loading ? null : onPickCamera,
                  icon: const Icon(Icons.camera_alt_outlined, size: 16),
                  label: const Text('拍照'),
                ),
              OutlinedButton.icon(
                onPressed: loading ? null : onPickGallery,
                icon: const Icon(Icons.photo_library_outlined, size: 16),
                label: const Text('从相册选择'),
              ),
            ],
          ),
          if (imageName != null) ...[
            const SizedBox(height: 10),
            Text(
              imageName!,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final AiVisionResult result;

  @override
  Widget build(BuildContext context) {
    final isSkin = result.type == 'skin';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.summary,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          if (isSkin) ...[
            const SizedBox(height: 12),
            _SkinSummary(result: result),
          ],
          if (result.dimensions.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('维度分析', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final item in result.dimensions)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DimensionTile(item: item),
              ),
          ],
          if (result.observations.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('可见观察', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final item in result.observations)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $item'),
              ),
          ],
          if (result.careRoutine.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('护理建议', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final item in result.careRoutine)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $item'),
              ),
          ],
          const SizedBox(height: 12),
          const Text('综合建议', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(result.advice, style: const TextStyle(height: 1.5)),
          if (result.provider.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '识别服务：${result.provider}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _SkinSummary extends StatelessWidget {
  const _SkinSummary({required this.result});

  final AiVisionResult result;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (result.healthScore != null)
          _InfoPill(label: '肌肤评分', value: '${result.healthScore}'),
        if (result.skinType.isNotEmpty)
          _InfoPill(label: '肤质', value: result.skinType),
        if (result.skinTone.isNotEmpty)
          _InfoPill(label: '肤色', value: result.skinTone),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text('$label：$value',
          style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _DimensionTile extends StatelessWidget {
  const _DimensionTile({required this.item});

  final AiVisionDimension item;

  @override
  Widget build(BuildContext context) {
    final score = item.score;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (score != null) Text('$score/100'),
            ],
          ),
          if (score != null) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: (score.clamp(0, 100)) / 100,
              minHeight: 6,
              borderRadius: BorderRadius.circular(99),
            ),
          ],
          if (item.status.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('状态：${item.status}'),
          ],
          if (item.detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(item.detail, style: const TextStyle(height: 1.4)),
          ],
          if (item.suggestion.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '建议：${item.suggestion}',
              style: const TextStyle(color: AppTheme.deepBlue, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Text(message, style: const TextStyle(color: Colors.redAccent)),
    );
  }
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: AppTheme.cardBorder),
  );
}

enum _CheckType {
  skin(
    'skin',
    '测肤质',
    '测肤质',
    '请正脸居中拍摄，AI 会分析肤质、肤色、痘痘、毛孔、纹理、泛红等信息。',
    '测肤质',
  ),
  tongue(
    'tongue',
    '看舌苔',
    '看舌苔',
    '伸舌后拍清楚舌面，避免刚吃完有颜色的食物。',
    'AI 拍照自查',
  ),
  hair(
    'hair',
    '测脱发',
    '测脱发',
    '拍发际线、头顶或分缝位置，尽量保持光线均匀。',
    'AI 拍照自查',
  );

  const _CheckType(
    this.value,
    this.label,
    this.title,
    this.hint,
    this.appBarTitle,
  );

  final String value;
  final String label;
  final String title;
  final String hint;
  final String appBarTitle;
}
