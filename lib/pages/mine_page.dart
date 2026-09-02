import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import 'favorites_page.dart';
import 'history_page.dart';
import 'login_page.dart';
import 'my_comments_page.dart';
import 'signin_page.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  UserProfile? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isLoggedIn =>
      ApiClient.instance.auth.hasJmSession || _profile != null;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await ApiClient.instance.fetchMe();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _profile = null;
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loginJm() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoginPage(popAfterLogin: true),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _logoutJm() async {
    await ApiClient.instance.logoutJm();
    if (!mounted) return;
    setState(() => _profile = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已退出 JM 账号')));
    _load();
  }

  Future<void> _logoutServer() async {
    await ApiClient.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          _ProfileHeader(
            profile: _profile,
            isLoggedIn: _isLoggedIn,
            error: _error,
            onLogin: _loginJm,
            onLogoutJm: _logoutJm,
            onLogoutServer: _logoutServer,
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              children: [
                _MenuTile(
                  icon: Icons.calendar_month_rounded,
                  title: '每日签到',
                  subtitle: '连续签到领金币',
                  onTap: () => _open(const SigninPage()),
                ),
                _MenuTile(
                  icon: Icons.favorite_rounded,
                  title: '我的收藏',
                  subtitle: '收藏夹与云端同步',
                  onTap: () => _open(const FavoritesPage()),
                ),
                _MenuTile(
                  icon: Icons.history_rounded,
                  title: '阅读历史',
                  subtitle: '继续上次阅读',
                  onTap: () => _open(const HistoryPage()),
                ),
                _MenuTile(
                  icon: Icons.chat_bubble_rounded,
                  title: '我的评论',
                  subtitle: _isLoggedIn ? '查看和管理评论' : '登录后可查看',
                  onTap: () async {
                    if (!_isLoggedIn) {
                      await _loginJm();
                      return;
                    }
                    _open(const MyCommentsPage());
                  },
                ),
                if (_isLoggedIn)
                  _MenuTile(
                    icon: Icons.logout_rounded,
                    title: '退出 JM 账号',
                    subtitle: '保留服务器连接',
                    onTap: _logoutJm,
                  ),
                _MenuTile(
                  icon: Icons.power_settings_new_rounded,
                  title: '退出服务器',
                  subtitle: ApiClient.instance.baseUrl,
                  onTap: _logoutServer,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.isLoggedIn,
    required this.error,
    required this.onLogin,
    required this.onLogoutJm,
    required this.onLogoutServer,
  });

  final UserProfile? profile;
  final bool isLoggedIn;
  final String? error;
  final VoidCallback onLogin;
  final VoidCallback onLogoutJm;
  final VoidCallback onLogoutServer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = profile;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Avatar(user: user, isLoggedIn: isLoggedIn),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName ?? '未登录 JM 账号',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user == null
                          ? '登录后可同步收藏、历史、评论和签到'
                          : '${user.levelName ?? '会员'} Lv.${user.level} · ${user.coin} 金币',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (user != null)
                IconButton(
                  tooltip: '退出 JM 账号',
                  onPressed: onLogoutJm,
                  icon: const Icon(Icons.logout_rounded, size: 20),
                ),
            ],
          ),
          if (user != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (user.expPercent.clamp(0, 100)).toDouble() / 100,
                minHeight: 7,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Text(
                  '经验 ${user.exp} / ${user.nextLevelExp}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                Text(
                  '收藏 ${user.albumFavorites}/${user.albumFavoritesMax}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          if (user == null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text('登录 JM 账号'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(42)),
            ),
            if (error != null && error!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                ),
              ),
            ],
          ],
          const SizedBox(height: 10),
          Text(
            '服务器：${ApiClient.instance.baseUrl}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: onLogoutServer,
            icon: const Icon(Icons.power_settings_new_rounded, size: 16),
            label: const Text('退出服务器并更换地址'),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.isLoggedIn});

  final UserProfile? user;
  final bool isLoggedIn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = user == null ? '' : ApiClient.instance.avatarImageUrl(user!.photo);
    return CircleAvatar(
      radius: 30,
      backgroundColor: scheme.surfaceContainerHigh,
      foregroundImage: url.isEmpty ? null : NetworkImage(url),
      child: url.isEmpty
          ? Text(
              user == null
                  ? (isLoggedIn ? '?' : '登')
                  : (user!.username.isEmpty ? '友' : user!.username.substring(0, 1)),
              style: TextStyle(
                color: scheme.primary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
    );
  }
}
