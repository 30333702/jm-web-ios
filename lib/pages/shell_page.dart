import 'package:flutter/material.dart';

import 'categories_page.dart';
import 'home_page.dart';
import 'mine_page.dart';
import 'ranking_page.dart';
import 'search_page.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _index = 0;

  static const _titles = ['首页', '搜索', '分类', '周榜', '我的'];
  static const _icons = [
    Icons.home_rounded,
    Icons.search_rounded,
    Icons.grid_view_rounded,
    Icons.leaderboard_rounded,
    Icons.person_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index])),
      body: IndexedStack(
        index: _index,
        children: const [
          HomePage(),
          SearchPage(),
          CategoriesPage(),
          RankingPage(),
          MinePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          for (var i = 0; i < _titles.length; i++)
            NavigationDestination(icon: Icon(_icons[i]), label: _titles[i]),
        ],
      ),
    );
  }
}
