import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/content/content_models.dart';
import '../../core/content/site_message_service.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/content_api.dart';

class MessageCenterPage extends StatefulWidget {
  const MessageCenterPage({super.key});

  @override
  State<MessageCenterPage> createState() => _MessageCenterPageState();
}

class _MessageCenterPageState extends State<MessageCenterPage> {
  final ContentApi _api = sl<ContentApi>();
  final SiteMessageService _service = sl<SiteMessageService>();
  final List<SiteMessage> _items = [];
  final ScrollController _controller = ScrollController();
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _refresh();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_controller.position.extentAfter < 400) _loadMore();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final result = await _api.listMessages();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.items);
        _page = 1;
        _total = result.total;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _api.listMessages(page: _page + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _page++;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _markAll() async {
    await _service.markAllRead();
    await _refresh();
  }

  Future<void> _open(SiteMessage message) async {
    if (!message.read) await _service.markRead(message.id);
    if (!mounted) return;
    if (message.contentId == null || message.contentStatus != 'published') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该资讯已下架或不存在')),
      );
      await _refresh();
      return;
    }
    await context.push('/content/${message.contentId}');
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('消息中心'),
        actions: [
          TextButton(
            onPressed: _service.unreadCount > 0 ? _markAll : null,
            child: const Text('全部已读'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: _items.isEmpty
                  ? ListView(
                      children:  [
                        SizedBox(height: 190),
                        Icon(Icons.notifications_none,
                            size: 52, color: AppTheme.muted),
                        SizedBox(height: 14),
                        Center(child: Text('暂无站内消息')),
                      ],
                    )
                  : ListView.separated(
                      controller: _controller,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
                      itemCount: _items.length + (_loadingMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        if (index >= _items.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(18),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        final message = _items[index];
                        return ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 850),
                          child: Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              onTap: () => _open(message),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 10),
                              leading: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  const CircleAvatar(
                                    backgroundColor: Color(0xffecfeff),
                                    child: Icon(Icons.auto_stories_outlined,
                                        color: Color(0xff0e7490)),
                                  ),
                                  if (!message.read)
                                    const Positioned(
                                      right: -2,
                                      top: -2,
                                      child: CircleAvatar(
                                        radius: 5,
                                        backgroundColor: Color(0xffef4444),
                                      ),
                                    ),
                                ],
                              ),
                              title: Text(
                                message.title,
                                style: TextStyle(
                                  fontWeight: message.read
                                      ? FontWeight.w600
                                      : FontWeight.w800,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '${message.body}\n${message.createdAt == null ? '' : DateFormat('MM月dd日 HH:mm').format(message.createdAt!)}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
