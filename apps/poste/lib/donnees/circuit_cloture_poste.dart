import 'dart:async';

import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/service_parametres.dart';
import 'magasin.dart';

/// Le CIRCUIT DE CLÔTURE ANNUELLE au poste (lot CLO C1, PRD M12 clôture annuelle) : la colle entre le domaine (`cpc_circuit.dart`, rejoué sur les vecteurs de la maquette) et le registre des
/// paramètres du poste. Aucun nom de rôle ici : les cinq réglages se LISENT dans `parametres` (famille `exercice`, défauts semés, versionnés par date, réglage de BRANCHE : la mère écrit, les
/// fileuls lisent par le journal, jamais un mobile), à la date du geste. Les libellés des rôles viennent de la matrice (renommages compris), pour que le refus cite la liste LUE.
CpcCircuit circuitClotureDe(Magasin m, {DateTime Function()? horloge}) {
  final h = horloge ?? m.horloge;
  final service = serviceParametres(m, auteur: () => m.utilisateur, horloge: h);
  final date = parametreDateIso(h());
  final roles = secRoles(m.collection('rolesBase').toutes, secSurcharges(m.collection('rbac').toutes));
  return CpcCircuit.lire((cle) => service.valeur(cle, date), libelles: {for (final r in roles) r.id: r.label});
}

/// Les rôles de la matrice non archivés (les seuls admis dans une liste du circuit).
Set<String> rolesConnusDuCircuit(Magasin m) =>
    {for (final r in secRoles(m.collection('rolesBase').toutes, secSurcharges(m.collection('rbac').toutes))) if (!r.archive) r.id};

/// Règle un réglage du circuit : contrôle du domaine (geste réservé, motif, liste, mois), puis NOUVELLE version datée du jour (jamais une réécriture), journalisée (RG-12).
/// Un FILEUL ne règle pas : la collection des paramètres est tenue par la mère, le refus est nommé. Rend `null` si réglé, sinon le refus nommé.
CpcRefusCircuit? reglerCircuitCloture(Magasin m,
    {required String cle, required Object? valeur, required String role, required bool gesteAccorde, required String? motif, bool fileul = false, DateTime Function()? horloge}) {
  final h = horloge ?? m.horloge;
  final circuit = circuitClotureDe(m, horloge: h);
  final refus = cpcControleReglageCircuit(
      cle: cle,
      valeur: valeur,
      gesteAccorde: gesteAccorde,
      libelleRole: circuit.libelles[role] ?? role,
      motif: motif,
      rolesConnus: rolesConnusDuCircuit(m));
  if (refus != null) return refus;
  if (fileul) {
    return const CpcRefusCircuit('FILEUL_LECTURE_SEULE', 'Le circuit de clôture est un réglage de la clinique, posé à la poste mère : ce poste le reçoit par le journal.',
        'Régler le circuit sur le poste mère : ce poste reçoit ce réglage par le journal.');
  }
  final service = serviceParametres(m, auteur: () => m.utilisateur, horloge: h);
  final date = parametreDateIso(h());
  final avant = service.valeur(cle, date);
  final voulu = (cle == cpcCleMoisOuverture || cle == cpcCleDelaiPostes) ? (valeur is num ? valeur.toInt() : int.parse('$valeur')) : cpcListeRoles(valeur).join(',');
  try {
    final w = service.regler(cle, voulu, date, motif: (motif ?? '').trim());
    if (!w.ok) return CpcRefusCircuit('CIRCUIT_REGLAGE_REFUSE', '${w.refus!.code} : ${w.refus!.motif}', w.refus!.geste);
  } on EcritureRefusee catch (e) {
    return CpcRefusCircuit('FILEUL_LECTURE_SEULE', e.motif, 'Régler le circuit sur le poste mère : ce poste reçoit ce réglage par le journal.');
  }
  m.journaliser('Circuit de clôture : nouvelle version', 'M12', 'reglagesCloture', cle, {'valeur': avant}, {'valeur': voulu, 'dateEffet': date, 'motif': (motif ?? '').trim()});
  return null;
}

/// L'OUVERTURE DES EXERCICES (lot CLO C4, EF-CLO-1, E1 et E2) : une fiche par année portée par le journal, l'horloge et la liasse déposée ; l'année SUIVANTE s'ouvre à partir du mois
/// réglé du circuit de clôture (défaut semé : décembre). Idempotente : une année déjà ouverte ne se rouvre pas. CHAQUE ouverture est TRACÉE au journal d'audit (RG-12) avec sa cause
/// (`ecriture`, `annee_en_cours`, `ouverture_anticipee` ; la liasse, close d'office, n'est pas une ouverture du logiciel) et n'écrit AUCUNE pièce (ni à-nouveau ni écriture : les
/// à-nouveaux de N+1 restent PROVISOIRES et calculés jusqu'à la clôture de N). Rend les années ouvertes.
List<int> ouvrirExercices(Magasin m, DateTime auj) {
  final col = m.collection('exercices');
  final mois = circuitClotureDe(m, horloge: () => auj).moisOuvertureSuivant;
  final toutes = m.collection('ecritures').toutes;
  final fiches = cpcExercicesAAmorcer(col.toutes, toutes, auj, moisOuvertureSuivant: mois);
  final ouvertes = <int>[];
  for (final f in fiches) {
    col.inserer(f);
    final a = f['annee'] as int;
    final cause = cpcCauseOuverture(a, toutes, auj, moisOuvertureSuivant: mois);
    if (cause != 'liasse') {
      m.journaliser('Ouverture d’exercice', 'M12', 'Exercice', '$a', null, {'etat': 'ouvert', 'origine': cause});
      ouvertes.add(a);
    }
  }
  return ouvertes;
}

/// LA TÂCHE QUOTIDIENNE du poste : l'ouverture au démarrage, puis toutes les six heures (un poste resté ouvert la nuit du 31 décembre ouvre l'exercice sans attendre un écran). Un fileul
/// l'exécute comme la mère : les fiches portent un identifiant déterministe (`EXO-<année>`), deux postes qui ouvrent la même année produisent la même fiche.
Timer demarrerOuvertureDesExercices(Magasin m, {DateTime Function()? horloge, Duration periode = const Duration(hours: 6)}) {
  final h = horloge ?? m.horloge;
  ouvrirExercices(m, h());
  return Timer.periodic(periode, (_) => ouvrirExercices(m, h()));
}

/// Ce que la mère sait de ses fileuls (lot CLO-2, C5) : fourni par `main.dart` sur un poste MÈRE (sa console, indicateurs de supervision). Absent (fileul, poste autonome) : aucun
/// avertissement n'est inventé.
class PostesAppaires {
  PostesAppaires._();
  static Future<List<CpcPosteAppaire>> Function()? fournisseur;
}

/// L'avertissement non bloquant avant « Démarrer la clôture » : le texte, ou `''` (rien à signaler, ou aucune mère à interroger). Un service de la mère qui ne répond pas est DIT
/// (l'état des postes est inconnu), jamais lu comme « tout est à jour ».
Future<String> avertissementPostesAvantCloture(Magasin m, int annee, DateTime maintenant) async {
  final f = PostesAppaires.fournisseur;
  if (f == null) return '';
  final delai = circuitClotureDe(m, horloge: () => maintenant).delaiEtatPosteHeures;
  try {
    return cpcTexteAvertissementPostes(cpcAvertissementsPostes(await f(), maintenant, delaiHeures: delai), annee);
  } catch (_) {
    return 'Avertissement, non bloquant : le service de la mère ne répond pas, l’état des postes appairés est inconnu. Une fois $annee en clôture, la mère refuse les pièces datées de $annee '
        'qu’un poste lui enverrait ; vérifier les postes d’abord.';
  }
}
