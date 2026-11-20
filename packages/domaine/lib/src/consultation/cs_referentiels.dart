/// RÉFÉRENTIELS ET LECTURES DE LA CONSULTATION (zone 2) — port de `data-dossier.js`, `data-clinique.js` et du module `m2-consultations.js`.
///
/// Les données (appareils de l'examen IPPOA, états du dossier, types de venue, chapitres de morbidité, origines de prescription…) sont ENGENDRÉES
/// depuis la maquette (`cs_donnees.dart`, script `prototype_html/build/vecteurs-consultation.js`) — jamais recopiées à la main. Ce fichier ne porte
/// que les LECTURES (états, transitions, synthèse de l'examen, relais d'administration) et la liste des orientations, qui est locale à l'écran de
/// la fiche dans la maquette.
library;

import 'cs_donnees.dart';

typedef FicheCs = Map<String, Object?>;

bool csVrai(Object? v) => v != null && v != '' && v != 0 && v != false;

List<FicheCs> _liste(String cle) => [
      for (final x in (csDonnees[cle] as List)) (x as Map).cast<String, Object?>()
    ];

List<FicheCs> get csAppareils => _liste('appareils');
List<FicheCs> get csTempsExamen => _liste('temps');
List<FicheCs> get csCategoriesAntecedent => _liste('antecedents');
List<FicheCs> get csEtatsDossier => _liste('etatsDossier');
List<FicheCs> get csTypesVenue => _liste('typesVenue');
List<FicheCs> get csEtatsGeneraux => _liste('etatsGeneraux');
List<FicheCs> get csExamenObstetrical => _liste('examenObstetrical');
List<FicheCs> get csChapitresPathologie => _liste('chapitres');
List<FicheCs> get csOriginesPrescription => _liste('originesPrescription');
List<FicheCs> get csSecteursSoins => _liste('secteursSoins');
List<FicheCs> get csModalitesTraitement => _liste('modalites');
List<String> get csPathologiesObstetricales =>
    [for (final x in (csDonnees['pathologiesObstetricales'] as List)) '$x'];
List<String> get csRubriquesChirurgicales =>
    [for (final x in (csDonnees['rubriquesChirurgicales'] as List)) '$x'];
String get csMentionNormale => '${csDonnees['mentionNormale']}';

/// Les orientations de la fiche (`ORIENTATIONS`, locales à `m2-consultations.js`).
const csOrientations = <({String valeur, String libelle})>[
  (valeur: 'domicile', libelle: 'Domicile — traitement ambulatoire'),
  (valeur: 'hospitalisation', libelle: 'Hospitalisation'),
  (valeur: 'observation', libelle: 'Mise en observation'),
  (valeur: 'laboratoire', libelle: 'Laboratoire (en attente des résultats)'),
  (valeur: 'pharmacie', libelle: 'Pharmacie'),
  (valeur: 'reference', libelle: 'Référence vers un autre établissement'),
];

/// `libelleOrientation(code)` : une orientation inconnue s'affiche sous son code, absente sous un tiret.
String csLibelleOrientation(Object? code) {
  for (final o in csOrientations) {
    if (o.valeur == code) return o.libelle;
  }
  return csVrai(code) ? '$code' : '—';
}

/// `D.etatDossier(code)` : un code inconnu retombe sur le premier état.
FicheCs csEtatDossier(Object? code) =>
    csEtatsDossier.where((e) => e['code'] == code).firstOrNull ??
    csEtatsDossier.first;

/// `D.transitionPermise(de, vers)` : les sauts d'état sont REFUSÉS — clôturer un dossier resté « en attente » signerait une consultation qui n'a
/// pas eu lieu.
bool csTransitionPermise(Object? de, Object? vers) =>
    ((csEtatDossier(de)['suivants'] as List?) ?? const []).contains(vers);

String csLibelleTypeVenue(Object? code) {
  final t = csTypesVenue.where((x) => x['value'] == code).firstOrNull;
  return t != null ? '${t['label']}' : (csVrai(code) ? '$code' : '—');
}

String csLibelleEtatGeneral(Object? code) {
  final t = csEtatsGeneraux.where((x) => x['value'] == code).firstOrNull;
  return t != null ? '${t['label']}' : (csVrai(code) ? '$code' : '—');
}

/// `D.appareilExamen(code)` : « global » = les dossiers d'avant la refonte.
FicheCs csAppareilExamen(String code) {
  if (code == 'global') {
    return {
      'code': 'global',
      'label': 'Examen global (saisie antérieure à la refonte)',
      'icone': 'history'
    };
  }
  return csAppareils.where((a) => a['code'] == code).firstOrNull ??
      {'code': code, 'label': code, 'icone': 'circle'};
}

/// `D.tempsExamenDe(appareil)` : les quatre temps, plus la menstruation pour les appareils qui la portent.
List<FicheCs> csTempsExamenDe(FicheCs? appareil) => [
      for (final t in csTempsExamen)
        {'code': t['code'], 'label': t['label'], 'ordre': t['ordre']},
      if (appareil != null && csVrai(appareil['menstruation']))
        {'code': 'menstruation', 'label': 'Menstruation', 'ordre': 5},
    ];

/// `D.examensPhysiquesDe(dossier)` : l'objet par appareil ; un dossier d'ancienne génération (champs plats `exam_*`) devient un appareil « global ».
Map<String, Object?> csExamensPhysiquesDe(FicheCs? dossier) {
  if (dossier == null) return {};
  final e = dossier['examensPhysiques'];
  if (e is Map) return e.cast<String, Object?>();
  final global = <String, Object?>{};
  for (final t in csTempsExamen) {
    final v = dossier['exam_${t['code']}'];
    if (csVrai(v)) global['${t['code']}'] = v;
  }
  return global.isNotEmpty ? {'global': global} : {};
}

/// Une ligne de la synthèse de l'examen : un appareil examiné, normal ou non.
class SyntheseExamen {
  const SyntheseExamen(this.code, this.label, this.normal, this.texte);
  final String code, label, texte;
  final bool normal;
}

/// `D.syntheseExamen(examens)` : seuls les appareils EXAMINÉS apparaissent ; « RAS » partout = « RAS — examen normal ».
List<SyntheseExamen> csSyntheseExamen(Map<String, Object?>? examens) {
  final sortie = <SyntheseExamen>[];
  (examens ?? const <String, Object?>{}).forEach((code, b) {
    final bloc = (b as Map?)?.cast<String, Object?>() ?? const {};
    final ap = csAppareilExamen(code);
    final remplis = [
      for (final t in csTempsExamenDe(ap))
        if (csVrai(bloc[t['code']]) && '${bloc[t['code']]}'.trim().isNotEmpty) t
    ];
    if (remplis.isEmpty) return;
    final normal =
        remplis.every((t) => '${bloc[t['code']]}'.trim() == csMentionNormale);
    sortie.add(SyntheseExamen(
        code,
        '${ap['label']}',
        normal,
        normal
            ? 'RAS — examen normal'
            : remplis.map((t) => '${t['label']} : ${bloc[t['code']]}').join(' · ')));
  });
  return sortie;
}

/// `D.peutEcrireRubrique(rubrique, capacite)` : les rubriques chirurgicales ne s'ÉCRIVENT que par le chirurgien — mais se lisent par tous.
({bool ok, String? motif}) csPeutEcrireRubrique(String rubrique, String capacite) {
  if (!csRubriquesChirurgicales.contains(rubrique)) return (ok: true, motif: null);
  if (capacite == 'chirurgien') return (ok: true, motif: null);
  return (
    ok: false,
    motif:
        'Les actes chirurgicaux et la programmation du bloc ne sont renseignés que par le chirurgien. Un généraliste peut les LIRE — c’est son patient aussi — mais non les écrire.'
  );
}

/// `D.secteurAdministrateur(modalite, rang)` : la RÈGLE DE RELAIS. Traitement ambulatoire → salle de soins du premier au dernier passage ;
/// traitement hospitalier → PREMIÈRE administration en salle de soins, SUIVANTES en hospitalisation. C'est le rang qui décide.
({String secteur, String motif}) csSecteurAdministrateur(
    Object? modalite, int rang) {
  if (modalite == 'ambulatoire') {
    return (
      secteur: 'salle_soins',
      motif:
          'Traitement ambulatoire : toutes les administrations reviennent à la salle de soins.'
    );
  }
  if (rang <= 1) {
    return (
      secteur: 'salle_soins',
      motif:
          'Première administration d’un traitement hospitalier : elle revient à la salle de soins.'
    );
  }
  return (
    secteur: 'hospitalisation',
    motif: 'Administration n° $rang : le relais est passé à l’hospitalisation.'
  );
}

/// `libelleOrigine(code)` / `libelleSecteur(code)` de `m2-prescriptions`.
String csLibelleOrigine(Object? code) {
  final o = csOriginesPrescription.where((x) => x['code'] == code).firstOrNull;
  return o != null ? '${o['label']}' : (csVrai(code) ? '$code' : '—');
}

String csLibelleSecteur(Object? code) {
  final o = csSecteursSoins.where((x) => x['code'] == code).firstOrNull;
  if (o != null) return '${o['label']}';
  return code == 'pharmacie' ? 'Pharmacie' : (csVrai(code) ? '$code' : '—');
}
