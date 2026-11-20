import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';

/// LE REGISTRE DES SESSIONS DU POSTE (retour de la Direction du 01/11/2026 : « Clôturer » doit changer le statut).
///
/// Une fiche par session dans la collection `sessionsUtilisateur`, comme la maquette (`SIGH.sessions`) : `active`, `suspendue` (verrou d'inactivité) ou
/// `cloturee`. Les RÈGLES sont dans `packages/domaine` (`secCloturerSession`) ; ce service ne fait que lire et écrire le magasin.
///
/// Trois principes, ceux de la maquette : une session clôturée NE ROUVRE PAS (se reconnecter ouvre une AUTRE session) ; rien n'est supprimé (RG-14) ; la
/// clôture porte la date, l'heure et l'auteur (RG-12) et passe par le journal d'audit de la collection.
class RegistreSessions {
  RegistreSessions._(this._magasin);
  final Magasin _magasin;

  static final Expando<RegistreSessions> _registres = Expando<RegistreSessions>('RegistreSessions');

  /// Le registre d'un magasin (un seul par magasin).
  static RegistreSessions de(Magasin m) => _registres[m] ??= RegistreSessions._(m);

  /// La fiche de la session de CE poste, posée à la connexion ; `null` tant que personne ne s'est connecté (poste de développement `SIGH_ROLE`).
  String? sessionCourante;

  /// Posé à la connexion : ferme la session du poste (retour à l'écran de connexion). L'écran « Sessions actives » l'appelle quand l'administrateur
  /// clôture SA PROPRE session, après sa confirmation explicite.
  VoidCallback? surCloturePropre;

  /// Posé à la connexion : applique un nouveau délai d'inactivité à la session ouverte (la politique de sécurité le règle, CDCT §12.2).
  void Function(Duration)? appliquerDelaiVerrou;

  CollectionMagasin get _col => _magasin.collection('sessionsUtilisateur');

  Fiche? fiche(String? id) => id == null ? null : _col.parId(id);

  List<Fiche> get fiches => _col.actives;

  /// Les douze sessions de démonstration (graine 3413), amorcées par l'écran comme dans la maquette : sans écriture au journal, une seule fois.
  void amorcerDemonstration(Iterable<Fiche> comptesActifs, DateTime maintenant) {
    if (_col.toutes.any((f) => f['source'] == 'demonstration')) return;
    final demo = secSessionsDemonstration(comptesActifs, maintenant);
    // La maquette AJOUTE les fiches de démonstration à la fin de la collection (`push`) : les sessions réelles restent en tête.
    for (final f in demo) {
      _col.ajouterSansJournal({...f, '_creePar': 'Système', '_creeLe': maintenant.toIso8601String()});
    }
  }

  /// Ouvre la session d'un compte qui vient de se connecter : une NOUVELLE fiche, jamais la réouverture d'une ancienne. Rend son identifiant.
  String ouvrir({required String identifiant, required String nomComplet, required String role, required String poste, required DateTime maintenant}) {
    // L'ouverture d'une session n'est pas un geste de l'agent : elle s'écrit au registre SANS entrée de journal (la connexion est journalisée par l'écran de
    // connexion), comme la maquette. La suspension et la clôture, elles, passent par `mettreAJour` et se journalisent.
    final id = 'SES${(_col.toutes.length + 1).toString().padLeft(5, '0')}';
    _col.ajouterSansJournal({'id': id, 'statut': 'actif', ...secNouvelleSession(identifiant: identifiant, nomComplet: nomComplet, role: role, poste: poste, maintenant: maintenant)}, enTete: true);
    sessionCourante = id;
    return id;
  }

  /// La session est-elle clôturée au registre ? (contrôle au prochain geste)
  bool estCloturee(String id) => secSessionCloturee(fiche(id));

  /// Suspend (verrou d'inactivité) ou reprend une session. Une session clôturée n'en change plus.
  void changerEtat(String id, String etat, DateTime maintenant) {
    final f = fiche(id);
    if (f == null || '${f['etat']}' == 'cloturee' || '${f['etat']}' == etat) return;
    _col.mettreAJour(id, {'etat': etat, 'derniereActivite': maintenant.toIso8601String()});
  }

  /// CLOTURER : la règle du domaine décide, ce service écrit. Rend le résultat (patch appliqué ou refus nommé).
  ResultatSec cloturer(String id,
      {required SecActeurSession acteur, required bool droitEditer, required DateTime maintenant, bool confirmePropre = false, String? motif}) {
    final r = secCloturerSession(fiche: fiche(id), acteur: acteur, droitEditer: droitEditer, maintenant: maintenant, confirmePropre: confirmePropre, motif: motif);
    if (r.ok) _col.mettreAJour(id, r.patch);
    return r;
  }
}
