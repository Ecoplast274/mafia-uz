import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_uz/game.dart';

void main() {
  test('4-player minimum room gets one mafia, doctor and sheriff', () {
    final roles = dealRoles(4);

    expect(roles.length, 4);
    expect(roles.where((r) => r == Role.mafia).length, 1);
    expect(roles.where((r) => r == Role.doctor).length, 1);
    expect(roles.where((r) => r == Role.sheriff).length, 1);
    expect(roles.where((r) => r == Role.citizen).length, 1);
  });

  test('8-player room gets two mafia, doctor and sheriff', () {
    final roles = dealRoles(8);

    expect(roles.length, 8);
    expect(roles.where((r) => r == Role.mafia).length, 2);
    expect(roles.where((r) => r == Role.doctor).length, 1);
    expect(roles.where((r) => r == Role.sheriff).length, 1);
  });

  test('12-player room gets three mafia, doctor and sheriff', () {
    final roles = dealRoles(12);

    expect(roles.length, 12);
    expect(roles.where((r) => r == Role.mafia).length, 3);
    expect(roles.where((r) => r == Role.doctor).length, 1);
    expect(roles.where((r) => r == Role.sheriff).length, 1);
  });

  test('mafia count scales predictably with room size', () {
    for (var n = 4; n <= 12; n++) {
      final roles = dealRoles(n);
      final mafiaCount = roles.where((r) => r == Role.mafia).length;

      expect(mafiaCount, n ~/ 4);
      expect(roles.length, n);
    }
  });

  test('mafia wins when mafia count reaches or exceeds civilians', () {
    final players = [
      Player('M1', Role.mafia),
      Player('M2', Role.mafia),
      Player('C1', Role.citizen),
      Player('C2', Role.citizen),
    ];

    expect(checkWinner(players), 'Mafiya');
  });

  test('dead civilian is ignored when checking the winner', () {
    final players = [
      Player('M', Role.mafia),
      Player('D', Role.doctor),
      Player('S', Role.sheriff),
      Player('C', Role.citizen)..alive = false,
    ];

    expect(checkWinner(players), isNull);
  });

  test('citizens win when no mafia remains', () {
    final players = [
      Player('D', Role.doctor),
      Player('S', Role.sheriff),
      Player('C', Role.citizen),
    ];

    expect(checkWinner(players), 'Tinch aholi');
  });

  test('dead mafia does not count toward the mafia side', () {
    final mafia = Player('M', Role.mafia)..alive = false;
    final players = [
      mafia,
      Player('D', Role.doctor),
      Player('C', Role.citizen),
    ];

    expect(checkWinner(players), 'Tinch aholi');
  });

  test('empty player list has no winner', () {
    expect(checkWinner([]), isNull);
  });

  test('too-small games are rejected', () {
    expect(() => dealRoles(3), throwsArgumentError);
  });
}
