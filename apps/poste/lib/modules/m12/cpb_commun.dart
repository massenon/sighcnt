import 'package:flutter/material.dart';

import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

export 'cpa_commun.dart';

/// Briques communes à la comptabilité B de M12 (analytique, budgets, immobilisations, banques, compte de résultat, flux de trésorerie, seuil).
/// Les règles chiffrées vivent dans `packages/domaine/lib/src/comptabilite/cpb_*.dart` ; ce fichier ne porte que de la mise en page et de la lecture
/// du magasin.

/// `G.TONES` de la maquette (`charts.js`).
const Color tonNavy = Color(0xFF12315E);
const Color tonCiel = Color(0xFF6C9ED4);
const Color tonVert = Color(0xFF22A170);
const Color tonOrange = Color(0xFFF98307);
const Color tonRouge = Color(0xFFEF4444);

/// `ecrituresToutes()` : TOUTES les écritures actives (les écrans à bornes choisissent eux-mêmes leur exercice).
List<Fiche> ecrituresToutes(ContexteEcran c) => c.magasin.collection('ecritures').actives;

/// `K.charts` : une grille de deux colonnes dès 1024 px ; une carte seule n'occupe que la moitié.
Widget grilleCartes(List<Widget> cartes) => LayoutBuilder(builder: (_, k) {
      final deux = k.maxWidth >= 1024;
      final l = deux ? (k.maxWidth - 16) / 2 : k.maxWidth;
      return Wrap(spacing: 16, runSpacing: 16, children: [for (final x in cartes) SizedBox(width: l, child: x)]);
    });

/// Un empilement vertical d'écart 16 (`space-y-4`).
Widget pile(List<Widget?> enfants, {double ecart = 16}) {
  final l = [for (final w in enfants) if (w != null) w];
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    for (final (i, w) in l.indexed) ...[if (i > 0) SizedBox(height: ecart), w]
  ]);
}

/// Le bandeau de lecture seule du socle : posé quand l'écran se modifie et que le profil n'a pas le droit d'écrire.
Widget bandeauLectureSeule(ContexteEcran c) => (!c.droit.editer && c.droit.voir)
    ? Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: NoteSigh(
            'Lecture seule : le profil « ${c.role} » consulte cet écran sans pouvoir y écrire. Les droits se règlent dans la matrice des rôles.',
            ton: TonSigh.attention))
    : const SizedBox.shrink();

/// La signature « Directrice de l'Administration et des Finances » des feuillets de la liasse (la maquette l'écrit en dur).
const signDafFinances = Signature('La Directrice de l’Administration et des Finances', nom: 'TAKI Alimatou');
