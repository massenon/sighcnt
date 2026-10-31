import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import '../m9/commun.dart' show ecoute;

export '../m6/points_commun.dart' show champUnique, commande;
export '../m8/commun.dart' show n, m;
export '../m9/commun.dart' show pieceM9, signDaf, monoTexte, tiret, ecoute, deuxCartes, ClassementSigh;

/// Briques communes aux neuf écrans de M11 (paie & primes). Les règles chiffrées vivent dans `packages/domaine/lib/src/paie/pai_moteur.dart` — ce
/// fichier ne porte que de la mise en page et le branchement du moteur sur le magasin.

/// L'exercice des écrans de calcul : « 2026 » est ÉCRIT EN DUR dans la maquette (`calculerTous(2026, mois)`, libellés « Octobre 2026 ») ; porté tel quel,
/// signalé (écart E686).
const int paiAnnee = 2026;

const signComptable = Signature('Le Comptable', nom: 'KASSA Augustin');

/// La Direction signe la paie : son nom figure sur les journaux (« Validation » / « Bon à payer »).
const String paiNomDirection = 'BASSONGUI Chabi Séko';

/// Ce que le moteur lit au magasin (la maquette interroge les collections à chaque calcul).
PaiEntrees entreesPaie(Magasin mag) => PaiEntrees(
      planning: mag.collection('planning').actives,
      evaluations: mag.collection('evaluations').actives,
      avances: mag.collection('avances').actives,
      participations: mag.collection('participations').actives,
      grille: mag.collection('grillePrimes').actives,
      historique: mag.collection('historiquePrimes').actives,
      heuresSup: mag.collection('heuresSup').actives,
      prets: mag.collection('pretsEtudes').actives,
    );

/// Les collections que le calcul de la paie lit : un écran se redessine quand l'une d'elles bouge.
const collectionsPaie = ['personnel', 'planning', 'evaluations', 'avances', 'participations', 'grillePrimes', 'historiquePrimes', 'heuresSup', 'pretsEtudes'];

Listenable ecoutePaie(ContexteEcran c, [List<String> enPlus = const []]) => ecoute(c, [...collectionsPaie, ...enPlus]);

List<PaiCalcul> calculerTousPaie(ContexteEcran c, int mois) => paiCalculerTous(c.magasin.collection('personnel').actives, paiAnnee, mois, entreesPaie(c.magasin), c.aujourdhui);

/// `String(nombre)` de JavaScript : 10 → « 10 », 3.6 → « 3.6 » (jamais « 10.0 »).
String paiNum(num v) => v == v.truncate() ? '${v.truncate()}' : '$v';

/// « octobre 2026 » : les cartouches de période de la maquette n'ont PAS de majuscule (`C.MOIS[m]` brut).
String periodeBrute(int mois) => '${paiMois[mois]} $paiAnnee';

/// « Octobre 2026 » : les options des sélecteurs de période (`C.MOIS` capitalisé + année).
List<OptionChamp> optionsMoisCap(int annee) => [
      for (var i = 0; i < 12; i++) OptionChamp('$i', paiPeriodeLibelle(annee, i))
    ];

/// Les options de l'écran ORTB : `C.MOIS[m] + ' ' + annee` — SANS majuscule (comme la maquette).
List<OptionChamp> optionsMoisBrut(int annee) => [
      for (var i = 0; i < 12; i++) OptionChamp('$i', '${paiMois[i]} $annee')
    ];

/// Un sélecteur de mois à UN champ (la barre de l'écran), initialisé au mois de l'horloge du poste.
ControleurFormulaire selecteurMois(ContexteEcran c, String libelle, List<OptionChamp> options) => champUnique(
    ChampDef(nom: 'mois', libelle: libelle, type: TypeChamp.select, col: ColChamp.plein, options: options), '${c.aujourdhui.month - 1}');

int moisChoisi(ControleurFormulaire ctl) => int.tryParse('${ctl['mois']}') ?? 0;

/// La barre de commandes d'un écran de période : `.card > .card-body.flex.flex-wrap.items-end.gap-3` (le sélecteur, puis les boutons).
Widget barrePeriode(ControleurFormulaire selecteur, List<Widget> boutons) => CarteSigh(
    child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
      commande(selecteur, largeur: 224),
      ...boutons,
    ]));

/// Une cellule de montant (`C.money(v, false)`).
Widget cellMontant(num v, {bool fort = false, Color? couleur}) => Text(money(v, avecDevise: false),
    style: TextStyle(
        color: couleur ?? (fort ? JetonsShell.slate800 : JetonsShell.slate700),
        fontSize: 14,
        height: 20 / 14,
        fontWeight: fort ? FontWeight.w600 : FontWeight.w400,
        fontFeatures: const [FontFeature.tabularFigures()]));

Widget cellTexte(String t, {Color couleur = JetonsShell.slate700, FontWeight? poids, double taille = 14}) =>
    Text(t, style: TextStyle(color: couleur, fontSize: taille, height: taille == 14 ? 20 / 14 : 16 / 12, fontWeight: poids));

Widget cellSecondaire(String t) => Text(t, style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12));

/// Deux lignes (nom, puis détail) : la cellule « Agent » des écrans de paie.
Widget cellAgent(String nom, String detail) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(nom, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)),
      Text(detail, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
    ]);

/// La ligne de tableau d'un calcul : les clés des colonnes, et le calcul lui-même sous `_c`.
Map<String, Object?> ligneCalcul(PaiCalcul c) => {
      'id': c.employe['id'],
      'matricule': c.matricule,
      'agent': c.nomComplet,
      'salaireBase': c.salaireBase,
      'gardes': c.gardes,
      'permanences': c.permanences,
      'totalPrimes': c.totalPrimes,
      'brut': c.brut,
      'sanction': c.sanction,
      'cnssOuvriere': c.cnssOuvriere,
      'cnssPatronale': c.cnssPatronale,
      'vps': c.vps,
      'its': c.its,
      'ortbRadio': c.ortbRadio,
      'ortbTele': c.ortbTele,
      'ortb': c.ortb,
      'avances': c.avances,
      'participations': c.participations,
      'net': c.net,
      '_c': c,
    };

PaiCalcul calculDe(Map<String, Object?> ligne) => ligne['_c'] as PaiCalcul;

const iconePaie = LucideIcons.calculator;
