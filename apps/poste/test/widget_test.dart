import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/main.dart';

void main() {
  testWidgets('le poste démarre et annonce son mode', (tester) async {
    await tester.pumpWidget(const SighPoste());
    expect(find.textContaining('SIGH-CNT'), findsOneWidget);
    expect(find.textContaining('fileul'), findsOneWidget); // mode par défaut
  });
}
