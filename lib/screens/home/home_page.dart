import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../utils/haptic.dart';
import '../../utils/exit_config.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  /// 长按选中的计划（用于删除）
  GuardSchedule? _longPressedSchedule;
  static const _maxVisibleChips = 7;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    final state = ref.read(guardStateProvider);
    if (state.active && state.endAt != null) {
      _remainingSeconds = state.remainingSeconds;
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final current = ref.read(guardStateProvider);
        if (!current.active) {
          _countdownTimer?.cancel();
          _countdownTimer = null;
          setState(() {});
          return;
        }
        final newSecs = current.remainingSeconds;
        if (newSecs != _remainingSeconds) {
          setState(() => _remainingSeconds = newSecs);
        }
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  // === P0-2.1 + P0-2.3: 时长选择 + 确认弹窗 ===
  Future<void> _onStartGuard(int selectedCount) async {
    if (selectedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择至少一个应用'), duration: Duration(seconds: 2)),
      );
      return;
    }
    Haptic.medium();

    // 弹出时长选择器
    final minutes = await _showDurationPicker();
    if (minutes == null || !mounted) return; // 用户取消

    // 获取已选应用列表（用于显示图标预览）
    final entries = ref.read(blocklistEntriesProvider);

    // 二次确认
    final confirmed = await _showStartConfirmDialog(selectedCount, minutes, entries);
    if (!confirmed || !mounted) return;

    Haptic.heavy();
    
    // 获取当前选中的黑名单（同步到原生端用于拦截）
    final selectedPackages = ref.read(selectedBlocklistProvider).toList();
    
    await ref.read(guardStateProvider.notifier).startManual(minutes, blocklist: selectedPackages);
    _startCountdown();
    // 不再直接推锁屏——锁屏只由原生端检测到黑名单App时触发
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('守护已开启 ($minutes 分钟)，打开受限应用将触发惩戒'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 底部弹出时长选择面板
  Future<int?> _showDurationPicker() async {
    return showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => const _DurationPickerSheet(),
    );
  }

  /// 启动守护确认对话框
  Future<bool> _showStartConfirmDialog(int appCount, int minutes, List<BlocklistEntry> entries) async {
    // 最多显示4个应用图标
    final displayEntries = entries.take(4).toList();
    final remaining = entries.length - 4;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('开始守护？', style: AppTextStyles.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('选中的 $appCount 个应用将被锁定', style: AppTextStyles.body),
            Text('守护时长：${_formatMinutes(minutes)}', style: AppTextStyles.caption.copyWith(color: AppColors.inkMuted48)),
            const SizedBox(height: 16),
            // 应用图标预览
            if (entries.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...displayEntries.map((entry) => Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surfacePearl,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.apps, color: AppColors.inkMuted48, size: 20),
                  )),
                  if (remaining > 0)
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.dividerSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text('+$remaining',
                            style: AppTextStyles.caption.copyWith(
                                color: AppColors.inkMuted48,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(color: AppColors.inkMuted48)),
          ),
          TextButton(
            onPressed: () { Haptic.select(); Navigator.of(ctx).pop(true); },
            child: const Text('开始守护', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ).then((v) => v ?? false);
  }

  // === P0-2.4: 长按删除计划 ===
  void _onScheduleLongPress(GuardSchedule schedule) {
    Haptic.heavy();
    setState(() => _longPressedSchedule = schedule);
  }

  void _cancelLongPressSelection() {
    setState(() => _longPressedSchedule = null);
  }

  Future<void> _confirmDeleteSchedule(GuardSchedule schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除计划？', style: AppTextStyles.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('「${schedule.label}」', style: AppTextStyles.bodyBold.copyWith(color: AppColors.ink)),
            Text(schedule.timeRange, style: AppTextStyles.caption.copyWith(color: AppColors.inkMuted48)),
            const SizedBox(height: 8),
            Text('删除后不可恢复。', style: AppTextStyles.caption.copyWith(color: AppColors.danger)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(color: AppColors.inkMuted48)),
          ),
          TextButton(
            onPressed: () { Haptic.heavy(); Navigator.of(ctx).pop(true); },
            child: const Text('删除', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(schedulesProvider.notifier).remove(schedule.id!);
      _cancelLongPressSelection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除「${schedule.label}」'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes 分钟';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '$h 小时 $m 分钟' : '$h 小时';
  }

  @override
  Widget build(BuildContext context) {
    final guardState = ref.watch(guardStateProvider);
    final schedules = ref.watch(schedulesProvider);
    final blocklistEntries = ref.watch(blocklistEntriesProvider);
    final selectedBlocklist = ref.watch(selectedBlocklistProvider);

    // 长按选中态下其他卡片半透明
    final isSelecting = _longPressedSchedule != null;

    return Scaffold(
      backgroundColor: AppColors.canvasParchment,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.canvasParchment,
        surfaceTintColor: Colors.transparent,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, Color(0xFF0052A3)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('自律', style: TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.w700, fontSize: 18)),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surfacePearl,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.bar_chart_outlined, size: 20, color: AppColors.inkMuted80),
            ),
            onPressed: () { Haptic.light(); context.push('/stats'); },
          )
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 8),
              children: [
                _buildGuardToggle(guardState, selectedBlocklist.length),

                const SizedBox(height: 24),

                _buildScheduleList(schedules, isSelecting),

                const SizedBox(height: 24),

                _buildBlocklistSection(blocklistEntries, selectedBlocklist),

                const SizedBox(height: 32),
              ],
            ),
          ),

          // 长按选中时的底部操作栏
          if (isSelecting)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _DeleteActionBar(
                label: _longPressedSchedule?.label ?? '',
                onDelete: () => _confirmDeleteSchedule(_longPressedSchedule!),
                onCancel: _cancelLongPressSelection,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGuardToggle(GuardState guardState, int selectedCount) {
    final isActive = guardState.active;

    return Container(
      decoration: BoxDecoration(
        gradient: isActive
            ? const LinearGradient(
                colors: [Color(0xFF0066CC), Color(0xFF0052A3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isActive ? null : AppColors.canvas,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isActive ? AppColors.primary : Colors.black).withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 24,
                  color: isActive ? AppColors.onPrimary.withValues(alpha: 0.9) : AppColors.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  '手动守护',
                  style: AppTextStyles.title.copyWith(
                    color: isActive ? AppColors.onPrimary : AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isActive)
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, __) {
                      return Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              AppColors.onPrimary.withValues(alpha: 0.3 + _pulseController.value * 0.2),
                              AppColors.onPrimary.withValues(alpha: 0.1),
                            ],
                          ),
                          border: Border.all(
                            color: AppColors.onPrimary.withValues(alpha: 0.4),
                            width: 2,
                          ),
                        ),
                        child: const Icon(Icons.shield, color: AppColors.onPrimary, size: 30),
                      );
                    },
                  ),
                if (isActive) const SizedBox(width: 16),
                Switch(
                  value: isActive,
                  onChanged: (value) {
                    Haptic.select();
                    if (value) {
                      _onStartGuard(selectedCount);
                    } else {
                      _stopGuard();
                    }
                  },
                  activeColor: AppColors.onPrimary,
                  activeTrackColor: AppColors.onPrimary.withValues(alpha: 0.4),
                ),
                if (isActive && guardState.endAt != null) ...[
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.onPrimary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_remainingSeconds ~/ 60}分${_remainingSeconds % 60}秒',
                      style: AppTextStyles.bodyBold.copyWith(
                        color: AppColors.onPrimary,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (!isActive && selectedCount == 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_rounded, size: 16, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Text(
                      '请先选择至少一个应用',
                      style: AppTextStyles.label.copyWith(color: AppColors.warning),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _stopGuard() async {
    await ref.read(guardStateProvider.notifier).stop();
    _startCountdown();
  }

  Widget _buildScheduleList(List<GuardSchedule> schedules, bool isSelecting) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('定时计划', style: AppTextStyles.title.copyWith(color: AppColors.ink)),
            IconButton(
              icon: const Icon(Icons.add, size: 20, color: AppColors.primary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () { Haptic.select(); context.push('/schedule-edit'); },
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...schedules.map((schedule) => Opacity(
          opacity: (isSelecting && _longPressedSchedule?.id != schedule.id) ? 0.4 : 1.0,
          child: _ScheduleCard(
            schedule: schedule,
            isSelected: _longPressedSchedule?.id == schedule.id,
            onToggle: (v) {
              Haptic.select();
              ref.read(schedulesProvider.notifier).toggleEnabled(schedule.id!, v);
            },
            onTap: isSelecting ? null : () => context.push('/schedule-edit?scheduleId=${schedule.id}'),
            onLongPress: () => _onScheduleLongPress(schedule),
          ),
        )),
        if (schedules.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('暂无定时计划，点击 + 添加', style: AppTextStyles.body.copyWith(color: AppColors.inkMuted48)),
          ),
      ],
    );
  }

  Widget _buildBlocklistSection(List<dynamic> entries, Set<String> selectedPackages) {
    // P1: 已选应用折叠显示
    final displayEntries = entries.length <= _maxVisibleChips
        ? entries
        : entries.take(_maxVisibleChips).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('已选应用 (${selectedPackages.length})', style: AppTextStyles.title.copyWith(color: AppColors.ink)),
            TextButton(onPressed: () { Haptic.light(); context.push('/app-select'); },
                child: const Text('管理', style: TextStyle(color: AppColors.primary))),
          ],
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty && selectedPackages.isEmpty)
          Text('还没有选择要限制的应用', style: AppTextStyles.body.copyWith(color: AppColors.inkMuted48))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...displayEntries.map((e) {
                final entry = e as BlocklistEntry;
                return Chip(
                  label: Text(entry.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () {
                    Haptic.light();
                    ref.read(blocklistEntriesProvider.notifier).remove(entry.packageName);
                    ref.read(selectedBlocklistProvider.notifier).remove(entry.packageName);
                  },
                  side: BorderSide.none,
                  backgroundColor: AppColors.surfacePearl,
                  labelStyle: AppTextStyles.caption.copyWith(color: AppColors.inkMuted80),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                );
              }),
              // 超过上限时显示 "+N 更多"
              if (entries.length > _maxVisibleChips)
                ActionChip(
                  label: Text('+${entries.length - _maxVisibleChips} 更多'),
                  onPressed: () => context.push('/app-select'),
                  labelStyle: AppTextStyles.caption.copyWith(color: AppColors.primary),
                  side: BorderSide.none,
                  backgroundColor: AppColors.surfacePearl,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                ),
            ],
          ),
      ],
    );
  }
}

// === 时长选择底部面板（P0-2.1）===
class _DurationPickerSheet extends StatefulWidget {
  const _DurationPickerSheet();

  @override
  State<_DurationPickerSheet> createState() => _DurationPickerSheetState();
}

class _DurationPickerSheetState extends State<_DurationPickerSheet> {
  int? _selectedMinutes;

  @override
  void initState() {
    super.initState();
    _selectedMinutes = DurationPresets.defaultMinutes;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动指示条
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: AppColors.dividerSoft, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('选择守护时长', style: AppTextStyles.title.copyWith(color: AppColors.ink)),
                const SizedBox(height: 20),
                // 预设选项网格（2列3行）
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.5,
                  children: DurationPresets.presets.map((preset) {
                    final isSelected = _selectedMinutes == preset.minutes;
                    return _DurationOption(
                      label: preset.label,
                      isSelected: isSelected,
                      onTap: () { Haptic.select(); setState(() => _selectedMinutes = preset.minutes); },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                // 自定义输入
                _CustomDurationInput(
                  onChanged: (v) => setState(() => _selectedMinutes = v),
                ),
                const SizedBox(height: 20),
                // 操作按钮行
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () { Haptic.light(); Navigator.pop(context); },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.hairline),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('取消', style: TextStyle(color: AppColors.inkMuted48)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _selectedMinutes != null
                            ? () { Haptic.heavy(); Navigator.pop(context, _selectedMinutes); }
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          disabledBackgroundColor: AppColors.dividerSoft,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text('开始守护 · ${_selectedMinutes != null ? _formatMins(_selectedMinutes!) : ""}',
                            style: const TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatMins(int m) => m < 60 ? '$m分' : '${m ~/ 60}h${m % 60 > 0 ? ' ${m % 60}m' : ''}';
}

class _DurationOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DurationOption({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: isSelected
            ? const LinearGradient(
                colors: [Color(0xFF0066CC), Color(0xFF0052A3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isSelected ? null : AppColors.canvas,
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.dividerSoft,
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            child: Text(
              label,
              style: AppTextStyles.body.copyWith(
                color: isSelected ? AppColors.onPrimary : AppColors.inkMuted80,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomDurationInput extends StatefulWidget {
  final ValueChanged<int> onChanged;
  const _CustomDurationInput({required this.onChanged});

  @override
  State<_CustomDurationInput> createState() => _CustomDurationInputState();
}

class _CustomDurationInputState extends State<_CustomDurationInput> {
  final _controller = TextEditingController(text: '');
  bool _focused = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _focused = true),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: _focused ? AppColors.primary : AppColors.hairline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.edit_outlined, size: 18, color: _focused ? AppColors.primary : AppColors.inkMuted48),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '自定义分钟数（${DurationPresets.minCustomMinutes}-${DurationPresets.maxCustomMinutes}）',
                  hintStyle: AppTextStyles.caption.copyWith(color: AppColors.inkMuted48),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                style: AppTextStyles.body.copyWith(color: AppColors.ink),
                onChanged: (val) {
                  final m = int.tryParse(val);
                  if (m != null &&
                      m >= DurationPresets.minCustomMinutes &&
                      m <= DurationPresets.maxCustomMinutes) {
                    widget.onChanged(m);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// === 长按删除操作栏 ===
class _DeleteActionBar extends StatelessWidget {
  final String label;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  const _DeleteActionBar({required this.label, required this.onDelete, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('删除计划', style: AppTextStyles.bodyBold.copyWith(color: AppColors.ink)),
                  Text(
                    '「$label」',
                    style: AppTextStyles.caption.copyWith(color: AppColors.inkMuted48),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: Text('取消', style: AppTextStyles.body.copyWith(color: AppColors.inkMuted80)),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onDelete,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: AppColors.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                elevation: 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.delete_outline, size: 18),
                  const SizedBox(width: 6),
                  const Text('删除', style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// === Schedule Card Widget（支持长按选中态）===
class _ScheduleCard extends StatelessWidget {
  final GuardSchedule schedule;
  final bool isSelected;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  const _ScheduleCard({
    required this.schedule,
    required this.isSelected,
    required this.onToggle,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: isSelected ? AppColors.danger.withValues(alpha: 0.05) : AppColors.canvas,
        border: Border.all(
          color: isSelected
              ? AppColors.danger
              : (schedule.enabled ? AppColors.dividerSoft : AppColors.hairline),
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(
                            colors: [AppColors.danger, Color(0xFFFF6961)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : (schedule.enabled
                            ? const LinearGradient(
                                colors: [AppColors.primary, Color(0xFF0071E3)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null),
                    color: schedule.enabled ? null : AppColors.surfacePearl,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: schedule.enabled
                        ? [
                            BoxShadow(
                              color: (isSelected ? AppColors.danger : AppColors.primary).withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            )
                          ]
                        : [],
                  ),
                  child: Icon(
                    isSelected ? Icons.delete_outline : Icons.access_time_rounded,
                    size: 22,
                    color: schedule.enabled ? AppColors.onPrimary : AppColors.inkMuted48,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        schedule.label.isEmpty ? '定时计划' : schedule.label,
                        style: AppTextStyles.bodyBold.copyWith(color: AppColors.ink),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        schedule.timeRange,
                        style: AppTextStyles.caption.copyWith(color: AppColors.inkMuted48),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: schedule.enabled,
                  onChanged: onToggle,
                  activeTrackColor: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
