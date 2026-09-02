import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import 'login_page.dart';

class SigninPage extends StatefulWidget {
  const SigninPage({super.key});

  @override
  State<SigninPage> createState() => _SigninPageState();
}

class _SigninPageState extends State<SigninPage> {
  DailySignIn? _daily;
  UserProfile? _me;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

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
      final me = await ApiClient.instance.fetchMe();
      if (me == null) {
        if (!mounted) return;
        setState(() {
          _me = null;
          _daily = null;
          _loading = false;
          _error = '请先登录 JM 账号';
        });
        return;
      }
      final daily = await ApiClient.instance.fetchDaily(me.uid);
      if (!mounted) return;
      setState(() {
        _me = me;
        _daily = daily;
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

  Future<void> _checkIn() async {
    final daily = _daily;
    final me = _me;
    if (daily == null || me == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final result = await ApiClient.instance.dailyCheckIn(me.uid, daily.dailyId);
      final raw = result['data'];
      final msg = raw is Map ? raw['msg']?.toString() : null;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg ?? '签到成功')));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('每日签到')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_me == null || _daily == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, size: 42),
              const SizedBox(height: 10),
              Text(_error ?? '需要登录'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LoginPage(popAfterLogin: true),
                    ),
                  );
                  if (mounted) _load();
                },
                child: const Text('登录 JM 账号'),
              ),
            ],
          ),
        ),
      );
    }
    final daily = _daily!;
    final now = DateTime.now();
    final todaySigned = daily.records.any((record) => _sameDay(record.date, now));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  daily.eventName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  '已连续签到 ${daily.currentProgress} 天 · 连续 3 天 +${daily.threeDaysCoin} 金币',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                _SignGrid(
                  records: daily.records,
                  now: now,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: todaySigned || _submitting ? null : _checkIn,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: Text(
                    _submitting
                        ? '签到中...'
                        : todaySigned
                        ? '今日已签到'
                        : '立即签到',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static bool _sameDay(String date, DateTime now) {
    final parsed = DateTime.tryParse(date);
    if (parsed != null) {
      return parsed.year == now.year &&
          parsed.month == now.month &&
          parsed.day == now.day;
    }
    final parts = date.split('-');
    if (parts.length == 2) {
      final month = int.tryParse(parts[0]);
      final day = int.tryParse(parts[1]);
      return month == now.month && day == now.day;
    }
    return false;
  }
}

class _SignGrid extends StatelessWidget {
  const _SignGrid({
    required this.records,
    required this.now,
  });

  final List<DailyRecord> records;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final leading = (first.weekday + 6) % 7;
    final result = <Widget>[
      for (final name in ['一', '二', '三', '四', '五', '六', '日'])
        Center(
          child: Text(
            name,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _DayCell(
          day: day,
          today: now.day == day,
          signed: _isSigned(day),
          bonus: _isBonus(day),
        ),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.92,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: result,
    );
  }

  bool _isSigned(int day) {
    return records.any((record) {
      final parsed = DateTime.tryParse(record.date);
      return parsed != null && parsed.day == day && record.signed;
    });
  }

  bool _isBonus(int day) {
    return records.any((record) {
      final parsed = DateTime.tryParse(record.date);
      return parsed != null && parsed.day == day && record.bonus;
    });
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.today,
    required this.signed,
    required this.bonus,
  });

  final int day;
  final bool today;
  final bool signed;
  final bool bonus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: signed ? scheme.primary : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: today
            ? Border.all(color: scheme.onSurface, width: 1.4)
            : null,
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            signed ? '✓' : '$day',
            style: TextStyle(
              color: signed ? scheme.onPrimary : scheme.onSurface,
              fontSize: 14,
              fontWeight: signed ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          if (bonus)
            Icon(Icons.stars_rounded, size: 11, color: scheme.tertiary),
        ],
      ),
    );
  }
}
