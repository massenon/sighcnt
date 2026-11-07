import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cpa_commun.dart';

/// `m12-ecritures` — « Écritures comptables » : saisie, consultation et validation des écritures, contrôle d'équilibre.
///
/// RG-10 : une écriture se VALIDE équilibrée. Un brouillon déséquilibré est accepté (la maquette le permet) et sa validation est REFUSÉE en nommant
/// l'écart. On valide et on archive la PIÈCE entière — toutes les lignes de même numéro — jamais une ligne seule (E710, E716). Une écriture dont la date
/// tombe dans un exercice clos est REFUSÉE, avec le motif du moteur, et rien n'est écrit (E713).
///
/// Les commandes d'écriture sont ABSENTES (jamais grisées) sans le droit : « Nouvelle écriture » et « Valider » → `droit.editer`, « Archiver » →
/// `droit.annuler`. La maquette offre ces deux gestes à tout profil qui ouvre l'écran (écart E723).
class EcranEcritures extends StatelessWidget with EcranMaquette {
  const EcranEcritures({super.key});

  @override
  String get titre => 'Écritures comptables';

  @override
  String get description =>
      'Saisie, consultation et validation des écritures, avec contrôle d’équilibre.';

  @override
  String get regle =>
      'RG-10 — toute écriture doit être équilibrée (total débit = total crédit) avant validation dans le journal correspondant.';

  static void _refus(BuildContext ctx, CpaRefus e) =>
      ToastsSigh.afficher(ctx, e.message, type: TypeToast.erreur, detail: e.detail);

  void _consulter(BuildContext ctx, ContexteEcran c, Fiche e) {
    final col = c.magasin.collection('ecritures');
    final meme = cpaPiece(col.actives, e['numero']);
    final td = meme.fold<num>(0, (a, x) => a + n(x['debit']));
    final tc = meme.fold<num>(0, (a, x) => a + n(x['credit']));
    afficherTiroir<void>(ctx,
        titre: 'Écriture ${e['numero']}',
        sousTitre: '${e['libelle']} — ${dateDe(e['date'])}',
        largeurMax: 768,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('N° de pièce', '${e['numero']}'),
            ('Date', dateDe(e['date'])),
            ('Journal', cpaJournalLibelle(e['journal'])),
            ('Libellé', '${e['libelle'] ?? ''}'),
            ('Centre de coûts', libelleCentre(c, e['centreCout'])),
            ('Origine', '${e['origine'] ?? ''}'),
            ('Pièce justificative', e['piece'] == null || e['piece'] == '' ? '—' : '${e['piece']}'),
            ('Statut', statutBadge(e['statut'])),
          ]),
          const SizedBox(height: 16),
          CarteSigh(
              titre: 'Lignes de l’écriture',
              sansRemplissage: true,
              child: MiniTableauSigh(colonnes: [
                ColonneMini('Compte', (x) => '${x['compte']}', rendu: (x) => Text('${x['compte']}', style: mono)),
                ColonneMini('Intitulé', (x) => '${x['compteLibelle'] ?? cpaCompteLibelle(x['compte'])}'),
                ColonneMini('Débit', (x) => n(x['debit']) != 0 ? m(x['debit']) : '—', droite: true),
                ColonneMini('Crédit', (x) => n(x['credit']) != 0 ? m(x['credit']) : '—', droite: true),
              ], lignes: meme)),
          const SizedBox(height: 16),
          noteEquilibre(td, tc),
        ]));
  }

  void _valider(BuildContext ctx, ContexteEcran c, Fiche e) {
    final col = c.magasin.collection('ecritures');
    try {
      final piece = cpaValiderPiece(col.actives, e);
      final undo = [for (final x in piece) col.mettreAJour(x['id'], {'statut': 'validee'})];
      ToastsSigh.afficher(ctx, 'Écriture validée.',
          type: TypeToast.succes, detail: '${piece.length} ligne(s).', annuler: () {
        for (final u in undo) {
          u();
        }
      });
    } on CpaRefus catch (r) {
      _refus(ctx, r);
    }
  }

  void _archiver(BuildContext ctx, ContexteEcran c, Fiche e) {
    final col = c.magasin.collection('ecritures');
    final piece = cpaPiece(col.actives, e['numero']);
    final undo = [for (final x in piece) col.archiver(x['id'])];
    ToastsSigh.afficher(ctx, 'Écriture archivée.', type: TypeToast.succes, detail: '${piece.length} ligne(s).', annuler: () {
      for (final u in undo) {
        u();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('ecritures');
    return ListenableBuilder(
      listenable: ecouteCompta(c),
      builder: (context, _) {
        final actifs = col.actives;
        final droit = c.droit;
        final centres = c.magasin.collection('centresCouts').actives;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!droit.editer && droit.voir)
            Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: NoteSigh(
                    'Lecture seule : le profil « ${c.role} » consulte cet écran sans pouvoir y écrire. Les droits se règlent dans la matrice des rôles.',
                    ton: TonSigh.attention)),
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Écritures enregistrées', valeur: nombre(actifs.length), icone: LucideIcons.fileText),
            KpiSigh(
                libelle: 'Validées',
                valeur: nombre(actifs.where((e) => e['statut'] == 'validee').length),
                icone: LucideIcons.circleCheckBig,
                ton: TonSigh.succes),
            KpiSigh(
                libelle: 'En brouillon',
                valeur: nombre(actifs.where((e) => e['statut'] == 'brouillon').length),
                icone: LucideIcons.fileClock,
                ton: TonSigh.attention),
            KpiSigh(
                libelle: 'Automatiques',
                valeur: nombre(actifs.where((e) => '${e['origine']}'.startsWith('Automatique')).length),
                icone: LucideIcons.zap,
                ton: TonSigh.info),
          ]),
          const SizedBox(height: 16),
          TableauSigh(
            titre: 'Écritures comptables',
            lignes: actifs,
            nomExport: 'ecritures',
            taillePage: 20,
            triInitial: 'date',
            sensInitial: 'desc',
            alClicLigne: (e) => _consulter(context, c, e),
            filtres: [
              FiltreTableau(nom: 'journal', libelle: 'Journal', options: [for (final j in cpaJournaux) OptionChamp(j.$1, j.$2)]),
              const FiltreTableau(nom: 'statut', libelle: 'Statut', options: [
                OptionChamp('validee', 'Validée'),
                OptionChamp('brouillon', 'Brouillon'),
              ]),
              FiltreTableau(
                  nom: 'centreCout',
                  libelle: 'Centre de coûts',
                  options: [for (final x in centres) OptionChamp('${x['code']}', '${x['libelle']}')]),
            ],
            actions: [
              if (droit.editer)
                BoutonSigh(
                    libelle: 'Nouvelle écriture',
                    icone: LucideIcons.plus,
                    taille: TailleBouton.sm,
                    onPressed: () => _saisie(context, c)),
            ],
            actionsLigne: (ctx, e) => [
              BoutonIcone(icone: LucideIcons.eye, libelle: 'Consulter', onPressed: () => _consulter(context, c, e)),
              if (droit.editer && e['statut'] == 'brouillon')
                BoutonIcone(icone: LucideIcons.check, libelle: 'Valider', onPressed: () => _valider(context, c, e)),
              if (droit.annuler)
                BoutonIcone(icone: LucideIcons.archive, libelle: 'Archiver', onPressed: () => _archiver(context, c, e)),
            ],
            colonnes: [
              colNumeroEcriture(),
              colDateEcriture(),
              colJournalEcriture(),
              colCompteEcriture(),
              const ColonneTableau(cle: 'libelle', libelle: 'Libellé de l’opération'),
              colDebitEcriture(),
              colCreditEcriture(),
              ColonneTableau(
                  cle: 'centreCout',
                  libelle: 'Centre de coûts',
                  texte: (e) => libelleCentre(c, e['centreCout']),
                  rendu: (_, e) => Text(libelleCentre(c, e['centreCout']),
                      style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12))),
              ColonneTableau(
                  cle: 'origine',
                  libelle: 'Origine',
                  texte: (e) => '${e['origine'] ?? ''}',
                  rendu: (_, e) => BadgeSigh('${e['origine'] ?? ''}',
                      ton: '${e['origine']}'.startsWith('Automatique') ? TonSigh.info : TonSigh.neutre)),
              ColonneTableau(
                  cle: 'statut',
                  libelle: 'Statut',
                  texte: (e) => '${statutsMetier['${e['statut']}']?.$1 ?? e['statut'] ?? ''}',
                  rendu: (_, e) => statutBadge(e['statut'])),
            ],
          ),
        ]);
      },
    );
  }

  // -------------------------------------------------------------------------------------------------------------------------------------------
  // LA SAISIE EN PARTIE DOUBLE : plusieurs lignes, contrôle d'équilibre.
  // -------------------------------------------------------------------------------------------------------------------------------------------

  static List<OptionChamp> _optionsCentres(ContexteEcran c) => [
        for (final x in c.magasin.collection('centresCouts').actives) OptionChamp('${x['code']}', '${x['libelle']}')
      ];

  static List<ChampDef> _champsEntete(ContexteEcran c) => [
        const ChampDef(nom: 'date', libelle: 'Date de l’opération', type: TypeChamp.date, requis: true),
        ChampDef(
            nom: 'journal',
            libelle: 'Journal',
            type: TypeChamp.select,
            requis: true,
            options: [for (final j in cpaJournaux) OptionChamp(j.$1, '${j.$1} — ${j.$2}')]),
        const ChampDef(nom: 'libelle', libelle: 'Libellé de l’opération', requis: true, col: ColChamp.plein),
        ChampDef(
            nom: 'centreCout',
            libelle: 'Centre de coûts',
            type: TypeChamp.select,
            options: _optionsCentres(c),
            aide:
                'Axe d’imputation analytique. Un centre manquant se crée depuis le bouton ci-dessous, sans quitter la saisie.'),
        const ChampDef(nom: 'piece', libelle: 'Référence de la pièce justificative'),
      ];

  void _saisie(BuildContext ctx, ContexteEcran c) {
    final col = c.magasin.collection('ecritures');
    final comptes = trierPar(c.magasin.collection('comptes').actives, (x) => x['num']);
    var form = ControleurFormulaire(_champsEntete(c), {'date': iso(c.aujourdhui)});
    final ajout = ControleurFormulaire([
      ChampDef(
          nom: 'compte',
          libelle: 'Compte',
          type: TypeChamp.select,
          col: ColChamp.plein,
          options: [for (final x in comptes) OptionChamp('${x['num']}', '${x['num']} — ${x['libelle']}')]),
      const ChampDef(nom: 'debit', libelle: 'Débit', type: TypeChamp.nombre),
      const ChampDef(nom: 'credit', libelle: 'Crédit', type: TypeChamp.nombre),
    ], {
      'compte': comptes.isEmpty ? '' : '${comptes.first['num']}',
      'debit': '0',
      'credit': '0'
    });
    final lignes = <Fiche>[];
    void Function(VoidCallback)? majModale;

    afficherModale<void>(ctx,
        titre: 'Nouvelle écriture comptable',
        sousTitre: 'Saisie en partie double — contrôle d’équilibre appliqué (RG-10)',
        taille: TailleModale.xl,
        corps: StatefulBuilder(builder: (mctx, maj) {
          majModale = maj;
          final td = lignes.fold<num>(0, (a, l) => a + n(l['debit']));
          final tc = lignes.fold<num>(0, (a, l) => a + n(l['credit']));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FormulaireSigh(controleur: form),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: JetonsShell.slate50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: JetonsShell.slate200)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(flex: 3, child: FormulaireSigh(controleur: ajout)),
                const SizedBox(width: 8),
                BoutonSigh(
                    libelle: 'Ajouter la ligne',
                    icone: LucideIcons.plus,
                    onPressed: () {
                      final d = num.tryParse('${ajout['debit']}'.replaceAll(',', '.')) ?? 0;
                      final cr = num.tryParse('${ajout['credit']}'.replaceAll(',', '.')) ?? 0;
                      try {
                        cpaVerifierLigne(d, cr);
                      } on CpaRefus catch (r) {
                        _refus(ctx, r);
                        return;
                      }
                      final cmp = '${ajout['compte']}';
                      lignes.add({'compte': cmp, 'compteLibelle': cpaCompteLibelle(cmp), 'debit': d, 'credit': cr});
                      ajout.poser('debit', '0');
                      ajout.poser('credit', '0');
                      maj(() {});
                    }),
              ]),
            ),
            const SizedBox(height: 16),
            if (lignes.isEmpty)
              const VideSigh('Aucune ligne saisie.', icone: LucideIcons.list)
            else
              Container(
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
                child: Column(children: [
                  MiniTableauSigh(colonnes: [
                    ColonneMini('Compte', (x) => '${x['compte']} ${x['compteLibelle']}',
                        rendu: (x) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              Text('${x['compte']}', style: mono.copyWith(fontWeight: FontWeight.w600)),
                              Text('${x['compteLibelle']}',
                                  style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
                            ])),
                    ColonneMini('Débit', (x) => n(x['debit']) != 0 ? m(x['debit']) : '—', droite: true),
                    ColonneMini('Crédit', (x) => n(x['credit']) != 0 ? m(x['credit']) : '—', droite: true),
                    ColonneMini('', (x) => '',
                        rendu: (x) => BoutonIcone(
                            icone: LucideIcons.x,
                            libelle: 'Retirer',
                            onPressed: () {
                              lignes.remove(x);
                              maj(() {});
                            })),
                  ], lignes: lignes),
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        const Expanded(child: Text('TOTAUX', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                        Text(m(td), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(width: 24),
                        Text(m(tc), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(width: 48),
                      ])),
                ]),
              ),
            const SizedBox(height: 12),
            noteEquilibre(td, tc, saisie: true),
          ]);
        }),
        pied: (fermer) {
          void enregistrer(String statut) {
            final v = form.valider();
            if (v == null) {
              ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
              return;
            }
            try {
              final plates = cpaEcrituresDeSaisie(
                  date: '${v['date']}',
                  journal: '${v['journal']}',
                  libelle: '${v['libelle']}',
                  centreCout: '${v['centreCout'] ?? ''}',
                  piece: '${v['piece'] ?? ''}',
                  lignes: lignes,
                  statut: statut,
                  exercice: exerciceChoisi(c),
                  toutes: col.toutes);
              final crees = [for (final l in plates) col.inserer(l, prefixe: 'ECR')];
              fermer();
              ToastsSigh.afficher(ctx, 'Écriture ${plates.first['numero']} enregistrée (${crees.length} ligne(s)).',
                  type: TypeToast.succes,
                  detail: statut == 'validee' ? 'Validée et équilibrée.' : 'Enregistrée en brouillon.',
                  annuler: () {
                for (final r in crees) {
                  r.annuler();
                }
              });
            } on CpaRefus catch (r) {
              _refus(ctx, r);
            }
          }

          return [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            // Créer un centre de coûts sans quitter la saisie : attendre une livraison pour imputer une charge n'aurait pas de sens.
            BoutonSigh(
                libelle: 'Nouveau centre de coûts',
                icone: LucideIcons.target,
                variante: VarianteBouton.secondaire,
                onPressed: () => _nouveauCentre(ctx, c, (code) {
                      final valeurs = {for (final ch in form.champs) ch.nom: form[ch.nom]};
                      form = ControleurFormulaire(_champsEntete(c), {...valeurs, 'centreCout': code});
                      majModale?.call(() {});
                    })),
            BoutonSigh(
                libelle: 'Enregistrer en brouillon',
                variante: VarianteBouton.secondaire,
                onPressed: () => enregistrer('brouillon')),
            BoutonSigh(libelle: 'Valider l’écriture', icone: LucideIcons.check, onPressed: () => enregistrer('validee')),
          ];
        });
  }

  void _nouveauCentre(BuildContext ctx, ContexteEcran c, void Function(String code) apres) {
    final cf = ControleurFormulaire([
      const ChampDef(nom: 'libelle', libelle: 'Intitulé du centre', requis: true, col: ColChamp.plein),
      const ChampDef(nom: 'type', libelle: 'Type', type: TypeChamp.select, requis: true, options: [
        OptionChamp('exploitation', 'Centre d’exploitation'),
        OptionChamp('support', 'Centre de support'),
      ]),
      const ChampDef(nom: 'responsable', libelle: 'Responsable', col: ColChamp.plein),
    ]);
    afficherModale<void>(ctx,
        titre: 'Nouveau centre de coûts',
        taille: TailleModale.md,
        corps: FormulaireSigh(controleur: cf),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Créer',
                  icone: LucideIcons.plus,
                  onPressed: () {
                    final cv = cf.valider();
                    if (cv == null) return;
                    final col = c.magasin.collection('centresCouts');
                    final code = 'CC${(col.toutes.length + 1).toString().padLeft(2, '0')}';
                    col.inserer({
                      ...cv,
                      'code': code,
                      'source': 'Créé depuis la saisie comptable',
                      'statut': 'actif',
                    }, prefixe: 'CC');
                    fermer();
                    apres(code);
                    ToastsSigh.afficher(ctx, 'Centre « ${cv['libelle']} » créé et sélectionné.', type: TypeToast.succes);
                  }),
            ]);
  }
}
