import 'dart:async';
import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Online • ' + widget.roomId)),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: roomStream,
        builder: (context, rs) {
          if (rs.hasError) return Center(child: Text(rs.error.toString()));
          if (!rs.hasData || !rs.data!.exists) return const Center(child: CircularProgressIndicator());
          final data = rs.data!.data()!;
          final phase = data['phase']?.toString() ?? 'lobby';
          final round = (data['round'] as num?)?.toInt() ?? 0;
          final phaseEndsAt = (data['phaseEndsAt'] as num?)?.toInt() ?? 0;
          schedulePhaseSync(phase, round, phaseEndsAt);

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: playersStream,
            builder: (context, ps) {
              if (ps.hasError) return Center(child: Text(ps.error.toString()));
              if (!ps.hasData) return const Center(child: CircularProgressIndicator());
              final docs = ps.data!.docs;
              final winner = data['winner']?.toString();
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Expanded(child: Text(
                        phase.toUpperCase() + ' • ' + round.toString() + '-RAUND',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                      if (phase == 'night' || phase == 'talk' || phase == 'vote')
                        Text(seconds.toString() + 's',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    ]),
                  )),
                  if (phase == 'finished') Card(child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(child: Text(
                      winner == 'mafia' ? '🏆 MAFIYA G‘ALABA QILDI' : '🏆 TINCH AHOLI G‘ALABA QILDI',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900))))),
                  if (phase == 'night') nightPanel(),
                  if (phase == 'talk') Card(child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(children: [
                      const Text('Muhokama vaqti. Tirik o‘yinchilar gaplashadi.',
                        textAlign: TextAlign.center),
                      FilledButton(
                        onPressed: busy || seconds > 0 ? null : startVote,
                        child: const Text('Ovoz berishga o‘tish')),
                    ]))),
                  if (phase == 'vote') Card(child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: FilledButton(
                      onPressed: target == null || busy || sent ? null : () => send('vote'),
                      child: Text(sent ? 'Ovoz yuborildi' : 'Ovoz berish')))),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton.icon(
                        onPressed: giftLoading ? null : () => openGiftPicker(context, docs),
                        icon: const Icon(Icons.card_giftcard),
                        label: Text(giftLoading ? 'Sovg‘alar yuklanmoqda...' : '🎁 Sovg‘a yuborish • TEST TEKIN'),
                      ),
                    ),
                  ),
                  playerList(docs, service.user?.uid, phase),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
