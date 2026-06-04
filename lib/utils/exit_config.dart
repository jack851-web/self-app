/// 困难退出机制配置
class ExitConfig {
  ExitConfig._();

  /// 每步等待时间（秒）
  static const stepWaitSeconds = [15, 30, 45, 60, 10];

  /// 每步标题
  static const stepTitles = [
    '你确定要放弃吗？',
    '冷静期 · 请再思考',
    '最后的反悔机会',
    '警告：即将解除所有保护',
    '守护即将结束',
  ];

  /// 每步图标 emoji
  static const stepIcons = ['⚠️', '🛑', '🔄', '🔥', '👋'];

  /// 每步按钮文字
  static const stepButtonTexts = [
    '继续退出',
    '我仍要退出',
    '确认退出',
    '最终确认',
    '解除守护',
  ];

  /// 总步骤数
  static const totalSteps = 5;

  /// 总最短退出时间（秒）
  static int get totalMinWaitSeconds => stepWaitSeconds.reduce((a, b) => a + b);
}

/// 励志文案池（每步 8 条，随机轮换）
class ExitQuotes {
  ExitQuotes._();

  static const step1Quotes = [
    '现在的每一秒坚持，都在为未来的自由积累资本。',
    '你选择了开始，就一定有理由坚持下去。',
    '想想当初为什么要开启这个守护？',
    '再给自己 15 分钟，你会发现其实没那么难。',
    '你的目标值得你此刻的坚持。',
    '你已经迈出了最难的第一步，别在这里停下来。',
    '此刻的不适，正是成长的声音。',
    '你比自己想象的更有毅力。',
  ];

  static const step2Quotes = [
    '自律不是从不失败，而是每次跌倒后都重新站起来。',
    '冲动是魔鬼，让理智回来做决定。',
    '这个应用真的有那么重要吗？',
    '深呼吸三次，然后问自己：我现在真的需要退出吗？',
    '你已经坚持了这么久，不要让这几分钟白费。',
    '问问自己：退出之后我会做什么？还是打开那个应用吗？',
    '如果 30 分钟后你仍然想退出，那时候再退也不迟。',
    '把这次退出当作一次练习 — 练习不屈服于冲动。',
  ];

  static const step3Quotes = [
    '你已经坚持了很久，真的要前功尽弃吗？',
    '未来的你会感谢现在没有放弃的自己。',
    '每一次克制都是对意志力的训练。',
    '你不是在对抗手机，你是在成为更好的自己。',
    '想想那些因为自律而达成目标的人，你也可以。',
    '这长时间的付出，不应该就这样被抹去。',
    '你离完成这次守护只剩一小段路了。',
    '想象一下成功完成守护后的成就感 — 那种感觉值得你等待。',
  ];

  static const step4Quotes = [
    '真正的强者，是那些敢于直面诱惑并战胜它的人。',
    '一旦退出，所有的努力将从零开始。',
    '这是你最后的机会重新考虑。',
    '如果你确定要退出，请承担这个决定的后果。',
    '记住这一刻的感受，它将成为你下一次坚持的动力。',
    '大多数人的自律失败，就发生在「再坚持一下」的前一秒。',
    '你确定这个决定是出于理性，而非一时的软弱？',
    '退出很容易，但之后的愧疚感不会容易消散。',
  ];

  static const step5Quotes = [
    '下次再来的时候，你会更强大。我们等你。',
    '守护结束了，但自律的习惯可以继续。',
    '休息是为了走更远的路，下次见。',
    '感谢你今天的尝试，每一次努力都有意义。',
    '这不是失败，这是为下一次更好的准备。',
    '今天的坚持已经成为了你的一部分。',
    '好好休息，我们下次继续。',
    '无论结果如何，你今天已经比昨天的自己更好了。',
  ];

  /// 获取指定步骤的随机文案（排除已使用的索引）
  static String getRandomQuote(int step, Set<int> usedIndices) {
    final pool = _getPool(step);
    if (usedIndices.length >= pool.length) usedIndices.clear;
    int index;
    do {
      index = pool.length * DateTime.now().microsecond ~/ 1000000 % pool.length;
    } while (usedIndices.contains(index));
    usedIndices.add(index);
    return pool[index];
  }

  static List<String> _getPool(int step) {
    switch (step) {
      case 1: return step1Quotes;
      case 2: return step2Quotes;
      case 3: return step3Quotes;
      case 4: return step4Quotes;
      case 5: return step5Quotes;
      default: return step1Quotes;
    }
  }
}

/// 守护时长预设选项
class DurationPresets {
  DurationPresets._();

  static const presets = [
    _Preset(15, '15 分钟'),
    _Preset(25, '25 分钟'),
    _Preset(45, '45 分钟'),
    _Preset(60, '1 小时'),
    _Preset(120, '2 小时'),
  ];

  static const defaultMinutes = 25;
  static const minCustomMinutes = 5;
  static const maxCustomMinutes = 480; // 8小时
  static const customStepMinutes = 5;
}

class _Preset {
  final int minutes;
  final String label;
  const _Preset(this.minutes, this.label);
}
