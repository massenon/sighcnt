import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// Briques communes des écrans de la qualité (M13) : enquêtes et questionnaires, satisfaction des patients, centre des validations, page publique.
/// Les règles vivent dans `packages/domaine/lib/src/qualite/qual_*.dart`, rejouées sur les vecteurs de la maquette.

CollectionMagasin colEnquetes(Magasin m) => m.collection('enquetes');
CollectionMagasin colReponses(Magasin m) => m.collection('reponsesEnquetes');
CollectionMagasin colJetons(Magasin m) => m.collection('jetonsEnquete');

/// Les icônes de la maquette (Lucide) par leur nom.
IconData iconeQual(String nom) => switch (nom) {
      'shield-check' => LucideIcons.shieldCheck,
      'pencil-line' => LucideIcons.pencilLine,
      'clipboard-list' => LucideIcons.clipboardList,
      'shopping-cart' => LucideIcons.shoppingCart,
      'file-badge' => LucideIcons.fileBadge,
      'scan-line' => LucideIcons.scanLine,
      'calendar-clock' => LucideIcons.calendarClock,
      _ => LucideIcons.circle,
    };

/// Les tons de la maquette (`success`, `warning`…) → ceux du kit.
TonSigh tonQual(String ton) => switch (ton) {
      'success' => TonSigh.succes,
      'warning' => TonSigh.attention,
      'danger' => TonSigh.danger,
      'info' => TonSigh.info,
      'navy' => TonSigh.navy,
      _ => TonSigh.neutre,
    };

/// Le jour courant en ISO (`C.iso(new Date())`), d'après l'horloge du poste.
String jourIso(ContexteEcran c) {
  final d = c.aujourdhui;
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// `K.source` : la provenance de la donnée, en pied d'écran.
Widget sourceQual(String texte) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(children: [
      const Icon(LucideIcons.fileCheck2, size: 14, color: JetonsShell.slate400),
      const SizedBox(width: 6),
      Flexible(
          child: Text('Source : $texte',
              style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12))),
    ]));

/// La date ISO d'une fiche en `jj/mm/aaaa`.
String dateJj(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// Une police fixe (`font-mono text-xs`).
Widget mono(String texte, {Color couleur = JetonsShell.slate500, double taille = 12}) =>
    Text(texte, style: TextStyle(fontFamily: 'LiberationMono', fontSize: taille, color: couleur));

/// `champsDepuisModele(enq, opts)` : LE générateur du formulaire d'une enquête — la saisie au guichet et la page publique en naissent TOUS DEUX. Un second
/// générateur aurait divergé à la première question ajoutée : on l'aurait ajoutée au modèle, elle serait apparue au guichet et pas sur le lien.
/// `pleineLargeur` ne touche que la mise en page.
List<ChampDef> champsDeModele(Object? questions, {bool pleineLargeur = false}) => [
      for (final f in qualChampsDepuisModele(questions, pleineLargeur: pleineLargeur))
        ChampDef(
            nom: f.nom,
            libelle: f.libelle,
            type: f.type == 'select' ? TypeChamp.select : TypeChamp.textarea,
            requis: f.requis,
            lignes: f.lignes,
            col: f.pleine ? ColChamp.plein : ColChamp.demi,
            options: [for (final o in f.options) OptionChamp(o)])
    ];
