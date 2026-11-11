import 'package:flutter_test/flutter_test.dart';
import 'package:pinty/app_state.dart';
import 'package:pinty/data/local_store.dart';
import 'package:pinty/data/vault_repository.dart';
import 'package:pinty/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('első indításkor a fiók létrehozása képernyő látszik', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = VaultRepository(
      store: MemoryLocalStore(),
      apiFactory: (_) => throw UnimplementedError(),
    );
    final state = AppState(repo: repo);
    await state.init();
    await tester.pumpWidget(PintyApp(state: state));

    expect(state.stage, Stage.welcome);
    expect(find.text('Új fiók'), findsOneWidget);
    expect(find.text('Fiók létrehozása'), findsOneWidget);
  });
}
