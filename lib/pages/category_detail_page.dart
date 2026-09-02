import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import 'album_grid.dart';

class CategoryDetailPage extends StatefulWidget {
  const CategoryDetailPage({
    super.key,
    required this.category,
    required this.title,
  });

  final CategoryInfo category;
  final String title;

  @override
  State<CategoryDetailPage> createState() => _CategoryDetailPageState();
}

class _CategoryDetailPageState extends State<CategoryDetailPage> {
  String _slug = '';
  int _revision = 0;

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          if (category.subCategories.isNotEmpty)
            SizedBox(
              height: 54,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('全部'),
                      selected: _slug.isEmpty,
                      onSelected: (_) => _select(''),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  for (final sub in category.subCategories)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(sub.name),
                        selected: _slug == _combined(category, sub),
                        onSelected: (_) => _select(_combined(category, sub)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: AlbumGridView(
              key: ValueKey('category-${category.id}-$_slug-$_revision'),
              loadPage: _loadPage,
            ),
          ),
        ],
      ),
    );
  }

  String _combined(CategoryInfo category, SubCategory sub) {
    if (category.slug.isEmpty || sub.slug.isEmpty) return sub.slug;
    return '${category.slug}_${sub.slug}';
  }

  void _select(String slug) {
    if (_slug == slug) return;
    setState(() {
      _slug = slug;
      _revision++;
    });
  }

  Future<PagedAlbums> _loadPage(int page) {
    final category = widget.category;
    if (_slug.isEmpty) {
      if (category.slug.isNotEmpty || category.id == '0') {
        return ApiClient.instance.fetchCategory(category.slug, 'mr', page);
      }
      return ApiClient.instance.search(category.name, 'mr', page);
    }
    final combined = _slug.contains('_');
    return ApiClient.instance.fetchCategory(_slug, combined ? '' : 'mr', page);
  }
}
