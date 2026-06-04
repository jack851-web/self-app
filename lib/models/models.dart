class GuardSchedule {
  final int? id;
  final String label;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final int daysOfWeek; // bitmask: bit0=Sun, bit1=Mon, ..., bit6=Sat
  final bool enabled;
  final int createdAt;

  GuardSchedule({
    this.id,
    required this.label,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.daysOfWeek,
    this.enabled = true,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  GuardSchedule copyWith({
    int? id,
    String? label,
    int? startHour,
    int? startMinute,
    int? endHour,
    int? endMinute,
    int? daysOfWeek,
    bool? enabled,
    int? createdAt,
  }) {
    return GuardSchedule(
      id: id ?? this.id,
      label: label ?? this.label,
      startHour: startHour ?? this.startHour,
      startMinute: startMinute ?? this.startMinute,
      endHour: endHour ?? this.endHour,
      endMinute: endMinute ?? this.endMinute,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
        'daysOfWeek': daysOfWeek,
        'enabled': enabled,
        'createdAt': createdAt,
      };

  factory GuardSchedule.fromJson(Map<String, dynamic> json) => GuardSchedule(
        id: json['id'] as int?,
        label: json['label'] as String,
        startHour: json['startHour'] as int,
        startMinute: json['startMinute'] as int,
        endHour: json['endHour'] as int,
        endMinute: json['endMinute'] as int,
        daysOfWeek: json['daysOfWeek'] as int,
        enabled: json['enabled'] as bool? ?? true,
        createdAt: json['createdAt'] as int?,
      );

  String get timeRange => '${_pad(startHour)}:${_pad(startMinute)} – ${_pad(endHour)}:${_pad(endMinute)}';

  static String _pad(int n) => n.toString().padLeft(2, '0');
}

class BlocklistEntry {
  final String packageName;
  final String label;
  final int addedAt;

  BlocklistEntry({
    required this.packageName,
    required this.label,
    int? addedAt,
  }) : addedAt = addedAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {'packageName': packageName, 'label': label, 'addedAt': addedAt};
  factory BlocklistEntry.fromJson(Map<String, dynamic> json) => BlocklistEntry(
        packageName: json['packageName'] as String,
        label: json['label'] as String,
        addedAt: json['addedAt'] as int?,
      );
}

class GuardRecord {
  final int? id;
  final int startAt;
  final int endAt;
  final int durationMs;
  final String triggerType; // MANUAL | SCHEDULED
  final int? scheduleId;
  final int blockCount;

  const GuardRecord({
    this.id,
    required this.startAt,
    required this.endAt,
    required this.durationMs,
    required this.triggerType,
    this.scheduleId,
    this.blockCount = 0,
  });
}

class GuardState {
  final bool active;
  final int? startAt;  // 毫秒级时间戳 (millisecondsSinceEpoch)
  final int? endAt;    // 毫秒级时间戳 (millisecondsSinceEpoch)
  final String? triggerType; // MANUAL | SCHEDULED
  final int? scheduleId;

  const GuardState({
    this.active = false,
    this.startAt,
    this.endAt,
    this.triggerType,
    this.scheduleId,
  });

  /// 计算剩余秒数（基于当前时间与结束时间的差值）
  int get remainingSeconds {
    if (endAt == null) return 0;
    return (((endAt! - DateTime.now().millisecondsSinceEpoch) / 1000).round()).clamp(0, 999999);
  }
}
