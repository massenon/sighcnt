import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import 'cpa_commun.dart';

/// `m12-depenses` — « Dépenses journalières » : saisie au fil de l'eau des charges de trésorerie directes, avec justificatif, écriture automatique et
/// historique. Une dépense produit UNE ÉCRITURE PLATE PAR LIGNE de même numéro de pièce (un débit par ligne de charge, un crédit de trésorerie du
/// total), contrôlée ÉQUILIBRÉE avant d'être posée (RG-10) et créée EN BROUILLON. Le justificatif n'est pas bloquant mais il est COMPTÉ. Une pièce porte
/// UNE OU PLUSIEURS lignes ; le montant est LEUR SOMME. QUATRE indicateurs (la « dépense moyenne » est retirée).
///
/// Écarts : E712 la référence se lit sur les dépenses existantes (la maquette lisait un compteur de page) ; E714 un exercice clos est refusé AVANT toute
/// écriture ; E719 le journal d'une dépense par banque est `BQE`, code absent du référentiel ; E726 le poste n'a pas de sélecteur de fichier : le
/// justificatif est désigné par le NOM du fichier joint ; E727 annuler une dépense qui vient d'être saisie archive aussi son écriture.
/// Les commandes d'écriture sont ABSENTES sans le droit de l'écran : « Nouvelle dépense » et « Modifier » → `editer`, « Archiver » → `annuler`.
class EcranDepenses extends StatefulWidget with EcranMaquette {
  const EcranDepenses({super.key});

  @override
  String get titre => 'Dépenses journalières';

  @override
  String get description =>
      'Saisie au fil de l’eau des charges de trésorerie directes, avec justificatif, écriture automatique et historique.';

  @override
  String get regle =>
      'Une dépense de trésorerie constate une charge et sort de l’argent : elle produit une écriture débit charge / crédit trésorerie, contrôlée équilibrée avant d’être posée (RG-10) et créée en brouillon — la validation comptable reste un geste humain. Le justificatif n’est pas bloquant mais il est compté : une charge sans reçu est une charge contestable.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Écritures comptables',
          icone: LucideIcons.pencilLine,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m12-ecritures')),
    ];
  }

  @override
  State<EcranDepenses> createState() => _EtatDepenses();
}

class _EtatDepenses extends State<EcranDepenses> {
  ControleurFormulaire? _du, _au;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_du != null) return;
    // La plage de dates survit au redessin : la remettre à zéro à chaque saisie ferait perdre le filtre au moment où l'on s'en sert le plus.
    _du = champUnique(const ChampDef(nom: 'du', libelle: 'Du', type: TypeChamp.date, col: ColChamp.plein), '');
    _au = champUnique(const ChampDef(nom: 'au', libelle: 'Au', type: TypeChamp.date, col: ColChamp.plein), '');
    _du!.addListener(_maj);
    _au!.addListener(_maj);
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _du?.removeListener(_maj);
    _au?.removeListener(_maj);
    _du?.dispose();
    _au?.dispose();
    super.dispose();
  }

  bool _dansPlage(Fiche r) {
    final d = '${r['date'] ?? ''}'.padRight(10).substring(0, 10).trim();
    final du = '${_du!['du'] ?? ''}', au = '${_au!['au'] ?? ''}';
    if (du.isNotEmpty && d.compareTo(du) < 0) return false;
    if (au.isNotEmpty && d.compareTo(au) > 0) return false;
    return true;
  }

  Fiche? _tresorerie(ContexteEcran c, Object? id) {
    for (final b in c.magasin.collection('banques').actives) {
      if (b['id'] == id) return b;
    }
    return null;
  }

  // -------------------------------------------------------------------------------------------------------------------------------------------
  // L'ÉCRITURE : posée, refaite, archivée avec la dépense — jamais à moitié
  // -------------------------------------------------------------------------------------------------------------------------------------------

  /// `poserEcriture` : les lignes plates en BROUILLON ; rend leurs identifiants (on les retient TOUS : archiver une dépense archive l'écriture entière).
  List<Object?> _poser(BuildContext ctx, ContexteEcran c, Fiche dep) {
    final col = c.magasin.collection('ecritures');
    try {
      final lignes = cpaEcrituresDepense(dep, _tresorerie(c, dep['compteTresorerie']));
      final posees = [for (final l in lignes) col.inserer(l, prefixe: 'ECR').fiche];
      c.magasin.journaliser('Écriture de dépense', 'M12', 'Ecriture', '${dep['reference']}', null,
          {'debit': lignes.fold<num>(0, (a, l) => a + n(l['debit'])), 'credit': lignes.fold<num>(0, (a, l) => a + n(l['credit'])), 'lignes': posees.length});
      return [for (final p in posees) p['id']];
    } on CpaRefus catch (e) {
      ToastsSigh.afficher(ctx, e.message, type: TypeToast.erreur, detail: e.detail);
      c.magasin.journaliser('Écriture de dépense refusée — déséquilibre', 'M12', 'Ecriture', '${dep['reference']}', null, {'motif': e.detail}, succes: false);
      return const [];
    }
  }

  List<Object?> _idsEcritures(Fiche r) {
    final ids = r['ecritureIds'];
    return [
      for (final x in (ids is List ? ids : [r['ecritureId']]))
        if (x != null && x != '' && x != false) x
    ];
  }

  // -------------------------------------------------------------------------------------------------------------------------------------------
  // LA SAISIE : une pièce, une ou plusieurs lignes
  // -------------------------------------------------------------------------------------------------------------------------------------------

  List<ChampDef> _champs(ContexteEcran c) => [
        const ChampDef(nom: 'date', libelle: 'Date de la transaction', type: TypeChamp.date, requis: true),
        ChampDef(
            nom: 'compteTresorerie',
            libelle: 'Compte de trésorerie',
            type: TypeChamp.select,
            requis: true,
            options: [for (final b in c.magasin.collection('banques').actives) OptionChamp('${b['id']}', '${b['intitule']}')],
            aide: 'D’où l’argent est sorti.'),
        ChampDef(
            nom: 'categorie',
            libelle: 'Catégorie de dépenses',
            type: TypeChamp.select,
            requis: true,
            options: [for (final k in cpaCategoriesDepense) OptionChamp(k.$1, k.$2)],
            aide:
                'La lecture de gestion, distincte du compte : c’est elle que lit la Direction, qui ne raisonne pas en numéros de compte.'),
        const ChampDef(
            nom: 'libelle',
            libelle: 'Objet de la pièce (facultatif)',
            col: ColChamp.plein,
            indicatif: 'Repris de la première ligne si vide',
            aide: 'La pièce porte SES LIGNES ci-dessous : le montant total est leur somme, jamais saisi à part.'),
      ];

  /// Le formulaire d'UNE ligne (libellé, compte de charge SYSCOHADA, montant ≥ 1), à l'ajout comme à la modification.
  void _formLigne(BuildContext ctx, Fiche? valeurs, void Function(Fiche) surValide) {
    final f = ControleurFormulaire([
      const ChampDef(nom: 'libelle', libelle: 'Libellé de la ligne', requis: true, col: ColChamp.plein),
      ChampDef(
          nom: 'compteCharge',
          libelle: 'Compte de charge (SYSCOHADA)',
          type: TypeChamp.select,
          requis: true,
          options: [for (final k in cpaComptesCharge()) OptionChamp(k.$1, '${k.$1} — ${k.$2}')]),
      ChampDef(
          nom: 'montant',
          libelle: 'Montant (FCFA)',
          type: TypeChamp.nombre,
          requis: true,
          valider: (v, _) => (num.tryParse('$v'.replaceAll(',', '.')) ?? 0) < 1 ? 'La valeur doit être supérieure ou égale à 1.' : null),
    ], valeurs == null ? {} : {'libelle': valeurs['libelle'], 'compteCharge': valeurs['compteCharge'], 'montant': '${valeurs['montant']}'});
    afficherModale<void>(ctx,
        titre: valeurs == null ? 'Ajouter une ligne' : 'Modifier la ligne',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: f),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: valeurs == null ? 'Ajouter' : 'Enregistrer',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) return;
                    surValide({
                      'libelle': '${v['libelle']}',
                      'compteCharge': '${v['compteCharge']}',
                      'montant': num.parse('${v['montant']}'.replaceAll(',', '.')),
                    });
                    fermer();
                  }),
            ]);
  }

  /// `editeurLignes` : la table des lignes DANS la modale — ajout, édition, suppression ; le total est la somme.
  Widget _editeurLignes(BuildContext ctx, List<Fiche> lignes, void Function(VoidCallback) maj) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const LibelleChamp('Lignes de la dépense *'),
        if (lignes.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Aucune ligne — la pièce en exige au moins une.',
                  style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)))
        else ...[
          for (final (i, l) in lignes.indexed)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(flex: 4, child: Text('${l['libelle']}', style: const TextStyle(fontSize: 14, height: 20 / 14))),
                  Expanded(
                      flex: 1,
                      child: Text('${l['compteCharge']}', style: mono.copyWith(color: JetonsShell.slate500))),
                  SizedBox(
                      width: 100,
                      child: Text(m(l['montant']), textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, height: 20 / 14))),
                  BoutonIcone(
                      icone: LucideIcons.pencil,
                      libelle: 'Modifier la ligne',
                      onPressed: () => _formLigne(ctx, l, (v) => maj(() => lignes[i] = v))),
                  BoutonIcone(
                      icone: LucideIcons.trash2,
                      libelle: 'Retirer la ligne',
                      onPressed: () => maj(() => lignes.removeAt(i))),
                ])),
          const Divider(height: 8, color: JetonsShell.slate300),
          Row(children: [
            Expanded(
                flex: 5,
                child: Text('TOTAL — ${lignes.length} ligne(s)',
                    style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
            SizedBox(
                width: 100,
                child: Text(m(lignes.fold<num>(0, (a, l) => a + n(l['montant']))),
                    textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
            const SizedBox(width: 80),
          ]),
        ],
        const SizedBox(height: 8),
        BoutonSigh(
            libelle: 'Ajouter une ligne',
            icone: LucideIcons.plus,
            taille: TailleBouton.sm,
            variante: VarianteBouton.secondaire,
            onPressed: () => _formLigne(ctx, null, (v) => maj(() => lignes.add(v)))),
      ]),
    );
  }

  ControleurFormulaire _champJustificatif(Fiche? r) => ControleurFormulaire([
        ChampDef(
            nom: 'justificatif',
            libelle: 'Reçu / facture (nom du fichier joint)',
            col: ColChamp.plein,
            aide:
                'Facultatif, mais une dépense sans justificatif est signalée : c’est la première pièce qu’un contrôle réclame. Le poste ne lit pas le fichier : il en retient le nom (E726).')
      ], {
        'justificatif': (r?['justificatif'] as Map?)?['nom'] ?? ''
      });

  Fiche? _justificatif(String nom, Fiche? ancien) {
    final t = nom.trim();
    if (t.isEmpty) return ancien;
    return {'nom': t, 'type': t.toLowerCase().endsWith('.pdf') ? 'application/pdf' : 'image/jpeg'};
  }

  /// La modale de saisie : [r] = `null` pour une nouvelle dépense, la fiche pour la modifier.
  void _saisie(BuildContext ctx, ContexteEcran c, {Fiche? r}) {
    final edition = r != null;
    final f = ControleurFormulaire(_champs(c),
        edition ? {...r, 'date': r['date']} : {'date': iso(c.aujourdhui), 'categorie': 'fonctionnement'});
    final lignes = edition ? [for (final l in cpaLignesDepense(r)) {...l}] : <Fiche>[];
    final fichier = _champJustificatif(r);
    final depenses = c.magasin.collection('depenses');
    afficherModale<void>(ctx,
        titre: edition ? 'Modifier la dépense — ${r['reference']}' : 'Nouvelle dépense',
        sousTitre: edition
            ? 'L’écriture liée sera refaite. Elle repart en brouillon.'
            : 'Une pièce, une ou plusieurs lignes de charge — le total est leur somme.',
        taille: TailleModale.lg,
        corps: StatefulBuilder(
            builder: (mctx, maj) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FormulaireSigh(controleur: f),
                  const SizedBox(height: 12),
                  _editeurLignes(ctx, lignes, maj),
                  const SizedBox(height: 12),
                  if (edition && r['justificatif'] != null) ...[
                    NoteSigh(
                        'Reçu déjà joint : ${(r['justificatif'] as Map)['nom']}. Saisir un autre nom le remplacera.',
                        icone: LucideIcons.paperclip),
                    const SizedBox(height: 12),
                  ],
                  FormulaireSigh(controleur: fichier),
                ])),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final v = f.valider();
                    if (v == null) return;
                    final CpaTotauxDepense t;
                    try {
                      t = cpaTotauxDepense('${v['libelle'] ?? ''}', lignes);
                    } on CpaRefus catch (e) {
                      ToastsSigh.afficher(ctx, e.message, type: TypeToast.erreur);
                      return;
                    }
                    // Un exercice clos refuse AVANT toute écriture (E714) : rien n'est écrit, ni la dépense ni son écriture.
                    final clos = cpaGardeEcriture(v['date']);
                    if (clos != null) {
                      ToastsSigh.afficher(ctx, 'Écriture refusée.', type: TypeToast.erreur, detail: clos);
                      return;
                    }
                    if (!edition) {
                      final rec = depenses.inserer({
                        'reference': cpaReferenceDepense('${v['date']}', depenses.toutes),
                        'date': '${v['date']}',
                        'lignes': t.lignes,
                        'montant': t.montant,
                        'libelle': t.libelle,
                        'compteCharge': t.compteCharge,
                        'compteTresorerie': '${v['compteTresorerie']}',
                        'categorie': '${v['categorie']}',
                        'justificatif': _justificatif('${fichier['justificatif']}', null),
                        'saisiPar': c.utilisateur.isEmpty ? 'Utilisateur' : c.utilisateur,
                        'saisiLe': iso(c.aujourdhui),
                        'statut': 'actif',
                      }, prefixe: 'DEP').fiche;
                      final ids = _poser(ctx, c, rec);
                      if (ids.isNotEmpty) depenses.mettreAJour(rec['id'], {'ecritureId': ids.first, 'ecritureIds': ids});
                      fermer();
                      ToastsSigh.afficher(ctx, 'Dépense enregistrée.',
                          type: TypeToast.succes,
                          detail:
                              '${money(rec['montant'])} en ${t.lignes.length} ligne(s) — écriture ${ids.isNotEmpty ? 'en brouillon, à valider' : 'non posée'}${rec['justificatif'] != null ? '' : ' · sans justificatif'}',
                          annuler: () {
                            // E727 : annuler la saisie archive la dépense ET son écriture, jamais l'une sans l'autre.
                            depenses.archiver(rec['id']);
                            for (final id in ids) {
                              c.magasin.collection('ecritures').archiver(id);
                            }
                          },
                          messageAnnulation: 'Dépense annulée.');
                    } else {
                      depenses.mettreAJour(r['id'], {
                        'date': '${v['date']}',
                        'lignes': t.lignes,
                        'montant': t.montant,
                        'libelle': t.libelle,
                        'compteCharge': t.compteCharge,
                        'compteTresorerie': '${v['compteTresorerie']}',
                        'categorie': '${v['categorie']}',
                        'justificatif': _justificatif('${fichier['justificatif']}', r['justificatif'] as Fiche?),
                      });
                      // L'écriture suit la dépense, et on archive TOUTES les lignes de l'ancienne : en laisser une seule déséquilibrerait le journal.
                      for (final id in _idsEcritures(r)) {
                        c.magasin.collection('ecritures').archiver(id);
                      }
                      final ids = _poser(ctx, c, depenses.parId(r['id'])!);
                      if (ids.isNotEmpty) depenses.mettreAJour(r['id'], {'ecritureId': ids.first, 'ecritureIds': ids});
                      fermer();
                      ToastsSigh.afficher(ctx, 'Dépense modifiée.',
                          type: TypeToast.succes, detail: 'L’écriture a été refaite et repart en brouillon.');
                    }
                  }),
            ]);
  }

  Future<void> _archiver(BuildContext ctx, ContexteEcran c, Fiche r) async {
    final ok = await confirmerSigh(ctx,
        titre: 'Archiver la dépense ${r['reference']} ?',
        message:
            'La dépense et son écriture sont archivées, jamais supprimées (RG-14). Elles restent consultables depuis la corbeille.',
        libelleOk: 'Archiver',
        dangereux: true);
    if (!ok || !ctx.mounted) return;
    final ids = _idsEcritures(r);
    final undo = [
      c.magasin.collection('depenses').archiver(r['id']),
      for (final id in ids) c.magasin.collection('ecritures').archiver(id),
    ];
    ToastsSigh.afficher(ctx, 'Dépense archivée.', type: TypeToast.succes, annuler: () {
      for (final u in undo) {
        u();
      }
    }, messageAnnulation: 'Archivage annulé.');
  }

  // -------------------------------------------------------------------------------------------------------------------------------------------
  // CONSULTER ET IMPRIMER
  // -------------------------------------------------------------------------------------------------------------------------------------------

  void _consulter(BuildContext ctx, ContexteEcran c, Fiche r) {
    final tres = _tresorerie(c, r['compteTresorerie']);
    final lignes = cpaLignesDepense(r);
    afficherTiroir<void>(ctx,
        titre: '${r['libelle']}',
        sousTitre: '${r['reference']} — ${dateDe(r['date'])}',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Référence', '${r['reference']}'),
            ('Date de la transaction', dateDe(r['date'])),
            ('Montant décaissé', '${money(r['montant'])} — ${lignes.length} ligne(s)'),
            ('Compte de trésorerie', tres != null ? '${tres['intitule']} (${tres['compteComptable']})' : '—'),
            ('Catégorie de gestion', cpaCategorieDepenseLibelle(r['categorie'])),
            ('Justificatif', r['justificatif'] != null ? '${(r['justificatif'] as Map)['nom']}' : 'AUCUN — charge contestable'),
            ('Saisie par', '${r['saisiPar'] ?? '—'} le ${dateDe(r['saisiLe'] ?? r['date'])}'),
            ('Écriture', r['ecritureId'] != null ? '${r['ecritureId']} — en brouillon jusqu’à validation' : 'non posée'),
          ]),
          const SizedBox(height: 16),
          CarteSigh(
              titre: 'Lignes de la pièce',
              sansRemplissage: true,
              child: MiniTableauSigh(colonnes: [
                ColonneMini('Libellé', (l) => '${l['libelle']}'),
                ColonneMini('Compte de charge', (l) => '${l['compteCharge']} — ${cpaCompteLibelle(l['compteCharge'])}'),
                ColonneMini('Montant', (l) => m(l['montant']), droite: true),
              ], lignes: lignes)),
          const SizedBox(height: 16),
          NoteSigh(
              'Un débit par ligne de charge, un crédit de trésorerie du total (${tres != null ? tres['compteComptable'] : '571000'}). Écriture équilibrée (RG-10), en brouillon : la validation comptable reste un geste humain.',
              icone: LucideIcons.scale),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Imprimer la pièce',
                  icone: LucideIcons.printer,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => _imprimerPiece(ctx, c, r)),
            ]);
  }

  void _imprimerPiece(BuildContext ctx, ContexteEcran c, Fiche r) {
    final tres = _tresorerie(c, r['compteTresorerie']);
    final lignes = cpaLignesDepense(r);
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Pièce de dépense',
            sousTitre: '${r['reference']} — ${dateDe(r['date'])}',
            cartouche: [
              ('Référence', '${r['reference']}'),
              ('Date', dateDe(r['date'])),
              ('Montant', '${money(r['montant'])} (${lignes.length} ligne(s))'),
              ('Trésorerie', tres != null ? '${tres['intitule']}' : '—'),
              ('Catégorie', cpaCategorieDepenseLibelle(r['categorie'])),
              ('Justificatif', r['justificatif'] != null ? '${(r['justificatif'] as Map)['nom']}' : 'AUCUN'),
              ('Saisie par', '${r['saisiPar'] ?? '—'}'),
            ],
            blocs: [
              const BlocTexte('Objet de la dépense', gras: true),
              BlocTexte('${r['libelle']}'),
              const BlocTexte('Écriture comptable', gras: true),
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Compte', valeur: (x) => x['compte']),
                ColonneEtat(libelle: 'Libellé', valeur: (x) => x['libelle']),
                ColonneEtat(libelle: 'Débit', droite: true, valeur: (x) => n(x['debit']) != 0 ? m(x['debit']) : '', somme: (x) => n(x['debit'])),
                ColonneEtat(libelle: 'Crédit', droite: true, valeur: (x) => n(x['credit']) != 0 ? m(x['credit']) : '', somme: (x) => n(x['credit'])),
              ], lignes: [
                for (final l in lignes) {'compte': l['compteCharge'], 'libelle': l['libelle'], 'debit': l['montant'], 'credit': 0},
                {
                  'compte': tres != null ? tres['compteComptable'] : '571000',
                  'libelle': 'Décaissement — ${tres != null ? tres['intitule'] : 'trésorerie'}',
                  'debit': 0,
                  'credit': r['montant'],
                }
              ])),
              if (r['justificatif'] == null)
                const BlocTexte('Aucun justificatif joint : cette charge est contestable en cas de contrôle.', italique: true),
            ],
            signatures: const [
              Signature('Le bénéficiaire'),
              Signature('Le Comptable'),
              Signature('La Directrice de l’Administration et des Finances', nom: 'TAKI Alimatou'),
            ]));
  }

  void _imprimerEtat(BuildContext ctx, ContexteEcran c, List<Fiche> rows) {
    final l = trierPar(rows, (r) => r['date']);
    final total = l.fold<num>(0, (a, r) => a + n(r['montant']));
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'État des dépenses de trésorerie',
            sousTitre: '${nombre(l.length)} dépense(s) — ${money(total)}',
            cartouche: [
              ('Nombre de pièces', nombre(l.length)),
              ('Total décaissé', money(total)),
              ('Sans justificatif', nombre(l.where((r) => r['justificatif'] == null).length)),
              ('Édité le', dateFR(c.aujourdhui)),
            ],
            // Un état tiré d'un écran filtré ne montre qu'une PARTIE des données : la plage en force est dite sur la pièce.
            filtres: [
              if ('${_du!['du'] ?? ''}'.isNotEmpty) ('Du', dateDe(_du!['du'])),
              if ('${_au!['au'] ?? ''}'.isNotEmpty) ('Au', dateDe(_au!['au'])),
            ],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Date', valeur: (r) => dateDe(r['date'])),
                ColonneEtat(libelle: 'N°', valeur: (r) => r['reference']),
                ColonneEtat(libelle: 'Libellé', valeur: (r) => r['libelle']),
                ColonneEtat(libelle: 'Compte', valeur: (r) => r['compteCharge']),
                ColonneEtat(libelle: 'Catégorie', valeur: (r) => cpaCategorieDepenseLibelle(r['categorie'])),
                ColonneEtat(libelle: 'Reçu', valeur: (r) => r['justificatif'] != null ? 'oui' : 'NON'),
                ColonneEtat(libelle: 'Montant', droite: true, valeur: (r) => m(r['montant']), somme: (r) => n(r['montant'])),
              ], lignes: l)
            ],
            signatures: const [
              Signature('Le Comptable'),
              Signature('La Directrice de l’Administration et des Finances', nom: 'TAKI Alimatou'),
            ]));
  }

  // -------------------------------------------------------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final droit = c.droit;
    return ListenableBuilder(
      listenable: Listenable.merge([ecouteCompta(c, const ['depenses', 'banques']), _du!, _au!]),
      builder: (context, _) {
        final tous = c.magasin.collection('depenses').actives;
        final rows = [for (final r in tous) if (_dansPlage(r)) r];
        final jour = iso(c.aujourdhui);
        final i = cpaIndicateursDepenses(rows, jour);
        final mois = cpaDepensesParMois(rows);
        final cats = cpaCumulCategories(rows);
        final comptes = (rows.map((r) => '${r['compteCharge']}').toSet().toList()..sort());
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CarteSigh(
              child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
            commande(_du!, largeur: 170),
            commande(_au!, largeur: 170),
            BoutonSigh(
                libelle: 'Aujourd’hui',
                icone: LucideIcons.calendar,
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                onPressed: () {
                  _du!.poser('du', jour);
                  _au!.poser('au', jour);
                }),
            BoutonSigh(
                libelle: 'Ce mois',
                icone: LucideIcons.calendarRange,
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                onPressed: () {
                  _du!.poser('du', '${jour.substring(0, 8)}01');
                  _au!.poser('au', jour);
                }),
            BoutonSigh(
                libelle: 'Tout l’historique',
                icone: LucideIcons.history,
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                onPressed: () {
                  _du!.poser('du', '');
                  _au!.poser('au', '');
                }),
          ])),
          const SizedBox(height: 16),
          // QUATRE indicateurs, pas cinq — arbitrage du 31/08/2026 : la « dépense moyenne » ne commande aucune action.
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Dépensé aujourd’hui', valeur: money(i.duJour), indice: '${nombre(i.nbJour)} pièce(s)', icone: LucideIcons.calendar),
            KpiSigh(libelle: 'Dépensé ce mois', valeur: money(i.duMois), indice: '${nombre(i.nbMois)} pièce(s)', icone: LucideIcons.calendarRange, ton: TonSigh.info),
            KpiSigh(libelle: 'Total enregistré', valeur: money(i.total), indice: '${nombre(i.nb)} dépense(s)', icone: LucideIcons.wallet, ton: TonSigh.attention),
            KpiSigh(
                libelle: 'Sans justificatif',
                valeur: nombre(i.nbSansRecu),
                indice: i.nbSansRecu > 0 ? '${money(i.sansRecu)} contestables' : 'toutes justifiées',
                icone: LucideIcons.fileX,
                ton: i.nbSansRecu > 0 ? TonSigh.danger : TonSigh.succes),
          ]),
          if (i.nbSansRecu > 0) ...[
            const SizedBox(height: 16),
            NoteSigh(
                '${i.nbSansRecu} dépense(s) sans justificatif, pour ${money(i.sansRecu)}. Le reçu n’est pas bloquant à la saisie — on n’empêche pas d’enregistrer une dépense réelle parce que le vendeur n’a pas de carnet — mais ces charges sont contestables en cas de contrôle. Le filtre « Justificatif » les isole.',
                ton: TonSigh.attention,
                icone: LucideIcons.fileX),
          ],
          const SizedBox(height: 16),
          TableauSigh(
            lignes: rows,
            nomExport: 'depenses-journalieres',
            taillePage: 15,
            triInitial: 'date',
            sensInitial: 'desc',
            alClicLigne: (r) => _consulter(context, c, r),
            filtres: [
              FiltreTableau(
                  nom: 'categorie',
                  libelle: 'Catégorie de dépenses',
                  options: [for (final k in cpaCategoriesDepense) OptionChamp(k.$1, k.$2)]),
              FiltreTableau(
                  nom: 'compteCharge',
                  libelle: 'Compte de charge',
                  options: [for (final k in comptes) OptionChamp(k, '$k — ${cpaCompteLibelle(k)}')]),
              FiltreTableau(
                  nom: 'compteTresorerie',
                  libelle: 'Trésorerie',
                  options: [for (final b in c.magasin.collection('banques').actives) OptionChamp('${b['id']}', '${b['intitule']}')]),
              FiltreTableau(
                  nom: 'justificatif',
                  libelle: 'Justificatif',
                  options: const [OptionChamp('oui', 'Avec reçu'), OptionChamp('non', 'Sans reçu')],
                  correspond: (r, v) => v == 'oui' ? r['justificatif'] != null : r['justificatif'] == null),
            ],
            actions: [
              if (droit.editer)
                BoutonSigh(libelle: 'Nouvelle dépense', icone: LucideIcons.plus, onPressed: () => _saisie(context, c)),
              BoutonSigh(
                  libelle: 'État des dépenses',
                  icone: LucideIcons.printer,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => _imprimerEtat(context, c, rows)),
            ],
            actionsLigne: (ctx, r) => [
              BoutonIcone(icone: LucideIcons.eye, libelle: 'Consulter', onPressed: () => _consulter(context, c, r)),
              if (droit.editer)
                BoutonIcone(icone: LucideIcons.pencilLine, libelle: 'Modifier', onPressed: () => _saisie(context, c, r: r)),
              if (droit.annuler)
                BoutonIcone(icone: LucideIcons.archive, libelle: 'Archiver', onPressed: () => _archiver(context, c, r)),
              BoutonIcone(icone: LucideIcons.printer, libelle: 'Imprimer la pièce', onPressed: () => _imprimerPiece(context, c, r)),
            ],
            colonnes: [
              ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, valeur: (r) => r['date'], texte: (r) => dateDe(r['date'])),
              ColonneTableau(
                  cle: 'reference',
                  libelle: 'N°',
                  sansCoupure: true,
                  rendu: (_, r) => Text('${r['reference']}', style: mono)),
              const ColonneTableau(cle: 'libelle', libelle: 'Libellé de la dépense'),
              ColonneTableau(
                  cle: 'categorie',
                  libelle: 'Catégorie',
                  texte: (r) => cpaCategorieDepenseLibelle(r['categorie']),
                  rendu: (_, r) => BadgeSigh(cpaCategorieDepenseLibelle(r['categorie']), ton: TonSigh.navy)),
              ColonneTableau(
                  cle: 'compteCharge',
                  libelle: 'Compte SYSCOHADA',
                  texte: (r) => '${r['compteCharge']} ${cpaCompteLibelle(r['compteCharge'])}',
                  rendu: (_, r) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text('${r['compteCharge']}', style: mono),
                        Text(cpaCompteLibelle(r['compteCharge']),
                            style: const TextStyle(color: JetonsShell.slate400, fontSize: 10, height: 14 / 10)),
                      ])),
              ColonneTableau(
                  cle: 'compteTresorerie',
                  libelle: 'Sortie de',
                  texte: (r) => '${_tresorerie(c, r['compteTresorerie'])?['intitule'] ?? '—'}',
                  rendu: (_, r) {
                    final b = _tresorerie(c, r['compteTresorerie']);
                    return b != null
                        ? BadgeSigh('${b['banque']}', ton: b['nature'] == 'caisse' ? TonSigh.attention : TonSigh.info)
                        : const Text('—', style: TextStyle(color: JetonsShell.slate300));
                  }),
              ColonneTableau(
                  cle: 'justificatif',
                  libelle: 'Reçu',
                  texte: (r) => r['justificatif'] != null ? 'oui' : 'non',
                  rendu: (_, r) => r['justificatif'] != null
                      ? const BadgeSigh('Joint', ton: TonSigh.succes)
                      : const BadgeSigh('Absent', ton: TonSigh.danger)),
              ColonneTableau(
                  cle: 'montant',
                  libelle: 'Montant',
                  droite: true,
                  texte: (r) => m(r['montant']),
                  rendu: (_, r) => Text(m(r['montant']),
                      style: const TextStyle(color: JetonsShell.navy800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]))),
            ],
          ),
          if (!droit.editer) ...[
            const SizedBox(height: 16),
            const NoteSigh(
                'Votre profil consulte les dépenses sans les saisir. La matrice des droits (M14) décide de cette ouverture.',
                ton: TonSigh.neutre,
                icone: LucideIcons.lock),
          ],
          const SizedBox(height: 16),
          deuxCartes(
            CarteSigh(
                titre: 'Dépenses par mois',
                child: GraphiqueBarres(
                    etiquettes: [for (final x in mois) x.$1],
                    series: [SerieGraphique('Décaissé', [for (final x in mois) x.$2], couleur: JetonsShell.danger500)])),
            CarteSigh(
                titre: 'Répartition par catégorie de dépenses',
                child: GraphiqueAnneau(etiquettes: [for (final x in cats) x.libelle], valeurs: [for (final x in cats) x.total])),
          ),
          const SizedBox(height: 16),
          CarteSigh(
              titre: 'Cumul par catégorie',
              sansRemplissage: true,
              child: TableauSigh(
                lignes: [for (final x in cats) {'id': x.id, 'label': x.libelle, 'nombre': x.nombre, 'total': x.total}],
                nomExport: 'depenses-categories',
                recherche: false,
                taillePage: 10,
                colonnes: [
                  const ColonneTableau(cle: 'label', libelle: 'Catégorie de dépenses'),
                  const ColonneTableau(cle: 'nombre', libelle: 'Pièces', droite: true),
                  ColonneTableau(
                      cle: 'total',
                      libelle: 'Montant',
                      droite: true,
                      texte: (r) => m(r['total']),
                      rendu: (_, r) => Text(m(r['total']),
                          style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]))),
                ],
              )),
        ]);
      },
    );
  }
}
