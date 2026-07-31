import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/user_session.dart';
import '../network/content_api.dart';
import 'content_models.dart';

class SiteMessageService extends ChangeNotifier {
  SiteMessageService({required ContentApi api}) : _api = api;

  final ContentApi _api;
  final StreamController<SiteMessage> _events =
      StreamController<SiteMessage>.broadcast();
  Timer? _timer;
  int _unreadCount = 0;
  int _lastAnnouncedId = 0;
  bool _polling = false;

  int get unreadCount => _unreadCount;
  Stream<SiteMessage> get events => _events.stream;

  void start() {
    _timer ??= Timer.periodic(
      const Duration(seconds: 60),
      (_) => poll(),
    );
    unawaited(poll());
  }

  Future<void> poll() async {
    if (_polling || !UserSession.instance.isAccountLogin) return;
    _polling = true;
    try {
      final results = await Future.wait<Object>([
        _api.unreadCount(),
        _api.listMessages(page: 1, size: 10),
      ]);
      final count = results[0] as int;
      final page = results[1] as ContentPage<SiteMessage>;
      if (count != _unreadCount) {
        _unreadCount = count;
        notifyListeners();
      }
      final unread = page.items.where((message) => !message.read).toList();
      if (unread.isNotEmpty && unread.first.id > _lastAnnouncedId) {
        _lastAnnouncedId = unread.first.id;
        _events.add(unread.first);
      }
    } catch (_) {
      // 站内消息不可阻塞主流程，下一轮自动重试。
    } finally {
      _polling = false;
    }
  }

  Future<void> markRead(int id) async {
    await _api.markMessageRead(id);
    if (_unreadCount > 0) {
      _unreadCount--;
      notifyListeners();
    }
  }

  Future<void> markAllRead() async {
    await _api.markAllMessagesRead();
    if (_unreadCount != 0) {
      _unreadCount = 0;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _events.close();
    super.dispose();
  }
}
