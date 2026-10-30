import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_mobile/main.dart';

void main() {
  testWidgets('le mobile démarre', (tester) async {
    await tester.pumpWidget(const SighMobile());
    expect(find.textContaining('SIGH-CNT'), findsOneWidget);
  });
}
