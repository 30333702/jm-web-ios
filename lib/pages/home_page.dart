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
          for (final section in _sections)
            _HomeSectionBlock(
              section: section,
              onMore: () => _openMore(section),
            ),
        ],
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
