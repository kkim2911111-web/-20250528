import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/staff_profile.dart';
import '../theme/danji_colors.dart';
import 'section_card.dart';

/// 차량 상세 — 실시간 위치 섹션 (단일 차량 또는 단지 전체)
class AdminVehicleLocationSection extends StatelessWidget {
  final AdminVehicleDetail? vehicle;
  final List<AdminReservationRow> operating;
  final DateFormat timeFormat;
  final bool compact;

  const AdminVehicleLocationSection({
    super.key,
    this.vehicle,
    required this.operating,
    required this.timeFormat,
    this.compact = false,
  });

  AdminReservationRow? _operatingForVehicle() {
    if (vehicle == null) return null;
    for (final r in operating) {
      if (r.vehicleName == vehicle!.name &&
          (vehicle!.carNumber == null || r.carNumber == vehicle!.carNumber)) {
        return r;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    final inUse = _operatingForVehicle();
    final hasCoords = v != null &&
        v.lastLatitude != null &&
        v.lastLongitude != null;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, color: DanjiColors.buttonBlue),
              const SizedBox(width: 8),
              Text(
                compact ? '실시간 위치' : '차량별 최근 위치',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (inUse != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '대여 중 · 임차인 ${inUse.renterDisplayName} · 예약 ${inUse.reservationNumberLabel}',
                style: const TextStyle(
                  color: Color(0xFFF97316),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ] else if (compact)
            const Text(
              '현재 대여 중이 아닙니다.',
              style: TextStyle(color: DanjiColors.textSecondary, fontSize: 13),
            ),
          if (v != null) ...[
            Text('주차: ${v.parkingLocation ?? '미등록'}'),
            if (hasCoords)
              Text(
                '좌표: ${v.lastLatitude!.toStringAsFixed(5)}, '
                '${v.lastLongitude!.toStringAsFixed(5)}',
              ),
            if (v.lastLocationUpdatedAt != null)
              Text(
                '갱신: ${timeFormat.format(v.lastLocationUpdatedAt!)}',
                style: const TextStyle(
                  color: DanjiColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            if (!hasCoords)
              const Text(
                'GPS 좌표 없음 — 주차 위치 기준으로 확인',
                style: TextStyle(
                  color: DanjiColors.textSecondary,
                  fontSize: 12,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
