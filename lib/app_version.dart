/// Versione corrente dell'app. UNICA SORGENTE DI VERITÀ.
///
/// Va bumpata insieme a `pubspec.yaml > version:` ad ogni release.
/// Usata da:
///   - Dashboard (badge nella AppBar)
///   - Settings (sezione "Info app")
///   - Login (subtitle sotto al titolo)
///   - Header generico delle schermate che la mostrano
///
/// REGOLA: ad ogni nuova release questa costante deve riflettere
/// esattamente la versione APK che l'utente sta scaricando.
const String kAppVersion = '0.2.60';
