import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import 'album_grid.dart';
import 'login_page.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<FavoriteFolder> _folders = const [
    FavoriteFolder(id: '0', name: '全部'),
  ];
  String _folderId = '0';
  String _scope = '';
  int _revision = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.instance.fetchFavoritesData(
        page: 1,
        folderId: _folderId,
      );
      if (!mounted) return;
      setState(() {
        _folders = data.folders.isEmpty ? _folders : data.folders;
        _scope = data.scope;
        _loading = false;
        _revision++;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<PagedAlbums> _loadPage(int page) async {
    final data = await ApiClient.instance.fetchFavoritesData(
      page: page,
      folderId: _folderId,
    );
    if (page == 1 && mounted) {
      final folders = data.folders;
      if (folders.isNotEmpty &&
          !_sameFolders(_folders, folders)) {
        setState(() => _folders = folders);
      }
      if (_scope != data.scope) {
        setState(() => _scope = data.scope);
      }
    }
    return PagedAlbums(
      items: data.items,
      total: data.total,
      hasMore: data.hasMore || (data.sourceCount > 0 && data.items.isNotEmpty),
    );
  }

  bool _sameFolders(List<FavoriteFolder> a, List<FavoriteFolder> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].name != b[i].name) return false;
    }
    return true;
  }

  Future<void> _newFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建收藏夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(
            labelText: '收藏夹名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await ApiClient.instance.favoriteFolder('add', folderName: name);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('收藏夹已创建')));
      await _bootstrap();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏'),
        actions: [
          IconButton(
            tooltip: '新建收藏夹',
            onPressed: _newFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.favorite_border_rounded,
                size: 42,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LoginPage(popAfterLogin: true),
                    ),
                  );
                  if (mounted) _bootstrap();
                },
                child: const Text('登录 JM 账号'),
              ),
              TextButton(
                onPressed: _bootstrap,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final folder in _folders)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(folder.name),
                    selected: _folderId == folder.id,
                    onSelected: (_) {
                      if (_folderId == folder.id) return;
                      setState(() {
                        _folderId = folder.id;
                        _revision++;
                      });
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              IconButton(
                tooltip: '新建收藏夹',
                onPressed: _newFolder,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
          child: Row(
            children: [
              Icon(
                _scope == 'cloud'
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                _scope == 'cloud' ? '已同步 JM 账号' : '仅保存在当前会话',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AlbumGridView(
            key: ValueKey('favorites-$_folderId-$_revision'),
            loadPage: _loadPage,
          ),
        ),
      ],
    );
  }
}
