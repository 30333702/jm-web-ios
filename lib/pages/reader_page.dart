import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/image_decoder.dart';
import '../services/scramble.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.chapterId, required this.title});

  final String chapterId;
  final String title;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final PageController _controller = PageController();
  final Map<int, Future<Uint8List>> _futures = {};
  ChapterData? _chapter;
  bool _loading = true;
  String? _error;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final chapter = await ApiClient.instance.fetchChapter(widget.chapterId);
      if (!mounted) return;
      setState(() {
        _chapter = chapter;
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

  Future<Uint8List> _imageAt(int index) {
    final cached = _futures[index];
    if (cached != null) return cached;
    final future = _fetchImage(index);
    _futures[index] = future;
    return future;
  }

  Future<Uint8List> _fetchImage(int index) async {
    final chapter = _chapter!;
    final item = chapter.images[index];
    final sourceUrl = ApiClient.instance.chapterImageUrl(item.url);
    final bytes = await ApiClient.instance.fetchImage(sourceUrl);
    final photoId = int.tryParse(chapter.albumId) ?? 0;
    if (photoId > 0 &&
        needsScramble(
          photoId: photoId,
          scrambleStart: chapter.scrambleStart,
          speed: chapter.speed,
          name: item.name,
        )) {
      final seed = calcSeed(photoId, item.page);
      return decodeScrambledImage(
        bytes,
        photoId: photoId,
        page: item.page,
        seed: seed,
      );
    }
    return bytes;
  }

  void _retry(int index) {
    setState(() {
      _futures.remove(index);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final chapter = _chapter;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: chapter == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(32),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_current + 1} / ${chapter.images.length} 页',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _chapter == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(_error ?? '加载失败'),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final chapter = _chapter!;
    if (chapter.images.isEmpty) {
      return const Center(child: Text('暂无内容'));
    }
    return PageView.builder(
      controller: _controller,
      itemCount: chapter.images.length,
      onPageChanged: (page) => setState(() => _current = page),
      itemBuilder: (context, index) {
        return FutureBuilder<Uint8List>(
          future: _imageAt(index),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 38),
                    const SizedBox(height: 8),
                    const Text('图片加载失败'),
                    TextButton(
                      onPressed: () => _retry(index),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              );
            }
            final bytes = snapshot.data;
            if (bytes == null) {
              return const Center(child: Text('暂无内容'));
            }
            return InteractiveViewer(
              maxScale: 5,
              child: SizedBox.expand(
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
