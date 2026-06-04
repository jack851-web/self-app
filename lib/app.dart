import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'screens/home/home_page.dart';
import 'screens/app_select/app_select_page.dart';
import 'screens/schedule_edit/schedule_edit_page.dart';
import 'screens/lock/lock_page.dart';
import 'screens/stats/stats_page.dart';
import 'providers/providers.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomePage()),
    GoRoute(path: '/app-select', builder: (_, __) => const AppSelectPage()),
    GoRoute(
      path: '/schedule-edit',
      builder: (context, state) {
        final scheduleId = state.uri.queryParameters['scheduleId'];
        return ScheduleEditPage(scheduleId: scheduleId);
      },
    ),
    GoRoute(path: '/stats', builder: (_, __) => const StatsPage()),
    GoRoute(path: '/lock', builder: (_, __) => const LockPage()),
  ],
);

class SelfApp extends ConsumerWidget {
  const SelfApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 监听 storageProvider，就绪后初始化所有 Notifier
    ref.watch(storageProvider);
    return MaterialApp.router(
      title: '自律',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}

/// 在 ProviderScope 层级初始化所有数据层
Future<void> initProviders(WidgetRef ref) async {
  final storage = await ref.read(storageProvider.future);
  await ref.read(schedulesProvider.notifier).init(storage);
  await ref.read(blocklistEntriesProvider.notifier).init(storage);
  await ref.read(selectedBlocklistProvider.notifier).init(storage);
  await ref.read(guardStateProvider.notifier).init(storage);
}
