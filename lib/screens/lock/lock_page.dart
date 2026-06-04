import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../utils/haptic.dart';
import '../../utils/exit_config.dart';

class LockPage extends ConsumerStatefulWidget {
  const LockPage({super.key});

  @override
  ConsumerState<LockPage> createState() => _LockPageState();
}

class _LockPageState extends ConsumerState<LockPage> with WidgetsBindingObserver {
  Timer? _relockTimer;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  // === 困难退出机制状态 ===
  int _exitStep = 0;
  int _countdownRemaining = 0;
  Timer? _exitCountdownTimer;
  final Set<int> _usedQuoteIndices = {};
  String _currentQuote = '';
  bool _isExitDialogShowing = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    WidgetsBinding.instance.addObserver(this);
    _startCountdown();
  }

  void _startCountdown() {
    // 先取消可能存在的旧Timer
    _countdownTimer?.cancel();
    _countdownTimer = null;

    final guardState = ref.read(guardStateProvider);
    if (guardState.triggerType == 'MANUAL' && guardState.endAt != null) {
      _updateRemaining(guardState.endAt!);
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          // 如果组件已销毁，立即停止定时器
          _countdownTimer?.cancel();
          _countdownTimer = null;
          return;
        }
        final state = ref.read(guardStateProvider);
        if (!state.active) {
          _countdownTimer?.cancel();
          _countdownTimer = null;
          Navigator.of(context).pop(true);
          return;
        }
        if (state.endAt != null) _updateRemaining(state.endAt!);
      });
    }
  }

  void _updateRemaining(int endAtMs) {
    final remaining = ((endAtMs - DateTime.now().millisecondsSinceEpoch) / 1000).round().clamp(0, 999999);
    if (remaining != _remainingSeconds) setState(() => _remainingSeconds = remaining);
  }

  // === P0-2.2: 启动退出流程 ===
  void _startExitFlow() {
    Haptic.heavy();
    final guardState = ref.read(guardStateProvider);

    // 定时模式：先显示前置信息页
    if (guardState.triggerType == 'SCHEDULED') {
      setState(() {
        _exitStep = -1; // 特殊状态：前置信息页
        _isExitDialogShowing = true;
      });
      return;
    }

    // 手动模式：直接进入第1步
    setState(() {
      _exitStep = 1;
      _countdownRemaining = ExitConfig.stepWaitSeconds[0];
      _currentQuote = ExitQuotes.getRandomQuote(1, _usedQuoteIndices);
      _isExitDialogShowing = true;
    });
    _runExitStepCountdown();
  }

  /// 运行当前步骤的倒计时
  void _runExitStepCountdown() {
    _exitCountdownTimer?.cancel();
    _exitCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_countdownRemaining > 0) {
        setState(() => _countdownRemaining--);
      }
    });
  }

  /// 用户点击当前步骤的「继续」按钮
  void _onExitStepContinue() {
    if (_countdownRemaining > 0) {
      // 倒计时未结束，点击无效 + 轻微震动
      Haptic.light();
      return;
    }

    Haptic.select();

    if (_exitStep < ExitConfig.totalSteps) {
      // 进入下一步
      setState(() {
        _exitStep++;
        _countdownRemaining = ExitConfig.stepWaitSeconds[_exitStep - 1];
        _currentQuote = ExitQuotes.getRandomQuote(_exitStep, _usedQuoteIndices);
      });
      _runExitStepCountdown();
    } else {
      // 全部完成 → 结束守护
      _completeExit();
    }
  }

  /// 返回守护（重置退出流程）
  void _returnToGuard() {
    Haptic.light();
    _exitCountdownTimer?.cancel();
    setState(() {
      _exitStep = 0;
      _countdownRemaining = 0;
      _isExitDialogShowing = false;
      _usedQuoteIndices.clear();
    });
  }

  /// 从前置信息页进入强制退出流程
  void _onForceExit() {
    Haptic.heavy();
    setState(() {
      _exitStep = 1; // 进入第1步
      _countdownRemaining = ExitConfig.stepWaitSeconds[0];
      _currentQuote = ExitQuotes.getRandomQuote(1, _usedQuoteIndices);
    });
    _runExitStepCountdown();
  }

  /// 完成全部退出步骤，结束守护
  Future<void> _completeExit() async {
    _exitCountdownTimer?.cancel();
    try {
      await ref.read(guardStateProvider.notifier).stop();
    } catch (e) {
      debugPrint('结束守护失败: $e');
    }
    if (!mounted) return;

    // 显示守护结束总结页
    setState(() {
      _exitStep = 99; // 特殊状态：已结束
      _isExitDialogShowing = false;
    });

    // 3 秒后自动返回首页
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  /// 格式化已坚持时长
  String _formatDurationMs(int startAtMs) {
    final elapsed = DateTime.now().millisecondsSinceEpoch - startAtMs;
    if (elapsed < 0) return '0分0秒';
    final mins = elapsed ~/ 60000;
    final secs = (elapsed % 60000) ~/ 1000;
    return '${mins > 0 ? '$mins分' : ''}$secs秒';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // 用户尝试切走，立即拉回并惩罚
      _relockTimer?.cancel();
      _relockTimer = Timer(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        // 强制拉回前台
        try {
          const MethodChannel('com.selfapp/native').invokeMethod('bringToFront');
        } catch (_) {}
        // 重置退出步骤作为惩罚
        Haptic.heavy();
        setState(() {
          _exitStep = 0;
          _exitCountdownTimer?.cancel();
          _exitCountdownTimer = null;
          _countdownRemaining = 0;
          _isExitDialogShowing = false;
        });
      });
    } else if (state == AppLifecycleState.resumed) {
      _relockTimer?.cancel();
      _relockTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final guardState = ref.watch(guardStateProvider);

    // 守护已结束状态
    if (_exitStep == 99 || !guardState.active) {
      return _buildEndedScreen(guardState);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // 用户尝试退出，重置困难退出步骤并给予惩罚
        Haptic.heavy();
        setState(() {
          _exitStep = 0;
          _exitCountdownTimer?.cancel();
          _exitCountdownTimer = null;
          _countdownRemaining = 0;
          _isExitDialogShowing = false;
        });
        // 显示Toast提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('请勿尝试跳过自律！退出步骤已重置', textAlign: TextAlign.center),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0C),
        body: Stack(
          children: [
            // 背景装饰
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primaryOnDark.withValues(alpha: 0.08),
                      AppColors.surfaceBlack,
                    ],
                    center: Alignment.topCenter,
                    radius: 1.2,
                  ),
                ),
              ),
            ),

            // 主锁屏内容
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!guardState.active) ...[
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.success.withValues(alpha: 0.15),
                            border: Border.all(color: AppColors.success.withValues(alpha: 0.3), width: 2),
                          ),
                          child: Icon(Icons.check_rounded, size: 48, color: AppColors.success),
                        ),
                        const SizedBox(height: 24),
                        Text('守护已结束', style: AppTextStyles.displayLg.copyWith(color: AppColors.onDark)),
                      ] else ...[
                        // 守护图标
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AppColors.primaryOnDark.withValues(alpha: 0.2),
                                AppColors.primaryOnDark.withValues(alpha: 0.05),
                              ],
                            ),
                            border: Border.all(
                              color: AppColors.primaryOnDark.withValues(alpha: 0.4),
                              width: 2,
                            ),
                          ),
                          child: Icon(Icons.shield, size: 48, color: AppColors.primaryOnDark),
                        ),

                        const SizedBox(height: 32),

                        // 核心显示区域
                        if (guardState.triggerType == 'MANUAL') ...[
                          Text(_formatCountdown(_remainingSeconds),
                              style: AppTextStyles.heroDisplay.copyWith(
                                color: AppColors.primaryOnDark,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              )),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primaryOnDark.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('手动守护中', style: AppTextStyles.caption.copyWith(color: AppColors.primaryOnDark)),
                          ),
                        ] else if (guardState.triggerType == 'SCHEDULED') ...[
                          Builder(builder: (ctx) {
                            final schedule = ref.watch(schedulesProvider)
                                .where((s) => s.id == guardState.scheduleId).firstOrNull;
                            return Column(children: [
                              Text('定时守护中',
                                  style: AppTextStyles.heroDisplay.copyWith(
                                    color: AppColors.primaryOnDark,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                  )),
                              if (schedule != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryOnDark.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text('「${schedule.label}」',
                                      style: AppTextStyles.bodyBold.copyWith(color: AppColors.bodyMuted)),
                                ),
                                const SizedBox(height: 6),
                                Text(schedule.timeRange,
                                    style: AppTextStyles.caption.copyWith(color: AppColors.bodyMuted.withValues(alpha: 0.7))),
                              ],
                            ]);
                          }),
                        ],

                        const SizedBox(height: 24),

                        Text('受保护的应用已锁定',
                            style: AppTextStyles.body.copyWith(
                              color: AppColors.bodyMuted,
                              letterSpacing: 0.3,
                            )),

                        const SizedBox(height: 32),

                        // 状态指示器
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.success,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.success.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                  )
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text('守护进行中 · 请专注当前任务',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.bodyMuted.withValues(alpha: 0.7),
                                  letterSpacing: 0.3,
                                )),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                ),
              ),

            // 底部退出按钮
            if (guardState.active && _exitStep == 0 && !_isExitDialogShowing)
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.of(context).padding.bottom + 24,
                child: Center(
                  child: GestureDetector(
                    onTap: _startExitFlow,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 12),
                      child: Text('退出守护',
                          style: AppTextStyles.finePrint.copyWith(
                              color: AppColors.bodyMuted.withValues(alpha: 0.4),
                              letterSpacing: 0.5)),
                    ),
                  ),
                ),
              ),

            // P0-2.2: 定时模式前置信息页
            if (_isExitDialogShowing && _exitStep == -1)
              _ScheduledModeInfoDialog(
                guardState: guardState,
                onWaitForSchedule: _returnToGuard,
                onForceExit: _onForceExit,
              ),

            // P0-2.2: 退出确认弹窗
            if (_isExitDialogShowing && _exitStep >= 1 && _exitStep <= ExitConfig.totalSteps)
              _ExitConfirmationDialog(
                step: _exitStep,
                totalSteps: ExitConfig.totalSteps,
                countdownRemaining: _countdownRemaining,
                totalWaitSeconds: ExitConfig.stepWaitSeconds[_exitStep - 1],
                title: ExitConfig.stepTitles[_exitStep - 1],
                icon: ExitConfig.stepIcons[_exitStep - 1],
                quote: _currentQuote,
                buttonText: ExitConfig.stepButtonTexts[_exitStep - 1],
                guardStartAt: guardState.startAt ?? 0,
                isLastStep: _exitStep == ExitConfig.totalSteps,
                onContinue: _onExitStepContinue,
                onReturnToGuard: _returnToGuard,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndedScreen(GuardState guardState) {
    return PopScope(
      canPop: false, // 防止返回键关闭结束页
      child: Scaffold(
      backgroundColor: AppColors.surfaceBlack,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline, size: 64, color: AppColors.success),
              const SizedBox(height: 24),
              Text('守护已结束', style: AppTextStyles.displayLg.copyWith(color: AppColors.onDark)),
              const SizedBox(height: 12),
              if (guardState.startAt != null)
                Text('本次守护时长：${_formatDurationMs(guardState.startAt!)}',
                    style: AppTextStyles.body.copyWith(color: AppColors.bodyMuted)),
              const SizedBox(height: 8),
              Text('坚持就是胜利，下次继续加油！',
                  style: AppTextStyles.caption.copyWith(color: AppColors.bodyMuted.withValues(alpha: 0.6))),
              const SizedBox(height: 40),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryOnDark,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                ),
                child: const Text('返回首页', style: TextStyle(color: AppColors.surfaceBlack, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
      ), // Close PopScope
    );
  }

  String _formatCountdown(int totalSecs) {
    final hours = totalSecs ~/ 3600;
    final minutes = (totalSecs % 3600) ~/ 60;
    final seconds = totalSecs % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _relockTimer?.cancel();
    _countdownTimer?.cancel();
    _exitCountdownTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

// === P0-2.2: 退出确认弹窗组件 ===
class _ExitConfirmationDialog extends StatelessWidget {
  final int step;
  final int totalSteps;
  final int countdownRemaining;
  final int totalWaitSeconds;
  final String title;
  final String icon;
  final String quote;
  final String buttonText;
  final int guardStartAt;
  final bool isLastStep;
  final VoidCallback onContinue;
  final VoidCallback onReturnToGuard;

  const _ExitConfirmationDialog({
    required this.step,
    required this.totalSteps,
    required this.countdownRemaining,
    required this.totalWaitSeconds,
    required this.title,
    required this.icon,
    required this.quote,
    required this.buttonText,
    required this.guardStartAt,
    required this.isLastStep,
    required this.onContinue,
    required this.onReturnToGuard,
  });

  bool get _canTap => countdownRemaining <= 0;

  Color get _stepColor {
    if (step <= 2) return AppColors.warning;
    if (step <= 3) return AppColors.primary;
    return AppColors.danger;
  }

  Color get _buttonColor {
    if (isLastStep) return AppColors.primary;
    if (step >= 4) return AppColors.danger;
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final displayQuote = quote.contains('{duration}')
        ? quote.replaceAll('{duration}', _elapsedString())
        : quote;

    return Center(
      child: Material(
        color: Colors.black.withValues(alpha: 0.7),
        child: Container(
          width: MediaQuery.of(context).size.width - 48,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.canvas, AppColors.surfacePearl],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部：返回链接 + 进度
              Row(
                children: [
                  GestureDetector(
                    onTap: onReturnToGuard,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.dividerSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_rounded, size: 16, color: AppColors.inkMuted80),
                          const SizedBox(width: 4),
                          Text('返回', style: AppTextStyles.caption.copyWith(color: AppColors.inkMuted80)),
                        ],
                      ),
                    ),
                  ),
                  Expanded(child: Container()),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _stepColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$step / $totalSteps',
                        style: AppTextStyles.captionBold.copyWith(color: _stepColor)),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // 进度条
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: step / totalSteps,
                  backgroundColor: AppColors.dividerSoft,
                  valueColor: AlwaysStoppedAnimation<Color>(_stepColor),
                  minHeight: 5,
                ),
              ),

              const SizedBox(height: 28),

              // 图标
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _stepColor.withValues(alpha: 0.1),
                  boxShadow: [
                    BoxShadow(
                      color: _stepColor.withValues(alpha: 0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    )
                  ],
                ),
                child: Center(child: Text(icon, style: const TextStyle(fontSize: 36))),
              ),

              const SizedBox(height: 16),

              // 标题
              Text(title,
                  style: AppTextStyles.title.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center),

              const SizedBox(height: 16),

              // 励志文案
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.canvasParchment.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(displayQuote,
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.inkMuted80,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
              ),

              const SizedBox(height: 28),

              // 操作按钮
              _buildActionButton(),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    final enabled = _canTap;
    final label = enabled ? buttonText : '$buttonText (${countdownRemaining}s)';

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: enabled ? onContinue : null,
        style: FilledButton.styleFrom(
          backgroundColor: enabled ? _buttonColor : AppColors.dividerSoft,
          disabledBackgroundColor: AppColors.dividerSoft,
          foregroundColor: enabled
              ? (isLastStep ? AppColors.onPrimary : AppColors.primary)
              : AppColors.inkMuted48,
          side: !enabled || !isLastStep
              ? (step < 4 ? BorderSide(color: _stepColor, width: 1) : null)
              : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label,
            style: TextStyle(
              color: enabled
                  ? (isLastStep ? AppColors.onPrimary : _buttonColor)
                  : AppColors.inkMuted48,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            )),
      ),
    );
  }

  String _elapsedString() {
    final elapsed = DateTime.now().millisecondsSinceEpoch - guardStartAt;
    if (elapsed < 0) return '0分0秒';
    final mins = elapsed ~/ 60000;
    final secs = (elapsed % 60000) ~/ 1000;
    return '${mins > 0 ? '$mins分' : ''}$secs秒';
  }
}

// === P0-2.2: 定时模式前置信息页 ===
class _ScheduledModeInfoDialog extends ConsumerWidget {
  final GuardState guardState;
  final VoidCallback onWaitForSchedule;
  final VoidCallback onForceExit;

  const _ScheduledModeInfoDialog({
    required this.guardState,
    required this.onWaitForSchedule,
    required this.onForceExit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 获取计划信息
    final endAt = guardState.endAt;
    final scheduleId = guardState.scheduleId;

    // 获取计划名称
    String? scheduleLabel;
    if (scheduleId != null) {
      final schedules = ref.watch(schedulesProvider);
      final schedule = schedules.where((s) => s.id == scheduleId).firstOrNull;
      scheduleLabel = schedule?.label;
    }

    return Center(
      child: Material(
        color: Colors.black54,
        child: Container(
          width: MediaQuery.of(context).size.width - 48,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 图标
              const Text('ℹ️', style: TextStyle(fontSize: 40)),

              const SizedBox(height: 16),

              // 标题
              Text('当前为定时守护模式',
                  style: AppTextStyles.title.copyWith(color: AppColors.ink),
                  textAlign: TextAlign.center),

              const SizedBox(height: 20),

              // 计划详情
              Column(
                children: [
                  if (scheduleLabel != null) ...[
                    Text('计划名称：「$scheduleLabel」',
                        style: AppTextStyles.bodyBold.copyWith(color: AppColors.ink)),
                    const SizedBox(height: 8),
                  ],
                  if (endAt != null) ...[
                    Text('预计结束时间：${_formatEndTime(endAt)}',
                        style: AppTextStyles.body.copyWith(color: AppColors.inkMuted80)),
                    const SizedBox(height: 12),
                  ],
                  Text('如果只是暂时需要用手机，\n建议等到定时结束后自动解锁。',
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.inkMuted48,
                          height: 1.5),
                      textAlign: TextAlign.center),
                ],
              ),

              const SizedBox(height: 28),

              // 操作按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onWaitForSchedule,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.hairline),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('等待定时结束',
                          style: TextStyle(color: AppColors.inkMuted48)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: onForceExit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('强制退出 >',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatEndTime(int endAtMs) {
    final endTime = DateTime.fromMillisecondsSinceEpoch(endAtMs);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDay = DateTime(endTime.year, endTime.month, endTime.day);

    final timeStr = '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';

    if (endDay == today) {
      return '今天 $timeStr';
    } else if (endDay == today.add(const Duration(days: 1))) {
      return '明天 $timeStr';
    } else {
      return '${endTime.month}月${endTime.day}日 $timeStr';
    }
  }
}
