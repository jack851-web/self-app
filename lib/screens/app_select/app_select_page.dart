import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/native_channel.dart';
import '../../utils/haptic.dart';

class AppSelectPage extends ConsumerStatefulWidget {
  const AppSelectPage({super.key});

  @override
  ConsumerState<AppSelectPage> createState() => _AppSelectPageState();
}

class _AppSelectPageState extends ConsumerState<AppSelectPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<_InstalledApp>? _cachedApps;
  String _lastQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedBlocklist = ref.watch(selectedBlocklistProvider);

    return Scaffold(
      backgroundColor: AppColors.canvasParchment,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.canvasParchment,
        surfaceTintColor: Colors.transparent,
        title: Text('选择应用', style: AppTextStyles.title.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ink), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          // 搜索框
          Container(
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索应用...',
                hintStyle: AppTextStyles.body.copyWith(color: AppColors.inkMuted48),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.inkMuted48, size: 22),
                // P1: 搜索清除按钮
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.dividerSoft,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 16, color: AppColors.inkMuted48),
                        ),
                        onPressed: () {
                          Haptic.light();
                          _searchController.clear();
                          setState(() {});
                          // 重新加载全量数据
                          _cachedApps = null;
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              style: AppTextStyles.body.copyWith(color: AppColors.ink),
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  // 仅在查询变化时重新请求，本地过滤不需要重新请求原生方法
                  if (_cachedApps == null || value.length < _lastQuery.length) {
                    setState(() {}); // 触发 FutureBuilder 重新加载（首次或缩短搜索词时）
                  } else {
                    setState(() {}); // 本地过滤，直接用缓存
                  }
                  _lastQuery = value;
                });
              },
            ),
          ),

          Expanded(
            child: FutureBuilder<List<_InstalledApp>>(
              future: _loadApps(_searchController.text),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && _cachedApps == null) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                }
                final apps = snapshot.data ?? _cachedApps ?? [];
                if (snapshot.hasData) _cachedApps = apps;

                // 客户端二次过滤（搜索词缩短时需要全量重载，搜索词加长时本地过滤即可）
                final query = _searchController.text.toLowerCase();
                final filtered = apps.where((a) =>
                    a.label.toLowerCase().contains(query) ||
                    a.packageName.toLowerCase().contains(query)).toList();

                if (filtered.isEmpty && apps.isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('没有找到匹配的应用', style: AppTextStyles.body.copyWith(color: AppColors.inkMuted48))),
                  );
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.dividerSoft, indent: 68),
                  itemBuilder: (context, index) {
                    final app = filtered[index];
                    final isSelected = selectedBlocklist.contains(app.packageName);
                    return _AppListItem(
                      app: app,
                      isSelected: isSelected,
                      onToggle: () async {
                        Haptic.select();
                        if (isSelected) {
                          await ref.read(selectedBlocklistProvider.notifier).remove(app.packageName);
                        } else {
                          await ref.read(selectedBlocklistProvider.notifier).add(app.packageName);
                          await ref.read(blocklistEntriesProvider.notifier).add(
                            BlocklistEntry(packageName: app.packageName, label: app.label),
                          );
                        }
                        setState(() {});
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 首次加载或缓存失效时调用原生方法获取应用列表
  Future<List<_InstalledApp>> _loadApps(String query) async {
    if (_cachedApps != null) return _cachedApps!;
    try {
      final result = await NativeChannel.getInstalledApps(query: query);
      final apps = result
          .map((e) => _InstalledApp(
            packageName: e['packageName'] as String,
            label: e['label'] as String,
          ))
          .toList();
      
      if (apps.isEmpty && query.isEmpty) {
        debugPrint('⚠️ 未获取到任何应用，可能原因：');
        debugPrint('  - Android 11+ 包可见性限制未正确配置');
        debugPrint('  - QUERY_ALL_PACKAGES 权限未授予（部分厂商需要手动授权）');
        debugPrint('  - 应用未正确安装或签名问题');
      }
      
      return apps;
    } catch (e, stackTrace) {
      debugPrint('❌ 获取应用列表失败: $e');
      debugPrint('堆栈信息: $stackTrace');
      
      // 显示错误提示给用户
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '无法获取应用列表：$e\n请检查是否已授予相关权限',
              style: AppTextStyles.body.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: '重试',
              textColor: Colors.white,
              onPressed: () {
                _cachedApps = null;
                setState(() {});
              },
            ),
          ),
        );
      }
      
      return [];
    }
  }
}

class _InstalledApp {
  final String packageName;
  final String label;

  _InstalledApp({required this.packageName, required this.label});
}

class _AppListItem extends StatelessWidget {
  final _InstalledApp app;
  final bool isSelected;
  final VoidCallback onToggle;

  const _AppListItem({required this.app, required this.isSelected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // 选择框
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.hairline,
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 16, color: AppColors.onPrimary)
                      : null,
                ),
                const SizedBox(width: 14),

                // 应用图标
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.surfacePearl, AppColors.dividerSoft],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.apps_rounded, color: AppColors.inkMuted48, size: 22),
                ),
                const SizedBox(width: 14),

                // 应用信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(app.label,
                          style: AppTextStyles.body.copyWith(
                            color: AppColors.ink,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          )),
                      const SizedBox(height: 2),
                      Text(app.packageName,
                          style: AppTextStyles.label.copyWith(color: AppColors.inkMuted48),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),

                // 选中指示器
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.1),
                    ),
                    child: const Icon(Icons.check_circle, size: 18, color: AppColors.primary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
