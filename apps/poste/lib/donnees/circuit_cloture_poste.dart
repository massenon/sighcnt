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
  final voulu = cle == cpcCleMoisOuverture ? (valeur is num ? valeur.toInt() : int.parse('$valeur')) : cpcListeRoles(valeur).join(',');
  try {
    final w = service.regler(cle, voulu, date, motif: (motif ?? '').trim());
    if (!w.ok) return CpcRefusCircuit('CIRCUIT_REGLAGE_REFUSE', '${w.refus!.code} : ${w.refus!.motif}', w.refus!.geste);
  } on EcritureRefusee catch (e) {
    return CpcRefusCircuit('FILEUL_LECTURE_SEULE', e.motif, 'Régler le circuit sur le poste mère : ce poste reçoit ce réglage par le journal.');
  }
  m.journaliser('Circuit de clôture : nouvelle version', 'M12', 'reglagesCloture', cle, {'valeur': avant}, {'valeur': voulu, 'dateEffet': date, 'motif': (motif ?? '').trim()});
  return null;
}
