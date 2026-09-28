import 'package:flutter/material.dart';
import 'game.dart';

void main() => runApp(const MafiaApp());

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
        ),
        home: const GamePage(),
      );
}

enum Stage { setup, reveal, night, info, vote, end }

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  Stage stage = Stage.setup;
  Stage after = Stage.night;
  final names = <String>[];
  final ctrl = TextEditingController();
  List<Player> players = [];
  int revealIndex = 0;
  bool revealed = false;
  int round = 1;
  Player? killTarget, saveTarget, checkTarget, voteTarget;
  String message = '';
  String? winner;

  List<Player> get alive => players.where((p) => p.alive).toList();

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  void _add() {
    final n = ctrl.text.trim();
    if (n.isEmpty || names.contains(n)) return;
    setState(() => names.add(n));
    ctrl.clear();
  }

  void _clearTargets() {
    killTarget = saveTarget = checkTarget = voteTarget = null;
  }

  void _start() {
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

  void _nextReveal() => setState(() {
        if (revealIndex == players.length - 1) {
          stage = Stage.night;
        } else {
          revealIndex++;
          revealed = false;
        }
      });

  void _show(String msg, Stage next) {
    message = msg;
    after = next;
    winner = checkWinner(players);
    stage = winner != null ? Stage.end : Stage.info;
  }

  void _resolveNight() => setState(() {
        final k = killTarget;
        String msg;
        if (k == null) {
          msg = "Tun tinch o'tdi. Hech kim o'lmadi.";
        } else if (k == saveTarget) {
          msg = "Mafiya hujum qildi, lekin doktor qutqardi! Hech kim o'lmadi.";
        } else {
          k.alive = false;
          msg = "${k.name} tunda o'ldirildi. Roli: ${k.role.title}.";
        }
        voteTarget = null;
        _show(msg, Stage.vote);
      });

  void _resolveVote() => setState(() {
        final v = voteTarget;
        String msg;
        if (v == null) {
          msg = "Hech kim chiqarilmadi.";
        } else {
          v.alive = false;
          msg = "${v.name} ovoz berish bilan chiqarildi. Roli: ${v.role.title}.";
        }
        round++;
        _clearTargets();
        _show(msg, Stage.night);
      });

  void _reset() => setState(() {
        players = [];
        stage = Stage.setup;
      });

  @override
  Widget build(BuildContext context) {
    final body = switch (stage) {
      Stage.setup => _setup(),
      Stage.reveal => _reveal(),
      Stage.night => _night(),
      Stage.info => _info(),
      Stage.vote => _vote(),
      Stage.end => _end(),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(
          (stage == Stage.setup || stage == Stage.reveal)
              ? 'Mafiya'
              : 'Mafiya · $round-raund',
        ),
      ),
      body: SafeArea(child: body),
    );
  }

  TextStyle? get _h => Theme.of(context).textTheme.headlineSmall;

  Widget _setup() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                decoration: const InputDecoration(labelText: "O'yinchi ismi"),
                onSubmitted: (_) => _add(),
              ),
            ),
            IconButton(onPressed: _add, icon: const Icon(Icons.add)),
          ]),
          Expanded(
            child: ListView(children: [
              for (var i = 0; i < names.length; i++)
                ListTile(
                  title: Text(names[i]),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => names.removeAt(i)),
                  ),
                ),
            ]),
          ),
          Text("Kamida 5 o'yinchi kerak (hozir: ${names.length})"),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: names.length >= 5 ? _start : null,
            child: const Text("O'yinni boshlash"),
          ),
        ]),
      );

  Widget _reveal() {
    final p = players[revealIndex];
    final mates = players
        .where((x) => x.role == Role.mafia && x != p)
        .map((x) => x.name)
        .join(', ');
    final last = revealIndex == players.length - 1;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            revealed ? p.role.title : p.name,
            style: Theme.of(context).textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (!revealed) ...[
            Text("Telefonni ${p.name}ga bering. Boshqalar qaramasin!",
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => setState(() => revealed = true),
              child: const Text("Rolimni ko'rish"),
            ),
          ] else ...[
            Text(p.role.hint, textAlign: TextAlign.center),
            if (p.role == Role.mafia && mates.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text("Sherigingiz: $mates", textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _nextReveal,
              child: Text(last
                  ? "Yetakchiga qaytaring va boshlang"
                  : "Yopish va keyingisiga"),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _pick(String label, Player? value, ValueChanged<Player?> on,
          {bool roles = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final p in alive)
            ChoiceChip(
              label: Text(roles ? '${p.name} (${p.role.title})' : p.name),
              selected: value == p,
              onSelected: (s) => setState(() => on(s ? p : null)),
            ),
        ]),
      ]);

  Widget _night() => ListView(padding: const EdgeInsets.all(16), children: [
        Text('Tun. Shahar uxlaydi.', style: _h),
        const SizedBox(height: 4),
        const Text(
            "Yetakchi: har bir rolni navbat bilan uyg'oting va tanlovini kiriting."),
        _pick("Mafiya kimni o'ldiradi?", killTarget, (p) => killTarget = p,
            roles: true),
        _pick("Doktor kimni qutqaradi?", saveTarget, (p) => saveTarget = p,
            roles: true),
        _pick("Komissar kimni tekshiradi?", checkTarget, (p) => checkTarget = p,
            roles: true),
        if (checkTarget != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              checkTarget!.role == Role.mafia
                  ? 'Javob: MAFIYA'
                  : "Javob: mafiya emas",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _resolveNight,
          child: const Text('Tongni boshlash'),
        ),
      ]);

  Widget _info() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message, textAlign: TextAlign.center, style: _h),
            const SizedBox(height: 8),
            Text("Tirik o'yinchilar: ${alive.length}"),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => setState(() => stage = after),
              child: Text(
                  after == Stage.vote ? "Ovoz berishga o'tish" : "Tunga o'tish"),
            ),
          ]),
        ),
      );

  Widget _vote() => ListView(padding: const EdgeInsets.all(16), children: [
        Text('Kun. Muhokama va ovoz berish', style: _h),
        const SizedBox(height: 4),
        const Text(
            "Eng ko'p ovoz olganni tanlang. Hech kim tanlanmasa, hech kim chiqarilmaydi."),
        _pick('Kim chiqariladi?', voteTarget, (p) => voteTarget = p),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _resolveVote,
          child: const Text('Ovozni yakunlash'),
        ),
      ]);

  Widget _end() => ListView(padding: const EdgeInsets.all(16), children: [
        Text("$winner g'alaba qildi!", style: _h),
        const SizedBox(height: 8),
        Text(message),
        const SizedBox(height: 16),
        for (final p in players)
          ListTile(
            title: Text(p.name),
            subtitle: Text(p.role.title),
            trailing: Text(p.alive ? 'Tirik' : "O'lgan"),
          ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _reset, child: const Text("Yangi o'yin")),
      ]);
}
