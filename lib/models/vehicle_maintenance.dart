import 'package:flutter/material.dart';

enum VehicleMaintenanceType {
  wash,
  repair,
  inspection,
  other;

  String get dbValue => name;

  String get label {
    switch (this) {
      case VehicleMaintenanceType.wash:
        return '세차';
      case VehicleMaintenanceType.repair:
        return '정비';
      case VehicleMaintenanceType.inspection:
        return '점검';
      case VehicleMaintenanceType.other:
        return '기타';
    }
  }

  IconData get icon {
    switch (this) {
      case VehicleMaintenanceType.wash:
        return Icons.water_drop_outlined;
      case VehicleMaintenanceType.repair:
        return Icons.build_outlined;
      case VehicleMaintenanceType.inspection:
        return Icons.search;
      case VehicleMaintenanceType.other:
        return Icons.sticky_note_2_outlined;
    }
  }

  static VehicleMaintenanceType? fromDb(String? value) {
    switch (value) {
      case 'wash':
        return VehicleMaintenanceType.wash;
      case 'repair':
        return VehicleMaintenanceType.repair;
      case 'inspection':
        return VehicleMaintenanceType.inspection;
      case 'other':
        return VehicleMaintenanceType.other;
      default:
        return null;
    }
  }
}

class VehicleMaintenanceRecord {
  final String id;
  final VehicleMaintenanceType type;
  final String? description;
  final int? mileage;
  final int cost;
  final DateTime performedAt;
  final DateTime createdAt;

  const VehicleMaintenanceRecord({
    required this.id,
    required this.type,
    this.description,
    this.mileage,
    required this.cost,
    required this.performedAt,
    required this.createdAt,
  });

  factory VehicleMaintenanceRecord.fromMap(Map<String, dynamic> map) {
    return VehicleMaintenanceRecord(
      id: map['id']?.toString() ?? '',
      type: VehicleMaintenanceType.fromDb(map['maintenance_type']?.toString()) ??
          VehicleMaintenanceType.other,
      description: map['description']?.toString(),
      mileage: (map['mileage'] as num?)?.toInt(),
      cost: (map['cost'] as num?)?.toInt() ?? 0,
      performedAt: _parseDateTime(map['performed_at']) ?? DateTime.now(),
      createdAt: _parseDateTime(map['created_at']) ?? DateTime.now(),
    );
  }

  static DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw.toString());
  }
}
