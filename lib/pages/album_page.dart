import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../widgets/album_cover.dart';
import 'reader_page.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key, required this.albumId, this.title = ''});

  final String albumId;
  final String title;

  static void open(BuildContext context, AlbumCard album) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumPage(albumId: album.id, title: album.name),
      ),
    );
  }

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  AlbumDetail? _detail;
  bool _loading = true;
  bool _favorite = false;
  bool _liked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await ApiClient.instance.fetchAlbum(widget.albumId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _favorite = detail.isFavorite;
        _liked = detail.liked;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final target = !_favorite;
    setState(() => _favorite = target);
    try {
      await ApiClient.instance.toggleFavorite(widget.albumId, target);
    } catch (_) {
      if (!mounted) return;
      setState(() => _favorite = !target);
      _showSnack('操作失败');
    }
  }

  Future<void> _toggleLike() async {
    final target = !_liked;
    setState(() => _liked = target);
    try {
      await ApiClient.instance.toggleLike(widget.albumId, target);
    } catch (_) {
      if (!mounted) return;
      setState(() => _liked = !target);
      _showSnack('操作失败');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openChapter(SeriesChapter chapter) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderPage(
          chapterId: chapter.id,
          title: chapter.name.isEmpty
              ? (_detail?.name ?? '阅读')
              : '${_detail?.name ?? ''} ${chapter.name}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_detail?.name ?? widget.title)),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _detail == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? '加载失败'),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final detail = _detail!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          _Header(
            detail: detail,
            favorite: _favorite,
            liked: _liked,
            onFavorite: _toggleFavorite,
            onLike: _toggleLike,
            onRead: detail.series.isEmpty
                ? null
                : () => _openChapter(detail.series.first),
          ),
          if (detail.description?.isNotEmpty ?? false) ...[
            const SizedBox(height: 18),
            Text(
              detail.description!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (detail.tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in detail.tags)
                  Chip(label: Text(tag), visualDensity: VisualDensity.compact),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text(
            '章节列表',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          if (detail.series.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text('暂无章节', style: Theme.of(context).textTheme.bodySmall),
            )
          else
            ...detail.series
                .take(100)
                .map(
                  (chapter) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: CircleAvatar(
                      radius: 15,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHigh,
                      child: Text(
                        '${chapter.sort}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    title: Text(
                      chapter.name.isEmpty
                          ? '第 ${chapter.sort} 话'
                          : chapter.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                    onTap: () => _openChapter(chapter),
                  ),
                ),
          if (detail.related.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(
              '相关推荐',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: detail.related.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final related = detail.related[index];
                  return SizedBox(
                    width: 118,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 150,
                          child: AlbumCover(
                            url: ApiClient.instance.albumCoverUrl(related),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          related.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.detail,
    required this.favorite,
    required this.liked,
    required this.onFavorite,
    required this.onLike,
    required this.onRead,
  });

  final AlbumDetail detail;
  final bool favorite;
  final bool liked;
  final VoidCallback onFavorite;
  final VoidCallback onLike;
  final VoidCallback? onRead;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 118,
              height: 157,
              child: AlbumCover(
                url: ApiClient.instance.albumImageUrl({
                  'id': detail.id,
                  'image': '',
                }),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  if ((detail.author ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      detail.author!,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      _Meta(label: _formatCount(detail.totalViews)),
                      _Meta(label: _formatCount(detail.totalPhotos)),
                      _Meta(label: _formatCount(detail.likes)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onFavorite,
                icon: Icon(
                  favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 18,
                ),
                label: Text(favorite ? '已收藏' : '收藏'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: onLike,
              icon: Icon(
                liked
                    ? Icons.thumb_up_alt_rounded
                    : Icons.thumb_up_off_alt_outlined,
                size: 18,
              ),
              label: Text(liked ? '已赞' : '点赞'),
            ),
            if (onRead != null) ...[
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: onRead,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('开始阅读'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

String _formatCount(int? value) {
  if (value == null) return '0';
  if (value >= 10000) {
    return '${(value / 10000).toStringAsFixed(1)}万+';
  }
  return value.toString();
}
