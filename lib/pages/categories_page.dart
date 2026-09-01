import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import 'album_list_page.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  static const categoryOrders = [
    ['', '最新'],
    ['tf', '最多爱心'],
    ['mv', '总排行'],
    ['mv_m', '月排行'],
    ['mv_w', '周排行'],
    ['mv_t', '日排行'],
  ];

  List<CategoryInfo> _categories = const [];
  List<CategoryBlock> _tags = const [];
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
      final results = await Future.wait<Object>([
        ApiClient.instance.fetchCategories(),
        ApiClient.instance.fetchCategoryBlocks(),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<CategoryInfo>;
        _tags = results[1] as List<CategoryBlock>;
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

  void _openCategory(CategoryInfo category) {
    final isSlug = category.slug.isNotEmpty || category.id == '0';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumListPage(
          title: category.name,
          loadPage: (page) => isSlug
              ? ApiClient.instance.fetchCategory(category.slug, 'mr', page)
              : ApiClient.instance.search(category.name, 'mr', page),
        ),
      ),
    );
  }

  void _openCombined(CategoryInfo category, SubCategory sub) {
    final combined = '${category.slug}_${sub.slug}';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumListPage(
          title: '${category.name} · ${sub.name}',
          loadPage: (page) =>
              ApiClient.instance.fetchCategory(combined, '', page),
        ),
      ),
    );
  }

  void _openTag(String tag) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumListPage(
          title: tag,
          loadPage: (page) => ApiClient.instance.search(tag, 'mr', page),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
        children: [
          const _SectionTitle('排行榜'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final order in categoryOrders)
                ActionChip(
                  label: Text(order[1]),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AlbumListPage(
                        title: order[1],
                        loadPage: (page) => ApiClient.instance.fetchCategory(
                          order[0],
                          '',
                          page,
                        ),
                      ),
                    ),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 22),
          const _SectionTitle('主分类'),
          const SizedBox(height: 4),
          for (final category in _categories) _buildCategoryTile(category),
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionTitle('热门标签'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final block in _tags)
                  for (final tag in block.content)
                    ActionChip(
                      label: Text(tag),
                      onPressed: () => _openTag(tag),
                      visualDensity: VisualDensity.compact,
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryTile(CategoryInfo category) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Text(
              category.name.substring(0, 1),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          title: Text(
            category.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: category.totalAlbums == null || category.totalAlbums == '0'
              ? null
              : Text(
                  '${category.totalAlbums} 本',
                  style: const TextStyle(fontSize: 12),
                ),
          trailing: const Icon(Icons.chevron_right_rounded, size: 20),
          onTap: () => _openCategory(category),
        ),
        if (category.subCategories.isNotEmpty && category.slug.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('全部'),
                  onPressed: () => _openCategory(category),
                  visualDensity: VisualDensity.compact,
                ),
                for (final sub in category.subCategories)
                  ActionChip(
                    label: Text(sub.name),
                    onPressed: () => _openCombined(category, sub),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}
