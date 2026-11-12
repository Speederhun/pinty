import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';

class _AuthFrame extends StatelessWidget {
  const _AuthFrame({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFF2B632),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.lock_outline, color: Color(0xFF0E3A35), size: 20),
        ),
        const SizedBox(width: 12),
        Text('Pinty', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const Spacer(),
        const LanguageMenu(),
      ]);
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(text!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    );
  }
}

/// Első indítás: új fiók létrehozása vagy bejelentkezés meglévő fiókba.
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, required this.state});
  final AppState state;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool _isNew = true;
  final _server = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _token = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _server.dispose();
    _email.dispose();
    _pass.dispose();
    _pass2.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _recover() async {
    final s = widget.state;
    final server = TextEditingController(text: _server.text);
    final email = TextEditingController(text: _email.text);
    final key = TextEditingController();
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    String? err;
    var working = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(tr('Visszaállítás kulccsal')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(tr('Add meg a fiókod visszaállító kulcsát és az új mesterjelszót. A széfed tartalma megmarad.')),
                const SizedBox(height: 12),
                TextField(controller: server, decoration: InputDecoration(labelText: tr('Szerver címe'))),
                const SizedBox(height: 12),
                TextField(controller: email, decoration: InputDecoration(labelText: tr('E-mail cím'))),
                const SizedBox(height: 12),
                TextField(controller: key, decoration: InputDecoration(labelText: tr('Visszaállító kulcs'), hintText: 'XXXX-XXXX-…')),
                const SizedBox(height: 12),
                TextField(controller: p1, obscureText: true, decoration: InputDecoration(labelText: tr('Új mesterjelszó (legalább 12 karakter)'))),
                const SizedBox(height: 12),
                TextField(controller: p2, obscureText: true, decoration: InputDecoration(labelText: tr('Új mesterjelszó újra'))),
                if (err != null) ...[
                  const SizedBox(height: 8),
                  Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: working ? null : () => Navigator.pop(ctx), child: Text(tr('Mégse'))),
            FilledButton(
              onPressed: working
                  ? null
                  : () async {
                      if (server.text.trim().isEmpty || email.text.trim().isEmpty || key.text.trim().isEmpty) {
                        setS(() => err = tr('Tölts ki minden mezőt.'));
                        return;
                      }
                      if (p1.text.length < 12) {
                        setS(() => err = tr('Az új mesterjelszó legyen legalább 12 karakter.'));
                        return;
                      }
                      if (p1.text != p2.text) {
                        setS(() => err = tr('A két jelszó nem egyezik.'));
                        return;
                      }
                      setS(() {
                        working = true;
                        err = null;
                      });
                      await s.recoverAccount(
                        serverUrl: server.text,
                        email: email.text,
                        recoveryKey: key.text,
                        newPassword: p1.text,
                      );
                      if (s.error != null) {
                        setS(() {
                          working = false;
                          err = s.error;
                        });
                      } else if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                    },
              child: Text(working ? tr('Folyamatban…') : tr('Visszaállítás')),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final s = widget.state;
    setState(() => _localError = null);
    if (_server.text.trim().isEmpty || _email.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _localError = tr('Tölts ki minden mezőt.'));
      return;
    }
    if (_isNew) {
      if (_pass.text.length < 12) {
        setState(() => _localError = tr('A mesterjelszó legyen legalább 12 karakter (jelmondat is jó).'));
        return;
      }
      if (_pass.text != _pass2.text) {
        setState(() => _localError = tr('A két jelszó nem egyezik.'));
        return;
      }
      s.register(
        serverUrl: _server.text,
        email: _email.text,
        password: _pass.text,
        inviteCode: _token.text,
      );
    } else {
      s.connect(serverUrl: _server.text, email: _email.text, password: _pass.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => _AuthFrame(children: [
        const _Brand(),
        const SizedBox(height: 20),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text(tr('Új fiók'))),
            ButtonSegment(value: false, label: Text(tr('Meglévő fiók'))),
          ],
          selected: {_isNew},
          onSelectionChanged: s.busy
              ? null
              : (v) => setState(() {
                    _isNew = v.first;
                    _localError = null;
                    s.clearError();
                  }),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _server,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(labelText: tr('Szerver címe'), hintText: tr('https://vault.példa.hu')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: tr('E-mail cím')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pass,
          obscureText: true,
          decoration: InputDecoration(labelText: tr('Mesterjelszó')),
        ),
        if (_isNew) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _pass2,
            obscureText: true,
            decoration: InputDecoration(labelText: tr('Mesterjelszó újra')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            decoration: InputDecoration(
              labelText: tr('Meghívókód'),
              helperText: tr('A rendszergazdától kapott, egyszer használható kód.'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tr('A mesterjelszót a szerver sem ismeri. Jegyezd meg, és a belépés után készíts visszaállító kulcsot is.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        _ErrorText(_localError ?? s.error),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: s.busy ? null : _submit,
          child: s.busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isNew ? tr('Fiók létrehozása') : tr('Bejelentkezés')),
        ),
        if (!_isNew) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: s.busy ? null : _recover, child: Text(tr('Elfelejtetted a mesterjelszót?'))),
        ],
      ]),
    );
  }
}

/// Zárolt széf feloldása.
class UnlockPage extends StatefulWidget {
  const UnlockPage({super.key, required this.state});
  final AppState state;

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final _pass = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Ha be van kapcsolva a biometrikus feloldás, rögtön felajánljuk.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.state.biometricEnabled && !widget.state.busy) widget.state.unlockBiometric();
    });
  }

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Kijelentkezés')),
        content: Text(
          tr('Az eszközön lévő másolat törlődik. A szerveren lévő adataid megmaradnak, és újra bejelentkezhetsz. A fel nem töltött módosítások elvesznek.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Mégse'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Kijelentkezés'))),
        ],
      ),
    );
    if (ok == true) await widget.state.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => _AuthFrame(children: [
        const _Brand(),
        const SizedBox(height: 8),
        Text(s.email, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 20),
        TextField(
          controller: _pass,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(labelText: tr('Mesterjelszó')),
          onSubmitted: (_) => s.busy ? null : s.unlock(_pass.text),
        ),
        _ErrorText(s.error),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: s.busy ? null : () => s.unlock(_pass.text),
          child: s.busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(tr('Feloldás')),
        ),
        if (s.biometricEnabled) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: s.busy ? null : s.unlockBiometric,
            icon: const Icon(Icons.fingerprint),
            label: Text(tr('Feloldás biometrikusan')),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(onPressed: s.busy ? null : _signOut, child: Text(tr('Kijelentkezés ezen az eszközön'))),
      ]),
    );
  }
}

/// Nyelvválasztó menü (EN / HU).
class LanguageMenu extends StatelessWidget {
  const LanguageMenu({super.key});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        icon: const Icon(Icons.language),
        tooltip: tr('Nyelv'),
        onSelected: (c) => languageRequest?.call(c),
        itemBuilder: (_) => [
          CheckedPopupMenuItem(value: 'en', checked: currentLang == 'en', child: const Text('English')),
          CheckedPopupMenuItem(value: 'hu', checked: currentLang == 'hu', child: const Text('Magyar')),
        ],
      );
}
