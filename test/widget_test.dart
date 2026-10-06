import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_uz/main.dart';

void main() {
  testWidgets('Mafia app starts', (tester) async {
    await tester.pumpWidget(const MafiaApp());
    expect(find.text('MAFIA'), findsOneWidget);
  });
}
