import 'package:flutter/material.dart';

import '../app_state.dart';

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
          title: const Text('Visszaállítás kulccsal'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Add meg a fiókod visszaállító kulcsát és az új mesterjelszót. A széfed tartalma megmarad.'),
                const SizedBox(height: 12),
                TextField(controller: server, decoration: const InputDecoration(labelText: 'Szerver címe')),
                const SizedBox(height: 12),
                TextField(controller: email, decoration: const InputDecoration(labelText: 'E-mail cím')),
                const SizedBox(height: 12),
                TextField(controller: key, decoration: const InputDecoration(labelText: 'Visszaállító kulcs', hintText: 'XXXX-XXXX-…')),
                const SizedBox(height: 12),
                TextField(controller: p1, obscureText: true, decoration: const InputDecoration(labelText: 'Új mesterjelszó (legalább 12 karakter)')),
                const SizedBox(height: 12),
                TextField(controller: p2, obscureText: true, decoration: const InputDecoration(labelText: 'Új mesterjelszó újra')),
                if (err != null) ...[
                  const SizedBox(height: 8),
                  Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: working ? null : () => Navigator.pop(ctx), child: const Text('Mégse')),
            FilledButton(
              onPressed: working
                  ? null
                  : () async {
                      if (server.text.trim().isEmpty || email.text.trim().isEmpty || key.text.trim().isEmpty) {
                        setS(() => err = 'Tölts ki minden mezőt.');
                        return;
                      }
                      if (p1.text.length < 12) {
                        setS(() => err = 'Az új mesterjelszó legyen legalább 12 karakter.');
                        return;
                      }
                      if (p1.text != p2.text) {
                        setS(() => err = 'A két jelszó nem egyezik.');
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
              child: Text(working ? 'Folyamatban…' : 'Visszaállítás'),
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
      setState(() => _localError = 'Tölts ki minden mezőt.');
      return;
    }
    if (_isNew) {
      if (_pass.text.length < 12) {
        setState(() => _localError = 'A mesterjelszó legyen legalább 12 karakter (jelmondat is jó).');
        return;
      }
      if (_pass.text != _pass2.text) {
        setState(() => _localError = 'A két jelszó nem egyezik.');
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
          segments: const [
            ButtonSegment(value: true, label: Text('Új fiók')),
            ButtonSegment(value: false, label: Text('Meglévő fiók')),
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
          decoration: const InputDecoration(labelText: 'Szerver címe', hintText: 'https://vault.példa.hu'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'E-mail cím'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pass,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Mesterjelszó'),
        ),
        if (_isNew) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _pass2,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Mesterjelszó újra'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            decoration: const InputDecoration(
              labelText: 'Meghívókód',
              helperText: 'A rendszergazdától kapott, egyszer használható kód.',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'A mesterjelszót a szerver sem ismeri. Jegyezd meg, és a belépés után készíts visszaállító kulcsot is.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        _ErrorText(_localError ?? s.error),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: s.busy ? null : _submit,
          child: s.busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isNew ? 'Fiók létrehozása' : 'Bejelentkezés'),
        ),
        if (!_isNew) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: s.busy ? null : _recover, child: const Text('Elfelejtetted a mesterjelszót?')),
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
        title: const Text('Kijelentkezés'),
        content: const Text(
          'Az eszközön lévő másolat törlődik. A szerveren lévő adataid megmaradnak, és újra bejelentkezhetsz. '
          'A fel nem töltött módosítások elvesznek.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Mégse')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kijelentkezés')),
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
          decoration: const InputDecoration(labelText: 'Mesterjelszó'),
          onSubmitted: (_) => s.busy ? null : s.unlock(_pass.text),
        ),
        _ErrorText(s.error),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: s.busy ? null : () => s.unlock(_pass.text),
          child: s.busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Feloldás'),
        ),
        if (s.biometricEnabled) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: s.busy ? null : s.unlockBiometric,
            icon: const Icon(Icons.fingerprint),
            label: const Text('Feloldás biometrikusan'),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(onPressed: s.busy ? null : _signOut, child: const Text('Kijelentkezés ezen az eszközön')),
      ]),
    );
  }
}
