import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/service_installation.dart';
import '../core/service_parametres.dart';
import 'magasin.dart';

/// Le verrou d'un poste de secours au poste (lot ORG2, Direction, 11/11/2026, décision P3) : la colle entre les fonctions pures de `packages/domaine/lib/src/securite/
/// verrou_secours.dart` (rejouées sur les vecteurs de la maquette) et le poste. Aucune règle ici : les bornes, les droits (administrateur et DAF seuls) et les refus nommés sont
/// ceux du domaine ; le délai se LIT au registre des paramètres (`securite.delaiVerrouPosteSecours`, 5 minutes par défaut, MARQUÉ « à valider », versionné par date, synchronisé par
/// le journal), jamais une constante. Quel poste est « de secours » est une donnée LOCALE de ce poste (`ParametresPoste.posteSecours`, jamais synchronisée) : ce n'est pas un droit.
class VerrouSecoursPoste {
  VerrouSecoursPoste(this.m, {required this.auteur, required this.role, DateTime Function()? horloge}) : _horloge = horloge ?? DateTime.now;
  final Magasin m;
  final String Function() auteur;
  final String role;
  final DateTime Function() _horloge;

  String get aujourdhui => parametreDateIso(_horloge());
  ServiceParametres get service => serviceParametres(m, auteur: auteur, horloge: _horloge);

  /// Ce poste est-il désigné poste de secours ?
  bool posteDeSecours() => ServiceInstallation.de(m).posteDeSecours;

  /// Le délai de secours en force AUJOURD'HUI, en minutes (défaut : 5, valeur d'attente à valider).
  int delaiSecours() => delaiVerrouSecoursMinutes(service.valeur(cleDelaiVerrouSecours, aujourdhui));

  /// Le délai du poste ordinaire : l'inactivité de la politique de sécurité quand elle est écrite, sinon quinze minutes (CDCT 12.2).
  int delaiOrdinaire() {
    final pol = m.collection('politiqueSecurite').actives.firstOrNull;
    return delaiVerrouOrdinaireMinutes(pol == null ? null : secPolitique(pol)['inactiviteMin']);
  }

  /// Le délai de verrou EN FORCE sur ce poste, en minutes.
  int delaiPoste() => posteDeSecours() ? delaiSecours() : delaiOrdinaire();

  /// Ce profil règle-t-il ? (administrateur et Directrice Administrative seuls : la commande est ABSENTE ailleurs.)
  bool get peutRegler => rolesVerrouSecours.contains(role);

  /// Règle le délai de secours : une NOUVELLE VERSION du paramètre effective aujourd'hui, journalisée avec l'ancienne et la nouvelle valeur (RG-12). Refus nommé du domaine
  /// (réservé, valeur hors bornes).
  Map<String, Object?> definirDelai(Object? minutes, {String? motif}) {
    final refus = controlerReglageDelaiSecours(role: role, minutes: minutes);
    if (refus != null) return refus.toJson();
    final avant = delaiSecours();
    final n = minutes is num ? minutes.toInt() : int.parse('$minutes'.trim());
    final r = service.regler(cleDelaiVerrouSecours, n, aujourdhui, motif: motif);
    if (!r.ok) return {'ok': false, 'code': r.refus!.code, 'motif': r.refus!.motif, 'geste': r.refus!.geste};
    m.journaliser('Délai de verrou d’un poste de secours', 'M14', 'reglage', 'verrouDelaiSecoursMinutes', {'minutes': avant}, {'minutes': n, 'motif': motif});
    return {'ok': true, 'minutes': n, 'avant': avant};
  }

  /// Désigne (ou retire la désignation de) CE poste comme poste de secours.
  Future<Map<String, Object?>> definirPoste(bool oui, {String? motif}) async {
    final refus = controlerDesignationPosteSecours(role: role);
    if (refus != null) return refus.toJson();
    final avant = posteDeSecours();
    await ServiceInstallation.de(m).designerPosteDeSecours(oui);
    m.journaliser('Poste de secours', 'M14', 'reglage', 'posteDeSecours', {'secours': avant}, {'secours': oui, 'delaiMinutes': delaiPoste(), 'motif': motif});
    return {'ok': true, 'secours': oui, 'avant': avant, 'delaiMinutes': delaiPoste()};
  }
}
