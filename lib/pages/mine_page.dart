import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import 'album_grid.dart';
import 'login_page.dart';

class MinePage extends StatelessWidget {
  const MinePage({super.key});

  Future<void> _logout(BuildContext context) async {
    await ApiClient.instance.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<PagedAlbums> _loadFavorites(int page) async {
    if (page > 1) {
      return const PagedAlbums(items: [], total: 0, hasMore: false);
    }
    final items = await ApiClient.instance.fetchFavorites();
    return PagedAlbums(items: items, total: items.length, hasMore: false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final server = ApiClient.instance.baseUrl;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.surfaceContainerHigh,
                child: Icon(Icons.person_rounded, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '禁漫客户端',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      server,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '退出登录',
                onPressed: () => _logout(context),
                icon: const Icon(Icons.logout_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(
            children: [
              Text(
                '我的收藏',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Icon(Icons.favorite_rounded, size: 18, color: scheme.primary),
            ],
          ),
        ),
        Expanded(child: AlbumGridView(loadPage: _loadFavorites)),
      ],
    );
  }
}
