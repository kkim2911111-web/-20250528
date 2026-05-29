import 'package:flutter/material.dart';

import 'screens/reservation_screen.dart';
import 'theme/danji_colors.dart';
import 'widgets/danji_app_bar.dart';
import 'widgets/vehicle_list_view.dart';

class ReservationsScreen extends StatelessWidget {
  const ReservationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '차량 예약'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '우리 단지 공용차',
                  style: TextStyle(
                    color: DanjiColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '예약할 차량을 선택하세요.',
                  style: TextStyle(
                    color: DanjiColors.textSecondary.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: VehicleListView(
              onVehicleTap: (vehicle) {
                if (!vehicle.isAvailable) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('현재 예약할 수 없는 차량입니다.')),
                  );
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReservationScreen(vehicle: vehicle),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
