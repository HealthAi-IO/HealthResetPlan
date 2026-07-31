import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/content/content_models.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/content_api.dart';

class ContentListPage extends StatefulWidget {
  const ContentListPage({super.key});

  @override
  State<ContentListPage> createState() => _ContentListPageState();
}

class _ContentListPageState extends State<ContentListPage> {
  final ContentApi _api = sl<ContentApi>();
  final ScrollController _scrollController = ScrollController();
  final List<ContentSummary> _items = [];
  String _type = '';
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _refresh();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 500) {
      _loadMore();
    }
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await _api.listContent(
        page: 1,
        size: 12,
        type: _type.isEmpty ? null : _type,
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.items);
        _page = 1;
        _total = result.total;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '资讯加载失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final result = await _api.listContent(
        page: next,
        size: 12,
        type: _type.isEmpty ? null : _type,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _page = next;
        _total = result.total;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _selectType(String value) {
    if (_type == value) return;
    setState(() => _type = value);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pageBg,
      appBar: AppBar(
        title: const Text('健康资讯'),
        actions: [
          IconButton(
            tooltip: '消息中心',
            onPressed: () => context.push('/messages'),
            icon: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(selected: _type, onSelected: _selectType),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return _ErrorView(message: _error!, onRetry: _refresh);
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: const [
            SizedBox(height: 180),
            Icon(Icons.auto_stories_outlined, size: 52, color: AppTheme.muted),
            SizedBox(height: 14),
            Center(child: Text('暂无已发布资讯')),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          >= 1500 => 4,
          >= 1050 => 3,
          >= 680 => 2,
          _ => 1,
        };
        return RefreshIndicator(
          onRefresh: _refresh,
          child: MasonryGridView.count(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
              constraints.maxWidth >= 1050 ? 28 : 16,
              14,
              constraints.maxWidth >= 1050 ? 28 : 16,
              32,
            ),
            crossAxisCount: columns,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            itemCount: _items.length + (_loadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _items.length) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return _ContentCard(
                item: _items[index],
                coverUrl: _api.assetUrl(_items[index].coverUrl),
                onTap: () => context.push('/content/${_items[index].id}').then(
                      (_) => _refresh(),
                    ),
              );
            },
          ),
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            _chip('全部', ''),
            const SizedBox(width: 8),
            _chip('科普卡片', 'card'),
            const SizedBox(width: 8),
            _chip('图文资讯', 'article'),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    return ChoiceChip(
      label: Text(label),
      selected: selected == value,
      onSelected: (_) => onSelected(value),
    );
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({
    required this.item,
    required this.coverUrl,
    required this.onTap,
  });

  final ContentSummary item;
  final String coverUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        item.type == 'card' ? const Color(0xff0ea5a8) : const Color(0xff2563eb);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (coverUrl.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _CoverPlaceholder(color: color),
                ),
              )
            else
              SizedBox(
                height: 130,
                width: double.infinity,
                child: _CoverPlaceholder(color: color),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          item.type == 'card' ? '科普卡片' : '图文资讯',
                          style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Spacer(),
                      if (!item.read)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xffef4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Text(
                    item.title,
                    style: const TextStyle(
                      color: AppTheme.ink,
                      fontSize: 18,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (item.summary.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Text(
                      item.summary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: AppTheme.muted, height: 1.55),
                    ),
                  ],
                  const SizedBox(height: 13),
                  Text(
                    item.publishedAt == null
                        ? ''
                        : DateFormat('yyyy年MM月dd日').format(item.publishedAt!),
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.82),
            color.withValues(alpha: 0.45)
          ],
        ),
      ),
      child: const Center(
        child: Icon(Icons.spa_outlined, color: Colors.white, size: 48),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48, color: AppTheme.muted),
          const SizedBox(height: 12),
          Text(message),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
