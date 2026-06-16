import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/auth/user_session.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/auth_api.dart';
import '../../core/sync/sync_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

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

  String _gender = 'female';
  String _goal = 'maintain';
  String _exerciseBase = 'none';
  String _dietPreference = 'normal';
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false; // 用户已手动修改表单但尚未保存
  UserProfileData? _profile;
  List<HealthIndicatorEntry> _indicators = const [];

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepoChanged);
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
    _nicknameController.dispose();
    _birthYearController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _medicalHistoryController.dispose();
    _medicationsController.dispose();
    super.dispose();
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
    final profile = await _repo.loadProfile();
    final indicators = await _repo.loadIndicators(limit: 10);
    if (!mounted) return;
    _profile = profile;
    _indicators = indicators;
    if (syncForm) _syncControllers(profile);
    setState(() => _loading = false);
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

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
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
      final syncMessage = await _syncProfileIfEnabled();
      if (!mounted) return;
      _dirty = false; // 保存成功后清除脏标记，允许后续 repo 变更同步表单
      messenger.showSnackBar(
        SnackBar(content: Text(syncMessage ?? '健康档案已保存到本地')),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _syncProfileIfEnabled() async {
    final sync = sl<SyncService>();
    if (!await sync.isSyncEnabled()) return null;
    final result = await sync.sync();
    if (result.hasError) {
      return '健康档案已保存到本地，云同步失败：${result.error}';
    }
    return '健康档案已保存并同步到云端';
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
      messenger.showSnackBar(const SnackBar(content: Text('已保存健康指标')));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final profile = _profile ?? UserProfileData.empty();
    final bottomPadding = MediaQuery.sizeOf(context).width < 960 ? 100.0 : 20.0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding),
        children: [
          _OverviewCard(profile: profile, indicators: _indicators),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 960;
              final form = Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _nicknameController,
                      decoration: const InputDecoration(labelText: '昵称'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? '请输入昵称'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _gender,
                      decoration: const InputDecoration(labelText: '性别'),
                      items: const [
                        DropdownMenuItem(value: 'female', child: Text('女')),
                        DropdownMenuItem(value: 'male', child: Text('男')),
                        DropdownMenuItem(value: 'unknown', child: Text('未填写')),
                      ],
                      onChanged: (value) =>
                          setState(() => _gender = value ?? 'unknown'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _birthYearController,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: '出生年份'),
                            validator: (value) {
                              final year = int.tryParse(value?.trim() ?? '');
                              if (year == null ||
                                  year < 1900 ||
                                  year > DateTime.now().year) {
                                return '请输入正确年份';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _heightController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                const InputDecoration(labelText: '身高（cm）'),
                            validator: (value) {
                              final height =
                                  double.tryParse(value?.trim() ?? '');
                              if (height == null || height <= 0) return '请输入身高';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _weightController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: '体重（kg）'),
                      validator: (value) {
                        final weight = double.tryParse(value?.trim() ?? '');
                        if (weight == null || weight <= 0) return '请输入体重';
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
                        DropdownMenuItem(value: 'fat_loss', child: Text('减脂')),
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
                        DropdownMenuItem(value: 'none', child: Text('无（久坐为主）')),
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
                  _Panel(title: '基础档案', subtitle: '完善后可用于本地计划计算', child: form),
                  const SizedBox(height: 16),
                  quickActions,
                  const SizedBox(height: 16),
                  recent,
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          _DangerZone(onClearAll: _clearAllData),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空全部数据'),
        content: const Text(
          '此操作将删除本地所有健康档案、指标记录、计划和打卡数据，且不可恢复。\n\n确认要继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _repo.clearAllData();
    await sl<SyncService>().resetLastSyncMs();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('本地健康数据已清空，账号登录状态已保留；下次同步会重新拉取云端数据')),
    );
    setState(() {});
  }
}

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
      subtitle: '本地资料与最近记录',
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
        color: AppTheme.pageBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
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
        color: AppTheme.pageBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.deepBlue),
          const SizedBox(width: 5),
          Text('$label  ',
              style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
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
          color: AppTheme.pageBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppTheme.deepBlue),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
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
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style:
                          const TextStyle(color: AppTheme.muted, fontSize: 12)),
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
      return const Text(
        '暂无记录',
        style: TextStyle(color: AppTheme.muted),
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
                color: AppTheme.pageBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_iconFor(item.type),
                        color: AppTheme.deepBlue, size: 20),
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
                        Text(item.displayValue,
                            style: const TextStyle(color: AppTheme.muted)),
                      ],
                    ),
                  ),
                  Text(
                    DateFormat('MM/dd').format(item.measuredTime),
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.account_circle_outlined,
                size: 18, color: AppTheme.muted),
            SizedBox(width: 8),
            Text('账号',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          const Text('退出当前账号后可登录其他账号；本地健康数据会保留',
              style: TextStyle(color: AppTheme.muted, fontSize: 12)),
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

class _DangerZone extends StatelessWidget {
  const _DangerZone({required this.onClearAll});
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.warning_amber_outlined,
                size: 18, color: Colors.red.shade400),
            const SizedBox(width: 8),
            Text('危险操作',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.red.shade400)),
          ]),
          const SizedBox(height: 4),
          const Text('以下操作不可撤销，请谨慎使用',
              style: TextStyle(color: AppTheme.muted, fontSize: 12)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onClearAll,
              icon:
                  const Icon(Icons.delete_forever_outlined, color: Colors.red),
              label: const Text('清空全部本地数据',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
                        validator: (value) {
                          if (int.tryParse(value ?? '') == null) return '请输入数字';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _diastolic,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '舒张压'),
                        validator: (value) {
                          if (int.tryParse(value ?? '') == null) return '请输入数字';
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
                  validator: (value) {
                    if (double.tryParse(value ?? '') == null) return '请输入数字';
                    return null;
                  },
                ),
              ] else if (widget.type == 'glucose') ...[
                TextFormField(
                  controller: _glucose,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '血糖（mmol/L）'),
                  validator: (value) {
                    if (double.tryParse(value ?? '') == null) return '请输入数字';
                    return null;
                  },
                ),
              ] else if (widget.type == 'lipid') ...[
                TextFormField(
                  controller: _tc,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '总胆固醇（mmol/L）'),
                  validator: (value) {
                    if (double.tryParse(value ?? '') == null) return '请输入数字';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ldl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'LDL-C（mmol/L）'),
                  validator: (value) {
                    if (double.tryParse(value ?? '') == null) return '请输入数字';
                    return null;
                  },
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
