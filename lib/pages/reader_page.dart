import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/image_decoder.dart';
import '../services/scramble.dart';

enum ReaderMode {
  verticalScroll('scroll', '连续滚动'),
  verticalPage('verticalPage', '竖向翻页'),
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
  static const _modeVersionKey = 'jm_reader_mode_version';
  static const _modeVersion = 2;
  static const _maxCachedPages = 24;

  final Map<int, Future<Uint8List>> _imageFutures = {};
  final LinkedHashMap<int, Uint8List> _imageCache = LinkedHashMap();
  final Map<int, double> _pageExtents = {};

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
  Timer? _prefetchTimer;

  @override
  void initState() {
    super.initState();
    _chapterIndex = _indexOfChapter(widget.chapterId);
    _loadModeAndChapter();
  }

  int _indexOfChapter(String chapterId) {
    for (var i = 0; i < widget.chapters.length; i++) {
      if (widget.chapters[i].id == chapterId) return i;
    }
    return -1;
  }

  Future<void> _loadModeAndChapter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_modeKey);
      final savedVersion = prefs.getInt(_modeVersionKey) ?? 0;
      ReaderMode? savedMode;
      if (saved != null) {
        savedMode = ReaderMode.values
            .where((item) => item.value == saved)
            .firstOrNull;
      }
      var next = savedMode ?? ReaderMode.verticalScroll;
      if (savedVersion < _modeVersion &&
          (saved == ReaderMode.leftToRight.value ||
              saved == ReaderMode.rightToLeft.value)) {
        next = ReaderMode.verticalScroll;
      }
      await prefs.setInt(_modeVersionKey, _modeVersion);
      if (next != savedMode) {
        await prefs.setString(_modeKey, next.value);
      }
      if (mounted) {
        setState(() {
          _mode = next;
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
    _prefetchTimer?.cancel();
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
      _scrollController = ScrollController()
        ..addListener(_handleVerticalScroll);
    } else {
      _pageController = PageController(
        initialPage: _imageCount == 0 ? 0 : _viewIndex(_current),
      );
    }
  }

  Future<void> _loadChapter(String chapterId, {required int index}) async {
    _chromeTimer?.cancel();
    _prefetchTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _chapter = null;
      _chapterIndex = index;
      _current = 0;
      _showChrome = true;
      _clearImages();
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
      _prefetchAround(0);
      _restoreCurrentPage();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _clearImages() {
    _imageFutures.clear();
    _imageCache.clear();
    _pageExtents.clear();
  }

  void _scheduleChromeHide() {
    _chromeTimer?.cancel();
    _chromeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _showChrome) {
        setState(() => _showChrome = false);
      }
    });
  }

  void _restoreCurrentPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _pageController;
      if (controller != null && controller.hasClients) {
        controller.jumpToPage(_viewIndex(_current));
      } else if (_scrollController?.hasClients ?? false) {
        _scrollController!.jumpTo(_offsetFor(_current));
      }
    });
  }

  double get _defaultPageExtent =>
      MediaQuery.sizeOf(context).height * 0.9;

  double _offsetFor(int index) {
    if (index <= 0) return 0;
    var offset = 0.0;
    for (var i = 0; i < index; i++) {
      offset += _pageExtents[i] ?? _defaultPageExtent;
    }
    return offset;
  }

  int _indexFromOffset(double offset) {
    if (_imageCount == 0) return 0;
    var accumulated = 0.0;
    for (var i = 0; i < _imageCount; i++) {
      final extent = _pageExtents[i] ?? _defaultPageExtent;
      if (offset < accumulated + extent) return i;
      accumulated += extent;
    }
    return _imageCount - 1;
  }

  void _handleVerticalScroll() {
    if (!mounted ||
        _mode != ReaderMode.verticalScroll ||
        _chapter == null ||
        _scrollController == null ||
        !_scrollController!.hasClients) {
      return;
    }
    final position = _scrollController!.position;
    final index = _indexFromOffset(
      position.pixels + position.viewportDimension * 0.15,
    ).clamp(0, _imageCount - 1);
    if (index != _current) {
      setState(() => _current = index);
    }
    _schedulePrefetch(index);
  }

  Future<Uint8List> _imageAt(int index) {
    final cached = _imageCache[index];
    if (cached != null) return Future.value(cached);
    final pending = _imageFutures[index];
    if (pending != null) return pending;
    final future = _fetchImage(index);
    _imageFutures[index] = future;
    future.then<void>((bytes) {
      if (!mounted) return;
      _imageCache[index] = bytes;
      _imageFutures.remove(index);
      while (_imageCache.length > _maxCachedPages) {
        _imageCache.remove(_imageCache.keys.first);
      }
    }, onError: (Object error, StackTrace stackTrace) {
      if (mounted) _imageFutures.remove(index);
    });
    return future;
  }

  Future<Uint8List> _fetchImage(int index) async {
    final chapter = _chapter!;
    final item = chapter.images[index];
    final sourceUrl = ApiClient.instance.chapterImageUrl(item.url);
    var bytes = await ApiClient.instance.fetchImage(sourceUrl);
    final photoId =
        int.tryParse(widget.chapterId) ?? int.tryParse(chapter.albumId) ?? 0;
    if (photoId > 0 &&
        needsScramble(
          photoId: photoId,
          scrambleStart: chapter.scrambleStart,
          speed: chapter.speed,
          name: item.name,
        )) {
      final seed = calcSeed(photoId, item.page);
      try {
        bytes = await decodeScrambledImage(
          bytes,
          photoId: photoId,
          page: item.page,
          seed: seed,
        );
      } catch (_) {
        // Keep the original bytes when the scramble decoder fails.
      }
    }
    return bytes;
  }

  void _schedulePrefetch(int index) {
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _chapter == null) return;
      final center = index.clamp(0, _imageCount - 1);
      _prefetchAround(center);
      _trimCache(center);
    });
  }

  void _prefetchAround(int index) {
    if (_chapter == null || _imageCount == 0) return;
    final start = (index - 4).clamp(0, _imageCount - 1);
    final end = (index + 9).clamp(0, _imageCount - 1);
    for (var i = start; i <= end; i++) {
      _imageAt(i);
    }
  }

  void _trimCache(int index) {
    final lower = index - 8;
    final upper = index + 22;
    _imageCache.removeWhere((key, _) => key < lower || key > upper);
    _imageFutures.removeWhere((key, _) => key < lower || key > upper);
  }

  void _retry(int index) {
    setState(() {
      _imageCache.remove(index);
      _imageFutures.remove(index);
    });
  }

  int get _imageCount => _chapter?.images.length ?? 0;

  bool get _hasPreviousChapter =>
      _chapterIndex > 0 && widget.chapters.isNotEmpty;

  bool get _hasNextChapter =>
      _chapterIndex >= 0 &&
      _chapterIndex < widget.chapters.length - 1 &&
      widget.chapters.length > 1;

  String get _pageLabel {
    if (_chapter == null || _imageCount == 0) return '';
    return '${_current + 1} / $_imageCount';
  }

  String get _currentChapterLabel {
    if (_chapterIndex >= 0 && _chapterIndex < widget.chapters.length) {
      return _chapterName(widget.chapters[_chapterIndex]);
    }
    return '';
  }

  String _chapterName(SeriesChapter chapter) {
    final name = chapter.name.trim();
    return name.isEmpty ? '第 ${chapter.sort} 话' : name;
  }

  void _goTo(int index) {
    if (_imageCount == 0) return;
    final target = index.clamp(0, _imageCount - 1);
    setState(() => _current = target);
    if (_mode == ReaderMode.verticalScroll) {
      if (_scrollController?.hasClients ?? false) {
        _scrollController!.jumpTo(_offsetFor(target));
      }
    } else {
      _pageController?.jumpToPage(_viewIndex(target));
    }
    _prefetchAround(target);
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

  void _handleTapUp(TapUpDetails details) {
    if (_chapter == null || _imageCount == 0) return;
    final size = MediaQuery.sizeOf(context);
    final dx = details.localPosition.dx;
    if (_mode == ReaderMode.verticalScroll) {
      setState(() => _showChrome = !_showChrome);
      if (_showChrome) _scheduleChromeHide();
      return;
    }
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
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _createControllers();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.value);
    await prefs.setInt(_modeVersionKey, _modeVersion);
    _prefetchAround(_current);
    _restoreCurrentPage();
  }

  Future<void> _pickChapter() async {
    final chapters = widget.chapters;
    if (chapters.isEmpty) return;
    final selected = await showModalBottomSheet<SeriesChapter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => _ChapterSheet(
        chapters: chapters,
        currentIndex: _chapterIndex < 0 ? 0 : _chapterIndex,
        currentChapterId: widget.chapterId,
      ),
    );
    if (selected == null || !mounted) return;
    final target = chapters.indexWhere((item) => item.id == selected.id);
    if (target >= 0 && target != _chapterIndex) {
      _loadChapter(selected.id, index: target);
    }
  }

  Future<void> _openModeMenu() async {
    final selected = await showModalBottomSheet<ReaderMode>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '阅读设置',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
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

  int get _cacheWidth {
    final size = MediaQuery.sizeOf(context);
    return (size.width * MediaQuery.devicePixelRatioOf(context)).round();
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
              return _EndCard(hasNext: true, onNext: _nextChapter);
            }
            return _ScrollPage(
              index: index,
              future: _imageAt(index),
              onRetry: () => _retry(index),
              placeholderHeight: _defaultPageExtent,
              cacheWidth: _cacheWidth,
              onExtent: (extent) {
                if (extent > 0) _pageExtents[index] = extent;
              },
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
        scrollDirection: mode == ReaderMode.verticalPage
            ? Axis.vertical
            : Axis.horizontal,
        reverse: mode == ReaderMode.rightToLeft,
        itemCount: _imageCount,
        onPageChanged: (view) {
          final index = _imageIndex(view);
          if (index != _current) setState(() => _current = index);
          _prefetchAround(index);
        },
        itemBuilder: (context, viewIndex) {
          final index = _imageIndex(viewIndex);
          return _FullPageImage(
            index: index,
            vertical: mode == ReaderMode.verticalPage,
            future: _imageAt(index),
            onRetry: () => _retry(index),
            cacheWidth: _cacheWidth,
          );
        },
      ),
    );
  }

  Widget _buildChrome() {
    final chapterLabel = _currentChapterLabel;
    final subtitle = chapterLabel.isEmpty
        ? _pageLabel
        : _pageLabel.isEmpty
        ? chapterLabel
        : '$chapterLabel · $_pageLabel';
    return Column(
      children: [
        _TopBar(
          title: widget.title,
          subtitle: subtitle,
          progress: _imageCount == 0 ? 0.0 : (_current + 1) / _imageCount,
          onBack: () => Navigator.of(context).maybePop(),
          onChapterList: widget.chapters.isEmpty ? null : _pickChapter,
          onMode: _openModeMenu,
        ),
        const Spacer(),
        _BottomBar(
          modeLabel: _mode.label,
          pageLabel: _pageLabel,
          canPrevious: _current > 0 || _hasPreviousChapter,
          canNext: _current < _imageCount - 1 || _hasNextChapter,
          onPrevious: _previousPage,
          onNext: _nextPage,
          onPreviousChapter: _previousChapter,
          onNextChapter: _nextChapter,
          hasPreviousChapter: _hasPreviousChapter,
          hasNextChapter: _hasNextChapter,
          onMode: _openModeMenu,
          onChapterList: _pickChapter,
          chapterName: _hasPreviousChapter || _hasNextChapter
              ? (_hasPreviousChapter
                    ? (_hasNextChapter ? '上一话 / 下一话' : '上一话')
                    : '下一话')
              : '',
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.onBack,
    required this.onChapterList,
    required this.onMode,
  });

  final String title;
  final String subtitle;
  final double progress;
  final VoidCallback onBack;
  final VoidCallback? onChapterList;
  final VoidCallback onMode;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.92),
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
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '目录',
                  onPressed: onChapterList,
                  icon: const Icon(Icons.format_list_bulleted_rounded),
                  color: Colors.white,
                ),
                IconButton(
                  tooltip: '阅读设置',
                  onPressed: onMode,
                  icon: const Icon(Icons.tune_rounded),
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
    required this.modeLabel,
    required this.pageLabel,
    required this.canPrevious,
    required this.canNext,
    required this.onPrevious,
    required this.onNext,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.hasPreviousChapter,
    required this.hasNextChapter,
    required this.onMode,
    required this.onChapterList,
    required this.chapterName,
  });

  final String modeLabel;
  final String pageLabel;
  final bool canPrevious;
  final bool canNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPreviousChapter;
  final VoidCallback onNextChapter;
  final bool hasPreviousChapter;
  final bool hasNextChapter;
  final VoidCallback onMode;
  final VoidCallback? onChapterList;
  final String chapterName;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.92),
            Colors.black.withValues(alpha: 0.5),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
          child: Row(
            children: [
              _CompactIconButton(
                icon: Icons.tune_rounded,
                tooltip: '阅读设置',
                onPressed: onMode,
              ),
              _CompactIconButton(
                icon: Icons.skip_previous_rounded,
                tooltip: '上一话',
                onPressed: hasPreviousChapter ? onPreviousChapter : null,
              ),
              _CompactIconButton(
                icon: Icons.chevron_left_rounded,
                tooltip: '上一页',
                onPressed: canPrevious ? onPrevious : null,
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      modeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (chapterName.isNotEmpty)
                      Text(
                        chapterName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      )
                    else if (pageLabel.isNotEmpty)
                      Text(
                        pageLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
              _CompactIconButton(
                icon: Icons.chevron_right_rounded,
                tooltip: '下一页',
                onPressed: canNext ? onNext : null,
              ),
              _CompactIconButton(
                icon: Icons.skip_next_rounded,
                tooltip: '下一话',
                onPressed: hasNextChapter ? onNextChapter : null,
              ),
              _CompactIconButton(
                icon: Icons.format_list_bulleted_rounded,
                tooltip: '目录',
                onPressed: onChapterList,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 22),
      color: Colors.white,
      disabledColor: Colors.white30,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ScrollPage extends StatelessWidget {
  const _ScrollPage({
    required this.index,
    required this.future,
    required this.onRetry,
    required this.onExtent,
    required this.placeholderHeight,
    required this.cacheWidth,
  });

  final int index;
  final Future<Uint8List> future;
  final VoidCallback onRetry;
  final ValueChanged<double> onExtent;
  final double placeholderHeight;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    return _ExtentReporter(
      onExtent: onExtent,
      child: SizedBox(
        width: double.infinity,
        child: FutureBuilder<Uint8List>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return SizedBox(
                height: placeholderHeight,
                child: const Center(
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
                height: 240,
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
              cacheWidth: cacheWidth,
            );
          },
        ),
      ),
    );
  }
}

class _ExtentReporter extends StatefulWidget {
  const _ExtentReporter({required this.child, required this.onExtent});

  final Widget child;
  final ValueChanged<double> onExtent;

  @override
  State<_ExtentReporter> createState() => _ExtentReporterState();
}

class _ExtentReporterState extends State<_ExtentReporter> {
  double? _lastExtent;

  @override
  void initState() {
    super.initState();
    _scheduleReport();
  }

  @override
  void didUpdateWidget(_ExtentReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleReport();
  }

  void _scheduleReport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final height = box.size.height;
        if (height != _lastExtent) {
          _lastExtent = height;
          widget.onExtent(height);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _FullPageImage extends StatelessWidget {
  const _FullPageImage({
    required this.index,
    required this.vertical,
    required this.future,
    required this.onRetry,
    required this.cacheWidth,
  });

  final int index;
  final bool vertical;
  final Future<Uint8List> future;
  final VoidCallback onRetry;
  final int cacheWidth;

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
        final image = Image.memory(
          snapshot.data!,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          cacheWidth: cacheWidth,
        );
        if (vertical) {
          return SizedBox.expand(child: image);
        }
        return InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: SizedBox.expand(child: Center(child: image)),
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
          const Icon(
            Icons.check_circle_outline_rounded,
            color: Colors.white54,
            size: 34,
          ),
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

class _ChapterSheet extends StatefulWidget {
  const _ChapterSheet({
    required this.chapters,
    required this.currentIndex,
    required this.currentChapterId,
  });

  final List<SeriesChapter> chapters;
  final int currentIndex;
  final String currentChapterId;

  @override
  State<_ChapterSheet> createState() => _ChapterSheetState();
}

class _ChapterSheetState extends State<_ChapterSheet> {
  static const _itemExtent = 56.0;

  late final ScrollController _controller;
  late List<int> _order;
  bool _reversed = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _order = _buildOrder();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToCurrent());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<int> _buildOrder() {
    final result = List<int>.generate(widget.chapters.length, (i) => i);
    return _reversed ? result.reversed.toList() : result;
  }

  void _setReversed(bool value) {
    if (_reversed == value) return;
    setState(() {
      _reversed = value;
      _order = _buildOrder();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToCurrent());
  }

  void _jumpToCurrent() {
    if (!mounted || !_controller.hasClients) return;
    final position = _order.indexOf(widget.currentIndex);
    final target = ((position * _itemExtent) - 120).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    _controller.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: FractionallySizedBox(
        heightFactor: 0.84,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Text(
                    '目录 (${widget.chapters.length})',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.arrow_upward_rounded, size: 16),
                        label: Text('正序'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.arrow_downward_rounded, size: 16),
                        label: Text('倒序'),
                      ),
                    ],
                    selected: {_reversed},
                    onSelectionChanged: (values) => _setReversed(values.first),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: _controller,
                itemExtent: _itemExtent,
                itemCount: widget.chapters.length,
                itemBuilder: (context, position) {
                  final originalIndex = _order[position];
                  final chapter = widget.chapters[originalIndex];
                  final selected =
                      originalIndex == widget.currentIndex ||
                      chapter.id == widget.currentChapterId;
                  return ListTile(
                    selected: selected,
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: colorScheme.surfaceContainerHigh,
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
                    trailing: selected
                        ? Icon(
                            Icons.check_circle_rounded,
                            color: colorScheme.primary,
                          )
                        : const Icon(Icons.chevron_right_rounded, size: 20),
                    onTap: () => Navigator.of(context).pop(chapter),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
