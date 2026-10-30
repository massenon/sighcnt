/// HABILITATIONS MÉTIER DU RÉSULTAT — ce que l'agent peut VOIR, pas seulement ouvrir.
/// Port de `D.CAPACITES`, `PR.capacites`, `PR.secteurCourant`, `PR.peutVoirResultat`, `PR.filtrerResultats` et `PR.continuiteRespectee`
/// (prototype_html/assets/js/data.js, parcours.js). Vecteurs : `test/vecteurs/resultats.json`.
///
/// Trois axes, et non un seul : le RÔLE décide des écrans (manifeste), la FONCTION des capacités, le SECTEUR du périmètre des données.
/// Le PREMIER VERROU est posé AVANT toute question d'habilitation : un résultat non validé biologiquement n'existe pas pour le prescripteur.
/// Une restriction s'ANNONCE : `peutVoirResultat` rend toujours un `motif`, destiné à l'écran.
library;

import 'res_etats.dart';

typedef FicheLabo = Map<String, Object?>;

/// La session de l'agent, telle que la maquette la porte : rôle, fonction, secteur (code NS 145), identifiant et nom.
class SessionLabo {
  const SessionLabo({this.role, this.fonction, this.secteur, this.id, this.nom});
  final String? role;
  final String? fonction;
  final String? secteur;
  final String? id;
  final String? nom;
}

class CapaciteLabo {
  const CapaciteLabo({
    required this.fonction,
    required this.label,
    required this.voirResultats,
    this.fonctionInconnue,
    this.validerTechnique = false,
    this.validerBiologique,
    this.continuitePrelevement = false,
    this.secteurs = const [],
    this.remettreResultats = false,
    this.note,
  });

  /// La fonction RETENUE (celle de la session si elle existe, sinon celle déduite du rôle).
  final String fonction;

  /// La fonction demandée par la session quand elle n'existe pas au référentiel : la substitution est SIGNALÉE, jamais muette.
  final String? fonctionInconnue;
  final String label;

  /// `tous` | `secteur` | `produits` | `aucun`.
  final String voirResultats;
  final bool validerTechnique;

  /// `null` (non habilité) | `true` (le biologiste médical) | `'interim'` (le TSL, en son absence — tracé sur la pièce).
  final Object? validerBiologique;
  final bool continuitePrelevement;
  final List<String> secteurs;
  final bool remettreResultats;
  final String? note;

  CapaciteLabo avec({required String fonction, String? fonctionInconnue}) =>
      CapaciteLabo(
          fonction: fonction,
          fonctionInconnue: fonctionInconnue,
          label: label,
          voirResultats: voirResultats,
          validerTechnique: validerTechnique,
          validerBiologique: validerBiologique,
          continuitePrelevement: continuitePrelevement,
          secteurs: secteurs,
          remettreResultats: remettreResultats,
          note: note);
}

/// `D.CAPACITES` — réduit à ce que le résultat d'analyse lit. La transcription est vérifiée contre la maquette (vecteur `toutesCapacites`).
const Map<String, CapaciteLabo> capacitesLabo = {
  'medecin': CapaciteLabo(
      fonction: 'medecin',
      label: 'Médecin',
      voirResultats: 'tous',
      note: 'Accès à tous les résultats, quel que soit le prescripteur.'),
  'sage_femme': CapaciteLabo(
      fonction: 'sage_femme',
      label: 'Sage-femme',
      voirResultats: 'secteur',
      secteurs: ['MATERNITE'],
      note: 'Résultats de la maternité seulement — pas ceux demandés par la chirurgie.'),
  'infirmier': CapaciteLabo(
      fonction: 'infirmier',
      label: 'Infirmier(ère)',
      voirResultats: 'aucun',
      note: 'Exécute les soins prescrits ; ne consulte pas les résultats d’analyses.'),
  'aide_soignant': CapaciteLabo(
      fonction: 'aide_soignant',
      label: 'Aide-soignant(e)',
      voirResultats: 'aucun',
      note: 'N’exécute pas les soins prescrits et ne consulte aucun résultat.'),
  'tsl': CapaciteLabo(
      fonction: 'tsl',
      label: 'Technicien de laboratoire',
      voirResultats: 'produits',
      remettreResultats: true,
      validerTechnique: true,
      validerBiologique: 'interim',
      note:
          'Produit les résultats, les valide techniquement et les remet aux patients externes. Peut porter la validation biologique par intérim, qui est alors tracée comme telle.'),
  'biologiste': CapaciteLabo(
      fonction: 'biologiste',
      label: 'Biologiste médical',
      voirResultats: 'tous',
      remettreResultats: true,
      validerTechnique: true,
      validerBiologique: true,
      continuitePrelevement: true,
      note: 'Détient la validation biologique : c’est elle qui rend le résultat visible du prescripteur.'),
  'accueil': CapaciteLabo(
      fonction: 'accueil',
      label: 'Accueil / Secrétaire médical',
      voirResultats: 'aucun',
      note: 'Aucun accès aux résultats ni aux prescriptions.'),
  'caissiere': CapaciteLabo(
      fonction: 'caissiere',
      label: 'Caissière',
      voirResultats: 'aucun',
      note: 'Voit la liste des prestations à encaisser, jamais leur contenu clinique.'),
  'dispensatrice': CapaciteLabo(
      fonction: 'dispensatrice',
      label: 'Dispensatrice',
      voirResultats: 'aucun',
      note: 'Voit les médicaments prescrits, non les résultats d’analyses.'),
  'direction': CapaciteLabo(
      fonction: 'direction',
      label: 'Direction',
      voirResultats: 'tous',
      note: 'Accès de supervision, sans droit de prescription.'),
  'stock': CapaciteLabo(
      fonction: 'stock', label: 'Gestionnaire de stock', voirResultats: 'aucun'),
  'comptable': CapaciteLabo(
      fonction: 'comptable', label: 'Comptable', voirResultats: 'aucun'),
  'securite': CapaciteLabo(
      fonction: 'securite', label: 'Agent de sécurité', voirResultats: 'aucun'),
  'entretien': CapaciteLabo(
      fonction: 'entretien', label: 'Agent d’entretien', voirResultats: 'aucun'),
  'chauffeur': CapaciteLabo(
      fonction: 'chauffeur', label: 'Chauffeur coursier', voirResultats: 'aucun'),
  'chirurgien': CapaciteLabo(
      fonction: 'chirurgien',
      label: 'Chirurgien',
      voirResultats: 'tous',
      note:
          'Seul à renseigner les actes chirurgicaux et la programmation du bloc. Consulte le mardi et le jeudi (chirurgien-gynécologue).'),
};

/// `ROLE_VERS_FONCTION` : la fonction déduite d'un rôle quand la session n'en porte pas. Un rôle absent d'ici retombe sur `accueil`
/// (le profil le plus restrictif) — comme la maquette, qui ne connaît pas encore l'aide-soignant ou l'échographiste par ce chemin.
const Map<String, String> roleVersFonction = {
  'medecin': 'medecin',
  'dm': 'medecin',
  'direction': 'direction',
  'da': 'direction',
  'infirmier': 'infirmier',
  'pharmacien': 'dispensatrice',
  'laborantin': 'tsl',
  'caissier': 'caissiere',
  'reception': 'accueil',
  'stock': 'stock',
  'comptable': 'comptable',
  'rh': 'direction',
  'admin': 'direction',
  'agentadmin': 'entretien',
  'ambulancier': 'chauffeur',
};

/// `PR.capacites(session)`. UNE FONCTION INCONNUE NE FERME PAS L'ÉCRAN EN SILENCE : elle retombe sur la fonction déduite du RÔLE, et la
/// substitution est signalée par `fonctionInconnue`.
CapaciteLabo capacites([SessionLabo? session]) {
  final s = session ?? const SessionLabo();
  final demandee = (s.fonction ?? '').isEmpty ? null : s.fonction;
  final duRole = roleVersFonction[s.role];
  final inconnue = demandee != null && !capacitesLabo.containsKey(demandee);
  final f = (demandee != null && capacitesLabo.containsKey(demandee))
      ? demandee
      : (duRole ?? 'accueil');
  return capacitesLabo[f]!.avec(fonction: f, fonctionInconnue: inconnue ? demandee : null);
}

/// NS 145 — les secteurs de la clinique (identifiant, code, libellé). `PR.secteurCourant` y cherche le secteur de l'agent.
const List<(String, String, String)> secteursNs145 = [
  ('SEC01', 'ACC', 'ACCUEIL'),
  ('SEC02', 'ADM', 'ADMINISTRATION'),
  ('SEC03', 'MGE', 'MÉDECINE GÉNÉRALE'),
  ('SEC04', 'CHI', 'CHIRURGIE'),
  ('SEC05', 'MAT', 'MATERNITÉ'),
  ('SEC06', 'ECH', 'ÉCHOGRAPHIE'),
  ('SEC07', 'LAB', 'LABORATOIRE'),
  ('SEC08', 'HOS', 'HOSPI'),
  ('SEC09', 'SOI', 'SALLE DE SOINS'),
  ('SEC10', 'BLO', 'BLOC OPÉRATOIRE'),
  ('SEC11', 'SUR', 'SURVEILLANCE'),
  ('SEC12', 'CPH', 'CAISSE / PHARMACIE'),
  ('SEC13', 'SEC', 'SÉCURITÉ'),
  ('SEC14', 'ENT', 'ENTRETIEN'),
];

/// `PR.secteurCourant(session)` → le libellé du secteur de l'agent (`null` si la session n'en porte pas ou s'il est inconnu).
String? libelleSecteur(String? codeOuId) {
  if (codeOuId == null || codeOuId.isEmpty) return null;
  for (final s in secteursNs145) {
    if (s.$2 == codeOuId || s.$1 == codeOuId) return s.$3;
  }
  return null;
}

class VisibiliteResultat {
  const VisibiliteResultat(this.autorise, this.motif, {this.enAttenteValidation = false});
  final bool autorise;
  final String motif;
  final bool enAttenteValidation;
}

bool _vide(Object? v) => v == null || v == '' || v == false;

/// `PR.peutVoirResultat(demande, session)` — décide, et dit pourquoi.
VisibiliteResultat peutVoirResultat(FicheLabo? demande, [SessionLabo? session]) {
  final cap = capacites(session);

  // LE PREMIER VERROU, avant toute question d'habilitation. Le laboratoire voit son propre travail en cours : sans cela il ne pourrait pas le relire.
  final duLabo = cap.voirResultats == 'produits' || cap.validerTechnique;
  final etat = demande?['etatAnalyse'];
  if (demande != null && !_vide(etat) && !duLabo && !resultatRendu(etat)) {
    return VisibiliteResultat(
        false,
        'Résultat non encore validé biologiquement — ${etatResultat(etat).label.toLowerCase()}. Le laboratoire le relit avant de le rendre.',
        enAttenteValidation: true);
  }

  switch (cap.voirResultats) {
    case 'tous':
      return VisibiliteResultat(true, '${cap.label} — accès à tous les résultats');
    case 'aucun':
      return VisibiliteResultat(false,
          '${cap.label} — les résultats d’analyses ne lui sont pas accessibles');
    case 'produits':
      return const VisibiliteResultat(true, 'Laboratoire — résultat produit par le service');
    case 'secteur':
      final sect = libelleSecteur(session?.secteur);
      final dem = demande == null
          ? null
          : (!_vide(demande['secteurDemandeur'])
              ? '${demande['secteurDemandeur']}'
              : (!_vide(demande['secteur']) ? '${demande['secteur']}' : null));
      final mien = sect ?? (cap.secteurs.isNotEmpty ? cap.secteurs.first : '');
      final ok = dem != null &&
          mien.isNotEmpty &&
          dem.toUpperCase().contains(mien.toUpperCase());
      return VisibiliteResultat(
          ok,
          ok
              ? '${cap.label} — résultat demandé par son secteur ($dem)'
              : '${cap.label} — résultat demandé par ${dem ?? 'un autre secteur'}, hors de son périmètre');
  }
  return const VisibiliteResultat(false, 'Périmètre non défini');
}

/// `PR.filtrerResultats(liste, session)`.
List<FicheLabo> filtrerResultats(Iterable<FicheLabo> liste, [SessionLabo? session]) =>
    [for (final d in liste) if (peutVoirResultat(d, session).autorise) d];

class ContinuiteLabo {
  const ContinuiteLabo(this.ok, {this.motif, this.preleveur});
  final bool ok;
  final String? motif;
  final String? preleveur;
}

/// `PR.continuiteRespectee(demande, agent)` — CELUI QUI A PRÉLEVÉ EST CELUI QUI VALIDE. Règle de PREUVE : le validateur atteste d'un échantillon,
/// et s'il ne l'a pas vu arriver il atteste de ce qu'un collègue lui a dit. Le refus NOMME le préleveur.
ContinuiteLabo continuiteRespectee(FicheLabo? demande, {Object? agentId, Object? agentNom}) {
  if (demande == null) return const ContinuiteLabo(false, motif: 'Demande introuvable.');
  Object? ou(Object? a, Object? b) => _vide(a) ? b : a;
  final preleveur = ou(demande['preleveParId'], ou(demande['prelevePar'], null));
  if (_vide(preleveur)) {
    return const ContinuiteLabo(true,
        motif: 'Aucun prélèvement enregistré — la continuité ne s’applique pas encore.');
  }
  final meme = (!_vide(agentId) && preleveur == agentId) ||
      (!_vide(agentNom) && preleveur == agentNom);
  if (meme) return const ContinuiteLabo(true);
  final nom = _vide(demande['prelevePar']) ? '$preleveur' : '${demande['prelevePar']}';
  return ContinuiteLabo(false,
      preleveur: nom,
      motif:
          'Le prélèvement a été fait par $nom. C’est à lui de valider : un validateur qui n’a pas vu arriver l’échantillon atteste de ce qu’un collègue lui a dit, et la signature perd sa valeur.');
}
