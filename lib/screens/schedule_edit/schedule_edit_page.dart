import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../utils/haptic.dart';

class ScheduleEditPage extends ConsumerStatefulWidget {
  final String? scheduleId;

  const ScheduleEditPage({super.key, this.scheduleId});

  @override
  ConsumerState<ScheduleEditPage> createState() => _ScheduleEditPageState();
}

class _ScheduleEditPageState extends ConsumerState<ScheduleEditPage> {
  final _labelController = TextEditingController();
  int _startHour = 22;
  int _startMinute = 0;
  int _endHour = 7;
  int _endMinute = 0;
  int _daysOfWeek = 127; // 全选
  bool _isSaving = false;

  static const _dayLabels = ['日', '一', '二', '三', '四', '五', '六'];

  @override
  void initState() {
    super.initState();
    if (widget.scheduleId != null) {
      final schedules = ref.read(schedulesProvider);
      final existing = schedules.where((s) => s.id.toString() == widget.scheduleId).firstOrNull;
      if (existing != null) {
        _labelController.text = existing.label;
        _startHour = existing.startHour;
        _startMinute = existing.startMinute;
        _endHour = existing.endHour;
        _endMinute = existing.endMinute;
        _daysOfWeek = existing.daysOfWeek;
      }
    }
  }

  bool get _isCrossMidnight => (_endHour < _startHour) || (_endHour == _startHour && _endMinute <= _startMinute);

  /// P0-2.5: 校验逻辑
  String? _validate() {
    final label = _labelController.text.trim();
    
    if (label.isEmpty) return '请输入计划名称';
    if (label.length > 50) return '计划名称不能超过50个字符';
    if (_daysOfWeek == 0) return '请至少选择一天生效';
    if (_startHour == _endHour && _startMinute == _endMinute) return '开始时间和结束时间不能相同';
    
    // 检查时间范围是否合理（不超过24小时）
    final startMinutes = _startHour * 60 + _startMinute;
    var endMinutes = _endHour * 60 + _endMinute;
    
    // 如果结束时间小于开始时间，说明跨天，加24小时
    if (endMinutes <= startMinutes) {
      endMinutes += 24 * 60;
    }
    
    if ((endMinutes - startMinutes) > 24 * 60) return '时间范围不能超过24小时';
    
    return null; // 校验通过
  }

  /// P0-2.5: 保存（含校验反馈）
  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      Haptic.heavy();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final label = _labelController.text.trim();
      final schedule = GuardSchedule(
        id: widget.scheduleId != null ? int.tryParse(widget.scheduleId!) : DateTime.now().millisecondsSinceEpoch,
        label: label,
        startHour: _startHour,
        startMinute: _startMinute,
        endHour: _endHour,
        endMinute: _endMinute,
        daysOfWeek: _daysOfWeek,
      );

      if (widget.scheduleId != null) {
        await ref.read(schedulesProvider.notifier).update(schedule);
      } else {
        await ref.read(schedulesProvider.notifier).add(schedule);
      }

      if (mounted) {
        Haptic.success();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('计划已保存'), duration: Duration(seconds: 2)),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e'), duration: const Duration(seconds: 3)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvasParchment,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.canvasParchment,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.scheduleId != null ? '编辑计划' : '新建计划',
            style: AppTextStyles.title.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ink), onPressed: () => context.pop()),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, Color(0xFF0052A3)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ],
                      ),
                      child: const Text('保存', style: TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.w600)),
                    ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
        children: [
          // 计划名称
          TextField(
            controller: _labelController,
            decoration: InputDecoration(
              hintText: '如：睡眠锁机',
              hintStyle: AppTextStyles.body.copyWith(color: AppColors.inkMuted48),
            ),
            style: AppTextStyles.body.copyWith(color: AppColors.ink),
            onChanged: (_) => setState(() {}), // 触发重建以更新保存按钮状态
          ),
          const SizedBox(height: 24),

          // 时间段选择
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('时间段', style: AppTextStyles.title.copyWith(color: AppColors.ink)),
                  const SizedBox(height: 16),
                  _TimePickerRow(label: '开始时间', hour: _startHour, minute: _startMinute,
                      onHourChange: (v) { Haptic.tick(); setState(() => _startHour = v); },
                      onMinuteChange: (v) { Haptic.tick(); setState(() => _startMinute = v); }),
                  const Divider(color: AppColors.dividerSoft),
                  _TimePickerRow(label: '结束时间', hour: _endHour, minute: _endMinute,
                      onHourChange: (v) { Haptic.tick(); setState(() => _endHour = v); },
                      onMinuteChange: (v) { Haptic.tick(); setState(() => _endMinute = v); }),
                  if (_isCrossMidnight)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('跨天守护 · 次日 ${_pad(_endHour)}:${_pad(_endMinute)} 解锁',
                          style: AppTextStyles.label.copyWith(color: AppColors.warning)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 星期选择（含快捷按钮 P1）
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('生效日期', style: AppTextStyles.title.copyWith(color: AppColors.ink)),

                  // P1: 快捷按钮行
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _QuickChip(label: '全选', isSelected: _daysOfWeek == 127,
                          onTap: () { Haptic.select(); setState(() => _daysOfWeek = 127); }),
                      const SizedBox(width: 8),
                      _QuickChip(label: '工作日', isSelected: _daysOfWeek == 62,
                          onTap: () { Haptic.select(); setState(() => _daysOfWeek = 62); }),
                      const SizedBox(width: 8),
                      _QuickChip(label: '周末', isSelected: _daysOfWeek == 65,
                          onTap: () { Haptic.select(); setState(() => _daysOfWeek = 65); }),
                      const SizedBox(width: 8),
                      _QuickChip(label: '清除', isSelected: _daysOfWeek == 0,
                          onTap: () { Haptic.select(); setState(() => _daysOfWeek = 0); },
                              danger: true),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 星期圆圈选择器
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(7, (i) {
                      final selected = (_daysOfWeek & (1 << i)) != 0;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () { Haptic.select(); setState(() => _daysOfWeek ^= (1 << i)); },
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected ? AppColors.primary : AppColors.dividerSoft,
                            ),
                            child: Text(_dayLabels[i], style: AppTextStyles.body.copyWith(
                                color: selected ? AppColors.onPrimary : AppColors.inkMuted80)),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}

// === 快捷按钮 Chip ===
class _QuickChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool danger;

  const _QuickChip({required this.label, required this.isSelected, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: danger
                  ? (isSelected ? AppColors.danger : AppColors.hairline)
                  : (isSelected ? AppColors.primary : AppColors.hairline),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(8),
            color: danger
                ? (isSelected ? AppColors.danger.withValues(alpha: 0.08) : Colors.transparent)
                : (isSelected ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent),
          ),
          child: Text(label, style: AppTextStyles.caption.copyWith(
              color: danger
                  ? (isSelected ? AppColors.danger : AppColors.inkMuted48)
                  : (isSelected ? AppColors.primary : AppColors.inkMuted48),
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400)),
        ),
      ),
    );
  }
}

class _TimePickerRow extends StatelessWidget {
  final String label;
  final int hour, minute;
  final ValueChanged<int> onHourChange, onMinuteChange;

  const _TimePickerRow({required this.label, required this.hour, required this.minute,
      required this.onHourChange, required this.onMinuteChange});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.body.copyWith(color: AppColors.inkMuted48)),
        Row(children: [
          _NumberSpinner(value: hour, range: 24, onChange: onHourChange),
          Text(':', style: AppTextStyles.bodyBold.copyWith(color: AppColors.ink)),
          _NumberSpinner(value: minute, range: 60, onChange: onMinuteChange),
        ]),
      ],
    );
  }
}

class _NumberSpinner extends StatefulWidget {
  final int value, range;
  final ValueChanged<int> onChange;

  const _NumberSpinner({required this.value, required this.range, required this.onChange});

  @override
  State<_NumberSpinner> createState() => _NumberSpinnerState();
}

class _NumberSpinnerState extends State<_NumberSpinner> {
  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      onSelected: (v) { setState(() => _value = v); widget.onChange(v); },
      enabled: true,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      itemBuilder: (_) => List.generate(widget.range, (i) =>
          PopupMenuItem(value: i, child: Center(child: Text(i.toString().padLeft(2, '0'))))),
      child: OutlinedButton(
          onPressed: null,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.hairline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        child: Text(_value.toString().padLeft(2, '0'), style: AppTextStyles.bodyBold.copyWith(color: AppColors.ink)),
      ),
    );
  }
}
