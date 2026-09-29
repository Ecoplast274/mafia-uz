import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'game.dart';

void main() => runApp(const MafiaApp());

const turnSeconds = 30;

enum AppLang { uz, ru, en }

String langName(AppLang l) => switch (l) {
      AppLang.uz => "O'zbek",
      AppLang.ru => 'Русский',
      AppLang.en => 'English',
    };

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

String roleTitle(Role r, AppLang l) {
  const m = {
    Role.mafia: {'uz': 'Mafiya', 'ru': 'Мафия', 'en': 'Mafia'},
    Role.doctor: {'uz': 'Doktor', 'ru': 'Доктор', 'en': 'Doctor'},
    Role.sheriff: {'uz': 'Komissar', 'ru': 'Комиссар', 'en': 'Sheriff'},
    Role.citizen: {'uz': 'Tinch aholi', 'ru': 'Мирный житель', 'en': 'Citizen'},
  };
  return m[r]![l.name]!;
}

String roleHint(Role r, AppLang l) {
  const m = {
    Role.mafia: {
      'uz': "Har tuni tunda bitta odamni o'ldirasiz.",
      'ru': 'Каждую ночь вы убиваете одного игрока.',
      'en': 'Each night you kill one player.',
    },
    Role.doctor: {
      'uz': "Har tuni tunda bitta odamni o'limdan qutqarasiz.",
      'ru': 'Каждую ночь вы спасаете одного игрока.',
      'en': 'Each night you save one player.',
    },
    Role.sheriff: {
      'uz': "Har tuni tunda bitta odamni tekshirasiz: mafiyami yoki yo'q.",
      'ru': 'Каждую ночь вы проверяете одного игрока — мафия он или нет.',
      'en': "Each night you check one player: mafia or not.",
    },
    Role.citizen: {
      'uz': 'Kunduzi muhokama qilib, mafiyani toping.',
      'ru': 'Днём обсуждайте и вычисляйте мафию.',
      'en': 'During the day, discuss and find the mafia.',
    },
  };
  return m[r]![l.name]!;
}

const Map<String, Map<String, String>> _dict = {
  'appTitle': {'uz': 'MAFIYA', 'ru': 'МАФИЯ', 'en': 'MAFIA'},
  'subtitle': {
    'uz': "Shahar uxlaydi, mafiya uyg'onadi",
    'ru': 'Город спит, мафия просыпается',
    'en': 'The town sleeps, the mafia wakes',
  },
  'roomOddiy': {'uz': 'Oddiy xona', 'ru': 'Обычная комната', 'en': 'Standard room'},
  'roomPro': {'uz': 'Pro xona', 'ru': 'Про комната', 'en': 'Pro room'},
  'players': {'uz': "o'yinchi", 'ru': 'игроков', 'en': 'players'},
  'nameHint': {'uz': "O'yinchi ismi", 'ru': 'Имя игрока', 'en': 'Player name'},
  'fillDemo': {
    'uz': "Namuna ismlar bilan to'ldirish (sinash uchun)",
    'ru': 'Заполнить тестовыми именами',
    'en': 'Fill with sample names (for testing)',
  },
  'startGame': {'uz': "O'yinni boshlash", 'ru': 'Начать игру', 'en': 'Start game'},
  'dontLook': {
    'uz': 'Telefonni %n ga bering.\nBoshqalar qaramasin!',
    'ru': 'Передайте телефон %n.\nПусть другие не смотрят!',
    'en': "Hand the phone to %n.\nOthers shouldn't look!",
  },
  'showRole': {'uz': "Rolimni ko'rish", 'ru': 'Показать роль', 'en': 'Show my role'},
  'mates': {'uz': 'Sheriklaringiz: ', 'ru': 'Ваши сообщники: ', 'en': 'Your partners: '},
  'closeNext': {
    'uz': 'Yopish va keyingisiga',
    'ru': 'Закрыть и далее',
    'en': 'Close and next',
  },
  'closeToLeader': {
    'uz': 'Yetakchiga qaytaring',
    'ru': 'Верните ведущему',
    'en': 'Return to the host',
  },
  'nightTitle': {'uz': 'Tun', 'ru': 'Ночь', 'en': 'Night'},
  'nightSub': {
    'uz': 'Yetakchi: tanlovlarni kiriting.',
    'ru': 'Ведущий: введите выбор ролей.',
    'en': "Host: enter each role's choice.",
  },
  'mafiaAsk': {
    'uz': "Mafiya kimni o'ldiradi?",
    'ru': 'Кого убивает мафия?',
    'en': 'Who does the mafia kill?',
  },
  'doctorAsk': {
    'uz': 'Doktor kimni qutqaradi?',
    'ru': 'Кого спасает доктор?',
    'en': 'Who does the doctor save?',
  },
  'sheriffAsk': {
    'uz': 'Komissar kimni tekshiradi?',
    'ru': 'Кого проверяет комиссар?',
    'en': 'Who does the sheriff check?',
  },
  'answerMafia': {'uz': 'Javob: MAFIYA', 'ru': 'Ответ: МАФИЯ', 'en': 'Answer: MAFIA'},
  'showCheckResult': {'uz': "Komissar natijasini ko'rish", 'ru': 'Показать результат проверки', 'en': 'Show sheriff result'},
  'checkPrivate': {'uz': 'Telefonni faqat komissarga bering. Natijani boshqalarga ko\'rsatmang.', 'ru': 'Передайте телефон только комиссару. Не показывайте результат другим.', 'en': 'Give the phone only to the sheriff. Do not show the result to others.'},
  'answerClean': {
    'uz': "Javob: mafiya emas",
    'ru': 'Ответ: не мафия',
    'en': 'Answer: not mafia',
  },
  'startMorning': {'uz': 'Tongni boshlash', 'ru': 'Начать утро', 'en': 'Start morning'},
  'aliveCount': {
    'uz': "Tirik o'yinchilar: ",
    'ru': 'Живых игроков: ',
    'en': 'Alive players: ',
  },
  'goToTalk': {
    'uz': "Gaplashishga o'tish",
    'ru': 'Перейти к обсуждению',
    'en': 'Go to discussion',
  },
  'goToNight': {'uz': "Tunga o'tish", 'ru': 'Перейти к ночи', 'en': 'Go to night'},
  'talkTitle': {'uz': 'Gaplashish', 'ru': 'Обсуждение', 'en': 'Discussion'},
  'turn': {'uz': 'Navbat: ', 'ru': 'Очередь: ', 'en': 'Turn: '},
  'speaking': {'uz': ' gapiryapti', 'ru': ' говорит', 'en': ' is speaking'},
  'nextPlayer': {'uz': "Keyingi o'yinchi", 'ru': 'Следующий игрок', 'en': 'Next player'},
  'goToVote': {
    'uz': 'Ovoz berishga o\'tish',
    'ru': 'Перейти к голосованию',
    'en': 'Go to voting',
  },
  'voteTitle': {'uz': 'Ovoz berish', 'ru': 'Голосование', 'en': 'Voting'},
  'voter': {'uz': 'Ovoz beruvchi: ', 'ru': 'Голосует: ', 'en': 'Voting: '},
  'nextVoter': {'uz': 'Keyingi ovoz', 'ru': 'Следующий голос', 'en': 'Next vote'},
  'voteTie': {'uz': 'Ovozlar teng bo\'ldi. Hech kim chiqarilmadi.', 'ru': 'Голоса разделились поровну. Никто не выбыл.', 'en': 'The vote was tied. No one was eliminated.'},
  'voteSub': {
    'uz': "Eng ko'p ovoz olganni tanlang.",
    'ru': 'Выберите набравшего больше голосов.',
    'en': 'Choose who got the most votes.',
  },
  'voteAsk': {'uz': 'Kim chiqariladi?', 'ru': 'Кого исключаем?', 'en': 'Who is voted out?'},
  'voteNote': {
    'uz': "Hech kim tanlanmasa, hech kim chiqarilmaydi.",
    'ru': 'Если никто не выбран, никто не выбывает.',
    'en': 'If no one is chosen, no one is out.',
  },
  'finishVote': {'uz': 'Ovozni yakunlash', 'ru': 'Завершить голосование', 'en': 'Finish vote'},
  'citizenWin': {'uz': 'Tinch aholi', 'ru': 'Мирные жители', 'en': 'Citizens'},
  'mafiaWin': {'uz': 'Mafiya', 'ru': 'Мафия', 'en': 'Mafia'},
  'winSuffix': {"uz": " g'alaba qildi!", 'ru': ' побеждает!', 'en': ' wins!'},
  'newGame': {'uz': "Yangi o'yin", 'ru': 'Новая игра', 'en': 'New game'},
  'alive': {'uz': 'Tirik', 'ru': 'Жив', 'en': 'Alive'},
  'dead': {'uz': "O'lgan", 'ru': 'Мёртв', 'en': 'Dead'},
  'settings': {'uz': 'Sozlamalar', 'ru': 'Настройки', 'en': 'Settings'},
  'language': {'uz': 'Til', 'ru': 'Язык', 'en': 'Language'},
  'close': {'uz': 'Yopish', 'ru': 'Закрыть', 'en': 'Close'},
  'nightPeaceful': {
    'uz': "Tun tinch o'tdi. Hech kim o'lmadi.",
    'ru': 'Ночь прошла спокойно. Никто не погиб.',
    'en': 'The night was peaceful. No one died.',
  },
  'nightSaved': {
    'uz': "Mafiya hujum qildi, lekin doktor qutqardi! Hech kim o'lmadi.",
    'ru': 'Мафия напала, но доктор спас! Никто не погиб.',
    'en': 'The mafia attacked, but the doctor saved them! No one died.',
  },
  'nightKilled': {
    'uz': " tunda o'ldirildi.\nRoli: ",
    'ru': ' был убит ночью.\nРоль: ',
    'en': ' was killed at night.\nRole: ',
  },
  'voteNoneOut': {'uz': 'Hech kim chiqarilmadi.', 'ru': 'Никто не выбыл.', 'en': 'No one was voted out.'},
  'voteOut': {
    'uz': ' ovoz berish bilan chiqarildi.\nRoli: ',
    'ru': ' выбыл по голосованию.\nРоль: ',
    'en': ' was voted out.\nRole: ',
  },
};

extension _Tr on AppLang {
  String t(String key) => _dict[key]?[name] ?? _dict[key]?['uz'] ?? key;
}

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
          scaffoldBackgroundColor: const Color(0xFF09060A),
          splashFactory: InkSparkle.splashFactory,
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white10,
            hintStyle: const TextStyle(color: Colors.white38),
            prefixIconColor: Colors.white70,
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
          ),
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
  AppLang lang = AppLang.uz;
  final names = <String>[];
  final ctrl = TextEditingController();
  List<Player> players = [];
  List<Player> speakers = [];
  int speakIndex = 0;
  int revealIndex = 0;
  bool revealed = false;
  bool sheriffResultRevealed = false;
  int round = 1;
  int timeLeft = turnSeconds;
  Timer? timer;
  Player? killTarget, saveTarget, checkTarget, voteTarget;
  List<Player> voters = [];
  int voteIndex = 0;
  final Map<Player, int> voteCounts = {};
  String message = '';
  String? winner;
  IconData infoIcon = Icons.wb_sunny;
  Color infoColor = Colors.amber;

  String t(String key) => lang.t(key);

  @override
  void dispose() {
    timer?.cancel();
    ctrl.dispose();
    super.dispose();
  }

  List<Player> get alive => players.where((p) => p.alive).toList();

  bool _roleAlive(Role role) =>
      players.any((p) => p.alive && p.role == role);


  // ---------- Taymer ----------

  void _startTimer(VoidCallback onEnd) {
    timer?.cancel();
    timeLeft = turnSeconds;
    timer = Timer.periodic(const Duration(seconds: 1), (tm) {
      if (!mounted) return;
      setState(() => timeLeft--);
      if (timeLeft <= 0) {
        tm.cancel();
        onEnd();
      }
    });
  }

  // ---------- Mantiq ----------

  void _add() {
    final n = ctrl.text.trim();
    final duplicate = names.any(
      (x) => x.trim().toLowerCase() == n.toLowerCase(),
    );
    if (n.isEmpty || duplicate || names.length >= room) return;
    setState(() => names.add(n));
    ctrl.clear();
  }

  void _fill() => setState(() {
        for (var i = names.length; i < room; i++) {
          names.add('${i + 1}');
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
      sheriffResultRevealed = false;
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
    timer?.cancel();
    _clearTargets();

    final currentWinner = checkWinner(players);
    if (currentWinner != null) {
      setState(() {
        winner = currentWinner;
        stage = Stage.end;
      });
      return;
    }

    setState(() => stage = Stage.night);
    _startTimer(_resolveNight);
  }

  void _toTalk() {
    timer?.cancel();

    if (alive.isEmpty) {
      return;
    }

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

    if (speakers.isEmpty) {
      _toNight();
      return;
    }

    if (speakIndex >= speakers.length - 1) {
      _toVote();
      return;
    }
    setState(() => speakIndex++);
    _startTimer(_nextSpeaker);
  }

  void _toVote() {
    timer?.cancel();
    voters = alive.toList();
    voteIndex = 0;
    voteTarget = null;
    voteCounts.clear();

    if (voters.isEmpty) {
      _toNight();
      return;
    }

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
      final k = _roleAlive(Role.mafia) ? killTarget : null;
      String msg;
      IconData icon;
      Color color;
      if (k == null) {
        msg = _roleAlive(Role.mafia)
            ? t('nightPeaceful')
            : "Mafiya tirik emas. " + t('nightPeaceful');
        icon = Icons.nightlight_round;
        color = const Color(0xFF9FA8DA);
      } else if (k == saveTarget) {
        msg = t('nightSaved');
        icon = Icons.health_and_safety;
        color = Colors.greenAccent;
      } else {
        k.alive = false;
        msg =
            '№${players.indexOf(k) + 1} ${k.name}${t('nightKilled')}${roleTitle(k.role, lang)}';
        icon = Icons.dangerous;
        color = Colors.redAccent;
      }
      voteTarget = null;
      _show(msg, Stage.talk, icon, color);
    });
  }

  void _resolveVote() {
    timer?.cancel();

    final voter = voters.isEmpty ? null : voters[voteIndex];
    final target = voteTarget;
    if (voter != null && target != null && target != voter && target.alive) {
      voteCounts[target] = (voteCounts[target] ?? 0) + 1;
    }

    voteTarget = null;

    if (voter != null && voteIndex < voters.length - 1) {
      setState(() => voteIndex++);
      _startTimer(_resolveVote);
      return;
    }

    final maxVotes = voteCounts.values.isEmpty
        ? 0
        : voteCounts.values.reduce(math.max);
    final leaders = voteCounts.entries
        .where((e) => e.value == maxVotes && maxVotes > 0)
        .map((e) => e.key)
        .toList();

    setState(() {
      String msg;
      IconData icon;
      Color color;

      if (leaders.length != 1) {
        msg = leaders.isEmpty ? t('voteNoneOut') : t('voteTie');
        icon = Icons.how_to_vote;
        color = Colors.amber;
      } else {
        final v = leaders.single;
        v.alive = false;
        msg =
            '№${players.indexOf(v) + 1} ${v.name}${t('voteOut')}${roleTitle(v.role, lang)}';
        icon = Icons.gavel;
        color = Colors.orangeAccent;
      }

      round++;
      _clearTargets();
      voters = [];
      voteIndex = 0;
      voteCounts.clear();
      _show(msg, Stage.night, icon, color);
    });
  }

  void _reset() {
    timer?.cancel();
    setState(() {
      players = [];
      stage = Stage.setup;
      revealIndex = 0;
      revealed = false;
      round = 1;
      winner = null;
      message = '';
      speakers = [];
      speakIndex = 0;
      voters = [];
      voteIndex = 0;
      voteCounts.clear();
      _clearTargets();
    });
  }

  // ---------- Sozlamalar ----------

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1D1114),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Row(children: [
              const Icon(Icons.settings, color: Colors.redAccent),
              const SizedBox(width: 10),
              Text(t('settings'),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(t('language'),
                  style: const TextStyle(
                      color: Colors.white70, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            for (final l in AppLang.values)
              ListTile(
                onTap: () {
                  setState(() => lang = l);
                  setSheet(() {});
                },
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  lang == l
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: lang == l ? Colors.redAccent : Colors.white38,
                ),
                title: Text(langName(l)),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(t('close')),
              ),
            ),
          ]),
        ),
      ),
    );
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
          gradient: RadialGradient(
            colors: [color.withAlpha(80), color.withAlpha(18), Colors.transparent],
            stops: const [0.25, 0.68, 1.0],
          ),
          border: Border.all(color: color.withAlpha(210), width: 2),
          boxShadow: [
            BoxShadow(color: color.withAlpha(100), blurRadius: 28, spreadRadius: 3),
          ],
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
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              (color ?? Colors.white).withAlpha(30),
              Colors.white.withAlpha(9),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: (color ?? Colors.white).withAlpha(32)),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 7)),
          ],
        ),
        child: child,
      );

  Widget _btn(String text, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(58),
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            elevation: 8,
            shadowColor: Colors.redAccent.withAlpha(90),
            textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
    return roles ? '$s · ${roleTitle(p.role, lang)}' : s;
  }

  Widget _pick(String label, IconData icon, Color color, Player? value,
          ValueChanged<Player?> on,
          {bool roles = false, bool excludeMafia = false, Player? excludePlayer}) =>
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
            for (final p in alive.where(
                (p) =>
                    (!excludeMafia || p.role != Role.mafia) &&
                    (excludePlayer == null || p != excludePlayer)))
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
      final av = n > 8 ? 34.0 : 40.0;
      final sw = av + 22;
      final rx = w / 2 - sw / 2;
      final ry = w / 2 - av;
      return SizedBox(
        width: w,
        height: w,
        child: Stack(children: [
          Center(
            child: Container(
              width: w * 0.7,
              height: w * 0.7,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF1F5A38),
                    const Color(0xFF12351F),
                  ],
                ),
                border: Border.all(color: const Color(0xFF6D4C41), width: 6),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black54, blurRadius: 20, spreadRadius: 2),
                ],
              ),
              child: Text('MAFIYA',
                  style: TextStyle(
                    color: Colors.white.withAlpha(40),
                    fontSize: w * 0.11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  )),
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
        Stage.night => const [
            Color(0xFF05060F),
            Color(0xFF0E1A3D),
            Color(0xFF1B2A5A),
          ],
        Stage.talk || Stage.vote => const [
            Color(0xFF2A1206),
            Color(0xFF5A2E0C),
            Color(0xFF8A4B14),
          ],
        Stage.end => const [
            Color(0xFF120707),
            Color(0xFF3D0F0F),
            Color(0xFF5A1414),
          ],
        _ => const [
            Color(0xFF0F0506),
            Color(0xFF2B0A0D),
            Color(0xFF4A1013),
          ],
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
          (stage == Stage.setup || stage == Stage.reveal) ? '' : '$round-raund',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _bg,
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -90,
              right: -70,
              child: _ambientOrb(Colors.redAccent, 190),
            ),
            Positioned(
              top: 170,
              left: -110,
              child: _ambientOrb(
                stage == Stage.night
                    ? const Color(0xFF4A5FFF)
                    : Colors.deepOrange,
                220,
              ),
            ),
            Positioned(
              bottom: -120,
              right: -80,
              child: _ambientOrb(Colors.purpleAccent, 240),
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -0.35),
                      radius: 1.2,
                      colors: [Colors.transparent, Colors.black54],
                      stops: [0.35, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: KeyedSubtree(
                  key: ValueKey(
                    '$stage-$revealIndex-$revealed-$round-$speakIndex-${lang.name}',
                  ),
                  child: body,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ambientOrb(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withAlpha(55), color.withAlpha(8), Colors.transparent],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
      );

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
            Text('$size ${t('players')}',
                style: const TextStyle(color: Colors.white70)),
          ]),
        ),
      ),
    );
  }

  Widget _setup() => ListView(padding: const EdgeInsets.all(20), children: [
        const SizedBox(height: 28),
        Center(child: _hero(Icons.theater_comedy, Colors.redAccent, size: 78)),
        const SizedBox(height: 18),
        Text(t('appTitle'),
            textAlign: TextAlign.center,
            style: _big?.copyWith(letterSpacing: 8)),
        const SizedBox(height: 4),
        Text(
          t('subtitle'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 14, letterSpacing: 0.4),
        ),
        const SizedBox(height: 24),
        Row(children: [
          _roomCard(8, t('roomOddiy'), Icons.groups),
          _roomCard(12, t('roomPro'), Icons.workspace_premium),
        ]),
        const SizedBox(height: 14),
        _card(
          pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: Colors.redAccent,
          child: Row(
            children: [
              const Icon(Icons.nightlife, color: Colors.redAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${names.length} / $room  •  ${t('players')}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(
                names.length == room ? Icons.check_circle : Icons.groups,
                color: names.length == room ? Colors.greenAccent : Colors.white54,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              onSubmitted: (_) => _add(),
              decoration: InputDecoration(
                hintText: t('nameHint'),
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
            '${names.length} / $room',
            style: TextStyle(
              color: names.length == room ? Colors.greenAccent : Colors.white70,
            ),
          ),
        ),
        TextButton(
          onPressed: _fill,
          child: Text(t('fillDemo')),
        ),
        _btn(t('startGame'), names.length == room ? _start : null),
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
          Text(revealed ? roleTitle(p.role, lang).toUpperCase() : p.name,
              textAlign: TextAlign.center,
              style: _big?.copyWith(color: revealed ? c : Colors.white)),
          const SizedBox(height: 12),
          if (!revealed) ...[
            Text(t('dontLook').replaceAll('%n', p.name),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 32),
            _btn(t('showRole'), () => setState(() => revealed = true)),
          ] else ...[
            Text(roleHint(p.role, lang),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16)),
            if (p.role == Role.mafia && mates.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('${t('mates')}$mates',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            const SizedBox(height: 32),
            _btn(last ? t('closeToLeader') : t('closeNext'), _nextReveal),
          ],
        ]),
      ),
    );
  }

  Widget _night() => ListView(padding: const EdgeInsets.all(16), children: [
        _head(Icons.nightlight_round, const Color(0xFF9FA8DA), t('nightTitle'),
            t('nightSub'),
            timerOn: true),
        _table(),
        if (_roleAlive(Role.mafia))
          _pick(t('mafiaAsk'), roleIcon(Role.mafia), roleColor(Role.mafia),
              killTarget, (p) => killTarget = p,
              excludeMafia: true),
        if (_roleAlive(Role.doctor))
          _pick(t('doctorAsk'), roleIcon(Role.doctor), roleColor(Role.doctor),
              saveTarget, (p) => saveTarget = p,
              ),
        if (_roleAlive(Role.sheriff))
          _pick(t('sheriffAsk'), roleIcon(Role.sheriff), roleColor(Role.sheriff),
              checkTarget, (p) => checkTarget = p,
              ),
        if (checkTarget != null)
          _card(
            color: Colors.blueAccent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock, color: Colors.blueAccent),
                const SizedBox(height: 8),
                Text(t('checkPrivate'),
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 10),
                _btn(
                  sheriffResultRevealed
                      ? (checkTarget!.role == Role.mafia
                          ? t('answerMafia')
                          : t('answerClean'))
                      : t('showCheckResult'),
                  () => setState(
                      () => sheriffResultRevealed = !sheriffResultRevealed),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        _btn(t('startMorning'), _resolveNight),
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
            Text('${t('aliveCount')}${alive.length}',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 28),
            _btn(after == Stage.talk ? t('goToTalk') : t('goToNight'), _next),
          ]),
        ),
      );

  Widget _talk() {
    final sp = speakers[speakIndex];
    final last = speakIndex == speakers.length - 1;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _head(Icons.record_voice_over, Colors.amber, t('talkTitle'),
          '${t('turn')}${speakIndex + 1} / ${speakers.length}',
          timerOn: true),
      _table(speaker: sp),
      _card(
        color: Colors.amber,
        child: Row(children: [
          const Icon(Icons.mic, color: Colors.amber, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Text('${_lbl(sp, false)}${t('speaking')}',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
      _btn(last ? t('goToVote') : t('nextPlayer'), _nextSpeaker),
      const SizedBox(height: 16),
    ]);
  }

  Widget _vote() {
    final voter = voters[voteIndex];
    final last = voteIndex == voters.length - 1;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _head(Icons.how_to_vote, Colors.orangeAccent, t('voteTitle'),
          '${t('voter')}${_lbl(voter, false)}',
          timerOn: true),
      _table(speaker: voter),
      _pick(
        t('voteAsk'),
        Icons.how_to_vote,
        Colors.orangeAccent,
        voteTarget,
        (p) => voteTarget = p,
        excludePlayer: voter,
      ),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Text(t('voteNote'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70)),
      ),
      _btn(last ? t('finishVote') : t('nextVoter'), _resolveVote),
      const SizedBox(height: 16),
    ]);
  }

  Widget _end() {
    final winTxt = winner == 'Mafiya' ? t('mafiaWin') : t('citizenWin');
    return ListView(padding: const EdgeInsets.all(16), children: [
      const SizedBox(height: 48),
      Center(
        child: _hero(
          Icons.emoji_events,
          winner == 'Mafiya' ? Colors.redAccent : Colors.greenAccent,
        ),
      ),
      const SizedBox(height: 16),
      Text('$winTxt${t('winSuffix')}',
          textAlign: TextAlign.center, style: _big),
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
                  Text(roleTitle(players[i].role, lang),
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            Text(players[i].alive ? t('alive') : t('dead'),
                style: TextStyle(
                    color: players[i].alive
                        ? Colors.greenAccent
                        : Colors.white38)),
          ]),
        ),
      const SizedBox(height: 8),
      _btn(t('newGame'), _reset),
      const SizedBox(height: 16),
    ]);
  }
}