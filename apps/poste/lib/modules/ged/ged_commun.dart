import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// Briques communes aux trois écrans de la GED (bibliothèque de l'ÉTABLISSEMENT, workflow, archivage). Les règles vivent dans
/// `packages/domaine/lib/src/qualite/qual_ged.dart`, rejouées sur les vecteurs de la maquette.
///
/// La bibliothèque de l'établissement (`documents`) est DISTINCTE des documents du dossier patient (`documentsPatient`, M1).

/// Les icônes de la maquette (Lucide) par leur nom : les catégories de document, l'explorateur et le circuit.
IconData iconeGed(String nom) => switch (nom) {
      'file-text' => LucideIcons.fileText,
      'flask-conical' => LucideIcons.flaskConical,
      'stethoscope' => LucideIcons.stethoscope,
      'receipt' => LucideIcons.receipt,
      'truck' => LucideIcons.truck,
      'package-check' => LucideIcons.packageCheck,
      'file-signature' => LucideIcons.fileSignature,
      'banknote' => LucideIcons.banknote,
      'mail' => LucideIcons.mail,
      'lock' => LucideIcons.lock,
      'user' => LucideIcons.user,
      'id-card' => LucideIcons.idCard,
      'building-2' => LucideIcons.building2,
      'upload' => LucideIcons.upload,
      'tags' => LucideIcons.tags,
      'search-check' => LucideIcons.searchCheck,
      'badge-check' => LucideIcons.badgeCheck,
      'pen-tool' => LucideIcons.penTool,
      'folder-check' => LucideIcons.folderCheck,
      _ => LucideIcons.file,
    };

TonSigh tonDe(String ton) => switch (ton) {
      'success' => TonSigh.succes,
      'warning' => TonSigh.attention,
      'danger' => TonSigh.danger,
      'info' => TonSigh.info,
      'navy' => TonSigh.navy,
      _ => TonSigh.neutre,
    };

/// `C.dateFR` d'une date ISO du magasin.
String dateDe(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : dateFR(d);
}

Widget cellMono(String texte,
        {double taille = 12,
        FontWeight poids = FontWeight.w400,
        Color couleur = JetonsShell.slate700}) =>
    Text(texte,
        style: TextStyle(
            fontFamily: 'LiberationMono',
            fontSize: taille,
            fontWeight: poids,
            color: couleur));

/// `.truncate.text-sm` : une cellule de texte courant.
Widget cellule(String texte,
        {Color couleur = JetonsShell.slate700,
        double taille = 14,
        FontWeight poids = FontWeight.w400}) =>
    Text(texte,
        style: TextStyle(
            color: couleur, fontSize: taille, height: 20 / 14, fontWeight: poids));

/// Le badge d'état de validation (`Validé` / `En attente` / `Rejeté`) ; un état inconnu s'affiche « — ».
Widget badgeValidation(Object? etat) {
  final x = qualGedValidations['$etat'];
  return BadgeSigh(x?.$1 ?? '—', ton: tonDe(x?.$2 ?? 'neutral'));
}

/// Les documents ACTIFS de la bibliothèque de l'établissement.
CollectionMagasin colDocuments(Magasin m) => m.collection('documents');

/// La colonne « Catégorie » (badge navy) commune au workflow et à l'archivage : le TEXTE est le libellé de la catégorie (recherche, tri, export).
ColonneTableau colonneCategorie() => ColonneTableau(
    cle: 'categorie',
    libelle: 'Catégorie',
    texte: (d) => qualGedCategorieLabel(d['categorie']),
    rendu: (_, d) =>
        BadgeSigh(qualGedCategorieLabel(d['categorie']), ton: TonSigh.navy));

/// La référence `font-mono` d'un document.
ColonneTableau colonneReference({double taille = 12, FontWeight poids = FontWeight.w400}) =>
    ColonneTableau(
        cle: 'reference',
        libelle: 'Référence',
        sansCoupure: true,
        texte: (d) => '${d['reference']}',
        rendu: (_, d) => cellMono('${d['reference']}', taille: taille, poids: poids));

/// `K.source` : la provenance de la donnée, en pied d'écran.
Widget noteSource(String texte) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(children: [
      const Icon(LucideIcons.fileCheck2, size: 14, color: JetonsShell.slate400),
      const SizedBox(width: 6),
      Flexible(
          child: Text('Source : $texte',
              style: const TextStyle(
                  color: JetonsShell.slate400, fontSize: 12, height: 16 / 12))),
    ]));

/// Les deux signataires de toute pièce de la GED.
List<Signature> signaturesGed() => const [
      Signature('L’Agent administratif'),
      Signature('La Directrice Administrative', nom: 'TAKI Alimatou'),
    ];

/// Imprime une pièce de la GED dans l'aperçu commun.
Future<void> imprimerGed(BuildContext ctx, PieceA4 Function(ContexteEcran) fabrique) {
  final c = ContexteEcran.of(ctx);
  return afficherApercu(ctx, fabrique(c));
}

String referenceEtat(ContexteEcran c) =>
    PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero());

/// Une chaîne de pied de tableau : « N ko », « vN ».
String ko(Object? v) => '${v ?? ''} Ko';
