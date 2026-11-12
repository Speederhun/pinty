import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme/pinty_theme.dart';
import 'home_page.dart';
import 'notes_page.dart';
import 'settings_page.dart';

/// A bejelentkezés utáni keret: két fül (Jelszavak / Jegyzetek).
/// Széles képernyőn keskeny oldalsáv, telefonon alsó fülsor.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state});
  final AppState state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    // Új fiók után egyszer felajánljuk a visszaállító kulcs elkészítését.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && state.recoveryHint) {
        state.recoveryHint = false;
        showRecoverySetup(context, state);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = pintyPalettes[state.theme]!;
    final pages = IndexedStack(index: state.tab, children: [
      PasswordsPage(state: state),
      NotesPage(state: state),
      SettingsPage(state: state),
    ]);
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) {
        return Scaffold(
          body: Row(children: [
            _Rail(state: state, palette: p),
            Expanded(child: pages),
          ]),
        );
      }
      return Scaffold(
        body: pages,
        bottomNavigationBar: NavigationBar(
          selectedIndex: state.tab,
          onDestinationSelected: state.setTab,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.key_outlined), selectedIcon: Icon(Icons.key), label: 'Jelszavak'),
            NavigationDestination(
                icon: Icon(Icons.edit_note_outlined), selectedIcon: Icon(Icons.edit_note), label: 'Jegyzetek'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Beállítások'),
          ],
        ),
      );
    });
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.state, required this.palette});
  final AppState state;
  final PintyPalette palette;

  @override
  Widget build(BuildContext context) {
    Widget tab(int i, IconData icon, String label) {
      final on = state.tab == i;
      return Semantics(
        button: true,
        selected: on,
        label: label,
        child: InkWell(
          onTap: () => state.setTab(i),
          child: Container(
            width: 76,
            padding: const EdgeInsets.symmetric(vertical: 12),
            color: on ? Colors.white.withValues(alpha: 0.12) : null,
            child: Column(children: [
              Icon(icon, color: on ? Colors.white : Colors.white60),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 11, color: on ? Colors.white : Colors.white60)),
            ]),
          ),
        ),
      );
    }

    return Container(
      width: 76,
      color: Color.lerp(palette.side, Colors.black, 0.25),
      child: Column(children: [
        const SizedBox(height: 16),
        tab(0, Icons.key, 'Jelszavak'),
        tab(1, Icons.edit_note, 'Jegyzetek'),
        tab(2, Icons.settings, 'Beállítások'),
        const Spacer(),
        IconButton(
            tooltip: 'Szinkronizálás', color: Colors.white70, onPressed: state.sync, icon: const Icon(Icons.sync)),
        IconButton(
            tooltip: 'Zárolás', color: Colors.white70, onPressed: state.lock, icon: const Icon(Icons.lock_outline)),
        const SizedBox(height: 12),
      ]),
    );
  }
}
