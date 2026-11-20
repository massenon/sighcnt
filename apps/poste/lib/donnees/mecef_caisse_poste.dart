import 'package:sigh_domaine/sigh_domaine.dart' as d;

import '../core/service_parametres.dart';
import 'magasin.dart';
import 'mecef_poste.dart';

/// MECeF, lot MECEF-M au poste : l'IMPRIMANTE DE CAISSE datée, l'ÉTAT DE LA CAISSE, et le réglage du MODE par geste réservé. La colle entre le domaine
/// (`mecef/caisse.dart`, rejoué sur les vecteurs tirés de l'écran réel de la maquette) et le registre des paramètres du poste (famille `mecef`, défauts semés, versionnés par
/// date, réglage de BRANCHE posé à la mère, jamais vers un téléphone). Aucune valeur ici : le réglage se LIT à la date ; aucun nom de rôle : le droit vient de la fiche RBAC.

/// L'imprimante de caisse en vigueur à [jour] : la version datée en vigueur du paramètre `mecef.imprimante`, sinon le défaut semé.
d.ImprimanteALaDate imprimanteDuPoste(Magasin m, DateTime jour) {
  final versions = <d.VersionImprimante>[];
  for (final f in m.collection(d.parCollectionParametres).toutes) {
    if (f['cle'] != d.mecefCleImprimante || f['statut'] == 'archive' || f['dateEffet'] == null) continue;
    final v = d.imprimanteVersionDepuisRegistre('${f['dateEffet']}'.substring(0, 10), f['valeur'], motif: f['motif'] as String?);
    if (v != null) versions.add(v);
  }
  return d.imprimanteALaDate(versions, d.parametreDateIso(jour));
}

/// Règle l'imprimante : contrôle du domaine (droit réservé, fileul, motif, date passée, nom, liaison), puis NOUVELLE version datée du registre (jamais une réécriture),
/// journalisée (RG-12). Rend `null` si réglé, sinon le refus nommé.
d.RefusMecef? reglerImprimanteDuPoste(Magasin m,
    {required bool gesteAccorde,
    required bool fileul,
    required String libelleRole,
    required String rolesQuiLeDetiennent,
    required String? nom,
    required String? liaison,
    required String dateEffet,
    required String? motif,
    DateTime Function()? horloge}) {
  final h = horloge ?? m.horloge;
  final auj = d.parametreDateIso(h());
  final refus = d.imprimanteControler(
      aDroit: gesteAccorde,
      fileul: fileul,
      motif: motif,
      dateEffet: dateEffet,
      aujourdhui: auj,
      nom: nom,
      liaison: liaison,
      libelleRole: libelleRole,
      rolesQuiLeDetiennent: rolesQuiLeDetiennent);
  if (refus != null) return refus;
  final avant = imprimanteDuPoste(m, DateTime.parse(dateEffet));
  final valeur = d.imprimanteValeurJson(modele: avant.modele, type: avant.type, largeurMm: avant.largeurMm, liaison: liaison!, nom: nom!.trim());
  final service = serviceParametres(m, auteur: () => m.utilisateur, horloge: h);
  try {
    final w = service.regler(d.mecefCleImprimante, valeur, dateEffet, motif: (motif ?? '').trim());
    if (!w.ok) return d.RefusMecef('IMPRIMANTE_REGLAGE_REFUSE', w.refus!.motif, w.refus!.geste);
  } on EcritureRefusee catch (e) {
    return d.RefusMecef('FILEUL_LECTURE_SEULE', e.motif, 'Régler l’imprimante sur le poste mère : ce poste le reçoit par le journal.');
  }
  m.journaliser('Imprimante de caisse : nouvelle version', 'MECEF', 'reglage', 'imprimanteCaisse', {'liaison': avant.liaison, 'nom': avant.nom, 'dateEffet': avant.dateEffet},
      {'liaison': liaison, 'nom': nom.trim(), 'dateEffet': dateEffet, 'motif': (motif ?? '').trim()});
  return null;
}

/// Règle le MODE de facturation normalisée par le geste réservé `regler_mode_mecef` (plus de liste de rôles) : mode inconnu, droit, fileul, puis nouvelle version datée du
/// paramètre `mecef.mode`, journalisée. Rend `null` si réglé, sinon le refus nommé (le moteur refuse aussi : masquer le bouton ne protège rien).
d.RefusMecef? reglerModeMecefDuPoste(Magasin m,
    {required Object? mode,
    required bool gesteAccorde,
    required bool fileul,
    required String libelleRole,
    required String rolesQuiLeDetiennent,
    DateTime Function()? horloge}) {
  final h = horloge ?? m.horloge;
  final refus = d.mecefModeControler(mode: mode, aDroit: gesteAccorde, fileul: fileul, libelleRole: libelleRole, rolesQuiLeDetiennent: rolesQuiLeDetiennent);
  if (refus != null) return refus;
  final avant = modeMecefDuPoste(m, h());
  final service = serviceParametres(m, auteur: () => m.utilisateur, horloge: h);
  try {
    final w = service.regler(d.mecefCleMode, mode, d.parametreDateIso(h()), motif: 'Réglé à « Configuration fiscale ».');
    if (!w.ok) return d.RefusMecef(w.refus!.code, w.refus!.motif, w.refus!.geste);
  } on EcritureRefusee catch (e) {
    return d.RefusMecef('FILEUL_LECTURE_SEULE', e.motif, 'Régler le mode sur le poste mère : ce poste le reçoit par le journal.');
  }
  m.journaliser('Mode de facturation normalisée', 'MECEF', 'reglage', 'mecefMode', {'mode': avant}, {'mode': mode});
  return null;
}

/// L'état de la caisse : ventes encaissées non normalisées, avoirs en attente de certification à part, montant non calculable `null` (jamais zéro).
d.EtatCaisse etatCaissePoste(Magasin m) => d.etatCaisse([
      for (final f in m.collection('factures').actives) d.PieceCaisse.depuisJson(f),
    ], [
      for (final a in m.collection('avoirs').actives) d.AvoirCaisse.depuisJson(a),
    ]);
