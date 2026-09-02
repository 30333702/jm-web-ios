import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import 'album_page.dart';
import 'login_page.dart';

class MyCommentsPage extends StatefulWidget {
  const MyCommentsPage({super.key});

  @override
  State<MyCommentsPage> createState() => _MyCommentsPageState();
}

class _MyCommentsPageState extends State<MyCommentsPage> {
  UserProfile? _user;
  final List<Comment> _items = [];
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = true}) async {
    if (reset && _user == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (!reset) {
      setState(() => _loadingMore = true);
    }
    try {
      final user = _user ?? await ApiClient.instance.fetchMe();
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = '请先登录 JM 账号';
        });
        return;
      }
      final data = await ApiClient.instance.fetchUserComments(user.uid, _page);
      if (!mounted) return;
      setState(() {
        if (reset || _user == null) {
          _items
            ..clear()
            ..addAll(data.items);
        } else {
          _items.addAll(data.items);
        }
        _user = user;
        _hasMore = data.hasMore;
        _page++;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _login() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoginPage(popAfterLogin: true),
      ),
    );
    if (mounted) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的评论')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chat_bubble_outline_rounded, size: 42),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _login, child: const Text('登录 JM 账号')),
              TextButton(
                onPressed: () => _load(reset: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_hasMore && _items.isEmpty) {
      return const Center(child: Text('还没有发布过评论'));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 420 &&
            !_loadingMore &&
            !_loading &&
            _hasMore) {
          _load(reset: false);
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
          itemCount: _items.length + 1,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == _items.length) {
              return _CommentFooter(
                loading: _loadingMore,
                hasMore: _hasMore,
              );
            }
            final comment = _items[index];
            final aid = comment.aid ?? '';
            return _CommentTile(
              comment: comment,
              onTap: () {
                if (RegExp(r'^\d+$').hasMatch(aid)) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AlbumPage(albumId: aid),
                    ),
                  );
                }
              },
            );
          },
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.onTap});

  final Comment comment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final albumName = comment.albumName != null && comment.albumName!.isNotEmpty
        ? comment.albumName!
        : comment.aid == null || comment.aid!.isEmpty
        ? '未知漫画'
        : '漫画 ${comment.aid}';
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '《$albumName》',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (comment.addTime != null && comment.addTime!.isNotEmpty)
                    Text(
                      comment.addTime!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                comment.content.isEmpty ? '（空评论）' : comment.content,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                ),
              ),
              if (comment.likes > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.thumb_up_alt_outlined,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${comment.likes}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentFooter extends StatelessWidget {
  const _CommentFooter({required this.loading, required this.hasMore});

  final bool loading;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Text(
          hasMore ? '继续上拉加载' : '没有更多了',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
