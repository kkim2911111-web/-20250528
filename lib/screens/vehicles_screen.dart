import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import '../widgets/danji_app_bar.dart';
import '../widgets/vehicle_list_view.dart';

class VehiclesScreen extends StatelessWidget {
  const VehiclesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '차량 목록'),
      body: const VehicleListView(showPhoto: true),
    );
  }
}
