/// M1 — LA FICHE PATIENT : le dossier de consultation relu (examen IPPOA par appareil), l'imagerie au dossier et ses habilitations.
/// Rejoué sur `test/vecteurs/pat_profil.json`.
library;

import '../labo/res_habilitations.dart' show SessionLabo, capacites, libelleSecteur;
import 'pat_patients.dart';

/// `D.TEMPS_EXAMEN` : l'examen physique suit ses quatre temps, DANS L'ORDRE.
const patTempsExamen = [
  ('inspection', 'Inspection'),
  ('palpation', 'Palpation'),
  ('percussion', 'Percussion'),
  ('auscultation', 'Auscultation'),
];

/// `D.APPAREILS_EXAMEN` : (code, libellé, porte la menstruation ?).
const patAppareilsExamen = <(String, String, bool)>[
  ('cardio_vasculaire', 'Appareil cardio-vasculaire', false),
  ('pleuro_pulmonaire', 'Appareil pleuro-pulmonaire', false),
  ('hepato_gastro_digestif', 'Hépato-gastro-digestif', false),
  ('genito_urinaire', 'Génito-urinaire', true),
  ('locomoteur', 'Appareil locomoteur', false),
  ('orl', 'ORL', false),
  ('neurologie', 'Neurologie', false),
  ('gyneco_obstetrique', 'Gynéco-obstétrique', true),
  ('peau_phaneres', 'Peau et phanères', false),
];

/// La mention posée par « Normal par défaut » : une seule chaîne, pour reconnaître un appareil examiné normal d'un appareil non examiné.
const patMentionNormale = 'RAS';

({String code, String label, bool menstruation}) _appareil(String code) {
  if (code == 'global') {
    return (code: 'global', label: 'Examen global (saisie antérieure à la refonte)', menstruation: false);
  }
  final a = patAppareilsExamen.where((x) => x.$1 == code).firstOrNull;
  return a != null
      ? (code: a.$1, label: a.$2, menstruation: a.$3)
      : (code: code, label: code, menstruation: false);
}

/// `D.examensPhysiquesDe(dossier)` : l'examen physique d'un dossier, QUELLE QUE SOIT SA GÉNÉRATION. Les dossiers d'avant la refonte portent quatre
/// champs plats (`exam_inspection`…) : on les présente sous « Examen global », on ne les réécrit pas.
Map<String, Object?> patExamensPhysiquesDe(FichePat? dossier) {
  if (dossier == null) return const {};
  final e = dossier['examensPhysiques'];
  if (e is Map) return e.cast<String, Object?>();
  final global = <String, Object?>{};
  for (final t in patTempsExamen) {
    final v = dossier['exam_${t.$1}'];
    if (patVrai(v)) global[t.$1] = v;
  }
  return global.isEmpty ? const {} : {'global': global};
}

class PatLigneExamen {
  const PatLigneExamen(this.code, this.label, this.normal, this.texte);
  final String code;
  final String label;
  final bool normal;
  final String texte;
}

/// `D.syntheseExamen(examens)` : une ligne par appareil RENSEIGNÉ ; un appareil dont tous les temps valent « RAS » se condense en « RAS — examen
/// normal ». Elle reçoit les EXAMENS, non le dossier (écart E316 : la fiche lui passait le dossier entier et affirmait « aucun appareil renseigné »).
List<PatLigneExamen> patSyntheseExamen(Map<String, Object?>? examens) {
  final out = <PatLigneExamen>[];
  (examens ?? const {}).forEach((code, bloc0) {
    final bloc = bloc0 is Map ? bloc0.cast<String, Object?>() : const <String, Object?>{};
    final ap = _appareil(code);
    final temps = [
      for (final t in patTempsExamen) (t.$1, t.$2),
      if (ap.menstruation) ('menstruation', 'Menstruation'),
    ];
    final remplis = [
      for (final t in temps)
        if (patVrai(bloc[t.$1]) && '${bloc[t.$1]}'.trim().isNotEmpty) t
    ];
    if (remplis.isEmpty) return;
    final normal = remplis.every((t) => '${bloc[t.$1]}'.trim() == patMentionNormale);
    out.add(PatLigneExamen(
        code,
        ap.label,
        normal,
        normal
            ? 'RAS — examen normal'
            : remplis.map((t) => '${t.$2} : ${bloc[t.$1]}').join(' · ')));
  });
  return out;
}

/// Les trois catégories d'antécédents du dossier de consultation (`D.CATEGORIES_ANTECEDENT`).
const patCategoriesAntecedent = [
  ('medicaux', 'Antécédents médicaux'),
  ('chirurgicaux', 'Antécédents chirurgicaux'),
  ('gyneco_obstetricaux', 'Antécédents gynéco-obstétricaux'),
];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// L'imagerie médicale au dossier : le RBAC métier s'applique comme pour les analyses
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `porteeImagerie()` : `tous` · `secteur` · `aucun`. Le poste d'imagerie PRODUIT les comptes rendus : il les lit tous.
String patPorteeImagerie(SessionLabo session) {
  if (session.role == 'echographiste') return 'tous';
  switch (capacites(session).fonction) {
    case 'medecin':
    case 'chirurgien':
    case 'direction':
      return 'tous';
    case 'sage_femme':
      return 'secteur';
  }
  return 'aucun';
}

/// `peutLireCR(dem, cr)` : (autorisé, motif). Seul un compte rendu RENDU au prescripteur se lit ; le contenu obéit aux droits du profil.
({bool ok, String? motif}) patPeutLireCR(FichePat? dem, FichePat? cr, SessionLabo session) {
  final portee = patPorteeImagerie(session);
  if (portee == 'aucun') {
    return (ok: false, motif: 'Votre profil ne lit pas les comptes rendus d’imagerie (RG-13).');
  }
  final rendu = (cr != null && cr['statut'] == 'rendu') || (dem != null && dem['statut'] == 'validee');
  if (!rendu && session.role != 'echographiste') {
    return (ok: false, motif: 'Compte rendu non encore rendu au prescripteur — l’imagerie le relit.');
  }
  if (portee == 'secteur') {
    final sect = libelleSecteur(session.secteur);
    final demandeur = (dem?['secteurDemandeur'] ?? cr?['secteurDemandeur']);
    if (sect == null || !patVrai(demandeur) || demandeur != sect) {
      return (ok: false, motif: 'Compte rendu d’un autre secteur que le vôtre.');
    }
  }
  return (ok: true, motif: null);
}

/// Les états d'une demande d'imagerie, tels que l'onglet les écrit (libellé, ton).
const patEtatsImagerie = {
  'demandee': ('Demandée — attente caisse', 'warning'),
  'payee': ('Payée — à exécuter', 'info'),
  'executee': ('Exécutée — CR en rédaction', 'navy'),
  'validee': ('Validée — CR rendu', 'success'),
};
