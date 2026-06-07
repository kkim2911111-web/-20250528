import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../theme/danji_theme.dart';
import '../../widgets/section_card.dart';
import 'super_admin_nav.dart';

abstract final class SuperAdminUiColors {
  static const totalBlue = Color(0xFF3182F6);
  static const availableGreen = Color(0xFF22C55E);
  static const inUseOrange = Color(0xFFF97316);
  static const todayPurple = Color(0xFFA855F7);
  static const staffViolet = Color(0xFF8B5CF6);
  static const residentTeal = Color(0xFF14B8A6);
  static const revenueSky = Color(0xFF0EA5E9);
}

final superAdminWon = NumberFormat('#,###');
final superAdminDateTime = DateFormat('yyyy-MM-dd HH:mm');
final superAdminDateLine = DateFormat('M월 d일 (E)', 'ko_KR');

class SuperAdminSectionTitle extends StatelessWidget {
  final String title;

  const SuperAdminSectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: DanjiColors.textPrimary,
        fontWeight: FontWeight.w800,
        fontSize: 18,
      ),
    );
  }
}

class SuperAdminCompactStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const SuperAdminCompactStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: DanjiColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SuperAdminMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const SuperAdminMenuTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: DanjiColors.buttonBlue, size: 28),
          title: Text(
            title,
            style: const TextStyle(
              color: DanjiColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(color: DanjiColors.textSecondary),
          ),
          trailing: const Icon(Icons.chevron_right, color: DanjiColors.textMuted),
          onTap: onTap,
        ),
      ),
    );
  }
}

class SuperAdminListCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SuperAdminListCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: DanjiColors.buttonBlue, size: 26),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: DanjiColors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: DanjiColors.textSecondary,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        trailing: trailing ??
            (onTap != null
                ? const Icon(Icons.chevron_right, color: DanjiColors.textMuted)
                : null),
        onTap: onTap,
      ),
    );
  }
}

class SuperAdminChip extends StatelessWidget {
  final String label;
  final Color color;

  const SuperAdminChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class SuperAdminMonthFilter extends StatelessWidget {
  final int year;
  final int month;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<int> onMonthChanged;

  const SuperAdminMonthFilter({
    super.key,
    required this.year,
    required this.month,
    required this.onYearChanged,
    required this.onMonthChanged,
  });

  void _shift(int delta) {
    var y = year;
    var m = month + delta;
    while (m < 1) {
      m += 12;
      y--;
    }
    while (m > 12) {
      m -= 12;
      y++;
    }
    if (y != year) onYearChanged(y);
    onMonthChanged(m);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final canGoNext = year < now.year || (year == now.year && month < now.month);

    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _shift(-1),
            icon: const Icon(Icons.chevron_left_rounded),
            color: DanjiColors.buttonBlue,
          ),
          Expanded(
            child: Text(
              '$year년 $month월',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: DanjiColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: canGoNext ? () => _shift(1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
            color: canGoNext ? DanjiColors.buttonBlue : DanjiColors.textMuted,
          ),
        ],
      ),
    );
  }
}

class SuperAdminVehicleFilterBar extends StatelessWidget {
  final SuperAdminVehicleFilter selected;
  final ValueChanged<SuperAdminVehicleFilter> onChanged;

  const SuperAdminVehicleFilterBar({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(6),
      child: SegmentedButton<SuperAdminVehicleFilter>(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        segments: const [
          ButtonSegment(value: SuperAdminVehicleFilter.all, label: Text('전체')),
          ButtonSegment(
            value: SuperAdminVehicleFilter.available,
            label: Text('가용'),
          ),
          ButtonSegment(
            value: SuperAdminVehicleFilter.inUse,
            label: Text('대여중'),
          ),
        ],
        selected: {selected},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class SuperAdminEmptyState extends StatelessWidget {
  final String message;

  const SuperAdminEmptyState(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: const TextStyle(color: DanjiColors.textSecondary),
      ),
    );
  }
}

class SuperAdminLoadingBody extends StatelessWidget {
  const SuperAdminLoadingBody({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: DanjiColors.buttonBlue),
    );
  }
}

Widget superAdminListBody<T>({
  required Future<List<T>>? future,
  required String empty,
  required Widget Function(List<T>) builder,
  Future<void> Function()? onRefresh,
}) {
  return FutureBuilder<List<T>>(
    future: future,
    builder: (context, snap) {
      if (snap.connectionState == ConnectionState.waiting) {
        return const SuperAdminLoadingBody();
      }
      if (snap.hasError) {
        return Center(child: Text(friendlySuperAdminError(snap.error!)));
      }
      final list = snap.data ?? [];
      if (list.isEmpty) {
        return SuperAdminEmptyState(empty);
      }
      final body = builder(list);
      if (onRefresh == null) return body;
      return RefreshIndicator(
        color: DanjiColors.buttonBlue,
        onRefresh: onRefresh,
        child: body is ScrollView
            ? body
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [body],
              ),
      );
    },
  );
}

Future<T?> showSuperAdminBottomSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DanjiColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: DanjiColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: DanjiColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      );
    },
  );
}

Future<bool> superAdminConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '확인',
  bool danger = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: danger ? DanjiTheme.dangerButton : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  ).then((v) => v == true);
}

ButtonStyle get superAdminPrimaryFabStyle => FilledButton.styleFrom(
      backgroundColor: DanjiColors.buttonBlue,
      minimumSize: const Size.fromHeight(48),
    );

String generateSuperAdminInviteCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random();
  return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
}

// 레거시 호환
@Deprecated('Use SuperAdminMonthFilter')
class SuperAdminPeriodFilter extends SuperAdminMonthFilter {
  const SuperAdminPeriodFilter({
    super.key,
    required super.year,
    required super.month,
    required super.onYearChanged,
    required super.onMonthChanged,
  });
}

@Deprecated('Use SuperAdminCompactStatCard')
class SuperAdminStatGrid extends StatelessWidget {
  final List<({String label, String value, Color color, VoidCallback? onTap})>
      items;

  const SuperAdminStatGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map(
            (e) => SizedBox(
              width: (MediaQuery.sizeOf(context).width - 48) / 2,
              child: SuperAdminCompactStatCard(
                label: e.label,
                value: e.value,
                icon: Icons.analytics_outlined,
                color: e.color,
                onTap: e.onTap,
              ),
            ),
          )
          .toList(),
    );
  }
}
