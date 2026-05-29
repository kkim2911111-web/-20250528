import 'package:flutter/material.dart';

import '../models/vehicle.dart';
import '../models/vehicle_query_result.dart';
import '../services/vehicle_service.dart';
import '../theme/danji_colors.dart';
import 'vehicle_card.dart';

class VehicleListView extends StatefulWidget {
  final bool showPhoto;
  final void Function(Vehicle vehicle)? onVehicleTap;

  const VehicleListView({
    super.key,
    this.showPhoto = false,
    this.onVehicleTap,
  });

  @override
  State<VehicleListView> createState() => _VehicleListViewState();
}

class _VehicleListViewState extends State<VehicleListView> {
  final _service = VehicleService();
  late Future<VehicleQueryResult> _vehiclesFuture;

  @override
  void initState() {
    super.initState();
    _vehiclesFuture = _service.fetchVehiclesForMyComplex();
  }

  Future<void> _reload() async {
    setState(() {
      _vehiclesFuture = _service.fetchVehiclesForMyComplex();
    });
    await _vehiclesFuture;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: DanjiColors.buttonBlue,
      backgroundColor: DanjiColors.surface,
      onRefresh: _reload,
      child: FutureBuilder<VehicleQueryResult>(
        future: _vehiclesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                Icon(Icons.error_outline, color: DanjiColors.accentRed, size: 48),
                const SizedBox(height: 12),
                Text(
                  '차량 목록을 불러오지 못했습니다.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: DanjiColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            );
          }

          final result = snapshot.data!;
          final vehicles = result.vehicles;

          if (vehicles.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 32),
                const Icon(Icons.directions_car_outlined,
                    color: DanjiColors.textSecondary, size: 56),
                const SizedBox(height: 16),
                Text(
                  result.issue == VehicleLoadIssue.none
                      ? '등록된 차량이 없습니다'
                      : '차량을 불러올 수 없습니다',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: DanjiColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  result.emptyMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: DanjiColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            );
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: vehicles.length + (result.complexName != null ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (result.complexName != null && index == 0) {
                return Text(
                  '${result.complexName} 공용차',
                  style: const TextStyle(
                    color: DanjiColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                );
              }
              final vehicle = vehicles[result.complexName != null ? index - 1 : index];
              return VehicleCard(
                vehicle: vehicle,
                showPhoto: widget.showPhoto,
                onTap: widget.onVehicleTap != null
                    ? () => widget.onVehicleTap!(vehicle)
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
