import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../widgets/album_cover.dart';
import 'album_list_page.dart';
import 'album_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<HomeSection> _sections = const [];
  bool _loading = true;
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
      final sections = await ApiClient.instance.fetchHome();
      if (!mounted) return;
      setState(() {
        _sections = sections;
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

  void _openMore(HomeSection section) {
    if (!SectionTools.hasMore(section)) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumListPage(
          title: section.title,
          loadPage: (page) => SectionTools.loadMore(section, page),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _sections.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.home_outlined, size: 44),
              const SizedBox(height: 10),
              Text(_error ?? '暂无内容'),
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          if (_sections.isNotEmpty && _sections.first.items.isNotEmpty) ...[
            _HeroCarousel(
              items: _sections.first.items,
              onTap: (album) => AlbumPage.open(context, album),
            ),
            const SizedBox(height: 6),
          ],
          for (final section in _sections.skip(1))
            _HomeSectionBlock(
              section: section,
              onMore: () => _openMore(section),
            ),
        ],
      ),
    );
  }
}

class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel({required this.items, required this.onTap});

  final List<AlbumCard> items;
  final ValueChanged<AlbumCard> onTap;

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 236,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) =>
                _HeroCard(album: widget.items[index], onTap: widget.onTap),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.items.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.album, required this.onTap});

  final AlbumCard album;
  final ValueChanged<AlbumCard> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 22),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AlbumCover(url: ApiClient.instance.albumCoverUrl(album)),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onTap(album),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          album.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                        ),
                        if (album.author.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            album.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.82),
                                ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Chip(
                          label: const Text('立即阅读'),
                          backgroundColor: scheme.primary,
                          labelStyle: TextStyle(
                            color: scheme.onPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                          side: BorderSide.none,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeSectionBlock extends StatelessWidget {
  const _HomeSectionBlock({required this.section, required this.onMore});

  final HomeSection section;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 6, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  section.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (SectionTools.hasMore(section))
                TextButton(onPressed: onMore, child: const Text('更多')),
            ],
          ),
        ),
        SizedBox(
          height: 212,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: section.items.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final album = section.items[index];
              return SizedBox(
                width: 118,
                child: AlbumTile(
                  album: album,
                  onTap: () => AlbumPage.open(context, album),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class SectionTools {
  SectionTools._();

  static bool hasMore(HomeSection section) {
    return section.type == 'promote' ||
        section.type == 'category_id' ||
        section.type == 'filter' ||
        section.type == 'not_in_category_id';
  }

  static Future<PagedAlbums> loadMore(HomeSection section, int page) async {
    final api = ApiClient.instance;
    switch (section.type) {
      case 'promote':
        return api.fetchPromoteList(
          section.id.isEmpty ? section.filterVal : section.id,
          page,
        );
      case 'category_id':
        final category = section.slug.isNotEmpty
            ? section.slug
            : section.filterVal;
        return api.fetchCategory(category, 'mr', page);
      default:
        final query = section.slug.isNotEmpty
            ? section.slug
            : section.filterVal.isNotEmpty
            ? section.filterVal
            : section.title;
        return api.search(query, 'mr', page);
    }
  }
}
