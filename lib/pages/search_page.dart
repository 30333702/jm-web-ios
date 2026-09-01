import 'package:flutter/material.dart';

import '../models/models.dart';
import 'album_grid.dart';
import '../services/api_client.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const orders = [
    ['mr', '最新'],
    ['mv', '最多收藏'],
    ['mp', '最多图片'],
    ['tf', '最多爱心'],
  ];

  final TextEditingController _controller = TextEditingController();
  List<CategoryBlock> _tags = const [];
  String _query = '';
  String _order = 'mr';
  int _version = 0;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    try {
      final blocks = await ApiClient.instance.fetchCategoryBlocks();
      if (!mounted) return;
      setState(() => _tags = blocks);
    } catch (_) {
      // 标签加载失败不影响直接搜索。
    }
  }

  void _submit([String? value]) {
    final query = (value ?? _controller.text).trim();
    if (query.isEmpty) return;
    _controller.text = query;
    setState(() {
      _query = query;
      _submitted = true;
      _version++;
    });
  }

  void _searchOrder(String order) {
    if (_order == order) return;
    setState(() {
      _order = order;
      _version++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: '搜索标题、作者或标签',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _controller.clear();
                        setState(() {});
                      },
                    ),
              filled: true,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: _submit,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final order in orders)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(order[1]),
                      selected: _order == order[0],
                      onSelected: (_) => _searchOrder(order[0]),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _submitted
              ? AlbumGridView(
                  key: ValueKey('$_version-$_query-$_order'),
                  loadPage: (page) =>
                      ApiClient.instance.search(_query, _order, page),
                )
              : _TagPicker(tags: _tags, onTap: _submit),
        ),
      ],
    );
  }
}

class _TagPicker extends StatelessWidget {
  const _TagPicker({required this.tags, required this.onTap});

  final List<CategoryBlock> tags;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      children: [
        for (final block in tags)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  block.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in block.content)
                      ActionChip(
                        label: Text(tag),
                        onPressed: () => onTap(tag),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
