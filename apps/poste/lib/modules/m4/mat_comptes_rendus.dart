import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'mat_commun.dart';

/// `m4-comptes-rendus` — TROIS pièces aux rubriques propres (accouchement, planning familial, AMIU), et non un gabarit unique : un formulaire commun
/// aurait fait remplir à la sage-femme des champs sans objet. Le rendu de chaque pièce est ENGENDRÉ depuis sa déclaration (`COMPTES_RENDUS_MATERNITE`) :
/// ajouter une pièce demain n'exigera pas d'écrire un quatrième écran. Les actes de planification familiale sont NON COUVERTS par les assurances.
class EcranComptesRendusMaternite extends StatelessWidget with EcranMaquette {
  const EcranComptesRendusMaternite({super.key});
  @override
  String get titre => 'Comptes rendus de maternité';
  @override
  String get description => 'Comptes rendus d’accouchement, de planning familial et d’AMIU.';
  @override
  String get regle =>
      'Trois pièces distinctes, aux rubriques propres. Les actes de planification familiale sont tous non couverts par les assurances — la grille gynéco-obstétricale le porte en toutes lettres, et la facture le dit au guichet.';

  static String court(Fiche m) => '${m['label']}'.replaceFirst('Compte rendu ', '');

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return AnimatedBuilder(
        animation: c.magasin.collection('crMaternite'),
        builder: (ctx, _) {
          final col = c.magasin.collection('crMaternite');
          final rows = col.actives;
          final modeles = matComptesRendus;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Comptes rendus', valeur: nombre(rows.length), icone: LucideIcons.fileText, ton: TonSigh.navy),
              for (final m in modeles)
                KpiSigh(
                    libelle: court(m),
                    valeur: nombre(rows.where((r) => r['typeCr'] == m['code']).length),
                    icone: _icone('${m['icone']}'),
                    ton: TonSigh.info),
            ]),
            const SizedBox(height: 16),
            matNote(
                'Les actes de planification familiale — pose et retrait d’implant, de DIU, injectables — sont NON COUVERTS par les assurances selon la grille gynéco-obstétricale de la clinique. La patiente assurée les règle au tarif non assuré, et la facture en porte le motif.',
                ton: TonSigh.attention,
                icone: LucideIcons.shieldOff),
            const SizedBox(height: 16),
            OngletsSigh(onglets: [
              for (final m in modeles)
                OngletDef(
                    id: '${m['code']}',
                    libelle: court(m),
                    compte: rows.where((r) => r['typeCr'] == m['code']).length,
                    construire: (cx) => _Tableau(m, [for (final r in rows) if (r['typeCr'] == m['code']) r])),
            ]),
          ]);
        });
  }

  static IconData _icone(String n) => switch (n) {
        'baby' => LucideIcons.baby,
        'calendar-heart' => LucideIcons.calendarHeart,
        _ => LucideIcons.activity,
      };
}

// ---- Le formulaire d'une pièce, engendré depuis sa déclaration ---------------------------------------------------------------------------------

List<ChampDef> _champs(Magasin m, Fiche mod) {
  final soignants = m.collection('soignants').actives;
  final femmes = [
    for (final p in trierPar([for (final x in matPatients(m)) if (x['sexe'] == 'F') x], (p) => p['code']))
      OptionChamp('${p['code']}', '${p['code']} — ${p['nom']} ${p['prenom']}')
  ];
  OptionChamp so(Fiche x) => OptionChamp('${x['id']}', '${x['nomComplet']} — ${x['poste']}');
  return [
    ChampDef(nom: 'patientCode', libelle: 'Patiente', type: TypeChamp.select, requis: true, options: femmes),
    ChampDef(nom: 'sageFemmeId', libelle: 'Sage-femme ou médecin', type: TypeChamp.select, requis: true, options: [
      for (final x in soignants) if (matVrai(x['prescrit']) || matVrai(x['execute'])) so(x)
    ]),
    ChampDef.section('${mod['label']}'),
    for (final r in (mod['rubriques'] as List)) ...() {
      final x = r as List;
      final nom = '${x[0]}', lib = '${x[1]}', type = '${x[2]}', req = x[3] == true;
      switch (type) {
        case 'liste':
          return [ChampDef(nom: nom, libelle: lib, type: TypeChamp.select, requis: req, options: [for (final v in (x[4] as List)) OptionChamp('$v')])];
        case 'binaire':
          return [
            ChampDef(
                nom: nom,
                libelle: lib,
                type: TypeChamp.case_,
                requis: req,
                // un champ à cocher obligatoire doit être COCHÉ (U.form de la maquette refuse « Non »)
                valider: req ? (v, _) => v == true ? null : 'Ce champ est obligatoire.' : null)
          ];
        case 'zone':
          return [ChampDef(nom: nom, libelle: lib, type: TypeChamp.textarea, requis: req)];
        case 'nombre':
          return [ChampDef(nom: nom, libelle: lib, type: TypeChamp.nombre, requis: req)];
        case 'date':
          return [ChampDef(nom: nom, libelle: lib, type: TypeChamp.date, requis: req)];
        case 'datetime':
          return matChampsDateHeure(nom, lib, requis: req);
        case 'soignant':
          return [ChampDef(nom: nom, libelle: lib, type: TypeChamp.select, requis: req, options: [for (final y in soignants) so(y)])];
        default:
          return [ChampDef(nom: nom, libelle: lib, requis: req)];
      }
    }(),
  ];
}

List<String> _datetimes(Fiche mod) => [
      for (final r in (mod['rubriques'] as List))
        if ((r as List)[2] == 'datetime') '${r[0]}'
    ];

String _nomSoignant(Magasin m, Object? id) => m.collection('soignants').actives.where((x) => x['id'] == id).map((x) => '${x['nomComplet']}').firstOrNull ?? '—';

/// Les valeurs saisies deviennent la fiche : nombres lus, dates-heures recomposées.
Fiche _fiche(Fiche mod, Fiche v) {
  for (final r in (mod['rubriques'] as List)) {
    final x = r as List;
    if (x[2] == 'nombre') v['${x[0]}'] = matNombreSaisi(v['${x[0]}']);
  }
  for (final n in _datetimes(mod)) {
    matRecomposerDateHeure(v, n);
  }
  return v;
}

class _Tableau extends StatelessWidget {
  const _Tableau(this.mod, this.rows);
  final Fiche mod;
  final List<Fiche> rows;

  void _saisir(BuildContext ctx, Magasin m, {Fiche? existante}) {
    final c = ContexteEcran.of(ctx);
    final col = m.collection('crMaternite');
    final ctl = ControleurFormulaire(_champs(m, mod), existante != null ? matValeursEdition(existante, _datetimes(mod)) : const {});
    afficherModale<void>(ctx,
        titre: existante == null ? '${mod['label']}' : 'Modifier l’enregistrement',
        sousTitre: existante == null ? 'Les champs marqués d’un astérisque sont obligatoires.' : '${existante['reference']}',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: existante == null ? 'Créer' : 'Enregistrer',
                  icone: existante == null ? LucideIcons.plus : LucideIcons.save,
                  onPressed: () {
                    final saisie = ctl.valider();
                    if (saisie == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final v = _fiche(mod, {...saisie});
                    fermer();
                    if (existante == null) {
                      final pt = matPatientDe(m, v['patientCode']);
                      final fiche = matSansNuls({
                        'statut': 'actif',
                        ...v,
                        'reference': matReferenceSuivante('CRM-', col.toutes),
                        'typeCr': mod['code'],
                        'typeLabel': mod['label'],
                        'patientId': pt?['id'],
                        'patient': pt != null ? '${pt['nom']} ${pt['prenom']}' : v['patientCode'],
                        'sageFemme': _nomSoignant(m, v['sageFemmeId']),
                        'creeLe': c.aujourdhui.toIso8601String(),
                        '_creePar': c.utilisateur,
                      });
                      final r = col.inserer(fiche, prefixe: 'CRM');
                      ToastsSigh.afficher(ctx, 'Compte rendu créé.', type: TypeToast.succes, detail: '${r.fiche['reference']}', annuler: r.annuler);
                    } else {
                      final annuler = col.mettreAJour(existante['id'], v);
                      ToastsSigh.afficher(ctx, 'Modifications enregistrées.', type: TypeToast.succes, detail: '${existante['reference']}', annuler: annuler);
                    }
                  }),
            ]);
  }

  Widget _detail(Magasin m, Fiche r) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DescListeSigh([
          ('Référence', '${r['reference']}'),
          ('Type', '${r['typeLabel'] ?? ''}'),
          ('Patiente', '${r['patient']} — ${r['patientCode']}'),
          ('Rédigé par', '${r['sageFemme'] ?? ''}'),
          ('Enregistré le', matDateHeure(r['creeLe'])),
        ]),
        const SizedBox(height: 16),
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('${mod['label']}', style: const TextStyle(color: JetonsShell.slate900, fontSize: 14, fontWeight: FontWeight.w600))),
        MiniTableauSigh(colonnes: [
          ColonneMini('Rubrique', (x) => '${x['k']}'),
          ColonneMini('Valeur', (x) => '${x['v']}'),
        ], lignes: [
          for (final rb in (mod['rubriques'] as List))
            () {
              final x = rb as List;
              Object? v = r['${x[0]}'];
              if (x[2] == 'binaire') v = matVrai(v) ? 'Oui' : 'Non';
              if (x[2] == 'soignant') v = _nomSoignant(m, v);
              if (x[2] == 'date' && matVrai(v)) v = matDateFR(v);
              return {'k': '${x[1]}', 'v': v == null || v == '' ? '—' : '$v'};
            }()
        ]),
      ]);

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    void detail(Fiche r) => afficherTiroir<void>(context,
        titre: '${r['reference']}', largeurMax: 672, corps: _detail(m, r), pied: (fermer) => [
              if (c.droit.editer)
                BoutonSigh(
                    libelle: 'Modifier',
                    icone: LucideIcons.pencil,
                    variante: VarianteBouton.secondaire,
                    onPressed: () {
                      fermer();
                      _saisir(context, m, existante: r);
                    }),
            ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (mod['note'] != null) ...[matNote('${mod['note']}'), const SizedBox(height: 12)],
      TableauSigh(
        colonnes: [
          ColonneTableau(cle: 'reference', libelle: 'Référence', texte: (r) => '${r['reference'] ?? ''}'),
          ColonneTableau(cle: 'creeLe', libelle: 'Enregistré le', valeur: (r) => matMs(r['creeLe']), texte: (r) => matDateHeure(r['creeLe'])),
          ColonneTableau(cle: 'patient', libelle: 'Patiente', texte: (r) => '${r['patient'] ?? ''} — ${r['patientCode'] ?? ''}'),
          const ColonneTableau(cle: 'sageFemme', libelle: 'Rédigé par'),
        ],
        lignes: rows,
        triInitial: 'creeLe',
        sensInitial: 'desc',
        taillePage: 12,
        nomExport: 'crMaternite',
        messageVide: 'Aucun ${'${mod['label']}'.toLowerCase()} enregistré.',
        alClicLigne: detail,
        actions: [
          if (c.droit.editer)
            BoutonSigh(libelle: 'Nouveau — ${EcranComptesRendusMaternite.court(mod)}', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _saisir(context, m)),
        ],
        actionsLigne: (ctx, r) => [
          BoutonIcone(icone: LucideIcons.eye, libelle: 'Consulter', onPressed: () => detail(r)),
          if (c.droit.editer) BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier', onPressed: () => _saisir(context, m, existante: r)),
          if (c.droit.annuler)
            BoutonIcone(
                icone: LucideIcons.archive,
                libelle: 'Archiver',
                onPressed: () async {
                  final motif = await confirmerAvecMotif(context,
                      titre: 'Archiver cet enregistrement ?',
                      message: 'L’enregistrement ne sera pas supprimé : il est archivé. L’opération est journalisée et peut être annulée.',
                      libelleOk: 'Archiver',
                      dangereux: true);
                  if (motif == null || !context.mounted) return;
                  final annuler = m.collection('crMaternite').archiver(r['id']);
                  ToastsSigh.afficher(context, 'Enregistrement archivé.', type: TypeToast.succes, annuler: annuler);
                }),
        ],
      ),
    ]);
  }
}
