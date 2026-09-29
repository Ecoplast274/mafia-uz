import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_uz/main.dart';

void main() {
  testWidgets('Mafiya app starts', (tester) async {
    await tester.pumpWidget(const MafiaApp());
    expect(find.text('MAFIYA'), findsOneWidget);
  });
}
