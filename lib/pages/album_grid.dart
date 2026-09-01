import 'package:flutter/material.dart';

import '../models/models.dart';
import '../widgets/album_cover.dart';
import 'album_page.dart';

class AlbumGridView extends StatefulWidget {
  const AlbumGridView({
    super.key,
    required this.loadPage,
    this.initialItems = const [],
  });

  final Future<PagedAlbums> Function(int page) loadPage;
  final List<AlbumCard> initialItems;

  @override
  State<AlbumGridView> createState() => _AlbumGridViewState();
}

class _AlbumGridViewState extends State<AlbumGridView> {
  final List<AlbumCard> _items = [];
  int _page = 1;
  int _seq = 0;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _items.addAll(widget.initialItems);
    _loadPage(1);
  }

  Future<void> _refreshPage() => _loadPage(1);

  Future<void> _loadPage(int page) async {
    final seq = ++_seq;
    setState(() {
      if (page == 1) {
        _initialLoading = _items.isEmpty;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final result = await widget.loadPage(page);
      if (!mounted || seq != _seq) return;
      setState(() {
        if (page == 1) {
          _items
            ..clear()
            ..addAll(result.items);
        } else {
          _items.addAll(result.items);
        }
        _page = page + 1;
        _hasMore = result.hasMore && result.items.isNotEmpty;
        _initialLoading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _initialLoading = false;
        _loadingMore = false;
        _error = error.toString();
      });
    }
  }

  void _loadMore() {
    if (_initialLoading || _loadingMore || !_hasMore || _error != null) return;
    _loadPage(_page);
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 42,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 10),
              const Text('加载失败'),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () {
                  setState(() {
                    _initialLoading = true;
                    _error = null;
                  });
                  _loadPage(1);
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_initialLoading && !_hasMore && _items.isEmpty) {
      return const Center(child: Text('暂无内容'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 700
            ? 6
            : constraints.maxWidth >= 500
            ? 5
            : constraints.maxWidth >= 360
            ? 3
            : 2;
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 520) _loadMore();
            return false;
          },
          child: RefreshIndicator(
            onRefresh: _refreshPage,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.58,
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final album = _items[index];
                      return AlbumTile(
                        album: album,
                        onTap: () => AlbumPage.open(context, album),
                      );
                    }, childCount: _items.length),
                  ),
                ),
                SliverToBoxAdapter(child: _buildFooter()),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (_error != null && _items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(10),
        child: Center(
          child: TextButton(
            onPressed: () => _loadPage(_page),
            child: const Text('加载更多失败，点击重试'),
          ),
        ),
      );
    }
    if (!_hasMore && _items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '没有更多了',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return const SizedBox(height: 4);
  }
}
