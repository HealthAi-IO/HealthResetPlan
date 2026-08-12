import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_settings_controller.dart';
import '../../app/app_theme.dart';
import '../../core/auth/user_session.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_data_import_service.dart';
import '../../core/data/health_pdf_service.dart';
import '../../core/data/health_repository.dart';
import '../../core/data/online_data_service.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../core/network/ai_consent_api.dart';
import '../../core/network/auth_api.dart';
import '../../core/notification/reminder_scheduler.dart';
import '../../core/privacy/privacy_consent_gate.dart';
import '../../core/storage/data_sync_status.dart';
import '../../core/storage/data_sync_merge.dart';
import 'cancel_account_dialog.dart';
import 'gender_selector.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    this.manageAiOnOpen = false,
    this.guideProfileOnOpen = false,
  });

  final bool manageAiOnOpen;
  final bool guideProfileOnOpen;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final HealthRepository _repo = sl<HealthRepository>();
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  final _birthYearController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _medicalHistoryController = TextEditingController();
  final _medicationsController = TextEditingController();
  final _scrollController = ScrollController();
  final _profileFormSectionKey = GlobalKey();
  final _nicknameFocusNode = FocusNode();
  final _genderFocusNode = FocusNode();
  final _birthYearFocusNode = FocusNode();
  final _heightFocusNode = FocusNode();
  final _weightFocusNode = FocusNode();

  String _gender = 'female';
  String _goal = 'maintain';
  String _exerciseBase = 'none';
  String _dietPreference = 'normal';
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false; // 用户已手动修改表单但尚未保存
  bool _avatarUploading = false;
  UserProfileData? _profile;
  List<HealthIndicatorEntry> _indicators = const [];
  AccountInfo? _accountInfo;
  bool _aiConsentOpened = false;
  bool _profileGuideOpened = false;
  bool? _notificationsEnabled;
  bool? _exactAlarmEnabled;
  late bool _profileGuideVisible;

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  @override
  void initState() {
    super.initState();
    _profileGuideVisible = widget.guideProfileOnOpen;
    _repo.addListener(_onRepoChanged);
    appSettingsController.addListener(_onSettingsChanged);
    dataSyncStatusController.addListener(_onSettingsChanged);
    _load();
    // 任意字段变化则标记为“有未保存改动”，防止后续 repo 变更覆盖用户编辑
    for (final ctrl in [
      _nicknameController,
      _birthYearController,
      _heightController,
      _weightController,
      _medicalHistoryController,
      _medicationsController,
    ]) {
      ctrl.addListener(_markDirty);
    }
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    appSettingsController.removeListener(_onSettingsChanged);
    dataSyncStatusController.removeListener(_onSettingsChanged);
    _nicknameController.dispose();
    _birthYearController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _medicalHistoryController.dispose();
    _medicationsController.dispose();
    _scrollController.dispose();
    _nicknameFocusNode.dispose();
    _genderFocusNode.dispose();
    _birthYearFocusNode.dispose();
    _heightFocusNode.dispose();
    _weightFocusNode.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _onRepoChanged() {
    // 无未保存改动时（如刚打开档案页），允许同步表单以反映最新数据
    _load(silent: true, syncForm: !_dirty);
  }

  Future<void> _load({bool silent = false, bool syncForm = true}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() => _loading = true);
    }
    UserProfileData? profile = _profile;
    List<HealthIndicatorEntry> indicators = _indicators;
    AccountInfo? accountInfo = _accountInfo;
    try {
      profile = await _repo.loadProfile();
    } catch (_) {}
    try {
      indicators = await _repo.loadIndicators(limit: 10);
    } catch (_) {}
    if (UserSession.instance.isAccountLogin) {
      try {
        accountInfo = await sl<AuthApi>().fetchAccountInfo();
      } catch (_) {}
    } else {
      accountInfo = null;
    }
    final scheduler = sl<ReminderScheduler>();
    bool? notificationsEnabled;
    bool? exactAlarmEnabled;
    try {
      notificationsEnabled = await scheduler.notificationsEnabled();
      exactAlarmEnabled = await scheduler.exactAlarmEnabled();
    } catch (_) {}
    if (!mounted) return;
    _profile = profile;
    _indicators = indicators;
    _accountInfo = accountInfo;
    _notificationsEnabled = notificationsEnabled;
    _exactAlarmEnabled = exactAlarmEnabled;
    if (syncForm) _syncControllers(profile);
    _profileGuideVisible =
        widget.guideProfileOnOpen && !_isBasicProfileComplete(profile);
    setState(() => _loading = false);
    if (widget.manageAiOnOpen && !_aiConsentOpened) {
      _aiConsentOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _manageAiConsent();
      });
    }
    if (_profileGuideVisible && !_profileGuideOpened) {
      _profileGuideOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openProfileGuide());
    }
  }

  Future<void> _changeAvatar() async {
    if (!UserSession.instance.isAccountLogin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录账号后即可上传并同步头像')),
      );
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;
      setState(() => _avatarUploading = true);
      final authApi = sl<AuthApi>();
      final avatarUrl = await authApi.uploadAvatar(image.path);
      final account = await authApi.updateAccountProfile(avatarUrl: avatarUrl);
      if (!mounted) return;
      setState(() => _accountInfo = account);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('头像已更新')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('头像更新失败，请检查相机、相册权限或网络后重试')),
      );
    } finally {
      if (mounted) setState(() => _avatarUploading = false);
    }
  }

  bool _isBasicProfileComplete(UserProfileData? profile) {
    return profile != null &&
        profile.nickname.trim().isNotEmpty &&
        profile.gender != 'unknown' &&
        profile.gender.isNotEmpty &&
        profile.birthYear > 0 &&
        profile.heightCm > 0 &&
        profile.weightKg > 0;
  }

  bool _isCurrentBasicProfileComplete() {
    return _nicknameController.text.trim().isNotEmpty &&
        _gender != 'unknown' &&
        _birthYearController.text.trim().isNotEmpty &&
        _heightController.text.trim().isNotEmpty &&
        _weightController.text.trim().isNotEmpty;
  }

  Future<void> _openProfileGuide() async {
    final sectionContext = _profileFormSectionKey.currentContext;
    if (!mounted || sectionContext == null) return;
    await Scrollable.ensureVisible(
      sectionContext,
      alignment: 0.04,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    if (_nicknameController.text.trim().isEmpty) {
      _nicknameFocusNode.requestFocus();
    } else if (_gender == 'unknown') {
      _genderFocusNode.requestFocus();
    } else if (_birthYearController.text.isEmpty) {
      _birthYearFocusNode.requestFocus();
    } else if (_heightController.text.isEmpty) {
      _heightFocusNode.requestFocus();
    } else if (_weightController.text.isEmpty) {
      _weightFocusNode.requestFocus();
    }
  }

  void _syncControllers(UserProfileData? profile) {
    if (profile == null) return;
    // 同步时暂时关闭 dirty 监听，避免赋值本身触发 _markDirty
    _dirty = false;
    _nicknameController.text = profile.nickname;
    _birthYearController.text =
        profile.birthYear == 0 ? '' : profile.birthYear.toString();
    _heightController.text =
        profile.heightCm == 0 ? '' : profile.heightCm.toStringAsFixed(1);
    _weightController.text =
        profile.weightKg == 0 ? '' : profile.weightKg.toStringAsFixed(1);
    _medicalHistoryController.text = profile.medicalHistory;
    _medicationsController.text = profile.medications;
    _gender = profile.gender.isEmpty ? 'female' : profile.gender;
    _goal = profile.goal;
    _exerciseBase = profile.exerciseBase;
    _dietPreference = profile.dietPreference;
    // 同步完成后 dirty 保持 false，下一帧用户操作再触发
  }

  Future<bool> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return false;
    final wasGuided = _profileGuideVisible;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final nickname = _nicknameController.text.trim();
      await _repo.saveProfile(
        UserProfileData(
          id: _profile?.id,
          userId: kLocalUserId,
          nickname: nickname,
          gender: _gender,
          birthYear: int.parse(_birthYearController.text.trim()),
          heightCm: double.parse(_heightController.text.trim()),
          weightKg: double.parse(_weightController.text.trim()),
          medicalHistory: _medicalHistoryController.text.trim(),
          medications: _medicationsController.text.trim(),
          createdAt: _profile?.createdAt ?? now,
          updatedAt: now,
          goal: _goal,
          exerciseBase: _exerciseBase,
          dietPreference: _dietPreference,
          version: _profile?.version ?? 0,
          isDirty: 1,
        ),
      );
      await UserSession.instance.setName(nickname);
      if (UserSession.instance.isAccountLogin) {
        await sl<AuthApi>().updateAccountProfile(nickname: nickname);
      }
      if (!mounted) return false;
      _dirty = false; // 保存成功后清除脏标记，允许后续 repo 变更同步表单
      final profileCompleted = _isCurrentBasicProfileComplete();
      setState(() => _profileGuideVisible = wasGuided && !profileCompleted);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            wasGuided && profileCompleted ? '健康档案已完善，可以开始生成计划了' : '健康档案已保存',
          ),
        ),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      messenger.showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickBirthYear() async {
    final currentYear = DateTime.now().year;
    final firstYear = currentYear - HealthRanges.maxAge;
    final lastYear = currentYear - HealthRanges.minAge;
    final currentValue = int.tryParse(_birthYearController.text);
    final initialYear =
        (currentValue ?? currentYear - 30).clamp(firstYear, lastYear).toInt();
    final index = await _showWheelPicker(
      title: '选择出生年份',
      itemCount: lastYear - firstYear + 1,
      initialIndex: initialYear - firstYear,
      itemLabel: (index) => '${firstYear + index} 年',
      helperText: (index) => '${currentYear - firstYear - index} 岁',
    );
    if (index != null) {
      _birthYearController.text = '${firstYear + index}';
    }
  }

  Future<void> _pickHeight() async {
    final minimum = HealthRanges.minHeightCm.round();
    final maximum = HealthRanges.maxHeightCm.round();
    final currentValue = double.tryParse(_heightController.text)?.round();
    final initialValue = (currentValue ?? 170).clamp(minimum, maximum).toInt();
    final index = await _showWheelPicker(
      title: '选择身高',
      itemCount: maximum - minimum + 1,
      initialIndex: initialValue - minimum,
      itemLabel: (index) => '${minimum + index} cm',
      helperText: (index) {
        final weight = double.tryParse(_weightController.text);
        if (weight == null) return '滑动选择身高';
        final meters = (minimum + index) / 100;
        return '当前 BMI ${(weight / (meters * meters)).toStringAsFixed(1)}';
      },
    );
    if (index != null) {
      _heightController.text = (minimum + index).toStringAsFixed(1);
    }
  }

  Future<void> _pickWeight() async {
    final minimum = HealthRanges.minWeightKg;
    final maximum = HealthRanges.maxWeightKg;
    final itemCount = ((maximum - minimum) * 10).round() + 1;
    final currentValue = double.tryParse(_weightController.text);
    final initialValue =
        (currentValue ?? 65).clamp(minimum, maximum).toDouble();
    final index = await _showWheelPicker(
      title: '选择体重',
      itemCount: itemCount,
      initialIndex: ((initialValue - minimum) * 10).round(),
      itemLabel: (index) => '${(minimum + index / 10).toStringAsFixed(1)} kg',
      helperText: (index) {
        final height = double.tryParse(_heightController.text);
        if (height == null) return '滑动选择体重';
        final meters = height / 100;
        final weight = minimum + index / 10;
        return '当前 BMI ${(weight / (meters * meters)).toStringAsFixed(1)}';
      },
    );
    if (index != null) {
      _weightController.text = (minimum + index / 10).toStringAsFixed(1);
    }
  }

  Future<int?> _showWheelPicker({
    required String title,
    required int itemCount,
    required int initialIndex,
    required String Function(int index) itemLabel,
    required String Function(int index) helperText,
  }) async {
    var selectedIndex = initialIndex;
    final scrollController =
        FixedExtentScrollController(initialItem: initialIndex);
    try {
      return await showModalBottomSheet<int>(
        context: context,
        useSafeArea: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => SizedBox(
            height: 340,
            child: Column(
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('取消'),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(sheetContext, selectedIndex),
                      child: const Text('完成'),
                    ),
                  ],
                ),
                Text(
                  helperText(selectedIndex),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: CupertinoPicker.builder(
                    scrollController: scrollController,
                    itemExtent: 44,
                    childCount: itemCount,
                    onSelectedItemChanged: (index) =>
                        setSheetState(() => selectedIndex = index),
                    itemBuilder: (context, index) => Center(
                      child: Text(
                        itemLabel(index),
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      await Future<void>.delayed(kThemeAnimationDuration);
      scrollController.dispose();
    }
  }

  Future<void> _openLegalDocument(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _manageAiConsent() async {
    if (!UserSession.instance.isAccountLogin) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('登录账号后可管理 AI 授权')));
      return;
    }
    final api = sl<AiConsentApi>();
    final accepted = await api.accepted();
    if (!mounted) return;
    final action = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(accepted ? '管理 AI 数据处理授权' : 'AI 数据处理说明'),
        content: Text(accepted
            ? '你已同意云端 AI 数据处理。撤回后，AI 健康顾问、智能计划、报告识别、餐食识别和图像分析将停止；账号中的健康记录不受影响。'
            : '使用 AI 健康顾问、智能计划、报告识别、餐食识别或图像分析时，你主动提交的必要健康信息或图片会由本服务的受控服务器短暂转发给已配置的千问、豆包、智谱 GLM 或 DeepSeek 模型处理。请求正文、AI 回答和图片不写入运营数据、审计日志或明文数据库；管理后台无法查看。AI 仅提供健康管理参考，不能替代医生诊断。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(accepted ? '撤回授权' : '同意并启用 AI')),
        ],
      ),
    );
    if (action != true) return;
    if (accepted) {
      await api.revoke();
    } else {
      await api.accept();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(accepted ? '已撤回 AI 授权' : '已启用 AI 功能')));
    }
  }

  Future<void> _addIndicatorDialog(String type) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<_IndicatorDraft>(
      context: context,
      builder: (_) => _IndicatorDialog(type: type),
    );
    if (result == null) return;
    try {
      await _repo.addIndicator(
        type: type,
        payload: result.payload,
        source: result.source,
        measuredAt: result.measuredAt,
      );
      if (!mounted) return;
      final isCritical = HealthSafety.isCriticalIndicator(type, result.payload);
      messenger.showSnackBar(SnackBar(
        content: Text(isCritical ? '检测到紧急健康风险，请立即就医，已停止运动计划' : '已保存健康指标'),
        duration: Duration(seconds: isCritical ? 6 : 2),
      ));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
    }
  }

  Future<void> _shareHealthPdf() async {
    final days = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择摘要范围'),
        children: [
          for (final value in const [7, 30, 90])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, value),
              child: Text('最近 $value 天'),
            ),
        ],
      ),
    );
    if (days == null || !mounted) return;
    try {
      final bytes = await HealthPdfService(_repo).build(days);
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            '健康摘要_$days天_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('健康摘要生成失败，请重试')),
        );
      }
    }
  }

  Future<void> _saveImportTemplate() async {
    try {
      final bytes = HealthDataImportService(_repo).buildTemplate();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '保存健康数据导入模板',
        fileName: '健康数据导入模板.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes,
      );
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入模板已保存')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('模板保存失败，请重试')),
        );
      }
    }
  }

  Future<void> _importHealthData() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file?.bytes == null || !mounted) return;
    final service = HealthDataImportService(_repo);
    final preview = await service.preview(
      file!.bytes!,
      file.extension ?? '',
    );
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认导入'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('可导入 ${preview.importCount} 条'),
                Text('重复跳过 ${preview.duplicateCount} 条'),
                Text('错误 ${preview.errors.length} 条'),
                if (preview.errors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...preview.errors.take(8).map(Text.new),
                  if (preview.errors.length > 8)
                    Text('另有 ${preview.errors.length - 8} 条错误'),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: preview.importCount == 0
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('确认导入'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final count = await service.commit(preview);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 $count 条，重复数据未覆盖')),
      );
      await _load(silent: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入未完成，请检查网络后重试')),
        );
      }
    }
  }

  Future<void> _setSeniorMode(bool value) async {
    if (!value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('关闭长辈模式'),
          content: const Text('关闭后将恢复普通首页和标准字号。确认关闭吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认关闭'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await appSettingsController.setSeniorMode(value);
  }

  Future<void> _requestNotificationPermission() async {
    await sl<ReminderScheduler>().requestPermission();
    await _load(silent: true, syncForm: false);
  }

  Future<void> _requestExactAlarmPermission() async {
    await sl<ReminderScheduler>().ensureExactAlarmPermission();
    await _load(silent: true, syncForm: false);
  }

  Future<void> _showSeniorProfileEditor() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.9,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              children: [
                const Text('编辑健康档案',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _nicknameController,
                  focusNode: _nicknameFocusNode,
                  decoration: const InputDecoration(labelText: '姓名或称呼'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请输入姓名或称呼' : null,
                ),
                const SizedBox(height: 14),
                GenderSelector(
                  value: _gender,
                  focusNode: _genderFocusNode,
                  onChanged: (value) {
                    setSheetState(() => _gender = value);
                    _markDirty();
                  },
                ),
                const SizedBox(height: 14),
                _ProfileNumberField(
                  controller: _birthYearController,
                  focusNode: _birthYearFocusNode,
                  keyboardType: TextInputType.number,
                  label: '出生年份',
                  onTap: _pickBirthYear,
                  validator: (value) {
                    final year = int.tryParse(value?.trim() ?? '');
                    final age = DateTime.now().year - (year ?? 0);
                    return age < HealthRanges.minAge ||
                            age > HealthRanges.maxAge
                        ? '仅支持 18–100 岁成年人'
                        : null;
                  },
                ),
                const SizedBox(height: 14),
                _ProfileNumberField(
                  controller: _heightController,
                  focusNode: _heightFocusNode,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  label: '身高（cm）',
                  onTap: _pickHeight,
                  validator: (value) {
                    final number = double.tryParse(value?.trim() ?? '');
                    return number == null ||
                            number < HealthRanges.minHeightCm ||
                            number > HealthRanges.maxHeightCm
                        ? '请输入 100–230 cm'
                        : null;
                  },
                ),
                const SizedBox(height: 14),
                _ProfileNumberField(
                  controller: _weightController,
                  focusNode: _weightFocusNode,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  label: '体重（kg）',
                  onTap: _pickWeight,
                  validator: (value) {
                    final number = double.tryParse(value?.trim() ?? '');
                    return number == null ||
                            number < HealthRanges.minWeightKg ||
                            number > HealthRanges.maxWeightKg
                        ? '请输入 20–300 kg'
                        : null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _medicalHistoryController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: '既往病史（选填）'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _medicationsController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: '长期用药（选填）'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _goal,
                  decoration: const InputDecoration(labelText: '健康目标'),
                  items: const [
                    DropdownMenuItem(value: 'maintain', child: Text('保持健康')),
                    DropdownMenuItem(value: 'fat_loss', child: Text('减脂')),
                    DropdownMenuItem(
                        value: 'glucose_control', child: Text('控糖')),
                    DropdownMenuItem(value: 'bp_control', child: Text('控压')),
                  ],
                  onChanged: (value) {
                    setSheetState(() => _goal = value ?? 'maintain');
                    _markDirty();
                  },
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: () async {
                    final saved = await _saveProfile();
                    if (saved && sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                    }
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存健康档案'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSeniorMoreSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        child: Column(
          children: [
            const ListTile(
              title: Text('更多设置',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ),
            _SeniorSettingsTile(
              icon: Icons.psychology_outlined,
              title: 'AI 数据处理授权',
              onTap: () {
                Navigator.pop(sheetContext);
                _manageAiConsent();
              },
            ),
            _SeniorSettingsTile(
              icon: Icons.picture_as_pdf_outlined,
              title: '生成健康摘要 PDF',
              onTap: () {
                Navigator.pop(sheetContext);
                _shareHealthPdf();
              },
            ),
            _SeniorSettingsTile(
              icon: Icons.download_outlined,
              title: '保存数据导入模板',
              onTap: () {
                Navigator.pop(sheetContext);
                _saveImportTemplate();
              },
            ),
            _SeniorSettingsTile(
              icon: Icons.upload_file_outlined,
              title: '导入健康数据',
              onTap: () {
                Navigator.pop(sheetContext);
                _importHealthData();
              },
            ),
            _SeniorSettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: '隐私政策',
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/privacy-policy');
              },
            ),
            _SeniorSettingsTile(
              icon: Icons.description_outlined,
              title: '用户协议',
              onTap: () {
                Navigator.pop(sheetContext);
                _openLegalDocument(termsOfServiceUrl);
              },
            ),
            if (_accountInfo?.hasPassword == false)
              _SeniorSettingsTile(
                icon: Icons.password_outlined,
                title: '设置登录密码',
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('/set-password?returnTo=%2Fprofile&required=1');
                },
              ),
            _SeniorSettingsTile(
              icon: Icons.person_remove_outlined,
              title: '注销账号',
              color: Colors.red,
              onTap: () {
                Navigator.pop(sheetContext);
                _cancelAccount();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('个人中心')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final profile = _profile ?? UserProfileData.empty();
    const bottomPadding = 24.0;

    if (appSettingsController.seniorMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('个人中心')),
        body: _SeniorProfileView(
          profile: profile,
          accountInfo: _accountInfo,
          seniorMode: appSettingsController.seniorMode,
          notificationsEnabled: _notificationsEnabled,
          exactAlarmEnabled: _exactAlarmEnabled,
          syncStatus: dataSyncStatusController,
          onEditProfile: _showSeniorProfileEditor,
          onNotificationPermission: _requestNotificationPermission,
          onExactAlarmPermission: _requestExactAlarmPermission,
          onToggleSeniorMode: _setSeniorMode,
          onReminderSettings: () => context.go('/clock?manage=rules'),
          onMoreSettings: _showSeniorMoreSettings,
          onLogin: () => context
              .push('/login', extra: true)
              .then((_) => _load(silent: true)),
          onSignOut: _signOut,
          onAvatarTap: _changeAvatar,
          avatarUploading: _avatarUploading,
          onRefresh: () => _load(silent: true),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('个人中心')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(20, 4, 20, bottomPadding),
          children: [
            _ProfileHero(
              profile: profile,
              indicators: _indicators,
              accountInfo: _accountInfo,
              onAvatarTap: _changeAvatar,
              avatarUploading: _avatarUploading,
            ),
            const SizedBox(height: 16),
            _Panel(
              title: '健康与智能',
              subtitle: '提醒与 AI 能力管理',
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.alarm_outlined),
                    title: const Text('提醒设置'),
                    subtitle: const Text('管理用药、长期和重复提醒'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/clock?manage=rules'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.psychology_outlined),
                    title: const Text('AI 数据处理授权'),
                    subtitle: const Text('管理 AI 顾问、计划、报告、餐食和图像分析授权'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _manageAiConsent,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _Panel(
              title: '隐私与协议',
              subtitle: '了解数据使用方式与服务条款',
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('隐私政策'),
                    subtitle: const Text('查看完整的个人信息与数据安全说明'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/privacy-policy'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('用户协议'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openLegalDocument(termsOfServiceUrl),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              key: _profileFormSectionKey,
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 960;
                final form = Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_profileGuideVisible) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  '先完善性别、出生年份、身高和体重，保存后即可生成健康计划。',
                                  style: TextStyle(
                                    height: 1.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: _nicknameController,
                        focusNode: _nicknameFocusNode,
                        decoration: const InputDecoration(labelText: '昵称'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? '请输入昵称'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      GenderSelector(
                        value: _gender,
                        focusNode: _genderFocusNode,
                        onChanged: (value) {
                          setState(() {
                            _gender = value;
                            _dirty = true;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _ProfileNumberField(
                              controller: _birthYearController,
                              focusNode: _birthYearFocusNode,
                              label: '出生年份',
                              keyboardType: TextInputType.number,
                              onTap: wide ? null : _pickBirthYear,
                              validator: (value) {
                                final year = int.tryParse(value?.trim() ?? '');
                                final currentYear = DateTime.now().year;
                                if (year == null ||
                                    currentYear - year < HealthRanges.minAge ||
                                    currentYear - year > HealthRanges.maxAge) {
                                  return '仅支持 18–100 岁成年人';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ProfileNumberField(
                              controller: _heightController,
                              focusNode: _heightFocusNode,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              label: '身高（cm）',
                              onTap: wide ? null : _pickHeight,
                              validator: (value) {
                                final height =
                                    double.tryParse(value?.trim() ?? '');
                                if (height == null ||
                                    height < HealthRanges.minHeightCm ||
                                    height > HealthRanges.maxHeightCm) {
                                  return '请输入 100–230 cm';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _ProfileNumberField(
                        controller: _weightController,
                        focusNode: _weightFocusNode,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        label: '体重（kg）',
                        onTap: wide ? null : _pickWeight,
                        validator: (value) {
                          final weight = double.tryParse(value?.trim() ?? '');
                          if (weight == null ||
                              weight < HealthRanges.minWeightKg ||
                              weight > HealthRanges.maxWeightKg) {
                            return '请输入 20–300 kg';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _medicalHistoryController,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: '既往病史'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _medicationsController,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: '用药记录'),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _goal,
                        decoration: const InputDecoration(labelText: '健康目标'),
                        items: const [
                          DropdownMenuItem(
                              value: 'maintain', child: Text('保持健康')),
                          DropdownMenuItem(
                              value: 'fat_loss', child: Text('减脂')),
                          DropdownMenuItem(
                              value: 'glucose_control', child: Text('控糖')),
                          DropdownMenuItem(
                              value: 'bp_control', child: Text('控压')),
                        ],
                        onChanged: (value) => setState(() {
                          _goal = value ?? 'maintain';
                          _dirty = true;
                        }),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _exerciseBase,
                        decoration: const InputDecoration(labelText: '运动基础'),
                        items: const [
                          DropdownMenuItem(
                              value: 'none', child: Text('无（久坐为主）')),
                          DropdownMenuItem(
                              value: 'light', child: Text('轻度（每周 1-2 次）')),
                          DropdownMenuItem(
                              value: 'moderate', child: Text('中等（每周 3-5 次）')),
                        ],
                        onChanged: (value) => setState(() {
                          _exerciseBase = value ?? 'none';
                          _dirty = true;
                        }),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _dietPreference,
                        decoration: const InputDecoration(labelText: '饮食偏好'),
                        items: const [
                          DropdownMenuItem(
                              value: 'normal', child: Text('普通（荤素搭配）')),
                          DropdownMenuItem(
                              value: 'light', child: Text('清淡（少盐少油）')),
                          DropdownMenuItem(
                              value: 'vegetarian', child: Text('素食')),
                          DropdownMenuItem(
                              value: 'custom', child: Text('自定义（参考病史）')),
                        ],
                        onChanged: (value) => setState(() {
                          _dietPreference = value ?? 'normal';
                          _dirty = true;
                        }),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _saving ? null : _saveProfile,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save_outlined),
                        label: const Text('保存档案'),
                      ),
                    ],
                  ),
                );

                final quickActions = _Panel(
                  title: '快速记录',
                  subtitle: '本地录入最近指标',
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _QuickActionChip(
                        icon: Icons.favorite_outline,
                        label: '血压',
                        onTap: () => _addIndicatorDialog('bp'),
                      ),
                      _QuickActionChip(
                        icon: Icons.scale_outlined,
                        label: '体重',
                        onTap: () => _addIndicatorDialog('weight'),
                      ),
                      _QuickActionChip(
                        icon: Icons.monitor_heart_outlined,
                        label: '血糖',
                        onTap: () => _addIndicatorDialog('glucose'),
                      ),
                      _QuickActionChip(
                        icon: Icons.science_outlined,
                        label: '血脂',
                        onTap: () => _addIndicatorDialog('lipid'),
                      ),
                    ],
                  ),
                );

                final recent = _Panel(
                  title: '最近指标',
                  subtitle: '最新 6 项，点全部查看完整记录',
                  trailing: TextButton(
                    onPressed: () => context.push('/indicators'),
                    child: const Text('全部'),
                  ),
                  child: _IndicatorList(indicators: _indicators),
                );

                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child: _Panel(
                              title: '基础档案',
                              subtitle: '完善后可用于本地计划计算',
                              child: form)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: [
                            quickActions,
                            const SizedBox(height: 16),
                            recent,
                          ],
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    _Panel(title: '基础档案', subtitle: '完善后可用于计划计算', child: form),
                    const SizedBox(height: 16),
                    quickActions,
                    const SizedBox(height: 16),
                    recent,
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            _Panel(
              title: '显示与数据',
              subtitle: '简洁显示、健康摘要和模板导入',
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.accessibility_new_outlined),
                    title: const Text('长辈模式'),
                    subtitle: const Text('放大文字和按钮，首页只保留常用内容'),
                    value: appSettingsController.seniorMode,
                    onChanged: _setSeniorMode,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _notificationsEnabled == true
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                    ),
                    title: const Text('普通通知权限'),
                    subtitle: Text(
                      _notificationsEnabled == true ? '已开启' : '未开启，提醒可能无法显示',
                    ),
                    trailing: _notificationsEnabled == true
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : TextButton(
                            onPressed: _requestNotificationPermission,
                            child: const Text('去开启'),
                          ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.alarm_on_outlined),
                    title: const Text('用药准点提醒权限'),
                    subtitle: Text(
                      _exactAlarmEnabled == true
                          ? '已允许精确闹钟'
                          : '未允许，保存用药提醒时可以申请',
                    ),
                    trailing: _exactAlarmEnabled == true
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : TextButton(
                            onPressed: _requestExactAlarmPermission,
                            child: const Text('去开启'),
                          ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.picture_as_pdf_outlined),
                    title: const Text('生成健康摘要 PDF'),
                    subtitle: const Text('可选择最近 7、30 或 90 天并保存或分享'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _shareHealthPdf,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.download_outlined),
                    title: const Text('保存数据导入模板'),
                    subtitle: const Text('仅支持使用本 APP 模板填写'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _saveImportTemplate,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.upload_file_outlined),
                    title: const Text('导入健康数据'),
                    subtitle: const Text('导入前预览；同类型同测量时间自动跳过'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _importHealthData,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SyncStatusPanel(status: dataSyncStatusController),
            const SizedBox(height: 20),
            _AccountSecurityPanel(
              accountInfo: _accountInfo,
              onLogin: () => context
                  .push('/login', extra: true)
                  .then((_) => setState(() {})),
              onSetPassword: () => context.push(
                '/set-password?returnTo=%2Fprofile&required=1',
              ),
              onSignOut: _signOut,
              onCancelAccount: _cancelAccount,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后，这台设备上的健康记录会被清除。再次登录同一账号后，记录会自动恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final refreshToken = UserSession.instance.refreshToken;
    await sl<OnlineDataService>().signOut();
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await sl<AuthApi>().logout(refreshToken);
      } catch (_) {}
    }
    await UserSession.instance.clear();
    sl<ApiClient>().setAccessToken(null);
    if (mounted) context.go('/login');
  }

  Future<void> _cancelAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const CancelAccountDialog(),
    );
    if (confirmed != true) return;
    await sl<OnlineDataService>().signOut();
    await UserSession.instance.clear();
    sl<ApiClient>().setAccessToken(null);
    if (mounted) context.go('/login');
  }
}

class _ProfileNumberField extends StatelessWidget {
  const _ProfileNumberField({
    required this.controller,
    required this.label,
    required this.keyboardType,
    required this.validator,
    this.onTap,
    this.focusNode,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType keyboardType;
  final FormFieldValidator<String> validator;
  final VoidCallback? onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      readOnly: onTap != null,
      showCursor: onTap == null,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: onTap == null ? null : const Icon(Icons.unfold_more),
      ),
      validator: validator,
    );
  }
}

ImageProvider<Object>? _authenticatedAvatarProvider(AccountInfo? info) {
  if (info == null || info.avatarUrl.isEmpty) return null;
  final objectKey = Uri.tryParse(info.avatarUrl)?.queryParameters['objectKey'];
  final token = UserSession.instance.accessToken;
  if (objectKey == null || objectKey.isEmpty || token == null) return null;
  final baseUrl =
      sl<ApiClient>().dio.options.baseUrl.replaceFirst(RegExp(r'/$'), '');
  return NetworkImage(
    '$baseUrl/files/content?objectKey=${Uri.encodeQueryComponent(objectKey)}'
    '&contentType=image%2Fjpeg',
    headers: {'Authorization': 'Bearer $token'},
  );
}

class _EditableAvatar extends StatelessWidget {
  const _EditableAvatar({
    required this.radius,
    required this.image,
    required this.fallback,
    required this.uploading,
    required this.onTap,
  });

  final double radius;
  final ImageProvider<Object>? image;
  final String fallback;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: uploading ? '正在更新头像' : '更换头像',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: uploading ? null : onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: radius,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              backgroundImage: image,
              child: image == null
                  ? Text(
                      fallback,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontSize: radius * 0.76,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : null,
            ),
            if (uploading)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.42),
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              )
            else
              Positioned(
                right: -2,
                bottom: -2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 2,
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child:
                        Icon(Icons.camera_alt, size: 13, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SeniorProfileView extends StatelessWidget {
  const _SeniorProfileView({
    required this.profile,
    required this.accountInfo,
    required this.seniorMode,
    required this.notificationsEnabled,
    required this.exactAlarmEnabled,
    required this.syncStatus,
    required this.onEditProfile,
    required this.onNotificationPermission,
    required this.onExactAlarmPermission,
    required this.onToggleSeniorMode,
    required this.onReminderSettings,
    required this.onMoreSettings,
    required this.onLogin,
    required this.onSignOut,
    required this.onAvatarTap,
    required this.avatarUploading,
    required this.onRefresh,
  });

  final UserProfileData profile;
  final AccountInfo? accountInfo;
  final bool seniorMode;
  final bool? notificationsEnabled;
  final bool? exactAlarmEnabled;
  final DataSyncStatusController syncStatus;
  final Future<void> Function() onEditProfile;
  final Future<void> Function() onNotificationPermission;
  final Future<void> Function() onExactAlarmPermission;
  final Future<void> Function(bool) onToggleSeniorMode;
  final VoidCallback onReminderSettings;
  final Future<void> Function() onMoreSettings;
  final VoidCallback onLogin;
  final Future<void> Function() onSignOut;
  final VoidCallback onAvatarTap;
  final bool avatarUploading;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final loggedIn = UserSession.instance.isAccountLogin;
    final nickname = accountInfo?.nickname.trim().isNotEmpty == true
        ? accountInfo!.nickname
        : profile.nickname.trim().isNotEmpty
            ? profile.nickname
            : '健康用户';
    final phone = accountInfo?.phoneTail ?? '';
    final syncText = switch (syncStatus.phase) {
      DataSyncPhase.syncing => '正在同步健康数据',
      DataSyncPhase.conflict => '发现其他设备的修改，请确认保留内容',
      DataSyncPhase.failed => '同步失败，请重新同步',
      DataSyncPhase.synced when syncStatus.lastSyncedAt != null =>
        '已同步 · ${DateFormat('MM月dd日 HH:mm').format(syncStatus.lastSyncedAt!)}',
      _ => loggedIn ? '登录后自动同步' : '尚未登录',
    };
    final bottomPad = MediaQuery.sizeOf(context).width < 960 ? 100.0 : 20.0;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey('senior-profile-scroll'),
        padding: EdgeInsets.fromLTRB(16, 18, 16, bottomPad),
        children: [
          const Text('我的',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _EditableAvatar(
                      radius: 30,
                      image: _authenticatedAvatarProvider(accountInfo),
                      fallback: nickname.characters.first,
                      uploading: avatarUploading,
                      onTap: onAvatarTap,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nickname,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 23, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(
                            loggedIn
                                ? (phone.isEmpty ? '账号已登录' : '手机号尾号 $phone')
                                : '尚未登录账号',
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '${profile.age > 0 ? '${profile.age} 岁 · ' : ''}BMI ${profile.bmi > 0 ? profile.bmi.toStringAsFixed(1) : '--'} · ${_seniorGoalLabel(profile.goal)}',
                  style: const TextStyle(fontSize: 17),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onEditProfile,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑健康档案'),
                ),
                if (!loggedIn) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onLogin,
                    icon: const Icon(Icons.login),
                    label: const Text('登录账号'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SeniorStatusPanel(
            notificationsEnabled: notificationsEnabled,
            exactAlarmEnabled: exactAlarmEnabled,
            syncText: syncText,
            syncFailed: syncStatus.phase == DataSyncPhase.failed,
            syncConflict: syncStatus.phase == DataSyncPhase.conflict,
            onNotificationPermission: onNotificationPermission,
            onExactAlarmPermission: onExactAlarmPermission,
            onRetrySync: syncStatus.canRetry ? syncStatus.retry : null,
            onResolveConflict: syncStatus.hasConflict
                ? () => _showSyncConflictSheet(context, syncStatus)
                : null,
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              secondary: const Icon(Icons.accessibility_new_outlined),
              title: const Text('长辈模式',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              subtitle: const Text('大字、简洁、易操作'),
              value: seniorMode,
              onChanged: onToggleSeniorMode,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onReminderSettings,
            icon: const Icon(Icons.alarm_outlined),
            label: const Text('提醒设置'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onMoreSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('更多设置'),
          ),
          if (loggedIn) ...[
            const SizedBox(height: 24),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: onSignOut,
              icon: const Icon(Icons.logout_outlined),
              label: const Text('退出登录'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SeniorStatusPanel extends StatelessWidget {
  const _SeniorStatusPanel({
    required this.notificationsEnabled,
    required this.exactAlarmEnabled,
    required this.syncText,
    required this.syncFailed,
    required this.syncConflict,
    required this.onNotificationPermission,
    required this.onExactAlarmPermission,
    required this.onRetrySync,
    required this.onResolveConflict,
  });

  final bool? notificationsEnabled;
  final bool? exactAlarmEnabled;
  final String syncText;
  final bool syncFailed;
  final bool syncConflict;
  final Future<void> Function() onNotificationPermission;
  final Future<void> Function() onExactAlarmPermission;
  final Future<void> Function()? onRetrySync;
  final VoidCallback? onResolveConflict;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('提醒与数据状态',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _SeniorPermissionRow(
            icon: Icons.notifications_active_outlined,
            title: '普通提醒',
            enabled: notificationsEnabled == true,
            enabledText: '通知已开启',
            disabledText: '通知未开启，普通提醒可能无法显示',
            onEnable: onNotificationPermission,
          ),
          const Divider(height: 24),
          _SeniorPermissionRow(
            icon: Icons.alarm_on_outlined,
            title: '用药准点提醒',
            enabled: exactAlarmEnabled == true,
            enabledText: '精确闹钟已允许',
            disabledText: '尚未允许精确闹钟',
            onEnable: onExactAlarmPermission,
          ),
          const Divider(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                syncFailed || syncConflict
                    ? Icons.sync_problem
                    : Icons.cloud_done_outlined,
                color:
                    syncFailed || syncConflict ? Colors.orange : Colors.green,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('数据同步',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                      syncText,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (syncFailed && onRetrySync != null) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: onRetrySync,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重新同步'),
                      ),
                    ],
                    if (syncConflict && onResolveConflict != null) ...[
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: onResolveConflict,
                        icon: const Icon(Icons.compare_arrows),
                        label: const Text('处理同步冲突'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SeniorPermissionRow extends StatelessWidget {
  const _SeniorPermissionRow({
    required this.icon,
    required this.title,
    required this.enabled,
    required this.enabledText,
    required this.disabledText,
    required this.onEnable,
  });

  final IconData icon;
  final String title;
  final bool enabled;
  final String enabledText;
  final String disabledText;
  final Future<void> Function() onEnable;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: enabled ? Colors.green : Colors.orange),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(
                enabled ? enabledText : disabledText,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (!enabled) ...[
                const SizedBox(height: 8),
                OutlinedButton(onPressed: onEnable, child: const Text('去开启')),
              ],
            ],
          ),
        ),
        if (enabled) const Icon(Icons.check_circle, color: Colors.green),
      ],
    );
  }
}

class _SeniorSettingsTile extends StatelessWidget {
  const _SeniorSettingsTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title,
          style: TextStyle(
              color: color, fontSize: 18, fontWeight: FontWeight.w700)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

String _seniorGoalLabel(String goal) => switch (goal) {
      'fat_loss' => '减脂',
      'glucose_control' => '控糖',
      'bp_control' => '控压',
      _ => '保持健康',
    };

class _SyncStatusPanel extends StatelessWidget {
  const _SyncStatusPanel({required this.status});

  final DataSyncStatusController status;

  @override
  Widget build(BuildContext context) {
    final last = status.lastSyncedAt;
    final subtitle = switch (status.phase) {
      DataSyncPhase.syncing => '正在同步健康数据…',
      DataSyncPhase.conflict => status.errorMessage ?? '发现其他设备的修改',
      DataSyncPhase.failed => status.errorMessage ?? '同步失败，请检查网络后重试',
      DataSyncPhase.synced when last != null =>
        '上次同步 ${DateFormat('MM-dd HH:mm').format(last)}',
      _ => '登录后自动同步健康数据',
    };
    return _Panel(
      title: '数据同步',
      subtitle: subtitle,
      child: status.phase == DataSyncPhase.conflict
          ? Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _showSyncConflictSheet(context, status),
                icon: const Icon(Icons.compare_arrows),
                label: const Text('比较并确认'),
              ),
            )
          : status.phase == DataSyncPhase.failed
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: status.canRetry ? status.retry : null,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新同步'),
                  ),
                )
              : const Text('数据正常时无需手动操作。'),
    );
  }
}

Future<void> _showSyncConflictSheet(
  BuildContext context,
  DataSyncStatusController status,
) async {
  final conflict = status.conflict;
  if (conflict == null) return;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SyncConflictSheet(status: status, merge: conflict),
  );
}

class _SyncConflictSheet extends StatefulWidget {
  const _SyncConflictSheet({required this.status, required this.merge});

  final DataSyncStatusController status;
  final DataSyncMergeResult merge;

  @override
  State<_SyncConflictSheet> createState() => _SyncConflictSheetState();
}

class _SyncConflictSheetState extends State<_SyncConflictSheet> {
  final Map<String, DataSyncConflictChoice> _choices = {};
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_choices.length != widget.merge.conflicts.length) {
      setState(() => _error = '请为每项冲突选择要保留的版本');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.status.resolveConflict(_choices);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存失败，请检查网络后重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('确认跨设备修改',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                const Text('未冲突的记录和字段已自动合并。以下项目需要你选择保留本机版或云端版。'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: widget.merge.conflicts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final item = widget.merge.conflicts[index];
                final selected = _choices[item.rowKey];
                return Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_syncTableLabel(item.table),
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        RadioGroup<DataSyncConflictChoice>(
                          groupValue: selected,
                          onChanged: _saving
                              ? (_) {}
                              : (value) => setState(() {
                                    if (value != null) {
                                      _choices[item.rowKey] = value;
                                    }
                                  }),
                          child: Column(
                            children: [
                              RadioListTile<DataSyncConflictChoice>(
                                contentPadding: EdgeInsets.zero,
                                value: DataSyncConflictChoice.local,
                                title: const Text('保留本机版本'),
                                subtitle: Text(_syncRowSummary(item.local)),
                              ),
                              RadioListTile<DataSyncConflictChoice>(
                                contentPadding: EdgeInsets.zero,
                                value: DataSyncConflictChoice.remote,
                                title: const Text('保留云端版本'),
                                subtitle: Text(_syncRowSummary(item.remote)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 8),
                ],
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '正在保存…' : '确认并继续同步'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _syncTableLabel(String table) => switch (table) {
      'health_indicator' => '健康指标',
      'meal_record' => '饮食记录',
      'plan' => '健康计划',
      'clock_record' => '打卡记录',
      'reminder' => '提醒',
      'user_profile' => '健康档案',
      _ => '健康数据',
    };

String _syncRowSummary(Map<String, Object?>? row) {
  if (row == null) return '此版本已删除该记录';
  const hidden = {'id', 'client_id', 'version', 'sync_at'};
  final values = row.entries
      .where((entry) => !hidden.contains(entry.key) && entry.value != null)
      .take(4)
      .map((entry) => '${entry.key}：${entry.value}')
      .join(' · ');
  return values.isEmpty ? '保留此版本的记录' : values;
}

class _AccountSecurityPanel extends StatelessWidget {
  const _AccountSecurityPanel(
      {required this.accountInfo,
      required this.onLogin,
      required this.onSetPassword,
      required this.onSignOut,
      required this.onCancelAccount});
  final AccountInfo? accountInfo;
  final VoidCallback onLogin;
  final VoidCallback onSetPassword;
  final VoidCallback onSignOut;
  final VoidCallback onCancelAccount;

  @override
  Widget build(BuildContext context) {
    final loggedIn = UserSession.instance.isAccountLogin;
    return _Panel(
      title: '账号与数据安全',
      subtitle: loggedIn ? '健康数据已与当前账号绑定' : '登录后加载账号中的健康数据',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!loggedIn)
          FilledButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login_outlined),
              label: const Text('注册 / 登录账号'))
        else ...[
          if (accountInfo != null) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(accountInfo!.nickname.isEmpty
                  ? '健康用户'
                  : accountInfo!.nickname),
              subtitle: Text(
                '手机号 *******${accountInfo!.phoneTail}\n账号 ID ${accountInfo!.userId}',
              ),
              trailing: IconButton(
                tooltip: '复制账号 ID',
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: accountInfo!.userId),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('账号 ID 已复制')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_outlined),
              ),
            ),
            if (!accountInfo!.hasPassword) ...[
              OutlinedButton.icon(
                onPressed: onSetPassword,
                icon: const Icon(Icons.password_outlined),
                label: const Text('设置登录密码（可选）'),
              ),
              const SizedBox(height: 8),
            ],
          ],
          TextButton.icon(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout_outlined),
              label: const Text('退出登录')),
          TextButton.icon(
              onPressed: onCancelAccount,
              icon: const Icon(Icons.person_remove_outlined),
              label: const Text('注销账号'),
              style:
                  TextButton.styleFrom(foregroundColor: Colors.red.shade700)),
        ],
      ]),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.profile,
    required this.indicators,
    required this.accountInfo,
    required this.onAvatarTap,
    required this.avatarUploading,
  });

  final UserProfileData profile;
  final List<HealthIndicatorEntry> indicators;
  final AccountInfo? accountInfo;
  final VoidCallback onAvatarTap;
  final bool avatarUploading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name =
        profile.nickname.trim().isEmpty ? '健康用户' : profile.nickname.trim();
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 38),
          decoration: BoxDecoration(
            gradient: AppTheme.accentSoftGradient(context),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            children: [
              _EditableAvatar(
                radius: 27,
                image: _authenticatedAvatarProvider(accountInfo),
                fallback: name.characters.first,
                uploading: avatarUploading,
                onTap: onAvatarTap,
              ),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      UserSession.instance.isAccountLogin
                          ? '已登录账号 · 健康数据自动同步'
                          : '本地健康档案 · 登录后可云端同步',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ])),
            ],
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Row(children: [
              _ProfileStat(
                  label: '年龄',
                  value: profile.age == 0 ? '--' : '${profile.age} 岁'),
              _ProfileStat(
                  label: 'BMI',
                  value:
                      profile.bmi == 0 ? '--' : profile.bmi.toStringAsFixed(1)),
              _ProfileStat(label: '健康记录', value: '${indicators.length} 条'),
            ]),
          ),
        ),
      ],
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Expanded(
          child: Column(children: [
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))
      ]));
}

// ignore: unused_element
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.profile,
    required this.indicators,
  });

  final UserProfileData profile;
  final List<HealthIndicatorEntry> indicators;

  @override
  Widget build(BuildContext context) {
    HealthIndicatorEntry? latestByType(String type) {
      for (final item in indicators) {
        if (item.type == type) return item;
      }
      return null;
    }

    final latestWeight = latestByType('weight');
    final latestBp = latestByType('bp');

    final goalLabel = switch (profile.goal) {
      'fat_loss' => '减脂',
      'glucose_control' => '控糖',
      'bp_control' => '控压',
      _ => '保持健康',
    };
    final exerciseLabel = switch (profile.exerciseBase) {
      'light' => '轻度',
      'moderate' => '中等',
      _ => '无',
    };
    final dietLabel = switch (profile.dietPreference) {
      'light' => '清淡',
      'vegetarian' => '素食',
      'custom' => '自定义',
      _ => '普通',
    };

    return _Panel(
      title: '档案概览',
      subtitle: '账号档案与最近记录',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900 ? 4 : 2;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: columns >= 4 ? 1.65 : 1.28,
                children: [
                  _SmallMetric(
                      title: '年龄',
                      value: profile.age == 0 ? '--' : '${profile.age} 岁'),
                  _SmallMetric(
                      title: 'BMI',
                      value: profile.bmi == 0
                          ? '--'
                          : profile.bmi.toStringAsFixed(1)),
                  _SmallMetric(
                      title: '最新体重', value: latestWeight?.displayValue ?? '--'),
                  _SmallMetric(
                      title: '最新血压', value: latestBp?.displayValue ?? '--'),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SettingTag(
                      icon: Icons.flag_outlined, label: '目标', value: goalLabel),
                  _SettingTag(
                      icon: Icons.directions_run_outlined,
                      label: '运动',
                      value: exerciseLabel),
                  _SettingTag(
                      icon: Icons.restaurant_outlined,
                      label: '饮食',
                      value: dietLabel),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SmallMetric extends StatelessWidget {
  const _SmallMetric({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _SettingTag extends StatelessWidget {
  const _SettingTag(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 5),
          Text(
            '$label  ',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ])),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _IndicatorList extends StatelessWidget {
  const _IndicatorList({required this.indicators});

  final List<HealthIndicatorEntry> indicators;

  @override
  Widget build(BuildContext context) {
    if (indicators.isEmpty) {
      return Text(
        '暂无记录',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      children: [
        for (final item in indicators.take(6))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _iconFor(item.type),
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.label,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          item.displayValue,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    DateFormat('MM/dd HH:mm').format(item.measuredTime),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

IconData _iconFor(String type) {
  return switch (type) {
    'bp' => Icons.favorite_outline,
    'weight' => Icons.scale_outlined,
    'glucose' => Icons.water_drop_outlined,
    'lipid' => Icons.science_outlined,
    'heart_rate' => Icons.monitor_heart_outlined,
    'body_fat' => Icons.person_outlined,
    'waist' => Icons.straighten_outlined,
    'spo2' => Icons.air_outlined,
    'sleep' => Icons.bedtime_outlined,
    'steps' => Icons.directions_walk_outlined,
    _ => Icons.fiber_manual_record_outlined,
  };
}

// ── 账号操作区 ───────────────────────────────────────────────────

// ignore: unused_element
class _AccountSignOutSection extends StatelessWidget {
  const _AccountSignOutSection({required this.onSignOut});
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              Icons.account_circle_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            const Text('账号',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          Text(
            '退出当前账号后可登录其他账号；本地健康数据会保留',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout),
              label: const Text('退出登录',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 危险操作区 ───────────────────────────────────────────────────

class _IndicatorDialog extends StatefulWidget {
  const _IndicatorDialog({required this.type});

  final String type;

  @override
  State<_IndicatorDialog> createState() => _IndicatorDialogState();
}

class _IndicatorDialogState extends State<_IndicatorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _systolic = TextEditingController();
  final _diastolic = TextEditingController();
  final _weight = TextEditingController();
  final _glucose = TextEditingController();
  final _tc = TextEditingController();
  final _ldl = TextEditingController();
  DateTime _measuredAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.type == 'bp') {
      _systolic.text = '130';
      _diastolic.text = '82';
    } else if (widget.type == 'weight') {
      _weight.text = '74.0';
    } else if (widget.type == 'glucose') {
      _glucose.text = '5.8';
    } else if (widget.type == 'lipid') {
      _tc.text = '5.4';
      _ldl.text = '3.3';
    }
  }

  @override
  void dispose() {
    _systolic.dispose();
    _diastolic.dispose();
    _weight.dispose();
    _glucose.dispose();
    _tc.dispose();
    _ldl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('录入$_title'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.type == 'bp') ...[
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _systolic,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '收缩压'),
                        validator: (value) => _validateRange(
                          value,
                          HealthRanges.minSystolic,
                          HealthRanges.maxSystolic,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _diastolic,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '舒张压'),
                        validator: (value) {
                          final rangeError = _validateRange(
                            value,
                            HealthRanges.minDiastolic,
                            HealthRanges.maxDiastolic,
                          );
                          if (rangeError != null) return rangeError;
                          final systolic = int.tryParse(_systolic.text.trim());
                          final diastolic = int.tryParse(value?.trim() ?? '');
                          if (systolic != null &&
                              diastolic != null &&
                              systolic <= diastolic) {
                            return '舒张压需低于收缩压';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ] else if (widget.type == 'weight') ...[
                TextFormField(
                  controller: _weight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '体重（kg）'),
                  validator: (value) => _validateRange(
                    value,
                    HealthRanges.minWeightKg,
                    HealthRanges.maxWeightKg,
                  ),
                ),
              ] else if (widget.type == 'glucose') ...[
                TextFormField(
                  controller: _glucose,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '血糖（mmol/L）'),
                  validator: (value) => _validateRange(
                    value,
                    HealthRanges.minGlucoseMmol,
                    HealthRanges.maxGlucoseMmol,
                  ),
                ),
              ] else if (widget.type == 'lipid') ...[
                TextFormField(
                  controller: _tc,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '总胆固醇（mmol/L）'),
                  validator: (value) => _validateRange(
                    value,
                    HealthRanges.minTcMmol,
                    HealthRanges.maxTcMmol,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ldl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'LDL-C（mmol/L）'),
                  validator: (value) => _validateRange(
                    value,
                    HealthRanges.minLdlMmol,
                    HealthRanges.maxLdlMmol,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('测量时间'),
                subtitle:
                    Text(DateFormat('yyyy-MM-dd HH:mm').format(_measuredAt)),
                trailing: TextButton(
                  onPressed: _pickTime,
                  child: const Text('选择'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }

  String get _title {
    return switch (widget.type) {
      'bp' => '血压',
      'weight' => '体重',
      'glucose' => '血糖',
      'lipid' => '血脂',
      _ => '指标',
    };
  }

  String? _validateRange(String? text, double min, double max) {
    final value = double.tryParse(text?.trim() ?? '');
    if (value == null) return '请输入数字';
    if (value < min || value > max) return '请输入 $min–$max';
    return null;
  }

  Future<void> _pickTime() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDate: _measuredAt,
    );
    if (picked == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_measuredAt));
    if (time == null) return;
    setState(() {
      _measuredAt = DateTime(
          picked.year, picked.month, picked.day, time.hour, time.minute);
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final payload = switch (widget.type) {
      'bp' => {
          'systolic': int.parse(_systolic.text.trim()),
          'diastolic': int.parse(_diastolic.text.trim()),
        },
      'weight' => {'weightKg': double.parse(_weight.text.trim())},
      'glucose' => {'glucoseMmol': double.parse(_glucose.text.trim())},
      'lipid' => {
          'tc': double.parse(_tc.text.trim()),
          'ldl': double.parse(_ldl.text.trim()),
        },
      _ => <String, dynamic>{},
    };
    Navigator.pop(
      context,
      _IndicatorDraft(
        payload: payload,
        source: 'manual',
        measuredAt: _measuredAt,
      ),
    );
  }
}

class _IndicatorDraft {
  const _IndicatorDraft({
    required this.payload,
    required this.source,
    required this.measuredAt,
  });

  final Map<String, dynamic> payload;
  final String source;
  final DateTime measuredAt;
}
