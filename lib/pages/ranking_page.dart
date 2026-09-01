import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import 'album_grid.dart';

class RankingPage extends StatefulWidget {
  const RankingPage({super.key});

  @override
  State<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<RankingPage> {
  WeekData? _week;
  bool _loading = true;
  String? _error;
  String _categoryId = '';
  String _typeId = '';

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
      final week = await ApiClient.instance.fetchWeek();
      if (!mounted) return;
      setState(() {
        _week = week;
        _categoryId = week.categories.isEmpty ? '' : week.categories.first.id;
        _typeId = week.types.isEmpty ? '' : week.types.first.id;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _week == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? '暂无数据'),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final week = _week!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Text('期数'),
              ),
              Expanded(
                child: InputDecorator(
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _categoryId,
                      isExpanded: true,
                      isDense: true,
                      style: Theme.of(context).textTheme.bodyMedium,
                      items: [
                        for (final category in week.categories)
                          DropdownMenuItem(
                            value: category.id,
                            child: Text(
                              _weekLabel(category),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _categoryId = value);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final type in week.types)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(type.title),
                      selected: _typeId == type.id,
                      onSelected: (_) => setState(() => _typeId = type.id),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: AlbumGridView(
            key: ValueKey('week-$_categoryId-$_typeId'),
            loadPage: (page) =>
                ApiClient.instance.fetchWeekFilter(_categoryId, _typeId, page),
          ),
        ),
      ],
    );
  }
}

String _weekLabel(WeekItem item) {
  if (item.time.isNotEmpty) return item.time;
  if (item.title.isNotEmpty) return item.title;
  return '第 ${item.id} 期';
}
