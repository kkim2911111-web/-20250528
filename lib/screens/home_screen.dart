import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/grouped_reservations.dart';
import '../models/home_banner.dart';
import '../models/reservation.dart';
import '../supabase_client.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';
import '../resident_profile_screen.dart';
import '../services/banner_service.dart';
import '../services/my_page_service.dart';
import '../services/rental_service.dart';
import '../services/reservation_refresh_bus.dart';
import '../theme/danji_theme.dart';
import '../utils/network_retry.dart';
import 'booking_screen.dart';
import 'my_reservations_screen.dart';
import '../utils/accident_emergency_flow.dart';
import '../utils/rental_extension_flow.dart';
import '../utils/rental_navigation.dart';
import '../utils/booking_eligibility.dart';
import '../widgets/danji_brand_title.dart';
import '../utils/danji_snackbar.dart';
import '../widgets/rental_inquiry_button.dart';
import '../widgets/smart_key_door_buttons.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onGoMyPage;

  const HomeScreen({super.key, this.onGoMyPage});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _rentalService = RentalService();
  final _myPageService = MyPageService();
  final _bannerService = BannerService();
  final _timeFormat = DateFormat('HH:mm');

  Future<_HomeData>? _future;
  Future<HomeBanner?>? _bannerFuture;

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
      _bannerFuture = _bannerService.fetchActiveBanner();
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
      final grouped = await withNetworkRetry(
        () => _rentalService.fetchGroupedReservations(forceRefresh: true),
      );
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

  List<Reservation> _homeCarouselReservations(GroupedReservations? grouped) {
    if (grouped == null) return [];

    final seen = <String>{};
    final list = <Reservation>[];
    for (final r in [...grouped.operating, ...grouped.waiting]) {
      if (seen.add(r.id)) list.add(r);
    }

    list.sort((a, b) {
      final aInUse = a.status == 'in_use';
      final bInUse = b.status == 'in_use';
      if (aInUse && !bInUse) return -1;
      if (bInUse && !aInUse) return 1;
      return a.sortByStart.compareTo(b.sortByStart);
    });
    return list;
  }

  _HomeReservationMode _homeMode(Reservation reservation) {
    if (reservation.status == 'in_use') {
      return _HomeReservationMode.inUse;
    }
    if (reservation.status == 'confirmed' || reservation.status == 'pending') {
      if (reservation.isWithinUsageWindow) {
        return _HomeReservationMode.confirmedInWindow;
      }
      return _HomeReservationMode.confirmedBeforeWindow;
    }
    if (reservation.isWithinUsageWindow) {
      return _HomeReservationMode.confirmedInWindow;
    }
    return _HomeReservationMode.confirmedBeforeWindow;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: AppBar(
        backgroundColor: DanjiColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const DanjiBrandTitle(),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            color: DanjiColors.textPrimary,
            tooltip: '알림',
            onPressed: () {
              DanjiSnackBar.show(context, '알림 기능은 준비 중입니다.');
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

            final reservations = _homeCarouselReservations(data.grouped);

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _GreetingCard(
                  name: data.userName,
                  location: data.locationLabel,
                  residentApproved: data.residentApproved,
                  hasResidentRegistration: data.hasResidentRegistration,
                  onResidentTap: _openResidentVerification,
                ),
                const SizedBox(height: 12),
                if (data.error != null) ...[
                  _ErrorBanner(message: data.error.toString()),
                  const SizedBox(height: 12),
                ],
                if (reservations.isEmpty)
                  _EmptyHomeBody(
                    onBook: () => _openBooking(context),
                    onReservations: () => _openMyReservations(context),
                  )
                else
                  _HomeReservationSection(
                    reservations: reservations,
                    timeFormat: _timeFormat,
                    onBook: () => _openBooking(context),
                    onReservations: () => _openMyReservations(context),
                    onStart: (r) => _openStartRental(r),
                    onReturn: (r) => _openReturn(r),
                    onExtend: (r) => _openExtension(r),
                    onAccident: (r) => _openAccidentReport(r),
                    onCancel: (r) => _onCancelReservation(r),
                    onRefresh: reload,
                    modeFor: _homeMode,
                  ),
                const SizedBox(height: 12),
                _HomeEventBannerSection(future: _bannerFuture),
                const SizedBox(height: 16),
                const RentalInquiryButton(),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openBooking(BuildContext context) async {
    try {
      final profile = await _myPageService.fetchProfile();
      final block = BookingEligibility.blockReason(profile);
      if (block != null) {
        if (!context.mounted) return;
        DanjiSnackBar.show(context, block);
        return;
      }
    } catch (e) {
      if (!context.mounted) return;
      DanjiSnackBar.show(context, '예약 정보 확인 실패: $e');
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context)
        .push(
      MaterialPageRoute(builder: (_) => const BookingScreen()),
    )
        .then((_) => reload());
  }

  void _openMyReservations(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyReservationsScreen()),
    ).then((_) => reload());
  }

  void _openStartRental(Reservation reservation) {
    if (reservation.status != 'in_use' &&
        reservation.isTooEarlyForRentalStart) {
      DanjiSnackBar.show(context, RentalStartMessages.tooEarly);
      return;
    }
    openRentalOrUseScreen(context, reservation).then((_) => reload());
  }

  void _openReturn(Reservation reservation) {
    openRentalReturn<bool>(context, reservation).then((_) => reload());
  }

  void _openExtension(Reservation reservation) {
    openRentalExtension(context, reservation).then((applied) {
      if (applied) reload();
    });
  }

  void _openAccidentReport(Reservation reservation) {
    showAccidentEmergencyDialog(context);
  }

  Future<void> _onCancelReservation(Reservation reservation) async {
    if (reservation.isCancelBlocked) {
      DanjiSnackBar.show(context, ReservationCancelMessages.tooLate);
      return;
    }
    if (!reservation.canCancel) {
      DanjiSnackBar.show(context, '취소할 수 없는 예약입니다.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DanjiColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('예약 취소', style: DanjiTypography.subtitleLarge),
        content: Text(
          '정말 취소하시겠습니까? 결제하신 금액은 전액 환불됩니다.',
          style: DanjiTypography.bodyRegular.copyWith(
            color: DanjiColors.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: DanjiTheme.dangerButton,
            child: const Text('예약취소'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _rentalService.cancelReservation(reservation.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      DanjiSnackBar.show(context, ReservationCancelMessages.success);
      reload();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      DanjiSnackBar.show(
        context,
        e.toString().replaceFirst('RentalException: ', ''),
      );
    }
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

enum _HomeReservationMode {
  confirmedBeforeWindow,
  confirmedInWindow,
  inUse,
}

_HomeCardBadgeStyle _homeCardBadgeStyle(Reservation reservation) {
  if (reservation.status == 'in_use') {
    return const _HomeCardBadgeStyle(
      label: '대여중',
      background: DanjiColors.tagRentingBg,
      textColor: DanjiColors.tagRentingText,
    );
  }

  final isConfirmed =
      reservation.status == 'confirmed' || reservation.status == 'pending';
  final inWindow = reservation.isWithinUsageWindow;
  final start = reservation.startAt;
  final startPassed =
      start != null && start.isBefore(DateTime.now());

  // 시작 시각 경과·이용 시간대 — "이용 가능 시간" 대신 예약확정만
  if (isConfirmed && (inWindow || startPassed)) {
    return const _HomeCardBadgeStyle(
      label: '예약확정',
      background: DanjiColors.tagConfirmedBg,
      textColor: DanjiColors.tagConfirmedText,
    );
  }

  if (inWindow) {
    return _HomeCardBadgeStyle(
      label: reservation.statusLabel,
      background: DanjiColors.tagRentingBg,
      textColor: DanjiColors.tagRentingText,
    );
  }

  return _HomeCardBadgeStyle(
    label: reservation.timeUntilStartLabel,
    background: DanjiColors.tagConfirmedBg,
    textColor: DanjiColors.tagConfirmedText,
  );
}

class _HomeCardBadgeStyle {
  final String label;
  final Color background;
  final Color textColor;

  const _HomeCardBadgeStyle({
    required this.label,
    required this.background,
    required this.textColor,
  });
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _rentalStartLine(DateTime? start) {
  if (start == null) return '대여 시작 -';
  final time = DateFormat('HH:mm').format(start);
  final now = DateTime.now();
  if (_isSameDay(start, now)) return '대여 시작 금일 $time';
  return '대여 시작 ${DateFormat('M/d').format(start)} $time';
}

String _rentalEndLine(DateTime? end) {
  if (end == null) return '대여 종료 -';
  final time = DateFormat('HH:mm').format(end);
  final now = DateTime.now();
  if (_isSameDay(end, now)) return '대여 종료 금일 $time';
  return '대여 종료 ${DateFormat('M/d').format(end)} $time';
}

/// 대여 중(in_use)일 때만 종료까지 남은 시간 — 시작 전 문구는 뱃지로만 표시
String? _remainingTimeLine(Reservation reservation) {
  if (reservation.status != 'in_use') return null;
  final end = reservation.endAt;
  if (end == null) return null;
  return _formatTimeRemaining(end);
}

String _formatTimeRemaining(DateTime end) {
  final diff = end.difference(DateTime.now());
  if (diff.isNegative) return '종료';
  if (diff.inHours >= 1) {
    return '${diff.inHours}시간 ${diff.inMinutes % 60}분 남음';
  }
  if (diff.inMinutes >= 1) return '${diff.inMinutes}분 남음';
  return '곧 종료';
}

class _HomeReservationSection extends StatefulWidget {
  final List<Reservation> reservations;
  final DateFormat timeFormat;
  final VoidCallback onBook;
  final VoidCallback onReservations;
  final void Function(Reservation reservation) onStart;
  final void Function(Reservation reservation) onReturn;
  final void Function(Reservation reservation) onExtend;
  final void Function(Reservation reservation) onAccident;
  final void Function(Reservation reservation) onCancel;
  final VoidCallback onRefresh;
  final _HomeReservationMode Function(Reservation reservation) modeFor;

  const _HomeReservationSection({
    required this.reservations,
    required this.timeFormat,
    required this.onBook,
    required this.onReservations,
    required this.onStart,
    required this.onReturn,
    required this.onExtend,
    required this.onAccident,
    required this.onCancel,
    required this.onRefresh,
    required this.modeFor,
  });

  @override
  State<_HomeReservationSection> createState() =>
      _HomeReservationSectionState();
}

class _HomeReservationSectionState extends State<_HomeReservationSection> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _HomeReservationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentPage >= widget.reservations.length) {
      final next = (widget.reservations.length - 1).clamp(0, 999);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pageController.jumpToPage(next);
        setState(() => _currentPage = next);
      });
    }
  }

  Reservation get _current => widget.reservations[_currentPage];

  @override
  Widget build(BuildContext context) {
    final mode = widget.modeFor(_current);
    final multi = widget.reservations.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.reservations.length,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemBuilder: (context, index) {
              final reservation = widget.reservations[index];
              return _ReservationInfoCard(
                reservation: reservation,
                badgeStyle: _homeCardBadgeStyle(reservation),
              );
            },
          ),
        ),
        if (multi) ...[
          const SizedBox(height: 12),
          _PageDots(
            count: widget.reservations.length,
            index: _currentPage,
          ),
        ],
        const SizedBox(height: 12),
        ...switch (mode) {
          _HomeReservationMode.inUse => [
              if (_current.status == 'in_use') ...[
                SmartKeyDoorButtons(
                  key: ValueKey('door-${_current.id}'),
                  reservation: _current,
                  onChanged: widget.onRefresh,
                ),
                const SizedBox(height: 12),
              ],
              _MainActionCard(
                icon: Icons.local_parking_rounded,
                title: '반납하기',
                onTap: () => widget.onReturn(_current),
              ),
              const SizedBox(height: 12),
              _QuickGrid2x2(
                tiles: [
                  _QuickTileData(
                    icon: Icons.schedule_outlined,
                    label: '연장하기',
                    onTap: () => widget.onExtend(_current),
                  ),
                  _QuickTileData(
                    icon: Icons.warning_amber_rounded,
                    label: '사고신고',
                    isAccident: true,
                    onTap: () => widget.onAccident(_current),
                  ),
                  _QuickTileData(
                    icon: Icons.calendar_month_outlined,
                    label: '예약하기',
                    onTap: widget.onBook,
                  ),
                  _QuickTileData(
                    icon: Icons.assignment_outlined,
                    label: '내 예약',
                    onTap: widget.onReservations,
                  ),
                ],
              ),
            ],
          _HomeReservationMode.confirmedBeforeWindow ||
          _HomeReservationMode.confirmedInWindow =>
            [
              _MainActionCard(
                icon: Icons.directions_car_outlined,
                title: '대여하기',
                subtitle: _current.canStartRental
                    ? RentalStartMessages.subtitleReady
                    : RentalStartMessages.subtitleWhenTooEarly,
                enabled: _current.canStartRental,
                onTap: () => widget.onStart(_current),
              ),
              const SizedBox(height: 12),
              _QuickGrid2x2(
                tiles: [
                  _QuickTileData(
                    icon: Icons.calendar_month_outlined,
                    label: '예약하기',
                    onTap: widget.onBook,
                  ),
                  _QuickTileData(
                    icon: Icons.assignment_outlined,
                    label: '내 예약',
                    onTap: widget.onReservations,
                  ),
                  if (_current.shouldShowCancelButton)
                    _QuickTileData(
                      icon: Icons.event_busy_outlined,
                      label: '예약취소',
                      onTap: () => widget.onCancel(_current),
                    ),
                ],
              ),
            ],
        },
      ],
    );
  }
}

class _QuickTileData {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isAccident;

  const _QuickTileData({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isAccident = false,
  });
}

class _QuickGrid2x2 extends StatelessWidget {
  final List<_QuickTileData> tiles;

  const _QuickGrid2x2({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.55,
      ),
      itemCount: tiles.length,
      itemBuilder: (context, index) {
        final tile = tiles[index];
        return _QuickTile(
          icon: tile.icon,
          label: tile.label,
          isAccident: tile.isAccident,
          onTap: tile.onTap,
        );
      },
    );
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int index;

  const _PageDots({
    required this.count,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 8 : 6,
          height: active ? 8 : 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? DanjiColors.brandBlue
                : DanjiColors.brandBlue.withValues(alpha: 0.25),
          ),
        );
      }),
    );
  }
}

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

class _HomeEventBannerSection extends StatelessWidget {
  final Future<HomeBanner?>? future;

  const _HomeEventBannerSection({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HomeBanner?>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          );
        }

        if (snap.hasError || snap.data == null) {
          return const SizedBox.shrink();
        }

        return _EventBannerCard(banner: snap.data!);
      },
    );
  }
}

class _EventBannerCard extends StatelessWidget {
  final HomeBanner banner;

  const _EventBannerCard({required this.banner});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: DanjiColors.bannerBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (banner.mainTitle.isNotEmpty)
            Text(
              banner.mainTitle,
              style: const TextStyle(
                color: DanjiColors.bannerText,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          if (banner.subTitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              banner.subTitle,
              style: const TextStyle(
                color: DanjiColors.bannerTextMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
          ],
          if (banner.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              banner.description,
              style: const TextStyle(
                color: DanjiColors.bannerTextMuted,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: BorderRadius.circular(16),
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
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: DanjiColors.textPrimary,
                    letterSpacing: -0.3,
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
          const SizedBox(height: 8),
          Text(
            location,
            style: const TextStyle(
              fontSize: 13,
              color: DanjiColors.textSecondary,
              height: 1.4,
            ),
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
      bg = DanjiColors.brandBlue;
      fg = Colors.white;
      icon = Icons.verified_outlined;
      label = '입주민 인증';
    } else if (hasRegistration) {
      bg = DanjiColors.tagRentingBg;
      fg = DanjiColors.tagRentingText;
      icon = Icons.hourglass_top_outlined;
      label = '승인 대기';
    } else {
      bg = DanjiColors.accentRed.withValues(alpha: 0.1);
      fg = DanjiColors.accentRed;
      icon = Icons.error_outline;
      label = '인증 필요';
    }

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: approved ? null : Border.all(color: fg.withValues(alpha: 0.35)),
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
              fontSize: 12,
              fontWeight: FontWeight.w700,
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

  const _EmptyHomeBody({
    required this.onBook,
    required this.onReservations,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MainActionCard(
          icon: Icons.calendar_month_outlined,
          title: '예약하기',
          subtitle: '날짜와 시간을 선택하세요',
          onTap: onBook,
        ),
        const SizedBox(height: 12),
        _QuickGrid2x2(
          tiles: [
            _QuickTileData(
              icon: Icons.assignment_outlined,
              label: '내 예약',
              onTap: onReservations,
            ),
          ],
        ),
      ],
    );
  }
}

class _ReservationInfoCard extends StatelessWidget {
  final Reservation reservation;
  final _HomeCardBadgeStyle badgeStyle;

  const _ReservationInfoCard({
    required this.reservation,
    required this.badgeStyle,
  });

  @override
  Widget build(BuildContext context) {
    final vehicle = reservation.vehicle;
    final carName = vehicle?.name ?? '차량';
    final carNumber = vehicle?.carNumber?.trim();
    final carImageUrl = vehicle?.carImageUrl?.trim();
    final remaining = _remainingTimeLine(reservation);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final halfWidth = constraints.maxWidth / 2;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: halfWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _HomeCardFittedLine(
                      text: carName,
                      style: _HomeCardTypography.carName,
                    ),
                    const SizedBox(height: 5),
                    _HomeCardFittedLine(
                      text: carNumber != null && carNumber.isNotEmpty
                          ? carNumber
                          : '차량번호 미등록',
                      style: _HomeCardTypography.carNumber,
                    ),
                    const SizedBox(height: 7),
                    _HomeCardFittedLine(
                      text: _rentalStartLine(reservation.startAt),
                      style: _HomeCardTypography.schedule,
                    ),
                    const SizedBox(height: 3),
                    _HomeCardFittedLine(
                      text: _rentalEndLine(reservation.endAt),
                      style: _HomeCardTypography.schedule,
                    ),
                    if (remaining != null) ...[
                      const SizedBox(height: 7),
                      _HomeCardFittedLine(
                        text: remaining,
                        style: _HomeCardTypography.remaining,
                      ),
                    ],
                    const SizedBox(height: 7),
                    _HomeStatusBadge(
                      label: badgeStyle.label,
                      background: badgeStyle.background,
                      textColor: badgeStyle.textColor,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: halfWidth,
                child: Center(
                  child: _HomeCarImage(url: carImageUrl),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 홈 차량 카드 — 고급스러운 타이포 계층
abstract final class _HomeCardTypography {
  static const carName = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: Color(0xFF15181C),
    height: 1.1,
    letterSpacing: -0.5,
  );

  static const carNumber = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: Color(0xFF8A9299),
    height: 1.25,
    letterSpacing: 0.2,
  );

  static const schedule = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: Color(0xFF6B737C),
    height: 1.35,
    letterSpacing: 0.02,
  );

  static const remaining = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
    color: DanjiColors.toneRed,
    height: 1.2,
    letterSpacing: -0.15,
  );
}

/// 좁은 영역(50%)에서도 잘리지 않도록 한 줄·축소 표시
class _HomeCardFittedLine extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _HomeCardFittedLine({
    required this.text,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 1,
          style: style,
        ),
      ),
    );
  }
}

class _HomeStatusBadge extends StatelessWidget {
  final String label;
  final Color background;
  final Color textColor;

  const _HomeStatusBadge({
    required this.label,
    required this.background,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
          height: 1.15,
        ),
      ),
    );
  }
}

/// 홈 예약 카드 차량 이미지 (오른쪽 50%) — URL 없음/실패 시 placeholder
class _HomeCarImage extends StatelessWidget {
  final String? url;

  const _HomeCarImage({this.url});

  bool get _hasUrl {
    final u = url?.trim();
    return u != null && u.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 120.0;
        final imageHeight = (h * 0.92).clamp(88.0, 118.0);

        return SizedBox(
          width: w,
          height: h,
          child: Center(
            child: SizedBox(
              width: w,
              height: imageHeight,
              child: _hasUrl
                  ? _networkImage(url!.trim(), w, imageHeight)
                  : _placeholder(w, imageHeight),
            ),
          ),
        );
      },
    );
  }

  Widget _networkImage(String imageUrl, double w, double h) {
    return Image.network(
      imageUrl,
      width: w,
      height: h,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _placeholder(w, h),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _placeholder(w, h, showProgress: true);
      },
    );
  }

  Widget _placeholder(double w, double h, {bool showProgress = false}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE8ECF1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: showProgress
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                Icons.directions_car_filled_outlined,
                size: (h * 0.45).clamp(40.0, 56.0),
                color: DanjiColors.textMuted.withValues(alpha: 0.85),
              ),
      ),
    );
  }
}
class _MainActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool enabled;

  const _MainActionCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  Widget _rowContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded,
              color: Colors.white70, size: 18),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: enabled ? DanjiColors.brandBlue : DanjiColors.textMuted,
          ),
          child: SizedBox(height: 60, child: _rowContent()),
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isAccident;

  const _QuickTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isAccident = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = isAccident ? DanjiColors.toneRed : DanjiColors.brandBlue;
    final textColor = isAccident ? DanjiColors.toneRed : DanjiColors.brandBlue;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: Colors.black.withValues(alpha: 0.06),
        highlightColor: Colors.black.withValues(alpha: 0.04),
        child: Ink(
          decoration: BoxDecoration(
            color: DanjiColors.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: DanjiColors.cardShadow,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 26, color: iconColor),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
