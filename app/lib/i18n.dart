import 'en.dart';

/// Az app szövegei magyar nyelven készültek; az angol fordítás az `en.dart` szótárból jön.
/// Alapértelmezett nyelv az angol. A fordítatlan szöveg magyarul marad.
String _lang = 'en';

String get currentLang => _lang;

/// Támogatott nyelvkódok: `en`, `hu`.
void setLang(String code) => _lang = code == 'hu' ? 'hu' : 'en';

/// A magyar szöveg fordítása az aktuális nyelvre.
String tr(String hu) => _lang == 'hu' ? hu : (enStrings[hu] ?? hu);

/// Fordítás behelyettesítéssel: a `%1`, `%2`… jelölők helyére kerülnek az [args] értékei.
String trf(String hu, List<Object?> args) {
  var s = tr(hu);
  for (var i = args.length; i >= 1; i--) {
    s = s.replaceAll('%$i', '${args[i - 1]}');
  }
  return s;
}

/// Az AppState ide köti a nyelvváltást, hogy a bejelentkező képernyők is válthassanak.
void Function(String code)? languageRequest;
