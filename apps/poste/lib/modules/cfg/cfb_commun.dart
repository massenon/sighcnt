import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';

/// Ce que partagent les neuf écrans de CFG (B). Les RÈGLES sont dans `packages/domaine/lib/src/configuration/cfb_regles.dart`, rejouées sur les vecteurs
/// de la maquette ; ces fichiers ne font que les mettre en page. Les composants communs (indicateurs, tableau adossé à une collection, saisie en modale,
/// archivage annulable) viennent de `cfa_commun.dart`.

/// `K.lien(ecran, libelle, { size: 'sm', icon: 'arrow-right' })` : un bouton secondaire qui ouvre un autre écran (refusé par la coque s'il est fermé).
Widget cfbLien(ContexteEcran c, String ecran, String libelle, {bool fleche = true}) => BoutonSigh(
    libelle: libelle,
    icone: fleche ? LucideIcons.arrowRight : null,
    variante: VarianteBouton.secondaire,
    taille: TailleBouton.sm,
    onPressed: () => c.aller(ecran));

/// Une note (`K.note`) : le texte de la maquette sans ses balises, le ton du domaine.
Widget cfbNote(String texte, {String ton = 'info', IconData? icone}) =>
    NoteSigh(sansBalises(texte), ton: cfaTonNote(ton == 'warning' ? 'attention' : (ton == 'success' ? 'succes' : ton)), icone: icone ?? LucideIcons.info);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les réglages d'exploitation (`S.reglage` / `S.setReglage` de la maquette) : une fiche par clé dans la collection `reglages`, comme le fait déjà
// l'écran des évaluations pour `baremeModifiable`. Absente = la valeur par défaut. Écrire passe par la collection : RG-12 journalise tout.
// ---------------------------------------------------------------------------------------------------------------------------------------------

Fiche? cfbFicheReglage(Magasin m, String id) => m.collection('reglages').actives.where((f) => f['id'] == id).firstOrNull;

Object? cfbReglage(Magasin m, String id, [Object? defaut]) {
  final f = cfbFicheReglage(m, id);
  return f != null && f.containsKey('valeur') ? f['valeur'] : defaut;
}

void cfbPoserReglage(Magasin m, String id, Object? valeur) {
  final col = m.collection('reglages');
  final f = cfbFicheReglage(m, id);
  if (f == null) {
    col.inserer({'id': id, 'statut': 'actif', 'valeur': valeur});
  } else {
    col.mettreAJour(id, {'valeur': valeur});
  }
}
