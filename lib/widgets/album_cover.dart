import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';

class AlbumCover extends StatelessWidget {
  const AlbumCover({super.key, required this.url, this.width, this.height});

  final String url;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: height,
        child: url.isEmpty
            ? const _EmptyCover()
            : Image.network(
                url,
                fit: BoxFit.cover,
                width: width,
                height: height,
                headers: {
                  'X-JMW-Data-Source': 'builtin',
                  if ((ApiClient.instance.cookie ?? '').isNotEmpty)
                    'Cookie': ApiClient.instance.cookie!,
                },
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const _CoverLoading();
                },
                errorBuilder: (context, error, stackTrace) =>
                    const _EmptyCover(),
              ),
      ),
    );
  }
}

class AlbumGridTile extends StatelessWidget {
  const AlbumGridTile({
    super.key,
    required this.title,
    required this.author,
    required this.imageUrl,
    this.onTap,
  });

  final String title;
  final String author;
  final String imageUrl;
  final VoidCallback? onTap;

  static const double coverAspect = 3 / 4;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: coverAspect,
            child: AlbumCover(url: imageUrl),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          if (author.isNotEmpty)
            Text(
              author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }
}

class AlbumTile extends StatelessWidget {
  const AlbumTile({super.key, required this.album, this.onTap});

  final AlbumCard album;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AlbumGridTile(
      title: album.name,
      author: album.author,
      imageUrl: ApiClient.instance.albumCoverUrl(album),
      onTap: onTap,
    );
  }
}

class _EmptyCover extends StatelessWidget {
  const _EmptyCover();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.auto_stories_outlined,
        color: scheme.onSurfaceVariant,
        size: 28,
      ),
    );
  }
}

class _CoverLoading extends StatelessWidget {
  const _CoverLoading();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
      ),
    );
  }
}
