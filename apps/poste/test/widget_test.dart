import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/main.dart';

void main() {
  testWidgets('le poste fileul démarre, annonce son mode et montre la pastille (hors ligne tant que rien n\'est branché)', (tester) async {
    await tester.pumpWidget(const SighPoste());
    expect(find.textContaining('fileul'), findsOneWidget);
    expect(find.textContaining('Hors ligne'), findsOneWidget);
  });
}
