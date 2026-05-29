import 'package:flutter/material.dart';

import '../models/vehicle.dart';
import '../theme/danji_colors.dart';

class VehicleCard extends StatelessWidget {
  final Vehicle vehicle;
  final bool showPhoto;
  final VoidCallback? onTap;

  const VehicleCard({
    super.key,
    required this.vehicle,
    this.showPhoto = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: DanjiColors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: DanjiColors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showPhoto) _ParkingPhoto(url: vehicle.parkingPhotoUrl),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                vehicle.name,
                                style: const TextStyle(
                                  color: DanjiColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                vehicle.vehicleType,
                                style: const TextStyle(
                                  color: DanjiColors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        VehicleAvailabilityBadge(isAvailable: vehicle.isAvailable),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.payments_outlined,
                            size: 18, color: DanjiColors.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          vehicle.priceLabel,
                          style: const TextStyle(
                            color: DanjiColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    if (vehicle.parkingLocation != null &&
                        vehicle.parkingLocation!.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.local_parking_outlined,
                              size: 18, color: DanjiColors.textSecondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              vehicle.parkingLocation!,
                              style: const TextStyle(
                                color: DanjiColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return card;
  }
}

class VehicleAvailabilityBadge extends StatelessWidget {
  final bool isAvailable;

  const VehicleAvailabilityBadge({super.key, required this.isAvailable});

  @override
  Widget build(BuildContext context) {
    final bg = isAvailable
        ? DanjiColors.buttonBlue.withValues(alpha: 0.12)
        : DanjiColors.border;
    final fg =
        isAvailable ? DanjiColors.buttonBlue : DanjiColors.textMuted;
    final label = isAvailable ? '예약가능' : '예약불가';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ParkingPhoto extends StatelessWidget {
  final String? url;

  const _ParkingPhoto({this.url});

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      color: DanjiColors.skyLight,
      child: SizedBox(
        height: 160,
        child: Center(
          child: Icon(Icons.photo_outlined,
              color: DanjiColors.textMuted, size: 40),
        ),
      ),
    );

    if (url == null || url!.trim().isEmpty) return placeholder;

    return SizedBox(
      height: 160,
      child: Image.network(
        url!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const ColoredBox(
            color: DanjiColors.skyLight,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
      ),
    );
  }
}
