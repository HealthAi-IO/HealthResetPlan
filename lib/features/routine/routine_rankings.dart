import 'package:flutter/material.dart';
import '../../core/auth/user_session.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import 'routine_service.dart';

class RoutineRankings extends StatefulWidget {
  const RoutineRankings({super.key});
  @override
  State<RoutineRankings> createState() => _RoutineRankingsState();
}

class _RoutineRankingsState extends State<RoutineRankings> {
  final service = RoutineService(sl<ApiClient>());
  final account = UserSession.instance.userId;
  String type = 'wake';
  int days = 7;
  int sequence = 0;
  bool loading = true;
  bool failed = false;
  Map<String, dynamic>? data;
  bool get active =>
      mounted &&
      UserSession.instance.isAccountLogin &&
      account == UserSession.instance.userId;

  @override
  void initState() {
    super.initState();
    UserSession.instance.addListener(sessionChanged);
    load();
  }

  void sessionChanged() {
    if (!active && mounted) {
      setState(() {
        data = null;
        sequence++;
      });
    }
  }

  @override
  void dispose() {
    UserSession.instance.removeListener(sessionChanged);
    super.dispose();
  }

  Future<void> load() async {
    if (!active) return;
    final request = ++sequence;
    setState(() {
      loading = true;
      failed = false;
      data = null;
    });
    try {
      final result = await service.rankings(type, days);
      if (active && request == sequence) setState(() => data = result);
    } catch (_) {
      if (active && request == sequence) setState(() => failed = true);
    } finally {
      if (active && request == sequence) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = List<Map>.from(data?['entries'] ?? []);
    final me = data?['myEntry'] as Map?;
    return Scaffold(
      appBar: AppBar(title: const Text('作息排行榜')),
      body: !active
          ? const Center(child: Text('请登录后查看作息排行榜'))
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: 'wake',
                            label: Text('早起榜'),
                            icon: Icon(Icons.wb_sunny_outlined)),
                        ButtonSegment(
                            value: 'bed',
                            label: Text('早睡榜'),
                            icon: Icon(Icons.bedtime_outlined)),
                      ],
                      selected: {
                        type
                      },
                      onSelectionChanged: (value) {
                        type = value.first;
                        load();
                      }),
                  const SizedBox(height: 12),
                  SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 7, label: Text('近 7 天')),
                        ButtonSegment(value: 30, label: Text('近 30 天')),
                      ],
                      selected: {
                        days
                      },
                      onSelectionChanged: (value) {
                        days = value.first;
                        load();
                      }),
                  const SizedBox(height: 20),
                  Text('按有效实时打卡的平均时间排名，${days == 7 ? 5 : 20} 天起上榜；平均时间相同则并列。'),
                  const SizedBox(height: 8),
                  Text(type == 'bed'
                      ? '北京时间中午 12 点至次日中午算同一晚，23:00 早于次日 01:00。仅统计已结束的完整周期。'
                      : '按北京时间统计，截至昨日的完整周期。'),
                  const SizedBox(height: 8),
                  const Text(
                      '补录、修改、删除的记录不参与。仅展示匿名编号、名次和有效天数，不公开个人时间。规律、充足的休息更重要。'),
                  const SizedBox(height: 20),
                  if (loading) const Center(child: CircularProgressIndicator()),
                  if (failed) ...[
                    const Text('排行榜暂时无法加载，请重试。'),
                    TextButton(onPressed: load, child: const Text('重新加载')),
                  ],
                  if (data != null) ...[
                    Text(
                        '${data!['from']} 至 ${data!['to']} · ${data!['participantCount']} 人上榜'),
                    const SizedBox(height: 12),
                    Text(
                        me == null
                            ? '我已完成 ${data!['myValidDays']} 天有效打卡，满 ${data!['minimumDays']} 天即可上榜'
                            : '我的排名：第 ${me['rank']} 名 · ${me['validDays']} 天有效打卡',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    if (entries.isEmpty)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('这个周期还没有符合条件的用户。坚持规律打卡，下次再来看看。')),
                    for (final entry in entries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: SizedBox(
                            width: 40,
                            child: Text('${entry['rank']}',
                                style: Theme.of(context).textTheme.titleLarge)),
                        title: Text(entry['isMe'] == true
                            ? '${entry['label']}（我）'
                            : '${entry['label']}'),
                        subtitle: Text('${entry['validDays']} 天有效打卡'),
                      ),
                    if (entries.isNotEmpty)
                      const Text('展示前 50 位，个人名次不受展示数量限制。'),
                  ],
                ],
              )),
    );
  }
}
