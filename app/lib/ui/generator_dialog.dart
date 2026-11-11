import 'package:flutter/material.dart';

import '../util/password_generator.dart';

/// Jelszógenerátor; a kiválasztott jelszót adja vissza, vagy null-t, ha mégsem kell.
Future<String?> showGeneratorDialog(BuildContext context) {
  return showDialog<String>(context: context, builder: (_) => const _GeneratorDialog());
}

class _GeneratorDialog extends StatefulWidget {
  const _GeneratorDialog();

  @override
  State<_GeneratorDialog> createState() => _GeneratorDialogState();
}

class _GeneratorDialogState extends State<_GeneratorDialog> {
  PasswordOptions _o = const PasswordOptions();
  late String _password = generatePassword(_o);

  void _update(PasswordOptions o) {
    // legalább egy csoport maradjon bekapcsolva
    if (!(o.lower || o.upper || o.digits || o.symbols)) return;
    setState(() {
      _o = o;
      _password = generatePassword(o);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Jelszó generálása'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _password,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
              ),
            ),
            const SizedBox(height: 12),
            Text('Hossz: ${_o.length}'),
            Slider(
              min: 8,
              max: 64,
              divisions: 56,
              value: _o.length.toDouble(),
              label: '${_o.length}',
              onChanged: (v) => _update(_o.copyWith(length: v.round())),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Kisbetűk'),
              value: _o.lower,
              onChanged: (v) => _update(_o.copyWith(lower: v)),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Nagybetűk'),
              value: _o.upper,
              onChanged: (v) => _update(_o.copyWith(upper: v)),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Számok'),
              value: _o.digits,
              onChanged: (v) => _update(_o.copyWith(digits: v)),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Szimbólumok'),
              value: _o.symbols,
              onChanged: (v) => _update(_o.copyWith(symbols: v)),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Mégse')),
        TextButton(onPressed: () => _update(_o), child: const Text('Új')),
        FilledButton(onPressed: () => Navigator.pop(context, _password), child: const Text('Használom')),
      ],
    );
  }
}
