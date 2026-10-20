import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/di/service_locator.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/auth/user_session.dart';
import '../../core/network/profile_api.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, this.returnTo = '/home'});
  final String returnTo;
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int step = 0;
  String goal = 'maintain';
  String gender = 'unknown';
  bool saving = false;
  final diet = <String>{}, allergies = <String>{}, conditions = <String>{};
  final height = TextEditingController(),
      weight = TextEditingController(),
      birthYear = TextEditingController(text: '${DateTime.now().year - 30}');
  @override
  void dispose() {
    height.dispose();
    weight.dispose();
    birthYear.dispose();
    super.dispose();
  }

  Future<void> skip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_skipped', true);
    if (mounted) context.go(widget.returnTo);
  }

  Future<void> next() async {
    if (step < 2) {
      setState(() => step++);
      return;
    }
    final y = int.tryParse(birthYear.text),
        h = double.tryParse(height.text),
        w = double.tryParse(weight.text);
    if (y == null || h == null || w == null || gender == 'unknown') {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请完善身体数据')));
      return;
    }
    setState(() => saving = true);
    try {
      await sl<ProfileApi>().saveOnboardingProfile(
          goal: goal,
          gender: gender,
          birthYear: y,
          heightCm: h,
          weightKg: w,
          dietPreferences: diet.toList(),
          allergies: allergies.toList(),
          conditions: conditions.toList(),
          reminders: const {'weight': true, 'meal': true});
      final now = DateTime.now().millisecondsSinceEpoch;
      await sl<HealthRepository>().saveProfile(UserProfileData(
            nickname: UserSession.instance.name,
            gender: gender,
            birthYear: y,
            heightCm: h,
            weightKg: w,
            medicalHistory: conditions.join('、'),
            medications: '',
            createdAt: now,
            updatedAt: now,
            goal: goal,
            dietPreference: diet.isEmpty ? 'normal' : diet.first,
          ));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_completed', true);
      if (mounted) context.go(widget.returnTo);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('资料保存失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final titles = ['你的健康目标', '身体数据', '饮食与健康情况'];
    return Scaffold(
        appBar: AppBar(
            leading: BackButton(
                onPressed: step == 0 ? skip : () => setState(() => step--)),
            actions: [TextButton(onPressed: skip, child: const Text('跳过'))]),
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          LinearProgressIndicator(value: (step + 1) / 3),
          const SizedBox(height: 28),
          Text(titles[step],
              style: Theme.of(c)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          content(),
          const SizedBox(height: 28),
          FilledButton(
              onPressed: saving ? null : next,
              child: Text(step == 2 ? '完成' : '下一步'))
        ])));
  }

  Widget content() => switch (step) {
        0 => choices({
            'maintain': '保持健康',
            'fat_loss': '减重塑形',
            'glucose_control': '控糖管理',
            'improve_sleep': '改善睡眠'
          }, (v) => setState(() => goal = v), goal),
        1 => Column(children: [
            DropdownButtonFormField(
                value: gender == 'unknown' ? null : gender,
                items: const [
                  DropdownMenuItem(value: 'female', child: Text('女性')),
                  DropdownMenuItem(value: 'male', child: Text('男性'))
                ],
                onChanged: (v) => setState(() => gender = v ?? 'unknown'),
                decoration: const InputDecoration(labelText: '性别')),
            TextField(
                controller: birthYear,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '出生年份')),
            TextField(
                controller: height,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '身高（厘米）')),
            TextField(
                controller: weight,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '体重（千克）'))
          ]),
        _ => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('饮食偏好'),
            multi(['均衡饮食', '多蔬菜', '多蛋白', '素食'], diet),
            const SizedBox(height: 18),
            const Text('过敏或忌口'),
            multi(['乳制品', '海鲜', '坚果', '无'], allergies),
            const SizedBox(height: 18),
            const Text('特殊情况'),
            multi(['血糖高', '血压高', '肠道敏感', '无'], conditions)
          ])
      };
  Widget choices(
          Map<String, String> v, ValueChanged<String> on, String selected) =>
      Column(children: [
        for (final e in v.entries)
          RadioListTile(
              value: e.key,
              groupValue: selected,
              onChanged: (x) => on(x!),
              title: Text(e.value))
      ]);
  Widget multi(List<String> v, Set<String> s) => Wrap(spacing: 8, children: [
        for (final x in v)
          FilterChip(
              label: Text(x),
              selected: s.contains(x),
              onSelected: (on) => setState(() => on ? s.add(x) : s.remove(x)))
      ]);
}
