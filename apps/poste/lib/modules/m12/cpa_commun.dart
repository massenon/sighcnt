import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m9/commun.dart' show n, m, dateDe, mono;

export '../m9/commun.dart'
    show n, m, dateDe, mono, monoTexte, tiret, ecoute, actives, deuxCartes, ClassementSigh, pieceM9, signDaf, montantFort;

/// Briques communes à la comptabilité de base de M12 (tableau de bord, plan comptable, journaux, écritures, grand livre, balance, dépenses).
/// Les règles chiffrées vivent dans `packages/domaine/lib/src/comptabilite/` ; ce fichier ne porte que de la mise en page et de la lecture du magasin.

/// `exo()` : l'exercice choisi. Le sélecteur d'exercice de la coque n'est pas porté (écart E717) : c'est l'année de l'horloge du poste, ce que la
/// maquette choisit tant que personne n'a rien mémorisé.
int exerciceChoisi(ContexteEcran c) => c.aujourdhui.year;

/// `ecritures()` : les écritures ACTIVES de l'exercice choisi.
List<Fiche> ecrituresExercice(ContexteEcran c) =>
    cpaEcrituresExercice(c.magasin.collection('ecritures').actives, exerciceChoisi(c));

/// `centreLabel(id)` : la collection ADMINISTRABLE fait foi (archivés compris), puis la semence ; sinon l'identifiant lui-même.
String libelleCentre(ContexteEcran c, Object? id) {
  for (final x in c.magasin.collection('centresCouts').toutes) {
    if (x['code'] == id) return '${x['libelle']}';
  }
  for (final x in cpaCentresCout) {
    if (x.$1 == id) return x.$2;
  }
  return '$id';
}

/// Les collections que lit la comptabilité : un écran se redessine quand l'une d'elles bouge.
Listenable ecouteCompta(ContexteEcran c, [List<String> en = const []]) => Listenable.merge([
      for (final k in ['ecritures', 'comptes', 'centresCouts', ...en]) c.magasin.collection(k)
    ]);

/// Signatures des états comptables (la maquette les écrit en dur).
const signComptable = Signature('Le Comptable', nom: 'KASSA Augustin');
const signDafCompta = Signature('La Directrice Administrative', nom: 'TAKI Alimatou');

// --- Colonnes réutilisables des écritures ------------------------------------------------------------------------------------------------------------

ColonneTableau colNumeroEcriture() => ColonneTableau(
    cle: 'numero',
    libelle: 'N° pièce',
    sansCoupure: true,
    texte: (e) => '${e['numero'] ?? ''}',
    rendu: (_, e) => Text('${e['numero'] ?? ''}',
        style: mono.copyWith(color: JetonsShell.navy800, fontWeight: FontWeight.w600)));

ColonneTableau colDateEcriture() => ColonneTableau(
    cle: 'date',
    libelle: 'Date',
    sansCoupure: true,
    valeur: (e) => e['date'],
    texte: (e) => dateDe(e['date']));

ColonneTableau colJournalEcriture() => ColonneTableau(
    cle: 'journal',
    libelle: 'Journal',
    sansCoupure: true,
    texte: (e) => '${e['journal'] ?? ''}',
    rendu: (_, e) => BadgeSigh('${e['journal'] ?? ''}', ton: TonSigh.navy));

ColonneTableau colCompteEcriture() => ColonneTableau(
    cle: 'compte',
    libelle: 'Compte',
    texte: (e) => '${e['compte']} ${e['compteLibelle'] ?? cpaCompteLibelle(e['compte'])}',
    rendu: (_, e) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${e['compte']}', style: mono.copyWith(color: JetonsShell.slate700, fontWeight: FontWeight.w600)),
          Text('${e['compteLibelle'] ?? cpaCompteLibelle(e['compte'])}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
        ]));

ColonneTableau _sens(String cle, String libelle) => ColonneTableau(
    cle: cle,
    libelle: libelle,
    droite: true,
    texte: (e) => n(e[cle]) != 0 ? m(e[cle]) : '',
    rendu: (_, e) => n(e[cle]) != 0
        ? Text(m(e[cle]),
            style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, fontFeatures: [FontFeature.tabularFigures()]))
        : const Text('—', style: TextStyle(color: JetonsShell.slate300, fontSize: 14, height: 20 / 14)));

ColonneTableau colDebitEcriture() => _sens('debit', 'Débit');
ColonneTableau colCreditEcriture() => _sens('credit', 'Crédit');

/// Un montant FORT (14 en 600), aligné à droite par la colonne.
Widget montantGras(num v, {Color couleur = JetonsShell.slate900}) => Text(m(v),
    style: TextStyle(color: couleur, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]));

/// Le bandeau « RG-10 respectée » ou « écart » d'une saisie ou d'une consultation.
Widget noteEquilibre(num debit, num credit, {bool saisie = false}) {
  final ok = debit == credit && (!saisie || debit > 0);
  return ok
      ? NoteSigh(
          saisie
              ? 'RG-10 respectée — l’écriture est équilibrée : débit = crédit = ${money(debit)}.'
              : 'Écriture équilibrée : débit = crédit = ${money(debit)} (RG-10).',
          ton: TonSigh.succes,
          icone: LucideIcons.scale)
      : NoteSigh(
          saisie
              ? 'RG-10 — l’écriture n’est pas équilibrée : écart de ${money((debit - credit).abs())}. La validation est impossible tant que débit ≠ crédit.'
              : 'Écart de ${money((debit - credit).abs())} entre débit et crédit (RG-10).',
          ton: TonSigh.danger,
          icone: LucideIcons.scale3d);
}
