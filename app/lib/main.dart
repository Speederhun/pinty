import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api/pinty_api.dart';
import 'app_state.dart';
import 'data/local_store.dart';
import 'data/vault_repository.dart';
import 'theme/pinty_theme.dart';
import 'ui/auth_pages.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await FileLocalStore.open();
  final state = AppState(
    repo: VaultRepository(store: store, apiFactory: (url) => PintyApi(url)),
  );
  await state.init();
  runApp(PintyApp(state: state));
}

class PintyApp extends StatefulWidget {
  const PintyApp({super.key, required this.state});
  final AppState state;

  @override
  State<PintyApp> createState() => _PintyAppState();
}

class _PintyAppState extends State<PintyApp> with WidgetsBindingObserver {
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(_onState);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Zároláskor minden megnyitott oldalt és párbeszédablakot bezárunk,
  // hogy ne maradjon kinyitott adat a képernyőn.
  void _onState() {
    if (widget.state.stage != Stage.unlocked) {
      _navKey.currentState?.popUntil((r) => r.isFirst);
    }
  }

  // Androidon háttérbe kerüléskor zárolunk.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused && defaultTargetPlatform == TargetPlatform.android) {
      widget.state.lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: 'Pinty',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navKey,
        theme: buildTheme(state.theme),
        builder: (context, child) => Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => state.touch(),
          child: child,
        ),
        home: switch (state.stage) {
          Stage.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
          Stage.welcome => WelcomePage(state: state),
          Stage.locked => UnlockPage(state: state),
          Stage.unlocked => HomePage(state: state),
        },
      ),
    );
  }
}
