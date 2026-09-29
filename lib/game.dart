import 'dart:math';

enum Role { mafia, doctor, sheriff, citizen }

extension RoleInfo on Role {
  String get title => switch (this) {
        Role.mafia => 'Mafiya',
        Role.doctor => 'Doktor',
        Role.sheriff => 'Komissar',
        Role.citizen => 'Tinch aholi',
      };

  String get hint => switch (this) {
        Role.mafia => "Har tuni tunda bitta odamni o'ldirasiz.",
        Role.doctor => "Har tuni tunda bitta odamni o'limdan qutqarasiz.",
        Role.sheriff =>
          "Har tuni tunda bitta odamni tekshirasiz: mafiyami yoki yo'q.",
        Role.citizen => "Kunduzi muhokama qilib, mafiyani toping.",
      };
}

class Player {
  final String name;
  final Role role;
  bool alive = true;
  Player(this.name, this.role);
}

List<Role> dealRoles(int n) {
  if (n < 4) {
    throw ArgumentError('Kamida 4 ta o\'yinchi kerak.');
  }

  final mafia = max(1, n ~/ 4);
  final roles = <Role>[
    ...List.filled(mafia, Role.mafia),
    Role.doctor,
    Role.sheriff,
  ];

  while (roles.length < n) {
    roles.add(Role.citizen);
  }

  // Himoyalangan rollar soni hech qachon o'yinchilar sonidan oshib ketmasin.
  if (roles.length > n) {
    roles.removeRange(n, roles.length);
  }

  roles.shuffle();
  return roles;
}

String? checkWinner(List<Player> ps) {
  if (ps.isEmpty) return null;

  final m = ps.where((p) => p.alive && p.role == Role.mafia).length;
  final o = ps.where((p) => p.alive && p.role != Role.mafia).length;

  if (m == 0) return 'Tinch aholi';
  if (m >= o) return 'Mafiya';
  return null;
}
