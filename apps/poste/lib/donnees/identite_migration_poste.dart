import 'package:sigh_domaine/sigh_domaine.dart';

import 'magasin.dart';

/// LA MIGRATION AUTOMATIQUE DE L'IDENTITÉ AU DÉMARRAGE (lot IDENT-MIG, décision de la Direction du 16/11/2026). Un poste déjà installé n'a que la version 1 de `identiteLegale` (RCCM d'origine) : la
/// reprise du jeu livré n'ajoute pas une fiche à une collection que le poste possède déjà. Au démarrage, la version 2 (RCCM à jour, effet le 16/11/2026) est posée, la version 1 CLOSE au 15/11/2026
/// sans être réécrite. Les règles sont au domaine (`cfbMigrerIdentiteV2`) ; ici seulement l'écriture, la SIGNATURE (`creePar`, `modifiePar`) et le journal (RG-12).
///
/// [fileul] : un poste rattaché à une mère ne migre pas, l'identité est de la configuration de la mère (elle la pose et la propage par le canal habituel). Idempotent. Un conflit se NOMME (refus,
/// une ligne de journal par poste et par code, jamais répétée à chaque démarrage) et n'écrit rien.
({String etat, String? raison, CfbRefus? refus}) migrerIdentiteVersion2(Magasin m, {bool fileul = false}) {
  if (fileul) return (etat: 'sans_objet', raison: 'FILEUL_ATTEND_LA_MERE', refus: null);
  final versions = m.collection('identiteLegale');
  final r = cfbMigrerIdentiteV2(versions.toutes, maintenant: m.horloge());
  if (r.etat == 'sans_objet') return (etat: r.etat, raison: r.raison, refus: null);
  if (!r.migree) {
    const action = 'Identité : migration automatique refusée';
    final deja = m.collection('audit').toutes.any((a) => a['action'] == action && '${(a['apres'] as Map?)?['code']}' == r.refus!.code);
    if (!deja) m.journaliser(action, 'CFG', 'IdentiteLegale', 'IDL001', null, {'code': r.refus!.code, 'motif': r.refus!.motif}, succes: false);
    return (etat: r.etat, raison: null, refus: r.refus);
  }
  if (r.precedenteId != null) versions.mettreAJour(r.precedenteId, r.patchPrecedente!, journaliser: false);
  versions.inserer(r.fiche!, prefixe: 'IDL');
  m.journaliser('Identité : migration automatique vers la version 2 (RCCM à jour)', 'CFG', 'IdentiteLegale', '${r.fiche!['id']}',
      {'version': 1, 'fin': r.precedenteId == null ? null : cfbMigrationFinVersion1, 'rccm': IdentiteClinique.rccmVersion1},
      {'version': 2, 'debut': cfbMigrationDebutVersion2, 'rccm': r.fiche!['rccm'], 'signePar': cfbActeurMigrationIdentite});
  return (etat: r.etat, raison: null, refus: null);
}
