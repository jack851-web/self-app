import 'package:flutter/services.dart';

/// 统一触觉反馈封装
class Haptic {
  Haptic._();

  static void light() {
    HapticFeedback.lightImpact();
  }

  static void medium() {
    HapticFeedback.mediumImpact();
  }

  static void heavy() {
    HapticFeedback.heavyImpact();
  }

  static void select() {
    HapticFeedback.selectionClick();
  }

  static void tick() {
    // 轻微的点击反馈（使用轻量级冲击作为替代）
    HapticFeedback.selectionClick();
  }

  static void success() {
    // 成功反馈（使用中等冲击作为替代）
    HapticFeedback.mediumImpact();
  }
}
