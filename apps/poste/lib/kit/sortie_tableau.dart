import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../core/service_parametres.dart';
import '../impression/apercu.dart';
import '../impression/piece.dart';
import '../import/classeur_xlsx.dart';
import '../import/selecteurs_import.dart';
import '../shell/contexte_ecran.dart';
import 'bouton.dart';
import 'modale.dart';
import 'tableau.dart';
import 'toast.dart';

/// LA SORTIE DES TABLEAUX AU POSTE (lot EXP, 16/11/2026) : port du moteur de la maquette (`ui.js`, « SORTIE DES TABLEAUX »), règles au domaine
/// (`packages/domaine/lib/src/tableaux/sortie_tableau.dart`, rejouées sur les vecteurs tirés de l'écran réel de la maquette).
///
/// Ce que la sortie LIT de l'écran (`ContexteEcran`) : le droit du rôle (geste réservé `exporter_donnees` de la fiche RBAC), son libellé, la limite de lignes
/// (paramètre de clinique `securite.limiteLignesExport`, défaut semé) et le magasin, qui JOURNALISE (RG-12) avant toute écriture : sans journal, pas de fichier.
class ContexteSortieTableau {
  const ContexteSortieTableau({
    required this.droit,
    required this.libelleRole,
    required this.limite,
    required this.journaliser,
    this.ecran,
    this.module = 'TAB',
    this.utilisateur = '',
    this.jour,
  });

  /// `true` / `false` : le droit lu de la fiche RBAC ; `null` : droits illisibles (aucune donnée de navigation) : la commande reste visible, le moteur refuse.
  final bool? droit;
  final String libelleRole;
  final int limite;

  /// Écrit l'entrée du journal ; `null` : aucun magasin, la sortie est refusée (un fichier sans trace n'existe pas).
  final void Function(Map<String, Object?> entree)? journaliser;
  final String? ecran;
  final String module;
  final String utilisateur;
  final DateTime? jour;
}

/// Les points d'injection (comme [SelecteursImport] et [ImpressionPoste]) : aucun test ne dépend d'une boîte de dialogue native.
class SortieTableauxPoste {
  SortieTableauxPoste._();

  /// Enregistre le fichier écrit (boîte « Enregistrer sous » de `file_selector`) ; rend le chemin, ou `null` si l'agent annule.
  static EnregistrerFichierImport enregistrer = SelecteursImport.enregistrerNatif;

  /// Un contexte posé par un test du kit (sans coque) ; `null` en exploitation.
  static ContexteSortieTableau? contexteDeTest;

  static void reinitialiser() {
    enregistrer = SelecteursImport.enregistrerNatif;
    contexteDeTest = null;
  }
}

/// Le seul DROIT de sortie (sans lire la limite) : `true`, `false`, ou `null` (droits illisibles). Lu à chaque construction d'un tableau.
bool? droitSortie(BuildContext context) {
  if (SortieTableauxPoste.contexteDeTest != null) return SortieTableauxPoste.contexteDeTest!.droit;
  final c = ContexteEcran.maybeOf(context);
  return c?.donnees?.matrice.droitGeste(c.role, tabGesteSortie);
}

/// Le contexte de sortie d'un écran : lu de la coque (`ContexteEcran`), ou celui d'un test.
ContexteSortieTableau contexteSortie(BuildContext context) {
  if (SortieTableauxPoste.contexteDeTest != null) return SortieTableauxPoste.contexteDeTest!;
  final c = ContexteEcran.maybeOf(context);
  if (c == null) return const ContexteSortieTableau(droit: null, libelleRole: 'inconnu', limite: tabLimiteDefaut, journaliser: null);
  final jour = c.aujourdhui;
  final limite = tabLimiteLue(serviceParametres(c.magasin, auteur: () => c.magasin.utilisateur, horloge: () => jour).valeur(tabCleLimiteLignes, iso(jour)));
  final module = c.donnees?.manifeste.ecran(c.ecranId)?.module ?? 'TAB';
  return ContexteSortieTableau(
    droit: c.donnees?.matrice.droitGeste(c.role, tabGesteSortie),
    libelleRole: c.donnees?.matrice.libelle(c.role) ?? c.role,
    limite: limite,
    ecran: c.ecranId,
    module: module,
    utilisateur: c.utilisateur,
    jour: jour,
    journaliser: (e) => c.magasin.journaliser('${e['action']}', '${e['module']}', 'Tableau', '${e['reference']}', null, {
      for (final k in const ['format', 'perimetre', 'lignes', 'references', 'referencesTotal', 'ecran', 'cible', 'role'])
        if (e[k] != null) k: e[k],
    }),
  );
}

/// Les colonnes de sortie d'un tableau du kit : la cellule sort typée si le texte montré (`texte`) est la valeur (`valeur` ou `ligne[cle]`), sinon sous le texte
/// montré. Une colonne à widget SANS `texte` sort sous sa valeur (le contrat du kit : `texte` est ce que l'écran exporte quand la cellule est un widget).
List<ColonneSortie<Ligne>> colonnesSortie(List<ColonneTableau> colonnes) => [
      for (final c in colonnes)
        ColonneSortie<Ligne>(c.libelle, (l) => tabCelluleSortie(brute: c.lire(l), montre: c.texte?.call(l), aucunTexte: c.texte == null),
            droite: c.droite, somme: c.somme),
    ];

/// Le résultat d'une sortie : un refus nommé, ou le nombre de lignes et le fichier écrit (`null` : impression, ou agent qui a annulé l'enregistrement).
class ResultatSortie {
  const ResultatSortie.refus(this.refus)
      : lignes = 0,
        fichier = null,
        format = '';
  const ResultatSortie.ok(this.format, this.lignes, this.fichier) : refus = null;
  final RefusSortieTableau? refus;
  final String format;
  final int lignes;
  final String? fichier;
  bool get ok => refus == null;
}

/// LE MOTEUR DE SORTIE du poste : contrôle (droit, vide, colonnes, limite) AVANT tout travail, journal AVANT l'écriture, puis le fichier ou l'aperçu.
Future<ResultatSortie> sortirLignesPoste(
  BuildContext context, {
  required String format,
  required List<ColonneTableau> colonnes,
  required List<Ligne> lignes,
  required String perimetre,
  required String nom,
  String? titre,
  String Function(Ligne)? cle,
  void Function(String nom, String csv)? alExporterCsv,
  ContexteSortieTableau? sortie,
}) async {
  final ctx = sortie ?? contexteSortie(context);
  if (ctx.droit == null && tabLibellesFormat.containsKey(format)) {
    return const ResultatSortie.refus(RefusSortieTableau('DROITS_ILLISIBLES', 'les droits de l’écran ne sont pas lisibles (aucune donnée de navigation)', 'Rouvrir l’écran depuis le ruban.'));
  }
  final refus = tabControleSortie(format: format, droit: ctx.droit == true, libelleRole: ctx.libelleRole, lignes: lignes.length, colonnes: colonnes.length, limite: ctx.limite);
  if (refus != null) return ResultatSortie.refus(refus);
  if (ctx.journaliser == null) {
    return const ResultatSortie.refus(RefusSortieTableau('JOURNAL_INDISPONIBLE', 'aucun journal n’est ouvert : une sortie de données ne s’écrit jamais sans trace (RG-12)', 'Rouvrir l’écran depuis le ruban.'));
  }
  final cs = colonnesSortie(colonnes);
  final matrice = tabMatriceSortie(cs, lignes);
  final jour = ctx.jour ?? DateTime.now();
  ctx.journaliser!(tabEntreeJournal(
      format: format,
      perimetre: perimetre,
      references: [for (final l in lignes) cle != null ? cle(l) : l['id']],
      utilisateur: ctx.utilisateur,
      ecran: ctx.ecran,
      nom: nom,
      module: ctx.module));
  if (format == 'impression') {
    if (!context.mounted) return ResultatSortie.ok(format, lignes.length, null);
    final totaux = tabTotaux(cs, matrice);
    String texte(Object? v, bool droite) => v is num && droite ? nombre(v, v == v.truncate() ? 0 : 2) : tabTexteCellule(v);
    await afficherApercu(
        context,
        PieceA4(
          titre: titre ?? nom,
          reference: '${ctx.ecran ?? nom}-${iso(jour)}',
          utilisateur: ctx.utilisateur,
          edite: jour,
          sousTitre: '${lignes.length} ligne(s) ${perimetre == tabPerimetreSelection ? 'cochée(s)' : perimetre == tabPerimetreFiltre ? 'filtrée(s)' : 'du tableau entier'}',
          tableaux: [
            TableauEtat(
              colonnes: [for (var i = 0; i < cs.length; i++) ColonneEtat(libelle: cs[i].libelle, droite: cs[i].droite, valeur: (r) => texte(r['c$i'], cs[i].droite))],
              lignes: [
                for (final l in matrice.skip(1)) {for (var i = 0; i < l.length; i++) 'c$i': l[i]}
              ],
              mentions: totaux == null
                  ? const {}
                  : {
                      for (var i = 0; i < cs.length; i++)
                        if (totaux[i] != null) cs[i].libelle: texte(totaux[i], true),
                    },
            ),
          ],
        ));
    return ResultatSortie.ok(format, lignes.length, null);
  }
  if (format == 'csv') {
    final nomFichier = tabNomFichier(nom, 'csv', jour);
    final csv = tabCsv(matrice);
    if (alExporterCsv != null) {
      alExporterCsv(nomFichier, csv);
      return ResultatSortie.ok(format, lignes.length, nomFichier);
    }
    final chemin = await SortieTableauxPoste.enregistrer(nomFichier, Uint8List.fromList(_utf8(csv)));
    return ResultatSortie.ok(format, lignes.length, chemin);
  }
  final nomFichier = tabNomFichier(nom, 'xlsx', jour);
  final octets = ecrireClasseur([FeuilleXlsx(tabNomFeuille(titre ?? nom, jour), matrice, largeurs: tabLargeurs(matrice))]);
  final chemin = await SortieTableauxPoste.enregistrer(nomFichier, octets);
  return ResultatSortie.ok(format, lignes.length, chemin);
}

List<int> _utf8(String s) => utf8.encode(s);

void direSortie(BuildContext context, ResultatSortie r) {
  if (!context.mounted) return;
  if (!r.ok) {
    ToastsSigh.afficher(context, 'Sortie refusée (${r.refus!.code}) : ${r.refus!.motif}.', type: TypeToast.erreur, detail: r.refus!.geste);
    return;
  }
  if (r.format == 'impression') return;
  ToastsSigh.afficher(context, 'Export ${r.format == 'xlsx' ? 'Excel (.xlsx)' : 'CSV'} généré (${r.lignes} ligne${r.lignes > 1 ? 's' : ''}).',
      type: TypeToast.succes, detail: r.fichier);
}

/// La fenêtre « Exporter les données » : le PÉRIMÈTRE (lignes cochées, lignes filtrées, tout le tableau) puis le FORMAT (.xlsx, CSV, impression).
Future<void> afficherFenetreSortie(
  BuildContext context, {
  required List<Ligne> Function() cochees,
  required List<Ligne> Function() filtrees,
  required List<Ligne> Function() toutes,
  required bool filtreActif,
  required List<ColonneTableau> Function() colonnes,
  required String nom,
  String? titre,
  String Function(Ligne)? cle,
  String? perimetre,
  void Function(String nom, String csv)? alExporterCsv,
}) {
  final ctx = contexteSortie(context);
  final nC = cochees().length, nF = filtrees().length, nT = toutes().length;
  String pl(int n, String s) => '$n $s${n > 1 ? 's' : ''}';
  final choix = <(String, String)>[
    if (nC > 0) (tabPerimetreSelection, 'Les ${pl(nC, 'ligne')} cochée${nC > 1 ? 's' : ''}'),
    if (filtreActif) (tabPerimetreFiltre, 'Les ${pl(nF, 'ligne')} filtrée${nF > 1 ? 's' : ''} (recherche et filtres actifs, toutes pages)'),
    (tabPerimetreTout, 'Tout exporter : les ${pl(nT, 'ligne')} du tableau, toutes pages${filtreActif ? ', sans le filtre' : ''}'),
  ];
  var courant = perimetre != null && choix.any((c) => c.$1 == perimetre) ? perimetre : choix.first.$1;
  List<Ligne> lignesDe(String p) => p == tabPerimetreSelection ? cochees() : p == tabPerimetreFiltre ? filtrees() : toutes();
  Future<void> sortir(String format, VoidCallback fermer) async {
    final r = await sortirLignesPoste(context,
        format: format, colonnes: colonnes(), lignes: lignesDe(courant), perimetre: courant, nom: nom, titre: titre, cle: cle, alExporterCsv: alExporterCsv, sortie: ctx);
    if (r.ok) fermer();
    if (context.mounted) direSortie(context, r);
  }

  const style = TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 20 / 14);
  return afficherModale<void>(context,
      titre: 'Exporter les données',
      corps: StatefulBuilder(
          builder: (_, maj) => Column(key: const Key('sortie:fenetre'), crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                const Text('Choisir les lignes, puis le format. Les colonnes masquées ne sortent pas ; la sortie ne contient que ce que l’écran montre à ce profil.', style: style),
                const SizedBox(height: 12),
                for (final c in choix)
                  InkWell(
                    key: Key('sortie:perimetre-${c.$1}'),
                    onTap: () => maj(() => courant = c.$1),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Icon(courant == c.$1 ? LucideIcons.circleDot : LucideIcons.circle, size: 16, color: courant == c.$1 ? JetonsShell.navy900 : JetonsShell.slate400),
                          const SizedBox(width: 8),
                          Flexible(child: Text(c.$2, style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
                        ])),
                  ),
                const SizedBox(height: 8),
                Text('Limite par export : ${ctx.limite} lignes (réglage de la clinique, valeur d’attente à valider). Au-delà, refus nommé, jamais de fichier tronqué.',
                    key: const Key('sortie:limite'), style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
              ])),
      pied: (fermer) => [
            BoutonSigh(
                key: const Key('sortie:format-xlsx'),
                libelle: 'Excel (.xlsx)',
                icone: LucideIcons.fileSpreadsheet,
                variante: VarianteBouton.secondaire,
                onPressed: () => sortir('xlsx', fermer)),
            BoutonSigh(key: const Key('sortie:format-csv'), libelle: 'CSV', icone: LucideIcons.fileText, variante: VarianteBouton.secondaire, onPressed: () => sortir('csv', fermer)),
            BoutonSigh(key: const Key('sortie:format-impression'), libelle: 'PDF / Impression', icone: LucideIcons.printer, onPressed: () => sortir('impression', fermer)),
          ]);
}
