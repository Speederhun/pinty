import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme/pinty_theme.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.load();
  runApp(PintyApp(state: state));
}

class PintyApp extends StatelessWidget {
  const PintyApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: 'Pinty',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(state.theme),
        home: HomePage(state: state),
      ),
    );
  }
}
