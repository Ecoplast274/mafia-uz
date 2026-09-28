import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'game.dart';

void main() => runApp(const MafiaApp());

const turnSeconds = 30;

const avatarColors = [
  Color(0xFFE53935),
  Color(0xFF8E24AA),
  Color(0xFF3949AB),
  Color(0xFF1E88E5),
  Color(0xFF00897B),
  Color(0xFF43A047),
  Color(0xFFFDD835),
  Color(0xFFFB8C00),
  Color(0xFF6D4C41),
  Color(0xFF546E7A),
  Color(0xFFD81B60),
  Color(0xFF00ACC1),
];

IconData roleIcon(Role r) => switch (r) {
      Role.mafia => Icons.theater_comedy,
      Role.doctor => Icons.medical_services,
      Role.sheriff => Icons.local_police,
      Role.citizen => Icons.person,
    };

Color roleColor(Role r) => switch (r) {
      Role.mafia => const Color(0xFFE53935),
      Role.doctor => const Color(0xFF43A047),
      Role.sheriff => const Color(0xFF1E88E5),
      Role.citizen => const Color(0xFFFFB300),
    };

String ini(String n) => n.isEmpty ? '?' : n[0].toUpperCase();

class MafiaApp extends StatelessWidget {
  const MafiaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mafiya',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorSchemeSeed: Colors.redAccent,
          scaffoldBackgroundColor: const Color(0xFF140A0A),
        ),
        home: const GamePage(),
      );
}

enum Stage { setup, reveal, night, info, talk, vote, end }

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  Stage stage = Stage.setup;
  Stage after = Stage.talk;
  int room = 8;
  final names = <String>[];
  final ctrl = TextEditingController();
  List<Player> players = [];
  List<Player> speakers = [];
  int speakIndex = 0;
  int revealIndex = 0;
  bool revealed = false;
  int round = 1;
  int timeLeft = turnSeconds;
  Timer? timer;
  Player? killTarget, saveTarget, checkTarget, voteTarget;
  String message = '';
  String? winner;
  IconData infoIcon = Icons.wb_sunny;
  Color infoColor = Colors.amber;

  List<Player> get alive => players.where((p) => p.alive).toList();

  @override
  void dispose() {
    timer?.cancel();
    ctrl.dispose();
    super.dispose();
  }

  // ---------- Taymer ----------

  void _startTimer(VoidCallback onEnd) {
    timer?.cancel();
    timeLeft = turnSeconds;
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => timeLeft--);
      if (timeLeft <= 0) {
        t.cancel();
        onEnd();
      }
    });
  }

  // ---------- Mantiq ----------

  void _add() {
    final n = ctrl.text.trim();
    if (n.isEmpty || names.contains(n) || names.length >= room) return;
    setState(() => names.add(n));
    ctrl.clear();
  }

  void _fill() => setState(() {
        for (var i = names.length; i < room; i++) {
          names.add('Ism ${i + 1}');
        }
      });

  void _clearTargets() {
    killTarget = saveTarget = checkTarget = voteTarget = null;
  }

  void _start() {
    timer?.cancel();
    final roles = dealRoles(names.length);
    setState(() {
      players = [
        for (var i = 0; i < names.length; i++) Player(names[i], roles[i])
      ];
      revealIndex = 0;
      revealed = false;
      round = 1;
      winner = null;
      _clearTargets();
      stage = Stage.reveal;
    });
  }

  void _nextReveal() {
    if (revealIndex == players.length - 1) {
      _toNight();
    } else {
      setState(() {
        revealIndex++;
        revealed = false;
      });
    }
  }

  void _toNight() {
    _clearTargets();
    setState(() => stage = Stage.night);
    _startTimer(_resolveNight);
  }

  void _toTalk() {
    final n = players.length;
    final start = (round - 1) % n;
    speakers = [
      for (var i = 0; i < n; i++) players[(start + i) % n]
    ].where((p) => p.alive).toList();
    speakIndex = 0;
    setState(() => stage = Stage.talk);
    _startTimer(_nextSpeaker);
  }

  void _nextSpeaker() {
    timer?.cancel();
    if (speakIndex >= speakers.length - 1) {
      _toVote();
      return;
    }
    setState(() => speakIndex++);
    _startTimer(_nextSpeaker);
  }

  void _toVote() {
    voteTarget = null;
    setState(() => stage = Stage.vote);
    _startTimer(_resolveVote);
  }

  void _next() {
    if (after == Stage.talk) {
      _toTalk();
    } else {
      _toNight();
    }
  }

  void _show(String msg, Stage next, IconData icon, Color color) {
    message = msg;
    after = next;
    infoIcon = icon;
    infoColor = color;
    winner = checkWinner(players);
    stage = winner != null ? Stage.end : Stage.info;
  }

  void _resolveNight() {
    timer?.cancel();
    setState(() {
      final k = killTarget;
      String msg;
      IconData icon;
      Color color;
      if (k == null) {
        msg = "Tun tinch o'tdi. Hech kim o'lmadi.";
        icon = Icons.nightlight_round;
        color = const Color(0xFF9FA8DA);
      } else if (k == saveTarget) {
        msg = "Mafiya hujum qildi, lekin doktor qutqardi! Hech kim o'lmadi.";
        icon = Icons.health_and_safety;
        color = Colors.greenAccent;
      } else {
        k.alive = false;
        msg = "№${players.indexOf(k) + 1} ${k.name} tunda o'ldirildi.\nRoli: ${k.role.title}";
        icon = Icons.dangerous;
        color = Colors.redAccent;
      }
      voteTarget = null;
      _show(msg, Stage.talk, icon, color);
    });
  }

  void _resolveVote() {
    timer?.cancel();
    setState(() {
      final v = voteTarget;
      String msg;
      IconData icon;
      Color color;
      if (v == null) {
        msg = "Hech kim chiqarilmadi.";
        icon = Icons.how_to_vote;
        color = Colors.amber;
      } else {
        v.alive = false;
        msg = "№${players.indexOf(v) + 1} ${v.name} ovoz berish bilan chiqarildi.\nRoli: ${v.role.title}";
        icon = Icons.gavel;
        color = Colors.orangeAccent;
      }
      round++;
      _clearTargets();
      _show(msg, Stage.night, icon, color);
    });
  }

  void _reset() {
    timer?.cancel();
    setState(() {
      players = [];
      stage = Stage.setup;
    });
  }

  // ---------- Umumiy vidjetlar ----------

  TextStyle? get _big => Theme.of(context)
      .textTheme
      .displaySmall
      ?.copyWith(fontWeight: FontWeight.w800);

  Widget _hero(IconData icon, Color color, {double size = 72}) => Container(
        width: size + 44,
        height: size + 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withAlpha(45),
          border: Border.all(color: color, width: 3),
        ),
        child: Icon(icon, size: size, color: color),
      );

  Widget _card(
          {required Widget child,
          Color? color,
          EdgeInsets pad = const EdgeInsets.all(16)}) =>
      Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: pad,
        decoration: BoxDecoration(
          color: (color ?? Colors.white).withAlpha(22),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: child,
      );

  Widget _btn(String text, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(58),
            textStyle:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          child: Text(text),
        ),
      );

  Widget _timerBadge() {
    final c = timeLeft <= 10 ? Colors.redAccent : Colors.white;
    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(
          value: timeLeft / turnSeconds,
          strokeWidth: 5,
          color: c,
          backgroundColor: Colors.white24,
        ),
        Text('$timeLeft',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: c)),
      ]),
    );
  }

  Widget _head(IconData icon, Color color, String title, String sub,
          {bool timerOn = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 56, bottom: 8),
        child: Row(children: [
          _hero(icon, color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              Text(sub,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
          ),
          if (timerOn) _timerBadge(),
        ]),
      );

  String _lbl(Player p, bool roles) {
    final s = '№${players.indexOf(p) + 1} ${p.name}';
    return roles ? '$s · ${p.role.title}' : s;
  }

  Widget _pick(String label, IconData icon, Color color, Player? value,
          ValueChanged<Player?> on,
          {bool roles = false}) =>
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in alive)
              ChoiceChip(
                avatar: CircleAvatar(
                  backgroundColor:
                      avatarColors[players.indexOf(p) % avatarColors.length],
                  child: Text(ini(p.name), style: const TextStyle(fontSize: 12)),
                ),
                label: Text(_lbl(p, roles)),
                selected: value == p,
                selectedColor: color.withAlpha(140),
                onSelected: (s) => setState(() => on(s ? p : null)),
              ),
          ]),
        ]),
      );

  // ---------- Stol ----------

  double _ang(int i, int n) => -math.pi / 2 + 2 * math.pi * i / n;

  Widget _seat(int i, double av, bool speaking, bool roles) {
    final p = players[i];
    final base = avatarColors[i % avatarColors.length];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Stack(clipBehavior: Clip.none, children: [
        Container(
          width: av,
          height: av,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.alive ? base : Colors.grey.shade800,
            border: Border.all(
              color: speaking ? Colors.amber : Colors.white24,
              width: speaking ? 4 : 2,
            ),
            boxShadow: speaking
                ? [
                    BoxShadow(
                        color: Colors.amber.withAlpha(150),
                        blurRadius: 14,
                        spreadRadius: 2)
                  ]
                : null,
          ),
          child: p.alive
              ? Text(ini(p.name),
                  style: TextStyle(
                      fontSize: av * 0.45, fontWeight: FontWeight.bold))
              : Icon(Icons.close, color: Colors.white38, size: av * 0.6),
        ),
        Positioned(
          left: -4,
          top: -4,
          child: CircleAvatar(
            radius: 10,
            backgroundColor: Colors.black87,
            child: Text('${i + 1}',
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ),
        if (speaking)
          const Positioned(
              right: -4,
              bottom: -4,
              child: Icon(Icons.mic, size: 20, color: Colors.amber)),
        if (roles && p.alive)
          Positioned(
              right: -4,
              bottom: -4,
              child: CircleAvatar(
                radius: 10,
                backgroundColor: Colors.black87,
                child: Icon(roleIcon(p.role), size: 13, color: roleColor(p.role)),
              )),
      ]),
      const SizedBox(height: 2),
      Text(p.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 11, color: p.alive ? Colors.white : Colors.white38)),
    ]);
  }

  Widget _table({Player? speaker, bool roles = false}) {
    final n = players.length;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final av = n > 8 ? 42.0 : 50.0;
      final sw = av + 24;
      final rx = w / 2 - sw / 2;
      final ry = w / 2 - av;
      return SizedBox(
        width: w,
        height: w,
        child: Stack(children: [
          Center(
            child: Container(
              width: w * 0.55,
              height: w * 0.55,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1B4D2E),
                border: Border.all(color: const Color(0xFF6D4C41), width: 6),
              ),
              child: const Icon(Icons.theater_comedy,
                  color: Colors.white24, size: 48),
            ),
          ),
          for (var i = 0; i < n; i++)
            Positioned(
              left: w / 2 + rx * math.cos(_ang(i, n)) - sw / 2,
              top: w / 2 + ry * math.sin(_ang(i, n)) - av / 2,
              width: sw,
              child: _seat(i, av, players[i] == speaker, roles),
            ),
        ]),
      );
    });
  }

  // ---------- Ekranlar ----------

  List<Color> get _bg => switch (stage) {
        Stage.night => const [Color(0xFF0B1026), Color(0xFF1B2A5A)],
        Stage.talk || Stage.vote => const [Color(0xFF3A1C0B), Color(0xFF8A4B14)],
        Stage.end => const [Color(0xFF1A0F0F), Color(0xFF4A1414)],
        _ => const [Color(0xFF140A0A), Color(0xFF3B0D0D)],
      };

  @override
  Widget build(BuildContext context) {
    final body = switch (stage) {
      Stage.setup => _setup(),
      Stage.reveal => _reveal(),
      Stage.night => _night(),
      Stage.info => _info(),
      Stage.talk => _talk(),
      Stage.vote => _vote(),
      Stage.end => _end(),
    };
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          (stage == Stage.setup || stage == Stage.reveal)
              ? ''
              : '$round-raund',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _bg,
          ),
        ),
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: KeyedSubtree(
              key: ValueKey('$stage-$revealIndex-$revealed-$round-$speakIndex'),
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  Widget _roomCard(int size, String title, IconData icon) {
    final on = room == size;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          room = size;
          if (names.length > size) names.removeRange(size, names.length);
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (on ? Colors.redAccent : Colors.white).withAlpha(on ? 60 : 22),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: on ? Colors.redAccent : Colors.white12, width: 2),
          ),
          child: Column(children: [
            Icon(icon, size: 32),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("$size o'yinchi",
                style: const TextStyle(color: Colors.white70)),
          ]),
        ),
      ),
    );
  }

  Widget _setup() => ListView(padding: const EdgeInsets.all(20), children: [
        const SizedBox(height: 40),
        Center(child: _hero(Icons.theater_comedy, Colors.redAccent)),
        const SizedBox(height: 16),
        Text('MAFIYA',
            textAlign: TextAlign.center,
            style: _big?.copyWith(letterSpacing: 8)),
        const SizedBox(height: 20),
        Row(children: [
          _roomCard(8, 'Oddiy xona', Icons.groups),
          _roomCard(12, 'Pro xona', Icons.workspace_premium),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              onSubmitted: (_) => _add(),
              decoration: InputDecoration(
                hintText: "O'yinchi ismi",
                filled: true,
                fillColor: Colors.white12,
                prefixIcon: const Icon(Icons.person_add),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
              onPressed: names.length < room ? _add : null,
              icon: const Icon(Icons.add)),
        ]),
        const SizedBox(height: 12),
        for (var i = 0; i < names.length; i++)
          _card(
            pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: avatarColors[i % avatarColors.length],
                child: Text('${i + 1}'),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(names[i], style: const TextStyle(fontSize: 18))),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => names.removeAt(i)),
              ),
            ]),
          ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            "O'yinchilar: ${names.length} / $room",
            style: TextStyle(
              color: names.length == room ? Colors.greenAccent : Colors.white70,
            ),
          ),
        ),
        TextButton(
          onPressed: _fill,
          child: const Text("Namuna ismlar bilan to'ldirish (sinash uchun)"),
        ),
        _btn("O'yinni boshlash", names.length == room ? _start : null),
      ]);

  Widget _reveal() {
    final p = players[revealIndex];
    final mates = players
        .where((x) => x.role == Role.mafia && x != p)
        .map((x) => '№${players.indexOf(x) + 1} ${x.name}')
        .join(', ');
    final last = revealIndex == players.length - 1;
    final c = revealed ? roleColor(p.role) : Colors.white54;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${revealIndex + 1} / ${players.length}',
              style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 16),
          _hero(revealed ? roleIcon(p.role) : Icons.help_outline, c, size: 88),
          const SizedBox(height: 24),
          Text(revealed ? p.role.title.toUpperCase() : p.name,
              textAlign: TextAlign.center,
              style: _big?.copyWith(color: revealed ? c : Colors.white)),
          const SizedBox(height: 12),
          if (!revealed) ...[
            Text("Telefonni ${p.name}ga bering.\nBoshqalar qaramasin!",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 32),
            _btn("Rolimni ko'rish", () => setState(() => revealed = true)),
          ] else ...[
            Text(p.role.hint,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16)),
            if (p.role == Role.mafia && mates.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Sheriklaringiz: $mates',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            const SizedBox(height: 32),
            _btn(last ? "Yetakchiga qaytaring" : "Yopish va keyingisiga",
                _nextReveal),
          ],
        ]),
      ),
    );
  }

  Widget _night() => ListView(padding: const EdgeInsets.all(16), children: [
        _head(Icons.nightlight_round, const Color(0xFF9FA8DA), 'Tun',
            "Yetakchi: tanlovlarni kiriting.",
            timerOn: true),
        _table(roles: true),
        _pick("Mafiya kimni o'ldiradi?", roleIcon(Role.mafia),
            roleColor(Role.mafia), killTarget, (p) => killTarget = p,
            roles: true),
        _pick("Doktor kimni qutqaradi?", roleIcon(Role.doctor),
            roleColor(Role.doctor), saveTarget, (p) => saveTarget = p,
            roles: true),
        _pick("Komissar kimni tekshiradi?", roleIcon(Role.sheriff),
            roleColor(Role.sheriff), checkTarget, (p) => checkTarget = p,
            roles: true),
        if (checkTarget != null)
          _card(
            color: checkTarget!.role == Role.mafia
                ? Colors.redAccent
                : Colors.greenAccent,
            child: Row(children: [
              Icon(checkTarget!.role == Role.mafia
                  ? Icons.warning_amber
                  : Icons.verified),
              const SizedBox(width: 10),
              Text(
                checkTarget!.role == Role.mafia
                    ? 'Javob: MAFIYA'
                    : "Javob: mafiya emas",
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ]),
          ),
        const SizedBox(height: 8),
        _btn('Tongni boshlash', _resolveNight),
        const SizedBox(height: 16),
      ]);

  Widget _info() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _hero(infoIcon, infoColor, size: 80),
            const SizedBox(height: 24),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("Tirik o'yinchilar: ${alive.length}",
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 28),
            _btn(after == Stage.talk ? "Gaplashishga o'tish" : "Tunga o'tish",
                _next),
          ]),
        ),
      );

  Widget _talk() {
    final sp = speakers[speakIndex];
    final last = speakIndex == speakers.length - 1;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _head(Icons.record_voice_over, Colors.amber, 'Gaplashish',
          'Navbat: ${speakIndex + 1} / ${speakers.length}',
          timerOn: true),
      _table(speaker: sp),
      _card(
        color: Colors.amber,
        child: Row(children: [
          const Icon(Icons.mic, color: Colors.amber, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Text('${_lbl(sp, false)} gapiryapti',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
      _btn(last ? "Ovoz berishga o'tish" : "Keyingi o'yinchi",
          _nextSpeaker),
      const SizedBox(height: 16),
    ]);
  }

  Widget _vote() => ListView(padding: const EdgeInsets.all(16), children: [
        _head(Icons.how_to_vote, Colors.orangeAccent, 'Ovoz berish',
            "Eng ko'p ovoz olganni tanlang.",
            timerOn: true),
        _table(),
        _pick('Kim chiqariladi?', Icons.how_to_vote, Colors.orangeAccent,
            voteTarget, (p) => voteTarget = p),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text("Hech kim tanlanmasa, hech kim chiqarilmaydi.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70)),
        ),
        _btn('Ovozni yakunlash', _resolveVote),
        const SizedBox(height: 16),
      ]);

  Widget _end() => ListView(padding: const EdgeInsets.all(16), children: [
        const SizedBox(height: 48),
        Center(
          child: _hero(
            Icons.emoji_events,
            winner == 'Mafiya' ? Colors.redAccent : Colors.greenAccent,
          ),
        ),
        const SizedBox(height: 16),
        Text("$winner g'alaba qildi!", textAlign: TextAlign.center, style: _big),
        const SizedBox(height: 8),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 16),
        for (var i = 0; i < players.length; i++)
          _card(
            pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: roleColor(players[i].role).withAlpha(60),
                child: Icon(roleIcon(players[i].role),
                    color: roleColor(players[i].role)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('№${i + 1} ${players[i].name}',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    Text(players[i].role.title,
                        style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
              Text(players[i].alive ? 'Tirik' : "O'lgan",
                  style: TextStyle(
                      color: players[i].alive
                          ? Colors.greenAccent
                          : Colors.white38)),
            ]),
          ),
        const SizedBox(height: 8),
        _btn("Yangi o'yin", _reset),
        const SizedBox(height: 16),
      ]);
}
