import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'online_service.dart';

class OnlineGamePage extends StatefulWidget {
  final String roomId;
  const OnlineGamePage({super.key, required this.roomId});
  @override
  State<OnlineGamePage> createState() => _OnlineGamePageState();
}

class _OnlineGamePageState extends State<OnlineGamePage> {
  final service = MafiaOnlineService.instance;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> roomStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> playersStream;
  Timer? timer;
  int seconds = 30;
  String? role;
  int? roleRound;
  String? checkResult;
  String? target;
  bool busy = false;
  bool sent = false;
  bool roleLoading = false;
  bool giftLoading = false;
  List<Map<String, dynamic>> giftCatalog = [];
  String? scheduledPhase;
  int? scheduledRound;
  String? phaseSeen;
  int? roundSeen;

  @override
  void initState() {
    super.initState();
    roomStream = service.roomStream(widget.roomId);
    playersStream = service.playersStream(widget.roomId);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> loadRole(int round) async {
    if (roleRound == round || roleLoading) return;
    roleLoading = true;
    try {
      final data = await service.getMyRole(widget.roomId);
      if (!mounted) return;
      setState(() {
        role = data['role']?.toString();
        roleRound = (data['round'] as num?)?.toInt();
        final value = data['checkResult'];
        checkResult = value == null ? null : value.toString();
        target = null;
        sent = false;
      });
    } catch (_) {} finally {
      roleLoading = false;
    }
  }

  void schedulePhaseSync(String phase, int round, int phaseEndsAt) {
    if (phaseSeen == phase && roundSeen == round) return;
    if (scheduledPhase == phase && scheduledRound == round) return;
    scheduledPhase = phase;
    scheduledRound = round;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || scheduledPhase != phase || scheduledRound != round) return;
      scheduledPhase = null;
      scheduledRound = null;
      syncTimer(phase, round, phaseEndsAt);
      if (phase == 'night' && round > 0) loadRole(round);
    });
  }

  void syncTimer(String phase, int round, int phaseEndsAt) {
    if (phaseSeen == phase && roundSeen == round) return;
    phaseSeen = phase;
    roundSeen = round;
    timer?.cancel();
    target = null;
    sent = false;
    if (phase != 'night' && phase != 'talk' && phase != 'vote') return;
    final deadline = phaseEndsAt > 0
        ? phaseEndsAt
        : DateTime.now().millisecondsSinceEpoch;
    void tick() {
      if (!mounted) return;
      final remainingMs =
          deadline - DateTime.now().millisecondsSinceEpoch;
      final remaining = remainingMs <= 0
          ? 0
          : (remainingMs / 1000).ceil();
      setState(() => seconds = remaining);
      if (remaining != 0) return;
      timer?.cancel();
      if (phase == 'night') resolveNight();
      if (phase == 'talk') startVote();
      if (phase == 'vote') resolveVote();
    }
    tick();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> send(String type) async {
    if (target == null || busy || sent) return;
    setState(() => busy = true);
    try {
      await service.submitAction(
        roomId: widget.roomId,
        type: type,
        targetUid: target!,
      );
      if (!mounted) return;
      setState(() {
        busy = false;
        sent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  Future<void> resolveNight() async {
    if (busy) return;
    try { await service.resolveNight(widget.roomId); } catch (_) {}
  }

  Future<void> startVote() async {
    if (busy) return;
    try { await service.startVote(widget.roomId); } catch (_) {}
  }

  Future<void> resolveVote() async {
    if (busy) return;
    try { await service.resolveVote(widget.roomId); } catch (_) {}
  }

  Future<void> openGiftPicker(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (giftLoading) return;
    setState(() => giftLoading = true);
    try {
      final data = await service.getGiftCatalog();
      final raw = (data['gifts'] as List?) ?? const [];
      giftCatalog = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sovg‘alar yuklanmadi: $e')),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => giftLoading = false);
    }

    if (!mounted || giftCatalog.isEmpty) return;
    final recipients = docs.where((d) => d.id != service.user?.uid).toList();
    String? recipientUid;
    Map<String, dynamic>? selectedGift;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final canSend = recipientUid != null && selectedGift != null;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text('🎁 Sovg‘a yuborish',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 14),
                  const Text('Kimga?', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      for (final p in recipients)
                        ChoiceChip(
                          label: Text((p.data()['name'] ?? p.id).toString()),
                          selected: recipientUid == p.id,
                          onSelected: (_) => setSheet(() => recipientUid = p.id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Sovg‘a', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: .85,
                    children: [
                      for (final g in giftCatalog)
                        InkWell(
                          onTap: () => setSheet(() => selectedGift = g),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: selectedGift?['id'] == g['id']
                                  ? Theme.of(context).colorScheme.primary.withAlpha(80)
                                  : Colors.black26,
                              border: Border.all(
                                color: selectedGift?['id'] == g['id']
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white12,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text((g['emoji'] ?? '🎁').toString(),
                                  style: const TextStyle(fontSize: 28)),
                                Text((g['name'] ?? '').toString(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 10)),
                                Text(
                                  (g['priceSom'] ?? 0).toString() + ' so‘m • TEST TEKIN',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 8,
                                    color: Colors.greenAccent,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: canSend ? () async {
                        Navigator.pop(sheetCtx);
                        try {
                          await service.sendGift(
                            roomId: widget.roomId,
                            recipientUid: recipientUid!,
                            giftId: selectedGift!['id'].toString(),
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(content: Text('🎁 Sovg‘a yuborildi — test rejimida bepul.')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text('Sovg‘a yuborilmadi: $e')),
                            );
                          }
                        }
                      } : null,
                      icon: const Icon(Icons.card_giftcard),
                      label: const Text('Yuborish • TEST TEKIN'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget playerList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String? me,
    String phase,
  ) {
    final selectable = phase == 'night' || phase == 'vote';
    return Card(
      child: Column(
        children: [
          for (final doc in docs)
            Builder(builder: (_) {
              final data = doc.data();
              final alive = data['alive'] != false;
              final mine = doc.id == me;
              final can = selectable && alive && !mine && !sent;
              final seat = (data['seat'] as num?)?.toInt() ?? 0;
              return RadioListTile<String>(
                value: doc.id,
                groupValue: can ? target : null,
                onChanged: can ? (v) => setState(() => target = v) : null,
                title: Text(
                  (seat + 1).toString() + '. ' + (data['name'] ?? doc.id).toString(),
                  style: TextStyle(
                    color: alive ? Colors.white : Colors.white38,
                    fontWeight: mine ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Text(alive ? (mine ? 'Siz' : 'Tirik') : 'O‘lgan'),
              );
            }),
        ],
      ),
    );
  }

  Widget nightPanel() {
    final r = role;
    if (r == null) return const Card(child: Padding(
      padding: EdgeInsets.all(18), child: Text('Rol yuklanmoqda...')));
    String? action;
    String prompt;
    if (r == 'mafia') {
      action = 'kill'; prompt = 'Kimni o‘ldirishni tanlang.';
    } else if (r == 'doctor') {
      action = 'save'; prompt = 'Kimni qutqarishni tanlang.';
    } else if (r == 'sheriff') {
      action = 'check'; prompt = 'Kimni tekshirishni tanlang.';
    } else {
      prompt = 'Siz tinch aholisiz. Bu tun harakat qilmaydi.';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sizning rolingiz: ' + r.toUpperCase(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(prompt),
            if (r == 'sheriff' && checkResult != null) ...[
              const SizedBox(height: 8),
              Text(checkResult == 'true' ? 'Tekshiruv: MAFIYA' : 'Tekshiruv: MAFIYA EMAS',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
            if (action != null) ...[
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: FilledButton(
                onPressed: target == null || busy || sent ? null : () => send(action!),
                child: Text(sent ? 'Tanlov yuborildi' : 'Tanlovni yuborish'),
              )),
            ],
          ],
        ),
      ),
    );
  }


  Widget _onlineSeat(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    int index,
    bool mine,
    bool selected,
  ) {
    final data = doc.data();
    final alive = data['alive'] != false;
    final name = (data['name'] ?? 'O‘yinchi').toString();
    const colors = [
      Color(0xFF00A7D8), Color(0xFF8E44AD), Color(0xFFE04B4B),
      Color(0xFF2E86DE), Color(0xFF00A878), Color(0xFFF39C12),
    ];
    final base = colors[index % colors.length];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: alive
                      ? [base.withAlpha(230), const Color(0xFF07111D)]
                      : [Colors.grey.shade800, Colors.black],
                ),
                border: Border.all(
                  color: selected
                      ? const Color(0xFFFFC857)
                      : mine
                          ? const Color(0xFF00E5FF)
                          : Colors.white24,
                  width: selected || mine ? 3 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: selected
                        ? const Color(0xFFFFC857).withAlpha(150)
                        : Colors.black87,
                    blurRadius: 12,
                    spreadRadius: selected ? 2 : 0,
                  ),
                ],
              ),
              child: alive
                  ? Text(
                      name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                  : const Icon(Icons.close, color: Colors.white38),
            ),
            Positioned(
              left: -5,
              top: -5,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF05070D),
                ),
                child: Text(
                  (index + 1).toString(),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Container(
          constraints: const BoxConstraints(maxWidth: 76),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xE6000A14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? const Color(0xFFFFC857) : Colors.white12,
            ),
          ),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: mine || selected ? FontWeight.w800 : FontWeight.w500,
              color: alive ? Colors.white : Colors.white38,
            ),
          ),
        ),
      ],
    );
  }

  Widget _onlineTable(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String? me,
    String phase,
  ) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = math.min(w * .82, 470.0);
        final tableW = math.min(w * .88, 760.0);
        final tableH = math.min(h * .60, 285.0);
        final n = docs.length;

        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(36),
                    gradient: const RadialGradient(
                      center: Alignment(0, -0.2),
                      radius: 1.2,
                      colors: [
                        Color(0xFF182D3C),
                        Color(0xFF080B12),
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: tableW,
                  height: tableH,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(150),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF8A4A22),
                        Color(0xFF3A1A0D),
                        Color(0xFF160B07),
                      ],
                    ),
                    border: Border.all(
                      color: const Color(0xFFFFC857).withAlpha(170),
                      width: 3,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black87,
                        blurRadius: 28,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(140),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            Color(0xFF0D4167),
                            Color(0xFF061B2D),
                          ],
                        ),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(
                            child: SvgPicture.asset(
                              'assets/sponsors/les_ailles_test.svg',
                              width: tableW * .52,
                              height: tableH * .64,
                              fit: BoxFit.contain,
                              semanticsLabel: 'CHEERS reklama',
                            ),
                          ),
                          Positioned(
                            left: tableW * .17,
                            bottom: tableH * .16,
                            child: Row(
                              children: const [
                                _MiniChip(color: Color(0xFF00A7D8)),
                                _MiniChip(color: Color(0xFFE04B4B)),
                                _MiniChip(color: Color(0xFFFFC857)),
                              ],
                            ),
                          ),
                          Positioned(
                            right: tableW * .17,
                            bottom: tableH * .16,
                            child: Row(
                              children: const [
                                _MiniChip(color: Color(0xFFFFC857)),
                                _MiniChip(color: Color(0xFFE04B4B)),
                                _MiniChip(color: Color(0xFF00A7D8)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (n > 0)
                for (var i = 0; i < n; i++)
                  Builder(
                    builder: (_) {
                      final angle = -math.pi / 2 + 2 * math.pi * i / n;
                      final rx = math.max(tableW / 2 + 18, w / 2 - 42);
                      final ry = math.max(tableH / 2 + 34, h / 2 - 35);
                      final cx = w / 2 + math.cos(angle) * rx;
                      final cy = h / 2 + math.sin(angle) * ry;
                      return Positioned(
                        left: cx - 45,
                        top: cy - 32,
                        width: 90,
                        child: _onlineSeat(
                          docs[i],
                          i,
                          docs[i].id == me,
                          target == docs[i].id,
                        ),
                      );
                    },
                  ),
              Positioned(
                top: 8,
                left: 14,
                child: _onlinePill(
                  Icons.groups,
                  docs.length.toString() + '/12',
                ),
              ),
              Positioned(
                top: 8,
                right: 14,
                child: _onlinePill(
                  phase == 'night' ? Icons.nightlight_round : Icons.wb_sunny,
                  phase == 'night' ? 'Tun' : 'Kunduz',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _onlinePill(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xE611182A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 12),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: const Color(0xFFFFC857)),
            const SizedBox(width: 6),
            Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _onlineActionBar(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            Icons.pan_tool_alt,
            'Qo‘l ko‘tarish',
            () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Qo‘l ko‘tarildi.')),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionButton(
            Icons.card_giftcard,
            'Sovg‘a',
            giftLoading ? null : () => openGiftPicker(context, docs),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionButton(
            Icons.emoji_emotions,
            'Emodji',
            () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Emodji paneli tez orada.')),
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback? onTap) =>
      FilledButton.tonalIcon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );

  Widget _chatBar() => Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xE611182A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: const Row(
          children: [
            Icon(Icons.chat_bubble_outline, color: Colors.white70),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Xabar yozing...',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            Icon(Icons.send_rounded, color: Color(0xFF00E5FF)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: roomStream,
        builder: (context, rs) {
          if (rs.hasError) return Center(child: Text(rs.error.toString()));
          if (!rs.hasData || !rs.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = rs.data!.data()!;
          final phase = data['phase']?.toString() ?? 'lobby';
          final round = (data['round'] as num?)?.toInt() ?? 0;
          final phaseEndsAt = (data['phaseEndsAt'] as num?)?.toInt() ?? 0;
          schedulePhaseSync(phase, round, phaseEndsAt);

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: playersStream,
            builder: (context, ps) {
              if (ps.hasError) return Center(child: Text(ps.error.toString()));
              if (!ps.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = ps.data!.docs;
              final winner = data['winner']?.toString();

              return Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF0A1220),
                      Color(0xFF05070D),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.arrow_back),
                            ),
                            const SizedBox(width: 4),
                            const Expanded(
                              child: Text(
                                'MAFIA UZ',
                                style: TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                            _onlinePill(Icons.groups, docs.length.toString() + '/12'),
                            const SizedBox(width: 6),
                            _onlinePill(
                              phase == 'night'
                                  ? Icons.nightlight_round
                                  : Icons.wb_sunny,
                              seconds.toString() + ' s',
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              onPressed: () {},
                              icon: const Icon(Icons.settings_outlined),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(10, 2, 10, 16),
                          children: [
                            _onlineTable(docs, service.user?.uid, phase),
                            if (phase == 'finished')
                              Card(
                                color: const Color(0xE611182A),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Center(
                                    child: Text(
                                      winner == 'mafia'
                                          ? '🏆 MAFIYA G‘ALABA QILDI'
                                          : '🏆 TINCH AHOLI G‘ALABA QILDI',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 23,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (phase == 'night') nightPanel(),
                            if (phase == 'talk')
                              Card(
                                color: const Color(0xE611182A),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'Muhokama vaqti. Tirik o‘yinchilar gaplashadi.',
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 10),
                                      FilledButton(
                                        onPressed:
                                            busy || seconds > 0 ? null : startVote,
                                        child: const Text('Ovoz berishga o‘tish'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (phase == 'vote')
                              Card(
                                color: const Color(0xE611182A),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: FilledButton(
                                    onPressed: target == null || busy || sent
                                        ? null
                                        : () => send('vote'),
                                    child: Text(
                                      sent ? 'Ovoz yuborildi' : 'Ovoz berish',
                                    ),
                                  ),
                                ),
                              ),
                            _chatBar(),
                            const SizedBox(height: 8),
                            _onlineActionBar(context, docs),
                            const SizedBox(height: 8),
                            Card(
                              color: const Color(0xE611182A),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: playerList(
                                  docs,
                                  service.user?.uid,
                                  phase,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final Color color;
  const _MiniChip({required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    margin: const EdgeInsets.symmetric(horizontal: 2),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      border: Border.all(color: Colors.white70, width: 1),
      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
    ),
  );
}

