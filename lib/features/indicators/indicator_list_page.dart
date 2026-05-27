import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';

class IndicatorListPage extends StatefulWidget {
  const IndicatorListPage({super.key});

  @override
  State<IndicatorListPage> createState() => _IndicatorListPageState();
}

class _IndicatorListPageState extends State<IndicatorListPage> {
  final HealthRepository _repo = sl<HealthRepository>();
  List<HealthIndicatorEntry> _items = const [];
  String _filter = 'all';
  bool _loading = true;

  static const _types = [
    ('all', '全部'),
    ('weight', '体重'),
    ('bp', '血压'),
    ('glucose', '血糖'),
    ('heart_rate', '心率'),
    ('lipid', '血脂'),
  ];

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    _repo.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _loading = true);
    final items = await _repo.loadIndicators(
      limit: 100,
      type: _filter == 'all' ? null : _filter,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _delete(HealthIndicatorEntry item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除记录'),
        content: Text('确定删除 ${item.label} 记录（${DateFormat('MM月dd日 HH:mm').format(item.measuredTime)}）？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || item.id == null) return;
    await _repo.deleteIndicator(item.id!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除')));
  }

  Future<void> _edit(HealthIndicatorEntry item) async {
    if (item.id == null) return;
    final result = await context.push<bool>('/indicators/edit/${item.id}', extra: item);
    if (result == true) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('健康指标记录'),
        actions: [
          IconButton(
            tooltip: '录入新指标',
            icon: const Icon(Icons.add),
            onPressed: () async {
              await context.push('/indicators/input');
              _load(silent: true);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _IndicatorCard(
                            item: _items[i],
                            onDelete: () => _delete(_items[i]),
                            onEdit: () => _edit(_items[i]),
                          ),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/indicators/input');
          _load(silent: true);
        },
        icon: const Icon(Icons.add),
        label: const Text('录入指标'),
        backgroundColor: AppTheme.deepBlue,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 52,
      color: Colors.white,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (final t in _types)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: _filter == t.$1,
                label: Text(t.$2),
                onSelected: (_) {
                  setState(() => _filter = t.$1);
                  _load();
                },
                labelStyle: TextStyle(
                  color: _filter == t.$1 ? Colors.white : AppTheme.deepBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                backgroundColor: Colors.white,
                selectedColor: AppTheme.deepBlue,
                side: const BorderSide(color: AppTheme.cardBorder),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.monitor_heart_outlined, size: 48, color: AppTheme.muted.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text('暂无${_filter == "all" ? "" : _typeName(_filter)}记录',
              style: const TextStyle(color: AppTheme.muted, fontSize: 15)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () async {
              await context.push('/indicators/input');
              _load(silent: true);
            },
            icon: const Icon(Icons.add),
            label: const Text('录入指标'),
          ),
        ],
      ),
    );
  }

  String _typeName(String type) {
    return switch (type) {
      'weight' => '体重',
      'bp' => '血压',
      'glucose' => '血糖',
      'heart_rate' => '心率',
      'lipid' => '血脂',
      _ => '',
    };
  }
}

class _IndicatorCard extends StatelessWidget {
  const _IndicatorCard({
    required this.item,
    required this.onDelete,
    required this.onEdit,
  });

  final HealthIndicatorEntry item;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _typeColor(item.type).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_typeIcon(item.type), color: _typeColor(item.type), size: 22),
        ),
        title: Text(
          item.displayValue,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        subtitle: Text(
          '${item.label} · ${DateFormat('yyyy年MM月dd日 HH:mm').format(item.measuredTime)}',
          style: const TextStyle(color: AppTheme.muted, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '编辑',
              icon: const Icon(Icons.edit_outlined, size: 20, color: AppTheme.muted),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  IconData _typeIcon(String type) {
    return switch (type) {
      'weight' => Icons.scale_outlined,
      'bp' => Icons.favorite_outline,
      'glucose' => Icons.water_drop_outlined,
      'heart_rate' => Icons.monitor_heart_outlined,
      'lipid' => Icons.science_outlined,
      _ => Icons.fiber_manual_record_outlined,
    };
  }

  Color _typeColor(String type) {
    return switch (type) {
      'weight' => AppTheme.deepBlue,
      'bp' => Colors.redAccent,
      'glucose' => Colors.orange,
      'heart_rate' => Colors.pink,
      'lipid' => Colors.teal,
      _ => AppTheme.deepBlue,
    };
  }
}
