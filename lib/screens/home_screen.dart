import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/grouped_reservations.dart';
import '../models/reservation.dart';
import '../supabase_client.dart';
import '../theme/danji_colors.dart';
import '../resident_profile_screen.dart';
import '../services/my_page_service.dart';
import '../services/rental_service.dart';
import '../services/reservation_refresh_bus.dart';
import 'booking_screen.dart';
import 'my_reservations_screen.dart';
import '../utils/rental_navigation.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onGoMyPage;

  const HomeScreen({super.key, this.onGoMyPage});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _rentalService = RentalService();
  final _myPageService = MyPageService();
  final _timeFormat = DateFormat('HH:mm');

  Future<_HomeData>? _future;

  @override
  void initState() {
    super.initState();
    ReservationRefreshBus.instance.version.addListener(_onReservationChanged);
    reload();
  }

  @override
  void dispose() {
    ReservationRefreshBus.instance.version.removeListener(_onReservationChanged);
    super.dispose();
  }

  void _onReservationChanged() {
    if (!mounted) return;
    reload();
  }

  void reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<_HomeData> _load() async {
    final user = supabase.auth.currentUser;
    var name = user?.email?.split('@').first ?? '입주민';
    var location = '우리 단지의 두 번째 차, 단지카';
    var residentApproved = false;
    var hasResidentRegistration = false;

    try {
      final profile = await _myPageService.fetchProfile();
      if (profile.name != null && profile.name!.trim().isNotEmpty) {
        name = profile.name!.trim();
      }
      residentApproved = profile.residentApproved;
      hasResidentRegistration = profile.hasResidentRegistration;
      if (profile.residentLocationLabel != null) {
        location = profile.residentLocationLabel!;
      }
    } catch (_) {
      try {
        final resident = await supabase
            .from('residents')
            .select('building, unit, approved, complexes(name)')
            .eq('user_id', user!.id)
            .maybeSingle();
        if (resident != null) {
          hasResidentRegistration = true;
          residentApproved = resident['approved'] == true;
          final complexRaw = resident['complexes'];
          final complexName = complexRaw is Map
              ? complexRaw['name']?.toString()
              : null;
          final building = resident['building']?.toString();
          final unit = resident['unit']?.toString();
          if (complexName != null &&
              building != null &&
              unit != null &&
              building.isNotEmpty &&
              unit.isNotEmpty) {
            location = '$complexName ${building}동 $unit호';
          }
        }
      } catch (_) {}
    }

    try {
      final grouped = await _rentalService.fetchGroupedReservations();
      return _HomeData(
        grouped: grouped,
        userName: name,
        locationLabel: location,
        residentApproved: residentApproved,
        hasResidentRegistration: hasResidentRegistration,
      );
    } catch (e) {
      return _HomeData(
        userName: name,
        locationLabel: location,
        residentApproved: residentApproved,
        hasResidentRegistration: hasResidentRegistration,
        error: e,
      );
    }
  }

  Reservation? _primary(GroupedReservations? grouped) {
    return grouped?.soonestUpcoming;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: AppBar(
        backgroundColor: DanjiColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            const Text(
              '단지카',
              style: TextStyle(
                color: DanjiColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 22,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.apartment_rounded,
              color: DanjiColors.buttonBlue,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '우리 아파트 단지의 두번째 차',
                style: TextStyle(
                  color: DanjiColors.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            color: DanjiColors.textPrimary,
            tooltip: '알림',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('알림 기능은 준비 중입니다.')),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: DanjiColors.primaryBlue,
        onRefresh: () async => reload(),
        child: FutureBuilder<_HomeData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snap.data;
            if (data == null) {
              return const SizedBox.shrink();
            }

            final primary = _primary(data.grouped);
            final view = primary == null
                ? _HomeView.empty
                : (primary.isOperating || primary.status == 'in_use')
                    ? _HomeView.operating
                    : _HomeView.waiting;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                _GreetingCard(
                  name: data.userName,
                  location: data.locationLabel,
                  residentApproved: data.residentApproved,
                  hasResidentRegistration: data.hasResidentRegistration,
                  onResidentTap: _openResidentVerification,
                ),
                const SizedBox(height: 20),
                if (data.error != null) ...[
                  _ErrorBanner(message: data.error.toString()),
                  const SizedBox(height: 16),
                ],
                switch (view) {
                  _HomeView.empty => _EmptyHomeBody(
                      onBook: () => _openBooking(context),
                      onReservations: () => _openMyReservations(context),
                      onMyPage: widget.onGoMyPage,
                    ),
                  _HomeView.waiting => _WaitingHomeBody(
                      reservation: primary!,
                      timeFormat: _timeFormat,
                      onStart: () => _openStartRental(primary),
                      onBook: () => _openBooking(context),
                      onReservations: () => _openMyReservations(context),
                      upcomingCount: data.grouped?.activeCount ?? 0,
                    ),
                  _HomeView.operating => _OperatingHomeBody(
                      reservation: primary!,
                      timeFormat: _timeFormat,
                      onReturn: () => _openReturn(primary),
                      onStartUse: () => _openStartRental(primary),
                      onReservations: () => _openMyReservations(context),
                    ),
                },
              ],
            );
          },
        ),
      ),
    );
  }

  void _openBooking(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BookingScreen()),
    ).then((_) => reload());
  }

  void _openMyReservations(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyReservationsScreen()),
    ).then((_) => reload());
  }

  void _openStartRental(Reservation reservation) {
    openRentalOrUseScreen(context, reservation).then((_) => reload());
  }

  void _openReturn(Reservation reservation) {
    openRentalReturn<bool>(context, reservation).then((_) => reload());
  }

  Future<void> _openResidentVerification() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ResidentProfileScreen(embedded: true),
      ),
    );
    reload();
  }
}

enum _HomeView { empty, waiting, operating }

class _HomeData {
  final GroupedReservations? grouped;
  final String userName;
  final String locationLabel;
  final bool residentApproved;
  final bool hasResidentRegistration;
  final Object? error;

  const _HomeData({
    this.grouped,
    required this.userName,
    required this.locationLabel,
    this.residentApproved = false,
    this.hasResidentRegistration = false,
    this.error,
  });
}

class _GreetingCard extends StatelessWidget {
  final String name;
  final String location;
  final bool residentApproved;
  final bool hasResidentRegistration;
  final VoidCallback? onResidentTap;

  const _GreetingCard({
    required this.name,
    required this.location,
    required this.residentApproved,
    required this.hasResidentRegistration,
    this.onResidentTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: DanjiColors.skyLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DanjiColors.skySoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '안녕하세요, $name 님',
                  style: const TextStyle(
                    color: DanjiColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _ResidentVerificationBadge(
                approved: residentApproved,
                hasRegistration: hasResidentRegistration,
                onTap: onResidentTap,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                residentApproved
                    ? Icons.apartment_outlined
                    : Icons.location_on_outlined,
                size: 16,
                color: DanjiColors.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  location,
                  style: const TextStyle(
                    color: DanjiColors.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResidentVerificationBadge extends StatelessWidget {
  final bool approved;
  final bool hasRegistration;
  final VoidCallback? onTap;

  const _ResidentVerificationBadge({
    required this.approved,
    required this.hasRegistration,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final IconData icon;
    late final String label;
    final bool tappable = !approved && onTap != null;

    if (approved) {
      bg = DanjiColors.buttonBlue.withValues(alpha: 0.12);
      fg = DanjiColors.buttonBlue;
      icon = Icons.verified_outlined;
      label = '입주민 인증';
    } else if (hasRegistration) {
      bg = DanjiColors.sectionOperating.withValues(alpha: 0.15);
      fg = DanjiColors.sectionOperating;
      icon = Icons.hourglass_top_outlined;
      label = '승인 대기';
    } else {
      bg = DanjiColors.accentRed.withValues(alpha: 0.1);
      fg = DanjiColors.accentRed;
      icon = Icons.error_outline;
      label = '인증 필요';
    }

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );

    if (!tappable) return badge;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: badge,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DanjiColors.danger.withValues(alpha: 0.4)),
      ),
      child: Text(
        message.replaceFirst('RentalException: ', ''),
        style: const TextStyle(color: DanjiColors.danger, height: 1.4),
      ),
    );
  }
}

class _EmptyHomeBody extends StatelessWidget {
  final VoidCallback onBook;
  final VoidCallback onReservations;
  final VoidCallback? onMyPage;

  const _EmptyHomeBody({
    required this.onBook,
    required this.onReservations,
    this.onMyPage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MainActionCard(
          color: DanjiColors.rentalBlue,
          icon: Icons.calendar_month_outlined,
          title: '예약하기',
          subtitle: '날짜와 시간을 선택하세요',
          onTap: onBook,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _QuickTile(
                icon: Icons.assignment_outlined,
                label: '내 예약',
                onTap: onReservations,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickTile(
                icon: Icons.person_outline,
                label: '마이페이지',
                onTap: onMyPage ?? () {},
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WaitingHomeBody extends StatelessWidget {
  final Reservation reservation;
  final DateFormat timeFormat;
  final VoidCallback onStart;
  final VoidCallback onBook;
  final VoidCallback onReservations;
  final int upcomingCount;

  const _WaitingHomeBody({
    required this.reservation,
    required this.timeFormat,
    required this.onStart,
    required this.onBook,
    required this.onReservations,
    this.upcomingCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ReservationInfoCard(
          reservation: reservation,
          timeFormat: timeFormat,
          title: '가장 임박한 예약',
          badge: reservation.timeUntilStartLabel,
          badgeColor: DanjiColors.buttonBlue,
          footer: reservation.startAt != null
              ? '${DateFormat('M월 d일 (E)', 'ko_KR').format(reservation.startAt!)} '
                  '${timeFormat.format(reservation.startAt!)} 시작'
              : null,
        ),
        if (upcomingCount > 1) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onReservations,
              child: Text('예약 ${upcomingCount}건 · 전체 보기'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _MainActionCard(
          color: DanjiColors.rentalBlue,
          icon: Icons.play_circle_outline,
          title: '운행시작',
          subtitle: '사진 등록 후 출발하세요',
          onTap: onStart,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _QuickTile(
                icon: Icons.calendar_month_outlined,
                label: '예약하기',
                iconColor: DanjiColors.primaryBlue,
                onTap: onBook,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickTile(
                icon: Icons.assignment_outlined,
                label: '내 예약',
                onTap: onReservations,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OperatingHomeBody extends StatelessWidget {
  final Reservation reservation;
  final DateFormat timeFormat;
  final VoidCallback onReturn;
  final VoidCallback onStartUse;
  final VoidCallback onReservations;

  const _OperatingHomeBody({
    required this.reservation,
    required this.timeFormat,
    required this.onReturn,
    required this.onStartUse,
    required this.onReservations,
  });

  @override
  Widget build(BuildContext context) {
    final end = reservation.endAt;
    final canReturn = reservation.canReturn;
    return Column(
      children: [
        _ReservationInfoCard(
          reservation: reservation,
          timeFormat: timeFormat,
          title: canReturn ? '이용 중인 차량' : '이용 시간대',
          badge: canReturn ? '대여 중' : '이용 중',
          badgeColor: DanjiColors.sectionOperating,
          footer: end != null
              ? '반납 마감 ${timeFormat.format(end)} · ${_timeRemaining(end)}'
              : null,
        ),
        const SizedBox(height: 16),
        _MainActionCard(
          color: DanjiColors.rentalBlue,
          icon: canReturn
              ? Icons.local_parking_outlined
              : Icons.directions_car_outlined,
          subtitle: canReturn
              ? (reservation.canEarlyReturn
                  ? '중도반납 · 남은 시간 환불 불가'
                  : '주차 후 사진 찍어 반납')
              : '대여 시작 후 반납할 수 있습니다',
          title: canReturn
              ? (reservation.canEarlyReturn ? '중도반납' : '반납하기')
              : '차량 이용 시작',
          onTap: canReturn ? onReturn : onStartUse,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _QuickTile(
                icon: Icons.assignment_outlined,
                label: '내 예약',
                onTap: onReservations,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickTile(
                icon: Icons.schedule_outlined,
                label: '연장하기',
                iconColor: DanjiColors.primaryBlue,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('연장 기능은 준비 중입니다.')),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickTile(
                icon: Icons.warning_amber_rounded,
                label: '사고신고',
                iconColor: DanjiColors.accentRed,
                labelColor: DanjiColors.accentRed,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('사고 신고는 반납 화면에서 등록할 수 있습니다.')),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _timeRemaining(DateTime end) {
    final diff = end.difference(DateTime.now());
    if (diff.isNegative) return '종료';
    if (diff.inHours >= 1) {
      return '${diff.inHours}시간 ${diff.inMinutes % 60}분 남음';
    }
    if (diff.inMinutes >= 1) return '${diff.inMinutes}분 남음';
    return '곧 종료';
  }
}

class _ReservationInfoCard extends StatelessWidget {
  final Reservation reservation;
  final DateFormat timeFormat;
  final String title;
  final String badge;
  final Color badgeColor;
  final String? footer;

  const _ReservationInfoCard({
    required this.reservation,
    required this.timeFormat,
    required this.title,
    required this.badge,
    this.badgeColor = DanjiColors.badgeBlue,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final vehicle = reservation.vehicle;
    final start = reservation.startAt;
    final end = reservation.endAt;
    final carLine = [
      vehicle?.name ?? '차량',
      if (vehicle?.carNumber != null) '(${vehicle!.carNumber})',
    ].join(' ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DanjiColors.skySoft),
        boxShadow: [
          BoxShadow(
            color: DanjiColors.buttonBlue.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: DanjiColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            carLine,
            style: const TextStyle(
              color: DanjiColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (start != null && end != null) ...[
            const SizedBox(height: 6),
            Text(
              '${timeFormat.format(start)} - ${timeFormat.format(end)}'
              '${vehicle?.parkingLocation != null ? ' · ${vehicle!.parkingLocation}' : ''}',
              style: const TextStyle(
                color: DanjiColors.textMuted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: 6),
            Text(
              footer!,
              style: TextStyle(
                color: badgeColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
class _MainActionCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MainActionCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 36),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;

  const _QuickTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DanjiColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DanjiColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 28,
                color: iconColor ?? DanjiColors.textPrimary,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: labelColor ?? DanjiColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
