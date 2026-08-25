import 'package:flutter/material.dart';

enum MetricType { reps, duration }

enum MovementCategory { strength, mobility }

enum MovementSide { left, right, both }

extension MetricTypeX on MetricType {
  String get storageValue => this == MetricType.reps ? 'reps' : 'duration';

  String get label => this == MetricType.reps ? 'Repetitions' : 'Duration';

  static MetricType fromStorage(String value) {
    return value == 'duration' ? MetricType.duration : MetricType.reps;
  }
}

extension MovementCategoryX on MovementCategory {
  String get label =>
      this == MovementCategory.strength ? 'Strength' : 'Mobility';
}

extension MovementSideX on MovementSide {
  String get storageValue => name;

  String get label => switch (this) {
    MovementSide.left => 'Left',
    MovementSide.right => 'Right',
    MovementSide.both => 'Both',
  };

  static MovementSide? fromStorage(String? value) {
    for (final side in MovementSide.values) {
      if (side.name == value) return side;
    }
    return null;
  }
}

class MovementDefinition {
  const MovementDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.metric,
    required this.icon,
    required this.color,
    required this.presets,
    this.supportsSides = false,
  });

  final String id;
  final String name;
  final String description;
  final MovementCategory category;
  final MetricType metric;
  final IconData icon;
  final Color color;
  final List<int> presets;
  final bool supportsSides;
}

abstract final class MovementCatalog {
  static const movements = <MovementDefinition>[
    MovementDefinition(
      id: 'squat',
      name: 'Squats',
      description: 'Legs & full body',
      category: MovementCategory.strength,
      metric: MetricType.reps,
      icon: Icons.accessibility_new_rounded,
      color: Color(0xFFC5F65A),
      presets: [10, 15, 20, 30],
    ),
    MovementDefinition(
      id: 'push_up',
      name: 'Push-ups',
      description: 'Chest, arms & core',
      category: MovementCategory.strength,
      metric: MetricType.reps,
      icon: Icons.fitness_center_rounded,
      color: Color(0xFF8BF17A),
      presets: [5, 10, 15, 20],
    ),
    MovementDefinition(
      id: 'wall_push_up',
      name: 'Wall push-ups',
      description: 'Low-impact upper body',
      category: MovementCategory.strength,
      metric: MetricType.reps,
      icon: Icons.vertical_align_center_rounded,
      color: Color(0xFF6BE7A7),
      presets: [10, 15, 20, 30],
    ),
    MovementDefinition(
      id: 'reverse_lunge',
      name: 'Reverse lunges',
      description: 'Legs, hips & balance',
      category: MovementCategory.strength,
      metric: MetricType.reps,
      icon: Icons.directions_walk_rounded,
      color: Color(0xFFE0EE64),
      presets: [6, 10, 12, 16],
    ),
    MovementDefinition(
      id: 'calf_raise',
      name: 'Calf raises',
      description: 'Lower-leg strength',
      category: MovementCategory.strength,
      metric: MetricType.reps,
      icon: Icons.height_rounded,
      color: Color(0xFFA9EC6B),
      presets: [10, 15, 20, 30],
    ),
    MovementDefinition(
      id: 'glute_bridge',
      name: 'Glute bridges',
      description: 'Hips, glutes & core',
      category: MovementCategory.strength,
      metric: MetricType.reps,
      icon: Icons.airline_seat_flat_rounded,
      color: Color(0xFF95E888),
      presets: [10, 15, 20, 25],
    ),
    MovementDefinition(
      id: 'hand_grip',
      name: 'Hand grip',
      description: 'Grip & forearm strength',
      category: MovementCategory.strength,
      metric: MetricType.reps,
      icon: Icons.pan_tool_alt_rounded,
      color: Color(0xFFD4F35C),
      presets: [10, 20, 30, 50],
      supportsSides: true,
    ),
    MovementDefinition(
      id: 'arm_circle',
      name: 'Arm circles',
      description: 'Shoulder activation',
      category: MovementCategory.strength,
      metric: MetricType.reps,
      icon: Icons.rotate_right_rounded,
      color: Color(0xFF72E5A4),
      presets: [10, 20, 30, 40],
    ),
    MovementDefinition(
      id: 'plank',
      name: 'Plank',
      description: 'Core stability',
      category: MovementCategory.strength,
      metric: MetricType.duration,
      icon: Icons.horizontal_rule_rounded,
      color: Color(0xFFB5EF61),
      presets: [15, 30, 45, 60],
    ),
    MovementDefinition(
      id: 'wall_sit',
      name: 'Wall sit',
      description: 'Leg endurance',
      category: MovementCategory.strength,
      metric: MetricType.duration,
      icon: Icons.airline_seat_recline_normal_rounded,
      color: Color(0xFF98E775),
      presets: [15, 30, 45, 60],
    ),
    MovementDefinition(
      id: 'chest_stretch',
      name: 'Doorway chest',
      description: 'Open chest & shoulders',
      category: MovementCategory.mobility,
      metric: MetricType.duration,
      icon: Icons.open_in_full_rounded,
      color: Color(0xFF4FE1C1),
      presets: [15, 30, 45, 60],
    ),
    MovementDefinition(
      id: 'shoulder_stretch',
      name: 'Shoulder stretch',
      description: 'Cross-body release',
      category: MovementCategory.mobility,
      metric: MetricType.duration,
      icon: Icons.swap_horiz_rounded,
      color: Color(0xFF58D7D0),
      presets: [15, 30, 45, 60],
      supportsSides: true,
    ),
    MovementDefinition(
      id: 'triceps_stretch',
      name: 'Triceps stretch',
      description: 'Arms & shoulders',
      category: MovementCategory.mobility,
      metric: MetricType.duration,
      icon: Icons.arrow_upward_rounded,
      color: Color(0xFF65D5E4),
      presets: [15, 30, 45, 60],
      supportsSides: true,
    ),
    MovementDefinition(
      id: 'wrist_stretch',
      name: 'Wrist & forearm',
      description: 'Desk-hand release',
      category: MovementCategory.mobility,
      metric: MetricType.duration,
      icon: Icons.back_hand_rounded,
      color: Color(0xFF5CDBC1),
      presets: [15, 30, 45, 60],
      supportsSides: true,
    ),
    MovementDefinition(
      id: 'neck_stretch',
      name: 'Neck side stretch',
      description: 'Neck & upper traps',
      category: MovementCategory.mobility,
      metric: MetricType.duration,
      icon: Icons.face_rounded,
      color: Color(0xFF6ED9C7),
      presets: [15, 30, 45, 60],
      supportsSides: true,
    ),
    MovementDefinition(
      id: 'upper_back_stretch',
      name: 'Upper-back stretch',
      description: 'Posture reset',
      category: MovementCategory.mobility,
      metric: MetricType.duration,
      icon: Icons.sync_alt_rounded,
      color: Color(0xFF48D8AD),
      presets: [20, 30, 45, 60],
    ),
    MovementDefinition(
      id: 'hip_flexor_stretch',
      name: 'Hip-flexor stretch',
      description: 'Undo prolonged sitting',
      category: MovementCategory.mobility,
      metric: MetricType.duration,
      icon: Icons.airline_seat_recline_extra_rounded,
      color: Color(0xFF4FD8D2),
      presets: [20, 30, 45, 60],
      supportsSides: true,
    ),
    MovementDefinition(
      id: 'hamstring_stretch',
      name: 'Hamstring stretch',
      description: 'Back-of-leg mobility',
      category: MovementCategory.mobility,
      metric: MetricType.duration,
      icon: Icons.expand_rounded,
      color: Color(0xFF60D3DC),
      presets: [20, 30, 45, 60],
      supportsSides: true,
    ),
  ];

  static const quickIds = [
    'squat',
    'push_up',
    'hand_grip',
    'plank',
    'shoulder_stretch',
    'hip_flexor_stretch',
  ];

  static MovementDefinition byId(String id) {
    return movements.firstWhere(
      (movement) => movement.id == id,
      orElse: () => MovementDefinition(
        id: id,
        name: 'Movement',
        description: 'Saved activity',
        category: MovementCategory.mobility,
        metric: MetricType.reps,
        icon: Icons.self_improvement_rounded,
        color: const Color(0xFF74DEC4),
        presets: const [5, 10, 15, 20],
      ),
    );
  }

  static List<MovementDefinition> get quickMovements =>
      quickIds.map(byId).toList();
}

class MovementLog {
  const MovementLog({
    this.id,
    required this.movementId,
    required this.metric,
    required this.amount,
    this.side,
    this.note,
    required this.performedAt,
    required this.createdAt,
  });

  final int? id;
  final String movementId;
  final MetricType metric;
  final int amount;
  final MovementSide? side;
  final String? note;
  final DateTime performedAt;
  final DateTime createdAt;

  MovementDefinition get movement => MovementCatalog.byId(movementId);

  Map<String, Object?> toDatabaseMap() => {
    'movement_id': movementId,
    'metric': metric.storageValue,
    'amount': amount,
    'side': side?.storageValue,
    'note': note?.trim().isEmpty == true ? null : note?.trim(),
    'performed_at': performedAt.millisecondsSinceEpoch,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory MovementLog.fromDatabase(Map<String, Object?> map) {
    return MovementLog(
      id: map['id'] as int,
      movementId: map['movement_id'] as String,
      metric: MetricTypeX.fromStorage(map['metric'] as String),
      amount: map['amount'] as int,
      side: MovementSideX.fromStorage(map['side'] as String?),
      note: map['note'] as String?,
      performedAt: DateTime.fromMillisecondsSinceEpoch(
        map['performed_at'] as int,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  MovementLog copyWith({
    int? id,
    String? movementId,
    MetricType? metric,
    int? amount,
    MovementSide? side,
    bool clearSide = false,
    String? note,
    DateTime? performedAt,
    DateTime? createdAt,
  }) {
    return MovementLog(
      id: id ?? this.id,
      movementId: movementId ?? this.movementId,
      metric: metric ?? this.metric,
      amount: amount ?? this.amount,
      side: clearSide ? null : (side ?? this.side),
      note: note ?? this.note,
      performedAt: performedAt ?? this.performedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

String formatAmount(MetricType metric, int amount) {
  if (metric == MetricType.reps) {
    return '$amount ${amount == 1 ? 'rep' : 'reps'}';
  }
  if (amount < 60) return '$amount sec';
  final minutes = amount ~/ 60;
  final seconds = amount % 60;
  return seconds == 0 ? '$minutes min' : '${minutes}m ${seconds}s';
}

String formatCompactDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return remainder == 0 ? '${minutes}m' : '${minutes}m ${remainder}s';
}
