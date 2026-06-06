import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';
import 'services/auth_service.dart';
import 'services/my_page_service.dart';
import 'services/push_notification_service.dart';
import 'theme/danji_colors.dart';
import 'utils/network_retry.dart';
import 'widgets/danji_app_bar.dart';
import 'widgets/resident_verification_pending.dart';

class ResidentProfile {
  final String userId;
  final String complexId;
  final String? building;
  final String? unit;
  final bool approved;

  ResidentProfile({
    required this.userId,
    required this.complexId,
    required this.building,
    required this.unit,
    required this.approved,
  });

  factory ResidentProfile.fromMap(Map<String, dynamic> m) {
    return ResidentProfile(
      userId: m['user_id'].toString(),
      complexId: m['complex_id'].toString(),
      building: m['building'] as String?,
      unit: m['unit'] as String?,
      approved: (m['approved'] as bool?) ?? false,
    );
  }
}

class ResidentRepository {
  Future<ResidentProfile?> fetchMyProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    final row = await withNetworkRetry(
      () => supabase
          .from('residents')
          .select()
          .eq('user_id', user.id)
          .maybeSingle(),
    );

    if (row == null) return null;
    return ResidentProfile.fromMap(row);
  }

  Stream<ResidentProfile?> watchMyProfile() async* {
    final user = supabase.auth.currentUser;
    if (user == null) {
      yield null;
      return;
    }

    yield await fetchMyProfile();

    // Realtime 미설정 DB에서도 승인 상태를 감지 (3초마다 갱신)
    await for (final _ in Stream.periodic(const Duration(seconds: 3))) {
      if (supabase.auth.currentUser?.id != user.id) break;
      try {
        yield await fetchMyProfile();
      } catch (_) {
        // 주기 갱신 실패는 스트림을 끊지 않음
      }
    }
  }

  Future<void> upsertMyProfile({
    required String complexId,
    required String building,
    required String unit,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw const AuthException('Not signed in');

    await supabase.from('residents').upsert({
      'user_id': user.id,
      'complex_id': complexId,
      'building': building.trim(),
      'unit': unit.trim(),
      'approved': false,
    });
  }
}

class ResidentProfileScreen extends StatefulWidget {
  final bool embedded;

  const ResidentProfileScreen({super.key, this.embedded = false});

  @override
  State<ResidentProfileScreen> createState() => _ResidentProfileScreenState();
}

class _ResidentProfileScreenState extends State<ResidentProfileScreen> {
  final _repo = ResidentRepository();
  final _myPage = MyPageService();
  StreamSubscription<ResidentProfile?>? _profileSub;

  final _inviteCode = TextEditingController();
  final _building = TextEditingController();
  final _unit = TextEditingController();

  Timer? _debounce;
  bool _lookingUp = false;
  String? _lookupError;

  String? _complexId;
  String? _complexName;

  ResidentProfile? _profile;
  bool _verificationRequested = false;
  bool _loadingProfileFlags = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    _profileSub = _repo.watchMyProfile().listen((p) {
      _profile = p;

      if ((_building.text.isEmpty) && (p?.building?.isNotEmpty ?? false)) {
        _building.text = p!.building!;
      }
      if ((_unit.text.isEmpty) && (p?.unit?.isNotEmpty ?? false)) {
        _unit.text = p!.unit!;
      }

      if (mounted) setState(() {});
    });

    _inviteCode.addListener(_onInviteCodeChanged);
    _loadVerificationFlags();
  }

  Future<void> _loadVerificationFlags() async {
    try {
      final requested = await _myPage.isResidentVerificationRequested();
      if (!mounted) return;
      setState(() {
        _verificationRequested = requested;
        _loadingProfileFlags = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingProfileFlags = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _profileSub?.cancel();
    _inviteCode
      ..removeListener(_onInviteCodeChanged)
      ..dispose();
    _building.dispose();
    _unit.dispose();
    super.dispose();
  }

  void _onInviteCodeChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      await _lookupComplexByInviteCodeRpc(_inviteCode.text);
    });
  }

  String _normalizeCode(String raw) {
    return raw.trim().replaceAll(' ', '').toUpperCase();
  }

  Future<void> _lookupComplexByInviteCodeRpc(String rawCode) async {
    final code = _normalizeCode(rawCode);

    if (code.length < 4) {
      setState(() {
        _lookingUp = false;
        _lookupError = null;
        _complexId = null;
        _complexName = null;
      });
      return;
    }

    setState(() {
      _lookingUp = true;
      _lookupError = null;
      _complexId = null;
      _complexName = null;
    });

    try {
      final payload = await supabase.rpc(
        'lookup_complex_by_invite_code',
        params: {'p_invite_code': code},
      );

      if (!mounted) return;

      if (payload == null) {
        setState(() => _lookupError = '유효하지 않은 초대코드입니다.');
        return;
      }

      if (payload is! Map) {
        setState(() => _lookupError = '단지 조회 응답이 올바르지 않습니다.');
        return;
      }

      final id = payload['id']?.toString();
      final name = payload['name']?.toString();

      if (id == null || id.isEmpty) {
        setState(() => _lookupError = '유효하지 않은 초대코드입니다.');
        return;
      }

      setState(() {
        _complexId = id;
        _complexName = (name == null || name.isEmpty) ? '단지' : name;
        _lookupError = null;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;

      final msg = e.message.toLowerCase();
      String friendly;
      if (msg.contains('rate_limited')) {
        friendly = '조회가 너무 잦습니다. 잠시 후 다시 시도해주세요.';
      } else if (msg.contains('invite_code_too_short')) {
        friendly = '초대코드를 더 길게 입력해주세요.';
      } else if (msg.contains('not_authenticated')) {
        friendly = '로그인이 필요합니다.';
      } else {
        friendly = '단지 조회 실패: ${e.message}';
      }
      setState(() => _lookupError = friendly);
    } catch (e) {
      if (!mounted) return;
      setState(() => _lookupError = '단지 조회 실패: $e');
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  Future<void> _apply() async {
    final complexId = _complexId;
    final b = _building.text.trim();
    final u = _unit.text.trim();

    if (complexId == null) {
      setState(() => _error = '초대코드를 확인해주세요. (단지 조회가 필요합니다)');
      return;
    }
    if (b.isEmpty || u.isEmpty) {
      setState(() => _error = '동/호수를 모두 입력해주세요.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _repo.upsertMyProfile(complexId: complexId, building: b, unit: u);
      await _myPage.markResidentVerificationRequested();
      await PushNotificationService.instance
          .staffResidentReviewRequest(complexId: complexId);

      if (!mounted) return;
      setState(() => _verificationRequested = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('인증 신청 완료 (승인 대기)')),
      );
      if (widget.embedded) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final approved = _profile?.approved == true;
    final pendingVerification = !approved && _verificationRequested;

    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: DanjiAppBar(
        title: '입주민 인증',
        showBack: widget.embedded,
        showHome: !widget.embedded,
        light: true,
        extraActions: widget.embedded
            ? null
            : [
                IconButton(
                  tooltip: '로그아웃',
                  onPressed: () async {
                    await AuthService.instance.signOut(toSignUp: true);
                  },
                  icon: const Icon(Icons.logout),
                ),
              ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loadingProfileFlags
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  if (approved) ...[
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.verified, color: Colors.green),
                        title: Text('승인 완료'),
                        subtitle: Text('예약 화면으로 자동 이동합니다.'),
                      ),
                    ),
                  ] else if (pendingVerification) ...[
                    const ResidentVerificationPendingPanel(),
                  ] else ...[
                    const Text(
                      '초대코드와 동/호수를 등록하면 관리자가 확인 후 승인합니다.',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: DanjiColors.textPrimary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _inviteCode,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: '초대코드',
                        border: OutlineInputBorder(),
                        hintText: '예) DANJI2026',
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_lookingUp) ...[
                      const LinearProgressIndicator(minHeight: 2),
                      const SizedBox(height: 8),
                    ],
                    if (_lookupError != null)
                      Text(
                        _lookupError!,
                        style: const TextStyle(color: DanjiColors.accentRed),
                      ),
                    if (_complexName != null)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.apartment),
                          title: Text(_complexName!),
                          subtitle: const Text('단지가 확인되었습니다.'),
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _building,
                      decoration: const InputDecoration(
                        labelText: '동',
                        border: OutlineInputBorder(),
                        hintText: '예) 101',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _unit,
                      decoration: const InputDecoration(
                        labelText: '호',
                        border: OutlineInputBorder(),
                        hintText: '예) 1203',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: DanjiColors.accentRed),
                        ),
                      ),
                    FilledButton(
                      onPressed: _saving ? null : _apply,
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('입주민 인증 신청하기'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
