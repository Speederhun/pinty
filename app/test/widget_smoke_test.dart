import 'package:flutter_test/flutter_test.dart';
import 'package:pinty/app_state.dart';
import 'package:pinty/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('az app elindul és üres állapotot mutat', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.load();
    await tester.pumpWidget(PintyApp(state: state));
    expect(find.textContaining('Még nincs elem'), findsOneWidget);
  });
}
