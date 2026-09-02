import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/image_decoder.dart';
import '../services/scramble.dart';

enum ReaderMode {
  verticalScroll('scroll', '连续滚动'),
  verticalPage('verticalPage', '竖向分页'),
  leftToRight('page', '向右翻页'),
  rightToLeft('pageReverse', '向左翻页');

  const ReaderMode(this.value, this.label);

  final String value;
  final String label;
}

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.chapterId,
    required this.title,
    this.albumId,
    this.chapters = const [],
  });

  final String chapterId;
  final String title;
  final String? albumId;
  final List<SeriesChapter> chapters;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  static const _modeKey = 'jm_reader_mode';

  final Map<int, Future<Uint8List>> _futures = {};
  ChapterData? _chapter;
  bool _loading = true;
  String? _error;
  int _current = 0;
  int _chapterIndex = -1;
  bool _showChrome = true;
  ReaderMode _mode = ReaderMode.verticalScroll;
  PageController? _pageController;
  ScrollController? _scrollController;
  Timer? _chromeTimer;

  @override
  void initState() {
    super.initState();
    _initialChapterIndex();
    _loadModeAndChapter();
  }

  void _initialChapterIndex() {
    for (var i = 0; i < widget.chapters.length; i++) {
      if (widget.chapters[i].id == widget.chapterId) {
        _chapterIndex = i;
        return;
      }
    }
  }

  Future<void> _loadModeAndChapter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_modeKey);
      final mode = ReaderMode.values
          .where((item) => item.value == saved)
          .firstOrNull;
      if (mode != null && mounted) {
        setState(() {
          _mode = mode;
          _createControllers();
        });
      }
    } catch (_) {}
    if (!mounted) return;
    _loadChapter(widget.chapterId, index: _chapterIndex);
  }

  @override
  void dispose() {
    _chromeTimer?.cancel();
    _pageController?.dispose();
    _scrollController?.dispose();
    super.dispose();
  }

  void _createControllers() {
    _pageController?.dispose();
    _scrollController?.dispose();
    _pageController = null;
    _scrollController = null;
    if (_mode == ReaderMode.verticalScroll) {
      _scrollController = ScrollController();
    } else {
      _pageController = PageController();
    }
  }

  Future<void> _loadChapter(String chapterId, {required int index}) async {
    _chromeTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _chapter = null;
      _chapterIndex = index;
      _futures.clear();
      _current = 0;
      _showChrome = true;
      _createControllers();
    });
    try {
      final chapter = await ApiClient.instance.fetchChapter(chapterId);
      if (!mounted) return;
      setState(() {
        _chapter = chapter;
        _loading = false;
      });
      _scheduleChromeHide();
      _restoreCurrentPage();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _restoreCurrentPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _pageController;
      if (controller != null && controller.hasClients) {
        controller.jumpToPage(_viewIndex(_current));
      } else if (_scrollController?.hasClients ?? false) {
        _scrollController!.jumpTo(_scrollOffsetFor(_current));
      }
    });
  }

  double _scrollOffsetFor(int index) {
    final dimension = MediaQuery.sizeOf(context).height;
    return index * dimension * 0.78;
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

  int get _imageCount => _chapter?.images.length ?? 0;

  bool get _hasPreviousChapter =>
      _chapterIndex > 0 && widget.chapters.isNotEmpty;

  bool get _hasNextChapter =>
      _chapterIndex >= 0 &&
      _chapterIndex < widget.chapters.length - 1 &&
      widget.chapters.length > 1;

  void _goTo(int index) {
    if (_imageCount == 0) return;
    final target = index.clamp(0, _imageCount - 1);
    if (target == _current) return;
    setState(() => _current = target);
    if (_mode != ReaderMode.verticalScroll) {
      _pageController?.jumpToPage(_viewIndex(target));
    } else {
      _scrollController?.jumpTo(_scrollOffsetFor(target));
    }
  }

  int _viewIndex(int imageIndex) {
    if (_mode == ReaderMode.rightToLeft) {
      return _imageCount - 1 - imageIndex;
    }
    return imageIndex;
  }

  int _imageIndex(int viewIndex) {
    if (_mode == ReaderMode.rightToLeft) {
      return _imageCount - 1 - viewIndex;
    }
    return viewIndex;
  }

  void _nextPage() {
    if (_current < _imageCount - 1) {
      _goTo(_current + 1);
      return;
    }
    _nextChapter();
  }

  void _previousPage() {
    if (_current > 0) {
      _goTo(_current - 1);
      return;
    }
    _previousChapter();
  }

  void _nextChapter() {
    if (!_hasNextChapter) return;
    final next = widget.chapters[_chapterIndex + 1];
    _loadChapter(next.id, index: _chapterIndex + 1);
  }

  void _previousChapter() {
    if (!_hasPreviousChapter) return;
    final previous = widget.chapters[_chapterIndex - 1];
    _loadChapter(previous.id, index: _chapterIndex - 1);
  }

  void _scheduleChromeHide() {
    _chromeTimer?.cancel();
    _chromeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _showChrome) {
        setState(() => _showChrome = false);
      }
    });
  }

  void _handleTapUp(TapUpDetails details) {
    if (_chapter == null) return;
    final size = MediaQuery.sizeOf(context);
    final dx = details.localPosition.dx;
    if (dx < size.width * 0.30) {
      _previousPage();
    } else if (dx > size.width * 0.70) {
      _nextPage();
    } else {
      setState(() => _showChrome = !_showChrome);
      if (_showChrome) _scheduleChromeHide();
    }
  }

  Future<void> _saveMode(ReaderMode mode) async {
    setState(() {
      _mode = mode;
      _createControllers();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.value);
    _restoreCurrentPage();
  }

  Future<void> _pickChapter() async {
    final chapters = widget.chapters;
    if (chapters.isEmpty) return;
    final selected = await showModalBottomSheet<SeriesChapter>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: chapters.length,
          itemBuilder: (context, index) {
            final chapter = chapters[index];
            final selected = index == _chapterIndex;
            return ListTile(
              selected: selected,
              leading: CircleAvatar(
                radius: 15,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHigh,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              title: Text(
                chapter.name.isEmpty ? '第 ${chapter.sort} 话' : chapter.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: selected
                  ? Icon(
                      Icons.check_circle_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => Navigator.of(context).pop(chapter),
            );
          },
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final index = chapters.indexWhere((item) => item.id == selected.id);
    if (index >= 0 && index != _chapterIndex) {
      _loadChapter(selected.id, index: index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBody(),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: _showChrome ? 1 : 0,
            child: IgnorePointer(
              ignoring: !_showChrome,
              child: _buildChrome(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }
    if (_error != null || _chapter == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.broken_image_outlined,
                size: 44,
                color: Colors.white38,
              ),
              const SizedBox(height: 10),
              const Text(
                '章节加载失败',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: () =>
                    _loadChapter(widget.chapterId, index: _chapterIndex),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_imageCount == 0) {
      return const Center(
        child: Text('暂无内容', style: TextStyle(color: Colors.white70)),
      );
    }
    final mode = _mode;
    if (mode == ReaderMode.verticalScroll) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _handleTapUp,
        child: ListView.builder(
          controller: _scrollController,
          itemCount: _imageCount + (_hasNextChapter ? 1 : 0),
          padding: const EdgeInsets.only(bottom: 120),
          itemBuilder: (context, index) {
            if (index == _imageCount) {
              return _EndCard(
                hasNext: true,
                onNext: _nextChapter,
              );
            }
            return _ScrollPage(
              index: index,
              future: _imageAt(index),
              onRetry: () => _retry(index),
            );
          },
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _handleTapUp,
      child: PageView.builder(
        controller: _pageController,
        reverse: mode == ReaderMode.rightToLeft,
        itemCount: _imageCount,
        onPageChanged: (view) => setState(() => _current = _imageIndex(view)),
        itemBuilder: (context, viewIndex) {
          final index = _imageIndex(viewIndex);
          return _FullPageImage(
            index: index,
            vertical: mode == ReaderMode.verticalPage,
            future: _imageAt(index),
            onRetry: () => _retry(index),
          );
        },
      ),
    );
  }

  Widget _buildChrome() {
    final chapter = _chapter;
    return Column(
      children: [
        _TopBar(
          child: widget.title,
          onBack: () => Navigator.of(context).maybePop(),
          onChapterList: widget.chapters.isEmpty ? null : _pickChapter,
          onMode: _openModeMenu,
          progress: _imageCount == 0
              ? 0.0
              : (_current + 1) / _imageCount,
          pageLabel: chapter == null || _imageCount == 0
              ? ''
              : '${_current + 1} / $_imageCount',
          modeLabel: _mode.label,
        ),
        const Spacer(),
        _BottomBar(
          modeLabel: _mode.label,
          canPrevious: _current > 0 || _hasPreviousChapter,
          canNext: _current < _imageCount - 1 || _hasNextChapter,
          onPrevious: _previousPage,
          onNext: _nextPage,
          onPreviousChapter: _previousChapter,
          onNextChapter: _nextChapter,
          hasPreviousChapter: _hasPreviousChapter,
          hasNextChapter: _hasNextChapter,
          onMode: _openModeMenu,
        ),
      ],
    );
  }

  Future<void> _openModeMenu() async {
    final selected = await showModalBottomSheet<ReaderMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '阅读模式',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final mode in ReaderMode.values)
              ListTile(
                leading: Icon(
                  _modeIcon(mode),
                  color: mode == _mode
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(mode.label),
                trailing: mode == _mode
                    ? Icon(
                        Icons.check_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.of(context).pop(mode),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null && selected != _mode && mounted) {
      await _saveMode(selected);
    }
  }

  IconData _modeIcon(ReaderMode mode) {
    switch (mode) {
      case ReaderMode.verticalScroll:
        return Icons.swap_vert_rounded;
      case ReaderMode.verticalPage:
        return Icons.vertical_align_center_rounded;
      case ReaderMode.leftToRight:
        return Icons.arrow_forward_rounded;
      case ReaderMode.rightToLeft:
        return Icons.arrow_back_rounded;
    }
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.child,
    required this.onBack,
    required this.onChapterList,
    required this.onMode,
    required this.progress,
    required this.pageLabel,
    required this.modeLabel,
  });

  final String child;
  final VoidCallback onBack;
  final VoidCallback? onChapterList;
  final VoidCallback onMode;
  final double progress;
  final String pageLabel;
  final String modeLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.9),
            Colors.black.withValues(alpha: 0.55),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '返回',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: Colors.white,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        child,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (pageLabel.isNotEmpty)
                        Text(
                          pageLabel,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '章节列表',
                  onPressed: onChapterList,
                  icon: const Icon(Icons.list_alt_rounded),
                  color: Colors.white,
                ),
              ],
            ),
            LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: Colors.white12,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.canPrevious,
    required this.canNext,
    required this.onPrevious,
    required this.onNext,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.hasPreviousChapter,
    required this.hasNextChapter,
    required this.onMode,
    required this.modeLabel,
  });

  final bool canPrevious;
  final bool canNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPreviousChapter;
  final VoidCallback onNextChapter;
  final bool hasPreviousChapter;
  final bool hasNextChapter;
  final VoidCallback onMode;
  final String modeLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.9),
            Colors.black.withValues(alpha: 0.5),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: '上一页',
                onPressed: canPrevious ? onPrevious : null,
                icon: const Icon(Icons.chevron_left_rounded),
                color: Colors.white,
              ),
              IconButton(
                tooltip: '下一页',
                onPressed: canNext ? onNext : null,
                icon: const Icon(Icons.chevron_right_rounded),
                color: Colors.white,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      modeLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hasPreviousChapter || hasNextChapter)
                      Text(
                        hasPreviousChapter
                            ? (hasNextChapter ? '上一话 / 下一话' : '上一话')
                            : '下一话',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: hasPreviousChapter ? '上一话' : null,
                onPressed: hasPreviousChapter ? onPreviousChapter : null,
                icon: const Icon(Icons.skip_previous_rounded),
                color: Colors.white,
              ),
              IconButton(
                tooltip: hasNextChapter ? '下一话' : null,
                onPressed: hasNextChapter ? onNextChapter : null,
                icon: const Icon(Icons.skip_next_rounded),
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrollPage extends StatelessWidget {
  const _ScrollPage({
    required this.index,
    required this.future,
    required this.onRetry,
  });

  final int index;
  final Future<Uint8List> future;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FutureBuilder<Uint8List>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              width: double.infinity,
              height: 420,
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    color: Colors.white54,
                    strokeWidth: 2.4,
                  ),
                ),
              ),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return SizedBox(
              width: double.infinity,
              height: 320,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '图片加载失败',
                      style: TextStyle(color: Colors.white54),
                    ),
                    TextButton(onPressed: onRetry, child: const Text('重试')),
                  ],
                ),
              ),
            );
          }
          return Image.memory(
            snapshot.data!,
            width: double.infinity,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          );
        },
      ),
    );
  }
}

class _FullPageImage extends StatelessWidget {
  const _FullPageImage({
    required this.index,
    required this.vertical,
    required this.future,
    required this.onRetry,
  });

  final int index;
  final bool vertical;
  final Future<Uint8List> future;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                color: Colors.white54,
                strokeWidth: 2.4,
              ),
            ),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '图片加载失败',
                  style: TextStyle(color: Colors.white54),
                ),
                TextButton(onPressed: onRetry, child: const Text('重试')),
              ],
            ),
          );
        }
        if (vertical) {
          return SizedBox.expand(
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            ),
          );
        }
        return InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: SizedBox.expand(
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            ),
          ),
        );
      },
    );
  }
}

class _EndCard extends StatelessWidget {
  const _EndCard({required this.hasNext, required this.onNext});

  final bool hasNext;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    if (!hasNext) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: Colors.white54, size: 34),
          const SizedBox(height: 10),
          const Text(
            '本话已读完',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.skip_next_rounded),
            label: const Text('下一话'),
          ),
        ],
      ),
    );
  }
}
