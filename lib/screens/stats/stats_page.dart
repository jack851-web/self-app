import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import '../../providers/providers.dart';

class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storageAsync = ref.watch(storageProvider);

    return Scaffold(
      backgroundColor: AppColors.canvasParchment,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.canvasParchment,
        surfaceTintColor: Colors.transparent,
        title: Text('统计', style: AppTextStyles.title.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ink), onPressed: () => context.pop()),
      ),
      body: storageAsync.when(
        data: (storage) {
          final stats = storage.getStats();
          final totalDurationMs = stats['totalDurationMs'] as int;
          final totalSessions = stats['totalSessions'] as int;
          final todayDurationMs = stats['todayDurationMs'] as int;
          final todaySessions = stats['todaySessions'] as int;
          const todayBlocks = 0; // TODO: 实现拦截计数

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              // 累计守护时长
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary.withValues(alpha: 0.1), AppColors.primary.withValues(alpha: 0.05)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.shield_outlined, size: 20, color: AppColors.primary),
                          ),
                          const SizedBox(width: 10),
                          Text('累计守护时长', style: AppTextStyles.captionBold.copyWith(color: AppColors.inkMuted48)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(_formatDuration(totalDurationMs),
                          style: AppTextStyles.displayLg.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          )),
                      const SizedBox(height: 4),
                      Text('共 $totalSessions 次守护',
                          style: AppTextStyles.caption.copyWith(color: AppColors.inkMuted48)),
                    ],
                  ),
                ),
              ),

              // 今日统计卡片
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.canvas,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.block, size: 14, color: AppColors.success),
                                ),
                                const SizedBox(width: 6),
                                Text('今日拦截', style: AppTextStyles.label.copyWith(color: AppColors.inkMuted48)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text('$todayBlocks 次',
                                style: AppTextStyles.displayMd.copyWith(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w600,
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.canvas,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppColors.warning.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.access_time_rounded, size: 14, color: AppColors.warning),
                                ),
                                const SizedBox(width: 6),
                                Text('今日守护', style: AppTextStyles.label.copyWith(color: AppColors.inkMuted48)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(_formatDuration(todayDurationMs),
                                style: AppTextStyles.displayMd.copyWith(
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.w600,
                                )),
                            if (todaySessions > 0)
                              Text('$todaySessions 次',
                                  style: AppTextStyles.caption.copyWith(color: AppColors.inkMuted48)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // 提示信息
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.dividerSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, size: 14, color: AppColors.inkMuted48),
                      const SizedBox(width: 6),
                      Text('每次守护结束时会自动更新统计数据',
                          style: AppTextStyles.caption.copyWith(color: AppColors.inkMuted48)),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (error, _) => Center(child: Text('加载失败：$error', style: AppTextStyles.body.copyWith(color: AppColors.danger))),
      ),
    );
  }

  /// 格式化时长显示
  String _formatDuration(int ms) {
    if (ms <= 0) return '0分钟';

    final hours = ms ~/ (1000 * 60 * 60);
    final minutes = (ms % (1000 * 60 * 60)) ~/ (1000 * 60);

    if (hours > 0) {
      return minutes > 0 ? '$hours小时$minutes分' : '$hours小时';
    }
    return '$minutes分钟';
  }
}
