import 'package:flutter/material.dart';

import '../models/models.dart';
import 'album_grid.dart';

class AlbumListPage extends StatelessWidget {
  const AlbumListPage({super.key, required this.title, required this.loadPage});

  final String title;
  final Future<PagedAlbums> Function(int page) loadPage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AlbumGridView(loadPage: loadPage),
    );
  }
}
