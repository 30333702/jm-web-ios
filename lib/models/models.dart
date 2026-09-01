class AlbumCard {
  const AlbumCard({
    required this.id,
    required this.name,
    required this.author,
    this.image,
    this.description,
    this.updateAt,
    this.categoryName,
    this.liked = false,
    this.isFavorite = false,
  });

  final String id;
  final String name;
  final String author;
  final String? image;
  final String? description;
  final int? updateAt;
  final String? categoryName;
  final bool liked;
  final bool isFavorite;

  factory AlbumCard.fromJson(Map<String, dynamic> json) {
    final category = json['category'];
    final categoryName = category is Map ? category['title']?.toString() : null;
    return AlbumCard(
      id: _asString(json['id'] ?? json['aid'] ?? ''),
      name: _asString(json['name']),
      author: _asAuthor(json['author']),
      image: json['image'] is String ? json['image'] as String : null,
      description: json['description'] is String
          ? json['description'] as String
          : null,
      updateAt: _asInt(json['update_at']),
      categoryName: categoryName,
      liked: json['liked'] == true,
      isFavorite: json['is_favorite'] == true,
    );
  }
}

class HomeSection {
  const HomeSection({
    required this.id,
    required this.title,
    required this.slug,
    required this.type,
    required this.filterVal,
    required this.items,
  });

  final String id;
  final String title;
  final String slug;
  final String type;
  final String filterVal;
  final List<AlbumCard> items;

  factory HomeSection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['content'];
    final items = <AlbumCard>[];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map) {
          items.add(AlbumCard.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return HomeSection(
      id: _asString(json['id']),
      title: _asString(json['title']),
      slug: _asString(json['slug'] ?? ''),
      type: _asString(json['type'] ?? ''),
      filterVal: _asString(json['filter_val'] ?? ''),
      items: items,
    );
  }
}

class SeriesChapter {
  const SeriesChapter({
    required this.id,
    required this.name,
    required this.sort,
  });

  final String id;
  final String name;
  final int sort;

  factory SeriesChapter.fromJson(Map<String, dynamic> json) => SeriesChapter(
    id: _asString(json['id']),
    name: _asString(json['name'] ?? ''),
    sort: _asInt(json['sort']) ?? 0,
  );
}

class AlbumDetail {
  const AlbumDetail({
    required this.id,
    required this.name,
    this.description,
    this.author,
    this.totalViews,
    this.totalPhotos,
    this.likes,
    this.liked = false,
    this.isFavorite = false,
    this.tags = const [],
    this.series = const [],
    this.related = const [],
  });

  final String id;
  final String name;
  final String? description;
  final String? author;
  final int? totalViews;
  final int? totalPhotos;
  final int? likes;
  final bool liked;
  final bool isFavorite;
  final List<String> tags;
  final List<SeriesChapter> series;
  final List<AlbumCard> related;

  factory AlbumDetail.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    final tags = <String>[];
    if (rawTags is List) {
      for (final tag in rawTags) {
        if (tag is String && tag.isNotEmpty) tags.add(tag);
      }
    }
    final rawSeries = json['series'];
    final series = <SeriesChapter>[];
    if (rawSeries is List) {
      for (final item in rawSeries) {
        if (item is Map) {
          series.add(SeriesChapter.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final rawRelated = json['related_list'];
    final related = <AlbumCard>[];
    if (rawRelated is List) {
      for (final item in rawRelated) {
        if (item is Map) {
          related.add(AlbumCard.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return AlbumDetail(
      id: _asString(json['id']),
      name: _asString(json['name'] ?? ''),
      description: json['description'] is String
          ? json['description'] as String
          : null,
      author: _asAuthor(json['author']) == ''
          ? null
          : _asAuthor(json['author']),
      totalViews: _asInt(json['total_views']),
      totalPhotos: _asInt(json['total_photos']),
      likes: _asInt(json['likes']),
      liked: json['liked'] == true,
      isFavorite: json['is_favorite'] == true,
      tags: tags,
      series: series,
      related: related,
    );
  }
}

class ChapterImage {
  const ChapterImage({
    required this.url,
    required this.name,
    required this.page,
  });

  final String url;
  final String name;
  final String page;

  factory ChapterImage.fromJson(Map<String, dynamic> json) => ChapterImage(
    url: _asString(json['url']),
    name: _asString(json['name']),
    page: _asString(json['page']),
  );
}

class ChapterData {
  const ChapterData({
    required this.albumId,
    required this.images,
    this.scrambleStart,
    this.speed,
  });

  final String albumId;
  final int? scrambleStart;
  final String? speed;
  final List<ChapterImage> images;

  factory ChapterData.fromJson(Map<String, dynamic> json) {
    final rawImages = json['images'];
    final images = <ChapterImage>[];
    if (rawImages is List) {
      for (final item in rawImages) {
        if (item is Map) {
          images.add(ChapterImage.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return ChapterData(
      albumId: _asString(json['aid'] ?? json['jmid'] ?? ''),
      scrambleStart: _asInt(json['scrambleId']),
      speed: json['speed'] is String ? json['speed'] as String : null,
      images: images,
    );
  }
}

class WeekItem {
  const WeekItem({required this.id, required this.title, required this.time});

  final String id;
  final String title;
  final String time;

  factory WeekItem.fromJson(Map<String, dynamic> json) => WeekItem(
    id: _asString(json['id']),
    title: _asString(json['title'] ?? ''),
    time: _asString(json['time'] ?? ''),
  );
}

class WeekType {
  const WeekType({required this.id, required this.title});

  final String id;
  final String title;

  factory WeekType.fromJson(Map<String, dynamic> json) =>
      WeekType(id: _asString(json['id']), title: _asString(json['title']));
}

class WeekData {
  const WeekData({required this.categories, required this.types});

  final List<WeekItem> categories;
  final List<WeekType> types;

  factory WeekData.fromJson(Map<String, dynamic> json) {
    final categories = <WeekItem>[];
    final rawCategories = json['categories'];
    if (rawCategories is List) {
      for (final item in rawCategories) {
        if (item is Map) {
          categories.add(WeekItem.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final types = <WeekType>[];
    final rawTypes = json['type'];
    if (rawTypes is List) {
      for (final item in rawTypes) {
        if (item is Map) {
          types.add(WeekType.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return WeekData(categories: categories, types: types);
  }
}

class CategoryInfo {
  const CategoryInfo({
    required this.id,
    required this.name,
    this.slug = '',
    this.type = '',
    this.totalAlbums,
    this.subCategories = const [],
  });

  final String id;
  final String name;
  final String slug;
  final String type;
  final String? totalAlbums;
  final List<SubCategory> subCategories;

  factory CategoryInfo.fromJson(Map<String, dynamic> json) {
    final rawSub = json['sub_categories'];
    final subs = <SubCategory>[];
    if (rawSub is List) {
      for (final item in rawSub) {
        if (item is Map) {
          subs.add(SubCategory.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return CategoryInfo(
      id: _asString(json['id']),
      name: _asString(json['name']),
      slug: _asString(json['slug'] ?? ''),
      type: _asString(json['type'] ?? ''),
      totalAlbums: json['total_albums']?.toString(),
      subCategories: subs,
    );
  }
}

class CategoryBlock {
  const CategoryBlock({required this.title, required this.content});

  final String title;
  final List<String> content;

  factory CategoryBlock.fromJson(Map<String, dynamic> json) {
    final raw = json['content'];
    final content = <String>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is String && item.trim().isNotEmpty) content.add(item.trim());
      }
    }
    return CategoryBlock(
      title: _asString(json['title'] ?? ''),
      content: content,
    );
  }
}

class SubCategory {
  const SubCategory({required this.id, required this.name, required this.slug});

  final String id;
  final String name;
  final String slug;

  factory SubCategory.fromJson(Map<String, dynamic> json) => SubCategory(
    id: _asString(json['CID']),
    name: _asString(json['name']),
    slug: _asString(json['slug'] ?? ''),
  );
}

class PagedAlbums {
  const PagedAlbums({
    required this.items,
    required this.total,
    required this.hasMore,
  });

  final List<AlbumCard> items;
  final int total;
  final bool hasMore;

  factory PagedAlbums.fromJson(Map<String, dynamic> json) {
    final content = json['content'] ?? json['list'];
    final items = <AlbumCard>[];
    if (content is List) {
      for (final item in content) {
        if (item is Map) {
          items.add(AlbumCard.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final total = _asInt(json['total']) ?? items.length;
    return PagedAlbums(
      items: items,
      total: total,
      hasMore: items.length < total,
    );
  }
}

String _asString(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is num) return value.toString();
  return value.toString();
}

String _asAuthor(dynamic value) {
  if (value is List) {
    return value
        .map((item) => _asString(item))
        .where((item) => item.isNotEmpty)
        .join(' / ');
  }
  return _asString(value);
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
