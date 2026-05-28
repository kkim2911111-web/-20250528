import 'package:flutter/material.dart';

import '../widgets/danji_app_bar.dart';
import '../widgets/vehicle_list_view.dart';

class VehiclesScreen extends StatelessWidget {
  const VehiclesScreen({super.key});

  static const _bg = Color(0xFF071826);
  static const _textPrimary = Color(0xFFEAF2FF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: const DanjiAppBar(title: '차량 목록'),
      body: const VehicleListView(showPhoto: true),
    );
  }
}
