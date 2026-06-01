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
        backgroundColor: DanjiColors.pageGray,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const DanjiBrandTitle(),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(block)),
        );
        return;
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('예약 정보 확인 실패: $e')),
      );
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
    if (reservation.isTooEarlyForRentalStart) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(RentalStartMessages.tooEarly)),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(ReservationCancelMessages.tooLate)),
      );
      return;
    }
    if (!reservation.canCancel) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('취소할 수 없는 예약입니다.')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(ReservationCancelMessages.success)),
      );
      reload();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('RentalException: ', ''),
          ),
        ),
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

class _HomeCardPresentation {
  final String title;
  final String badge;
  final Color badgeColor;
  final String? footer;
  final bool footerIsCountdown;

  const _HomeCardPresentation({
    required this.title,
    required this.badge,
    required this.badgeColor,
    this.footer,
    this.footerIsCountdown = false,
  });
}

_HomeCardPresentation _homeCardPresentation({
  required Reservation reservation,
  required int index,
  required DateFormat timeFormat,
}) {
  if (reservation.status == 'in_use') {
    final end = reservation.endAt;
    return _HomeCardPresentation(
      title: '지금 타는 차',
      badge: '대여중',
      badgeColor: DanjiColors.sectionOperating,
      footer: end != null
          ? '${_formatTimeRemaining(end)} 남음'
          : null,
      footerIsCountdown: true,
    );
  }

  final inWindow = reservation.isWithinUsageWindow;
  final isConfirmed =
      reservation.status == 'confirmed' || reservation.status == 'pending';
  return _HomeCardPresentation(
    title: index > 0
        ? '다음 예약'
        : (inWindow ? '이용 시간대' : '가장 임박한 예약'),
    badge: inWindow
        ? (isConfirmed ? '예약확정' : reservation.statusLabel)
        : reservation.timeUntilStartLabel,
    badgeColor: inWindow && isConfirmed
        ? DanjiColors.brandBlue
        : (inWindow
            ? DanjiColors.sectionOperating
            : DanjiColors.brandBlue),
    footer: reservation.startAt != null
        ? '${DateFormat('M월 d일 (E)', 'ko_KR').format(reservation.startAt!)} '
            '${timeFormat.format(reservation.startAt!)} 시작'
            '${reservation.vehicle?.parkingLocation != null ? ' · ${reservation.vehicle!.parkingLocation}' : ''}'
        : null,
  );
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
          height: 188,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.reservations.length,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemBuilder: (context, index) {
              final reservation = widget.reservations[index];
              final meta = _homeCardPresentation(
                reservation: reservation,
                index: index,
                timeFormat: widget.timeFormat,
              );
              return _ReservationInfoCard(
                reservation: reservation,
                timeFormat: widget.timeFormat,
                title: meta.title,
                badge: meta.badge,
                badgeColor: meta.badgeColor,
                footer: meta.footer,
                footerIsCountdown: meta.footerIsCountdown,
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
                color: DanjiColors.brandBlue,
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
                    iconColor: DanjiColors.brandBlue,
                    onTap: () => widget.onExtend(_current),
                  ),
                  _QuickTileData(
                    icon: Icons.warning_amber_rounded,
                    label: '사고신고',
                    iconColor: DanjiColors.accentRed,
                    labelColor: DanjiColors.accentRed,
                    onTap: () => widget.onAccident(_current),
                  ),
                  _QuickTileData(
                    icon: Icons.calendar_month_outlined,
                    label: '예약하기',
                    iconColor: DanjiColors.brandBlue,
                    onTap: widget.onBook,
                  ),
                  _QuickTileData(
                    icon: Icons.assignment_outlined,
                    label: '내 예약',
                    iconColor: DanjiColors.brandBlue,
                    onTap: widget.onReservations,
                  ),
                ],
              ),
            ],
          _HomeReservationMode.confirmedBeforeWindow ||
          _HomeReservationMode.confirmedInWindow =>
            [
              _MainActionCard(
                color: DanjiColors.brandBlue,
                icon: Icons.directions_car_outlined,
                title: '차량 이용 시작',
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
                    iconColor: DanjiColors.brandBlue,
                    onTap: widget.onBook,
                  ),
                  _QuickTileData(
                    icon: Icons.assignment_outlined,
                    label: '내 예약',
                    iconColor: DanjiColors.brandBlue,
                    onTap: widget.onReservations,
                  ),
                  if (_current.shouldShowCancelButton)
                    _QuickTileData(
                      icon: Icons.event_busy_outlined,
                      label: '예약취소',
                      iconColor: DanjiColors.accentRed,
                      labelColor: DanjiColors.accentRed,
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
  final Color? iconColor;
  final Color? labelColor;

  const _QuickTileData({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.labelColor,
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
          iconColor: tile.iconColor,
          labelColor: tile.labelColor,
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
        gradient: const LinearGradient(
          colors: [DanjiColors.brandBlue, DanjiColors.brandBlueDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (banner.mainTitle.isNotEmpty)
            Text(
              banner.mainTitle,
              style: const TextStyle(
                color: Colors.white,
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
                color: Color(0xB3FFFFFF),
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.45,
              ),
            ),
          ],
          if (banner.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              banner.description,
              style: const TextStyle(
                color: Color(0xB3FFFFFF),
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
          color: DanjiColors.brandBlue,
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
              iconColor: DanjiColors.brandBlue,
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
  final DateFormat timeFormat;
  final String title;
  final String badge;
  final Color badgeColor;
  final String? footer;
  final bool footerIsCountdown;

  const _ReservationInfoCard({
    required this.reservation,
    required this.timeFormat,
    required this.title,
    required this.badge,
    this.badgeColor = DanjiColors.badgeBlue,
    this.footer,
    this.footerIsCountdown = false,
  });

  @override
  Widget build(BuildContext context) {
    final vehicle = reservation.vehicle;
    final carLine = [
      vehicle?.name ?? '차량',
      if (vehicle?.carNumber != null) '(${vehicle!.carNumber})',
    ].join(' ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  color: DanjiColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
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
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: DanjiColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          if (reservation.usagePeriodLabel != null) ...[
            const SizedBox(height: 6),
            Text(
              '${reservation.usagePeriodLabel}'
              '${vehicle?.parkingLocation != null && !footerIsCountdown ? ' · ${vehicle!.parkingLocation}' : ''}',
              style: const TextStyle(
                fontSize: 13,
                color: DanjiColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: 6),
            Text(
              footer!,
              style: TextStyle(
                color: footerIsCountdown
                    ? DanjiColors.sectionOperating
                    : DanjiColors.textSecondary,
                fontSize: 13,
                fontWeight:
                    footerIsCountdown ? FontWeight.w700 : FontWeight.w400,
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
  final String? subtitle;
  final VoidCallback onTap;
  final bool enabled;

  const _MainActionCard({
    required this.color,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = enabled ? color : DanjiColors.textMuted;
    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 60,
          child: Padding(
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
                            color: Color(0xB3FFFFFF),
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
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 26,
                color: iconColor ?? DanjiColors.brandBlue,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: labelColor ?? DanjiColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
