/// CODE PIN DU MOBILE : la règle de l'écran « Code PIN » du simulateur (pavé à quatre chiffres, trois essais, message de refus), et le PORT du coffre.
///
/// La règle est relevée sur la page réelle, touche par touche, dans Chrome (`test/vecteurs/mobile_suite.json`, clé `pin`). Le STOCKAGE SÉCURISÉ n'est pas
/// ici : il dépend de la chaîne native (`flutter_secure_storage`, `local_auth`, SQLCipher), qu'on ne peut pas exercer sans appareil. Le domaine ne fait
/// que dire CE QUE le coffre doit savoir faire ([CoffrePin]) ; l'application fournit l'adaptation, les tests une implémentation en mémoire
/// ([CoffrePinMemoire]) qui n'est PAS un coffre. Voir ECARTS-MAQUETTE E1656 à E1658.
library;

import 'mob_regles.dart' show RefusMobile;
import 'mob_suite_donnees.dart';

const mobPinLongueur = 4;
const mobPinEssaisMax = 3;

/// « réessayez dans 30 s » : le message de la page annonce 30 secondes, mais la page ne les compte jamais (le blocage dure jusqu'au rechargement, qui
/// remet les essais à zéro sans rien retenir). Le téléphone les COMPTE, et retient les essais (E1656).
const mobPinBlocage = Duration(seconds: 30);

/// Les essais déjà faits et la fin du blocage éventuel (millisecondes d'époque) : ce que le coffre retient pour qu'un redémarrage ne rende pas les essais.
class MobPinCompteur {
  const MobPinCompteur({this.essais = 0, this.bloqueJusquaMs});
  final int essais;
  final int? bloqueJusquaMs;
}

/// Ce que le téléphone doit savoir faire pour garder un code. Une implémentation réelle range un HACHÉ SALÉ dans le coffre du système, jamais le code.
abstract class CoffrePin {
  Future<bool> aUnCode();

  /// Définit (ou remplace) le code : quatre chiffres, sinon [RefusMobile].
  Future<void> definir(String code);

  /// Vrai si le code saisi est le bon. Ne compte pas les essais : c'est [MobPin] qui les compte.
  Future<bool> verifier(String code);
  Future<MobPinCompteur> compteur();
  Future<void> poserCompteur(MobPinCompteur c);
}

/// Le code est fait de quatre chiffres, rien d'autre (E1657 : le pavé n'en propose pas d'autres, la définition doit le refuser aussi).
RefusMobile? mobPinRefusFormat(String code) => RegExp(r'^\d{4}$').hasMatch(code)
    ? null
    : const RefusMobile('PIN_FORMAT', 'Le code doit comporter quatre chiffres.', 'Saisir un code à quatre chiffres');

/// Le coffre des TESTS : un code en clair en mémoire. À ne jamais brancher sur un téléphone.
class CoffrePinMemoire implements CoffrePin {
  CoffrePinMemoire([this._code]);
  String? _code;
  MobPinCompteur _c = const MobPinCompteur();

  @override
  Future<bool> aUnCode() async => _code != null;

  @override
  Future<void> definir(String code) async {
    final r = mobPinRefusFormat(code);
    if (r != null) throw r;
    _code = code;
    _c = const MobPinCompteur();
  }

  @override
  Future<bool> verifier(String code) async => _code != null && code == _code;

  @override
  Future<MobPinCompteur> compteur() async => _c;

  @override
  Future<void> poserCompteur(MobPinCompteur c) async => _c = c;
}

/// Ce que l'écran affiche : les points pleins, le message, l'état.
class MobPinEtat {
  const MobPinEtat({this.saisie = '', this.essais = 0, this.message = '', this.bloqueJusquaMs, this.deverrouille = false});
  final String saisie;
  final int essais;
  final String message;
  final int? bloqueJusquaMs;
  final bool deverrouille;

  int get points => saisie.length;
  bool bloque(DateTime maintenant) => bloqueJusquaMs != null && maintenant.millisecondsSinceEpoch < bloqueJusquaMs!;
  int secondesRestantes(DateTime maintenant) => bloque(maintenant) ? ((bloqueJusquaMs! - maintenant.millisecondsSinceEpoch) / 1000).ceil() : 0;

  MobPinEtat _avec({String? saisie, int? essais, String? message, int? bloque, bool effacerBlocage = false, bool? deverrouille}) => MobPinEtat(
      saisie: saisie ?? this.saisie,
      essais: essais ?? this.essais,
      message: message ?? this.message,
      bloqueJusquaMs: effacerBlocage ? null : (bloque ?? bloqueJusquaMs),
      deverrouille: deverrouille ?? this.deverrouille);
}

String mobPinMessageIncorrect(int essais) => '${_pin['incorrect']}'.replaceFirst('#', '$essais');
Map<String, Object?> get _pin => (mobSuiteDonnees['pin'] as Map).cast<String, Object?>();

/// Les touches du pavé dans l'ordre de la page : chiffres, un vide, « 0 », effacer. Le vide est une chaîne vide.
List<String> get mobPinPave => [for (final k in (_pin['pave'] as List)) '$k'];

/// La phrase d'invite de la page (« Saisissez votre code à 4 chiffres. »). La ligne « Démonstration : 1234 » n'a pas de sens sur un vrai téléphone.
String get mobPinInvite => '${_pin['invite']}';
String get mobPinTitre => '${_pin['titre']}';
String get mobPinDemonstration => '${_pin['demo']}';

/// La machine de l'écran : une touche à la fois, comme la page.
///  - bloqué (trois essais ratés) : TOUTE touche est ignorée, effacer compris ;
///  - effacer retire le dernier chiffre ; un chiffre s'ajoute jusqu'à quatre ;
///  - au quatrième chiffre : bon code, c'est ouvert ; mauvais code, le compteur monte, la saisie est vidée et le message dit « Code incorrect (n/3). »,
///    ou « Trop d’essais — réessayez dans 30 s. » au troisième ;
///  - le message reste affiché tant qu'un autre échec ne le remplace pas (la page ne l'efface pas à la frappe).
/// Écart porté et signalé (E1656) : le blocage est RETENU par le coffre et LEVÉ au bout de 30 s ; la page ne le levait jamais.
class MobPin {
  MobPin(this.coffre, {DateTime Function()? horloge}) : _horloge = horloge ?? DateTime.now;
  final CoffrePin coffre;
  final DateTime Function() _horloge;
  MobPinEtat _etat = const MobPinEtat();

  MobPinEtat get etat => _etat;

  /// Relit les essais retenus (à l'ouverture de l'écran) : un redémarrage ne rend pas les essais.
  Future<MobPinEtat> charger() async {
    final c = await coffre.compteur();
    _etat = MobPinEtat(essais: c.essais, bloqueJusquaMs: c.bloqueJusquaMs, message: _messagePourReprise(c));
    return _lever();
  }

  String _messagePourReprise(MobPinCompteur c) => c.bloqueJusquaMs != null && _horloge().millisecondsSinceEpoch < c.bloqueJusquaMs!
      ? '${_pin['bloque']}'
      : (c.essais > 0 ? mobPinMessageIncorrect(c.essais) : '');

  /// Le blocage échu est levé : trois nouveaux essais, message effacé.
  Future<MobPinEtat> _lever() async {
    if (_etat.bloqueJusquaMs != null && !_etat.bloque(_horloge())) {
      _etat = _etat._avec(essais: 0, message: '', effacerBlocage: true);
      await coffre.poserCompteur(const MobPinCompteur());
    }
    return _etat;
  }

  /// Fait avancer l'horloge : un blocage échu est levé (appelé à chaque seconde par l'écran, sans quoi le message resterait affiché).
  Future<MobPinEtat> actualiser() => _lever();

  Future<MobPinEtat> touche(String k) async {
    await _lever();
    if (_etat.deverrouille || _etat.bloque(_horloge())) return _etat;
    var saisie = _etat.saisie;
    if (k == '⌫') {
      saisie = saisie.isEmpty ? '' : saisie.substring(0, saisie.length - 1);
    } else if (RegExp(r'^\d$').hasMatch(k) && saisie.length < mobPinLongueur) {
      saisie += k;
    }
    if (saisie.length < mobPinLongueur) {
      _etat = _etat._avec(saisie: saisie);
      return _etat;
    }
    if (await coffre.verifier(saisie)) {
      _etat = _etat._avec(saisie: '', essais: 0, message: '', effacerBlocage: true, deverrouille: true);
      await coffre.poserCompteur(const MobPinCompteur());
      return _etat;
    }
    final essais = _etat.essais + 1;
    final bloque = essais >= mobPinEssaisMax;
    final fin = bloque ? _horloge().add(mobPinBlocage).millisecondsSinceEpoch : null;
    _etat = _etat._avec(saisie: '', essais: essais, message: bloque ? '${_pin['bloque']}' : mobPinMessageIncorrect(essais), bloque: fin);
    await coffre.poserCompteur(MobPinCompteur(essais: essais, bloqueJusquaMs: fin));
    return _etat;
  }

  /// Définir le code (premier lancement, ou changement) : deux saisies identiques. Refus nommé sinon.
  static Future<void> definir(CoffrePin coffre, String code, String confirmation) async {
    final r = mobPinRefusFormat(code);
    if (r != null) throw r;
    if (code != confirmation) {
      throw const RefusMobile('PIN_DIFFERENT', 'Les deux saisies du code ne sont pas identiques.', 'Ressaisir le code');
    }
    await coffre.definir(code);
  }
}
