import 'package:sigh_domaine/sigh_domaine.dart';

import 'magasin.dart';

/// LA DÉCISION DE VALIDATION D'UN FILEUL AU POSTE (lot CONT, exigence de la Direction du 14/11/2026) : la colle entre les règles pures de
/// `packages/domaine/lib/src/validation/demande_validation.dart` et le magasin du poste. Aucune règle de validation ici.
///
///  * FILEUL rattaché : [deposer] SIGNE la décision (qui, quand, motif) et la dépose dans `demandesValidation` (famille A). L'écran ne se bloque jamais : l'élément reste utilisable avec
///    la règle en vigueur, le badge dit « décision déposée, en attente de la mère » et le compte « N décisions en attente de la mère » est lu de cette collection.
///  * MÈRE : [appliquer] est l'APPLICATEUR MÉCANIQUE. Pour chaque demande « déposée », dans l'ordre de la signature, elle refait les mêmes contrôles sous le rôle et le nom de l'AUTEUR
///    (un bouton absent ne protège rien), écrit le marquage (comme le geste direct), journalise et pose le verdict sur la demande (qui revient au fileul par le pont). Elle ne décide jamais :
///    personne n'a besoin de se tenir à son poste. Rejeu sans effet (seule une demande « déposée » est traitée).
///
/// [ecrireVerdict] est LE chemin d'écriture d'une validation, partagé avec le geste direct de `ValidationPoste` : une seule copie du code qui écrit le marquage et sa ligne de journal (RG-12).
class DemandesValidationPoste {
  DemandesValidationPoste(this.m, {required this.libelles, DateTime Function()? horloge, this.etiquette = 'F'}) : _horloge = horloge ?? DateTime.now;
  final Magasin m;
  final Map<String, String> libelles;
  final String etiquette;
  final DateTime Function() _horloge;

  LectureValidation get lire => (nom) => m.collection(nom).toutes;

  /// Les libellés de rôle de la matrice en force pour tous les profils du registre des validations.
  static Map<String, String> libellesDesRoles(MatriceDroits? matrice) => {
        for (final f in valFamilles)
          for (final r in f.roles) r: matrice?.libelle(r) ?? r,
      };

  List<Fiche> get demandes => m.collection(valCollectionDemandes).toutes;

  /// La demande qui attend la mère pour cette cible, ou `null`.
  Fiche? enAttenteDe(String famille, Object? id) => valDemandeEnAttenteDe(demandes, famille, '$id');

  SyntheseDecisionsEnAttente synthese() => valSyntheseEnAttente(demandes, _horloge());

  /// FILEUL : signe et dépose la décision. Rend le dépôt (refus nommé, ou la fiche écrite). Journalise une ligne (RG-12).
  VerdictDepotValidation deposer(String famille, Object? id, {required String role, required String acteur, String? motif}) {
    final r = valDeposerValidation(famille, '$id',
        role: role, acteur: acteur, maintenant: _horloge(), lire: lire, libelles: libelles, etiquette: etiquette, motif: motif);
    if (!r.ok) return r;
    try {
      m.collection(valCollectionDemandes).inserer(r.fiche!);
    } on EcritureRefusee catch (e) {
      return VerdictDepotValidation.refus(RefusValidation('ECRITURE_REFUSEE', e.motif, null));
    }
    final f = valFamille(famille)!;
    m.journaliser('Validation : décision déposée à la mère (signée)', f.module, f.libelle, '$id', null, {'role': role, 'demandePar': acteur, 'demandeLe': r.fiche!['demandeLe'], if (motif != null && motif.trim().isNotEmpty) 'motif': motif.trim()});
    return r;
  }

  /// MÈRE : applique les décisions déposées. Rend le nombre de demandes traitées (appliquées ou refusées en nommant).
  int appliquer() {
    var n = 0;
    final col = m.collection(valCollectionDemandes);
    for (final d in valDemandesEnAttente(col.toutes)) {
      // Lot CLO-3 point 6 : le compte signataire doit exister à la mère avec ce rôle à la date de la signature (refus nommé sinon).
      final a = valAppliquerDemande(d, maintenant: _horloge(), lire: lire, libelles: libelles, comptes: m.collection('utilisateurs').toutes);
      if (a == null) continue;
      var champs = a.champsDemande;
      if (a.verdict.ok) {
        final e = ecrireVerdict(m, a.verdict);
        if (e != null) champs = {'etat': valEtatRefusee, 'traiteLe': a.champsDemande['traiteLe'], 'resultatCode': e.code, 'resultatMotif': e.motif, 'resultatGeste': e.geste};
      }
      col.mettreAJour(d['id'], {...champs, 'traitePar': 'Mère'}, journaliser: false);
      n++;
    }
    return n;
  }

  /// Écrit ce qu'un verdict de validation commande (marquage, ou fiche VRF de création) puis UNE ligne de journal (RG-12). `null` : écrit ; sinon le refus nommé de l'écriture.
  static RefusValidation? ecrireVerdict(Magasin m, VerdictValidation r) {
    try {
      final col = m.collection(r.collection!);
      if (r.creation != null) {
        // La maquette pose la fiche de validation sans ligne « Création » : le geste est UNE ligne « Validation ».
        col.ajouterSansJournal(r.creation!);
      } else {
        final cible = r.collection == valCollectionValidations ? 'VRF-${r.id}' : '${r.id}';
        col.mettreAJour(cible, r.patch, journaliser: false);
      }
    } on EcritureRefusee catch (e) {
      return RefusValidation('ECRITURE_REFUSEE', e.motif, null);
    }
    final j = r.journal!;
    m.journaliser(j.action, j.module, j.entite, j.reference, j.avant, j.apres);
    return null;
  }
}
