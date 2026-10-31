import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m7/pv_crud.dart';
import 'commun.dart';

/// Le taux de couverture n'est PAS unique par patient : il varie d'une convention à l'autre et, pour un même assuré, selon la nature de la
/// prestation. Trois niveaux, tels que les pièces réelles les montrent : compagnie → souscripteur (n° de police) → assuré, et c'est le SOUSCRIPTEUR
/// qui porte la grille. Tant qu'une convention n'est pas saisie, la facturation reste intégralement à la charge du patient — et l'écran le dit.
class EcranConventions extends StatelessWidget with EcranMaquette {
  const EcranConventions({super.key});

  @override
  String get titre => 'Conventions & garanties';

  @override
  String get description =>
      'Grille de prise en charge par souscripteur : taux et plafonds par catégorie, exclusions et accords préalables.';

  @override
  String get regle =>
      'Le taux de couverture n’est pas unique par patient : il varie d’une convention à l’autre et, pour un même assuré, selon la nature de la prestation. Tant qu’une convention n’est pas saisie, la facturation reste intégralement à la charge du patient — et l’écran le dit. RG-09 — la prise en charge ne s’applique que si la carte est valide à la date de facturation.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Assurés & cartes',
          icone: LucideIcons.idCard,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m9-assures')),
      BoutonSigh(
          libelle: 'Compagnies',
          icone: LucideIcons.building2,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m9-compagnies')),
      BoutonSigh(
          libelle: 'Prises en charge',
          icone: LucideIcons.shieldCheck,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m9-prises-en-charge')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecoute(c, [
        'assureurs',
        'patients',
        'souscripteurs',
        'garanties',
        'couverturesAssurance'
      ]),
      builder: (context, _) {
        final sous = actives(c, 'souscripteurs');
        final garanties = actives(c, 'garanties');
        final avecGrille = sous
            .where((s) => garanties.any((g) => g['souscripteurId'] == s['id']))
            .length;
        final aCollecter = sous.length - avecGrille;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Souscripteurs',
                    valeur: nombre(sous.length),
                    indice:
                        'Contrats sous ${actives(c, 'assureurs').length} compagnies',
                    icone: LucideIcons.fileSignature),
                KpiSigh(
                    libelle: 'Conventions saisies',
                    valeur: nombre(avecGrille),
                    icone: LucideIcons.checkCircle2,
                    ton: avecGrille > 0 ? TonSigh.succes : TonSigh.attention),
                KpiSigh(
                    libelle: 'Conventions à collecter',
                    valeur: nombre(aCollecter),
                    icone: LucideIcons.circleHelp,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Lignes de garantie',
                    valeur: nombre(garanties.length),
                    icone: LucideIcons.percent,
                    ton: TonSigh.info),
              ]),
              if (aCollecter > 0) ...[
                const SizedBox(height: 16),
                NoteSigh(
                    '$aCollecter convention(s) non saisie(s). Un seul barème figure au dossier — celui d’un régime employeur, versé le 18/06/2026 — et il ne vaut que pour son souscripteur. Les grilles des autres compagnies restent à collecter. En attendant, leurs assurés sont facturés intégralement : mieux vaut une facture juste qu’une prise en charge supposée.',
                    ton: TonSigh.attention,
                    icone: LucideIcons.circleHelp),
              ],
              const SizedBox(height: 16),
              OngletsSigh(onglets: [
                OngletDef(
                    id: 'souscripteurs',
                    libelle: 'Souscripteurs',
                    compte: sous.length,
                    construire: (ctx) => _OngletSouscripteurs(c: c)),
                OngletDef(
                    id: 'garanties',
                    libelle: 'Grilles de garanties',
                    compte: garanties.length,
                    construire: (ctx) => _ongletGaranties(c, garanties, sous)),
                OngletDef(
                    id: 'simulateur',
                    libelle: 'Simulateur de répartition',
                    construire: (ctx) => _Simulateur(c: c)),
              ]),
            ]);
      },
    );
  }

  Widget _ongletGaranties(ContexteEcran c, List<Fiche> garanties, List<Fiche> sous) {
    if (garanties.isEmpty) {
      return const VideSigh(
          'Aucune convention saisie. Ouvrir un souscripteur pour saisir sa grille.',
          icone: LucideIcons.percent);
    }
    final rows = [
      for (final g in garanties)
        () {
          final s = sous.where((x) => x['id'] == g['souscripteurId']).firstOrNull;
          return {
            ...g,
            'souscripteur': s != null ? s['nom'] : '—',
            'compagnie': s != null ? s['assureurNom'] : g['assureur']
          };
        }()
    ];
    final noms = ({for (final r in rows) '${r['souscripteur']}'}.toList()..sort());
    return TableauSigh(
      lignes: rows,
      taillePage: 20,
      nomExport: 'garanties',
      triInitial: 'souscripteur',
      filtres: [
        FiltreTableau(
            nom: 'souscripteur',
            libelle: 'Souscripteur',
            options: [for (final x in noms) OptionChamp(x)]),
        FiltreTableau(nom: 'categorie', libelle: 'Catégorie', options: [
          for (final x in assCategoriesGarantie) OptionChamp(x.$1, x.$2)
        ]),
      ],
      colonnes: [
        const ColonneTableau(cle: 'souscripteur', libelle: 'Souscripteur'),
        ColonneTableau(
            cle: 'compagnie',
            libelle: 'Compagnie',
            texte: (g) => '${g['compagnie']}',
            rendu: (_, g) => BadgeSigh('${g['compagnie']}', ton: TonSigh.navy)),
        const ColonneTableau(cle: 'libelle', libelle: 'Garantie'),
        ColonneTableau(
            cle: 'categorie',
            libelle: 'Catégorie',
            texte: (g) => assLibelleCategorie(g['categorie'])),
        ColonneTableau(
            cle: 'taux',
            libelle: 'Taux',
            droite: true,
            texte: (g) => '${g['taux']} %',
            rendu: (_, g) => Text('${g['taux']} %',
                style: const TextStyle(
                    color: JetonsShell.slate700,
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w600))),
        ColonneTableau(
            cle: 'plafond',
            libelle: 'Plafond',
            droite: true,
            texte: (g) => g['plafond'] == null ? '' : '${g['plafond']}',
            rendu: (_, g) => g['plafond'] == null
                ? const Text('sans plafond',
                    style: TextStyle(
                        color: JetonsShell.slate300, fontSize: 12, height: 16 / 12))
                : Text(
                    '${m(g['plafond'])} ${assLibelleUnite(g['unitePlafond'])}',
                    style: const TextStyle(
                        color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
      ],
    );
  }
}

// --- Souscripteurs ---------------------------------------------------------------------------------------------------------------

List<ChampDef> champsSouscripteur(List<Fiche> assureurs) => [
      const ChampDef(
          nom: 'nom',
          libelle: 'Souscripteur',
          requis: true,
          col: ColChamp.plein,
          aide: 'Employeur, groupe ou particulier signataire du contrat.'),
      ChampDef(
          nom: 'assureur',
          libelle: 'Compagnie',
          type: TypeChamp.select,
          requis: true,
          options: [
            for (final a in assureurs) OptionChamp('${a['code']}', '${a['nom']}')
          ]),
      const ChampDef(nom: 'police', libelle: 'N° de police', requis: true),
      const ChampDef(
          nom: 'categorie',
          libelle: 'Catégorie',
          type: TypeChamp.select,
          requis: true,
          options: [
            OptionChamp('entreprise', 'Assurance entreprise'),
            OptionChamp('particulier', 'Assurance particulier'),
            OptionChamp('personnel', 'Assurance personnel de la clinique'),
          ]),
      const ChampDef(
          nom: 'effectif', libelle: 'Bénéficiaires déclarés', type: TypeChamp.nombre),
      const ChampDef(nom: 'contact', libelle: 'Interlocuteur', col: ColChamp.plein),
      const ChampDef(
          nom: 'dateDebut', libelle: 'Début de validité', type: TypeChamp.date),
      const ChampDef(
          nom: 'dateFin',
          libelle: 'Fin de validité',
          type: TypeChamp.date,
          aide: 'Laisser vide si la convention est en cours.'),
    ];

Fiche _souscripteurSaisi(Map<String, Object?> s) => {
      'nom': s['nom'],
      'assureur': s['assureur'],
      'police': s['police'],
      'categorie': s['categorie'],
      'effectif': num.tryParse('${s['effectif'] ?? ''}'.trim()),
      'contact': s['contact'] ?? '',
      'dateDebut': s['dateDebut'] ?? '',
      'dateFin': s['dateFin'] ?? '',
    };

class _OngletSouscripteurs extends StatelessWidget {
  const _OngletSouscripteurs({required this.c});
  final ContexteEcran c;

  List<Fiche> _garantiesDe(Object? id) =>
      actives(c, 'garanties').where((g) => g['souscripteurId'] == id).toList();
  List<Fiche> _assuresDe(Object? id) => actives(c, 'patients')
      .where((p) => p['souscripteurId'] == id)
      .toList();

  @override
  Widget build(BuildContext context) {
    final sous = actives(c, 'souscripteurs');
    final assureurs = actives(c, 'assureurs');
    final col = c.magasin.collection('souscripteurs');
    return TableauSigh(
      lignes: sous,
      taillePage: 15,
      nomExport: 'souscripteurs',
      triInitial: 'nom',
      alClicLigne: (s) => _fiche(context, s),
      filtres: [
        FiltreTableau(nom: 'categorie', libelle: 'Catégorie', options: [
          OptionChamp('entreprise', 'Entreprise'),
          OptionChamp('particulier', 'Particulier'),
          OptionChamp('personnel', 'Personnel de la clinique'),
        ]),
        FiltreTableau(
            nom: 'grille',
            libelle: 'Convention',
            options: [OptionChamp('oui', 'Saisie'), OptionChamp('non', 'À collecter')],
            correspond: (r, v) {
              final a = _garantiesDe(r['id']).isNotEmpty;
              return v == 'oui' ? a : !a;
            }),
      ],
      colonnes: [
        ColonneTableau(
            cle: 'nom',
            libelle: 'Souscripteur',
            texte: (s) => '${s['nom']} ${s['police']}',
            rendu: (_, s) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${s['nom']}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: JetonsShell.slate800,
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight: FontWeight.w500)),
                      Text('${s['police']}',
                          style: mono.copyWith(color: JetonsShell.slate400)),
                    ])),
        ColonneTableau(
            cle: 'assureurNom',
            libelle: 'Compagnie',
            texte: (s) => '${s['assureur']}',
            rendu: (_, s) => BadgeSigh('${s['assureur']}', ton: TonSigh.navy)),
        ColonneTableau(
            cle: 'categorie',
            libelle: 'Catégorie',
            texte: (s) => '${s['categorie']}',
            rendu: (_, s) {
              const mp = {
                'entreprise': ('Entreprise', TonSigh.info),
                'particulier': ('Particulier', TonSigh.neutre),
                'personnel': ('Personnel', TonSigh.succes)
              };
              final x = mp['${s['categorie']}'] ?? mp['particulier']!;
              return BadgeSigh(x.$1, ton: x.$2);
            }),
        ColonneTableau(
            cle: 'assures',
            libelle: 'Assurés',
            droite: true,
            valeur: (s) => _assuresDe(s['id']).length,
            texte: (s) => '${_assuresDe(s['id']).length}'),
        ColonneTableau(
            cle: 'grille',
            libelle: 'Convention',
            valeur: (s) => _garantiesDe(s['id']).length,
            texte: (s) => _garantiesDe(s['id']).isEmpty
                ? 'À collecter'
                : '${_garantiesDe(s['id']).length} garanties',
            rendu: (_, s) {
              final k = _garantiesDe(s['id']).length;
              return k > 0
                  ? BadgeSigh('$k garanties', ton: TonSigh.succes)
                  : const BadgeSigh('À collecter', ton: TonSigh.attention);
            }),
      ],
      actions: [
        if (c.droit.editer)
          BoutonSigh(
              libelle: 'Nouveau',
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              onPressed: () => ouvrirFormulaireFiche(context,
                  collection: col,
                  champs: champsSouscripteur(assureurs),
                  entite: 'Souscripteur',
                  prefixeId: 'SOU',
                  identifiant: (x) => '${x['nom'] ?? ''}',
                  valeursCreation: {
                    'categorie': 'entreprise',
                    'assureur': assureurs.isEmpty ? '' : '${assureurs.first['code']}'
                  },
                  versFiche: (s) =>
                      assSouscripteurDepuis(_souscripteurSaisi(s), assureurs),
                  detailMessage: false)),
      ],
      actionsLigne: (ctx, s) => [
        BoutonIcone(
            icone: LucideIcons.percent,
            libelle: 'Saisir la grille',
            onPressed: () => _fiche(ctx, s)),
        if (c.droit.editer)
          BoutonIcone(
              icone: LucideIcons.pencil,
              libelle: 'Modifier',
              onPressed: () => ouvrirFormulaireFiche(ctx,
                  collection: col,
                  champs: champsSouscripteur(assureurs),
                  entite: 'Souscripteur',
                  record: s,
                  identifiant: (x) => '${x['nom'] ?? ''}',
                  versFiche: _souscripteurSaisi,
                  detailMessage: false)),
      ],
    );
  }

  // --- La fiche d'un souscripteur : sa grille, ses exclusions, ses accords ------------------------------------------------------------

  Widget _bloc(String titre, Object? liste) {
    final l = [for (final x in (liste as List? ?? const [])) '$x'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titre.toUpperCase(),
          style: const TextStyle(
              color: JetonsShell.slate500,
              fontSize: 12,
              height: 16 / 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6)),
      const SizedBox(height: 4),
      if (l.isEmpty)
        const Text('Aucune — tout est couvert dans cette catégorie.',
            style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12))
      else
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final x in l)
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: JetonsShell.slate50,
                    border: Border.all(color: JetonsShell.slate200),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(x,
                    style: const TextStyle(
                        color: JetonsShell.slate600, fontSize: 12, height: 16 / 12))),
        ]),
    ]);
  }

  void _fiche(BuildContext ctx, Fiche s0) {
    afficherTiroir<void>(ctx,
        titre: '${s0['nom']}',
        sousTitre: '${s0['assureurNom']} — ${s0['police']}',
        largeurMax: 768,
        corps: ListenableBuilder(
            listenable: ecoute(c, ['souscripteurs', 'garanties', 'patients']),
            builder: (context, _) {
              final s = c.magasin.collection('souscripteurs').parId(s0['id']) ?? s0;
              final g = _garantiesDe(s['id']);
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DescListeSigh([
                      ('Compagnie', s['assureurNom']),
                      ('N° de police', s['police']),
                      ('Catégorie', s['categorie']),
                      (
                        'Bénéficiaires déclarés',
                        s['effectif'] != null ? nombre(s['effectif']) : '—'
                      ),
                      ('Assurés rattachés', nombre(_assuresDe(s['id']).length)),
                      ('Interlocuteur', s['contact'] == null || s['contact'] == '' ? '—' : s['contact']),
                      (
                        'Validité',
                        '${dateDe(s['dateDebut'])}${s['dateFin'] != null && '${s['dateFin']}'.isNotEmpty ? ' → ${dateDe(s['dateFin'])}' : ' → en cours'}'
                      ),
                    ]),
                    const SizedBox(height: 16),
                    CarteSigh(
                        titre: 'Grille de garanties',
                        child: g.isNotEmpty
                            ? MiniTableauSigh(colonnes: [
                                ColonneMini('Garantie', (x) => '${x['libelle']}'),
                                ColonneMini('Catégorie',
                                    (x) => assLibelleCategorie(x['categorie'])),
                                ColonneMini('Taux', (x) => '${x['taux']} %', droite: true),
                                ColonneMini(
                                    'Plafond',
                                    (x) => x['plafond'] == null
                                        ? '—'
                                        : '${m(x['plafond'])} ${assLibelleUnite(x['unitePlafond'])}',
                                    droite: true),
                              ], lignes: g)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                    const VideSigh(
                                        'Convention non saisie — les assurés de ce souscripteur sont facturés intégralement.',
                                        icone: LucideIcons.fileQuestion),
                                    if (c.droit.editer)
                                      Center(
                                          child: BoutonSigh(
                                              libelle:
                                                  'Saisir la grille depuis le barème de référence',
                                              icone: LucideIcons.filePlus,
                                              onPressed: () =>
                                                  _proposerBareme(context, s))),
                                  ])),
                    const SizedBox(height: 16),
                    CarteSigh(
                        titre: 'Exclusions et accords préalables',
                        actions: [
                          if (c.droit.editer)
                            BoutonSigh(
                                libelle: 'Modifier',
                                icone: LucideIcons.pencil,
                                taille: TailleBouton.sm,
                                variante: VarianteBouton.secondaire,
                                onPressed: () => _editerExclusions(context, s)),
                        ],
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _bloc('Actes exclus', s['actesExclus']),
                              const SizedBox(height: 12),
                              _bloc('Produits exclus', s['produitsExclus']),
                              const SizedBox(height: 12),
                              _bloc('Soumis à accord préalable', s['accordPrealable']),
                            ])),
                  ]);
            }),
        pied: (fermer) => [
              if (c.droit.editer)
                BoutonSigh(
                    libelle: 'Modifier la grille',
                    icone: LucideIcons.percent,
                    variante: VarianteBouton.secondaire,
                    onPressed: () {
                      final s = c.magasin.collection('souscripteurs').parId(s0['id']) ?? s0;
                      _editerGrille(ctx, s);
                    }),
              BoutonSigh(
                  libelle: 'Imprimer la convention',
                  icone: LucideIcons.printer,
                  onPressed: () => _imprimer(ctx, s0)),
            ]);
  }

  // --- Saisie de la grille : le barème versé au dossier sert de MODÈLE (on le propose, on ne l'impose pas) -------------------------------

  List<ChampDef> _champsGrille(List<Object> libelles) => [
        for (var i = 0; i < libelles.length; i++) ...[
          ChampDef(
              nom: 'taux_$i',
              libelle: '${libelles[i]} — taux (%)',
              type: TypeChamp.nombre),
          ChampDef(
              nom: 'plafond_$i',
              libelle: 'Plafond (FCFA)',
              type: TypeChamp.nombre),
        ]
      ];

  void _proposerBareme(BuildContext ctx, Fiche s) {
    final g = AssBareme.garanties;
    final ctl = ControleurFormulaire(_champsGrille([for (final x in g) x['libelle']!]), {
      for (var i = 0; i < g.length; i++) ...{
        'taux_$i': '${g[i]['taux']}',
        'plafond_$i': g[i]['plafond'] == null ? '' : '${g[i]['plafond']}',
      }
    });
    afficherModale<void>(ctx,
        titre: 'Saisir la grille de ${s['nom']}',
        taille: TailleModale.xl,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NoteSigh(
              'Barème proposé d’après ${AssBareme.reference} (${AssBareme.lieu}, ${dateDe(AssBareme.date)}). Ce document est celui d’un régime employeur : il donne la structure, pas les taux de cette convention. Ajuster avant d’enregistrer.',
              ton: TonSigh.attention,
              icone: LucideIcons.circleHelp),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer la convention',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final lignes = assGarantiesDepuisBareme(s,
                        taux: [for (var i = 0; i < g.length; i++) v['taux_$i']],
                        plafonds: [for (var i = 0; i < g.length; i++) v['plafond_$i']]);
                    final cg = c.magasin.collection('garanties');
                    for (final l in lignes) {
                      cg.inserer(l, prefixe: 'GAR');
                    }
                    c.magasin
                        .collection('souscripteurs')
                        .mettreAJour(s['id'], assConventionSaisie());
                    fermer();
                    ToastsSigh.afficher(ctx, 'Convention de ${s['nom']} enregistrée.',
                        type: TypeToast.succes,
                        detail:
                            '${lignes.length} garanties, exclusions et accords préalables repris.');
                  }),
            ]);
  }

  void _editerGrille(BuildContext ctx, Fiche s) {
    final g = _garantiesDe(s['id']);
    if (g.isEmpty) {
      _proposerBareme(ctx, s);
      return;
    }
    final ctl = ControleurFormulaire(_champsGrille([for (final x in g) x['libelle']!]), {
      for (var i = 0; i < g.length; i++) ...{
        'taux_$i': '${g[i]['taux']}',
        'plafond_$i': g[i]['plafond'] == null ? '' : '${g[i]['plafond']}',
      }
    });
    afficherModale<void>(ctx,
        titre: 'Grille de ${s['nom']}',
        taille: TailleModale.xl,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final cg = c.magasin.collection('garanties');
                    for (var i = 0; i < g.length; i++) {
                      final p = '${v['plafond_$i'] ?? ''}'.trim();
                      cg.mettreAJour(g[i]['id'], {
                        'taux': num.tryParse('${v['taux_$i']}'.trim()) ?? 0,
                        'plafond': p.isEmpty ? null : (num.tryParse(p) ?? 0),
                      });
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Grille mise à jour.',
                        type: TypeToast.succes);
                  }),
            ]);
  }

  void _editerExclusions(BuildContext ctx, Fiche s) {
    final actes = [
      ...AssBareme.actesExclus,
      for (final a in actives(c, 'actes')) '${a['libelle']}'
    ];
    List<String> liste(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];
    final ctl = ControleurFormulaire([
      ChampDef(
          nom: 'actesExclus',
          libelle: 'Actes exclus',
          type: TypeChamp.multiselect,
          col: ColChamp.plein,
          options: [for (final x in {...actes}) OptionChamp(x)]),
      ChampDef(
          nom: 'produitsExclus',
          libelle: 'Produits exclus',
          type: TypeChamp.multiselect,
          col: ColChamp.plein,
          options: [for (final x in AssBareme.produitsExclus) OptionChamp(x)]),
      ChampDef(
          nom: 'accordPrealable',
          libelle: 'Soumis à accord préalable',
          type: TypeChamp.multiselect,
          col: ColChamp.plein,
          options: [for (final x in AssBareme.accordPrealable) OptionChamp(x)]),
    ], {
      'actesExclus': liste(s['actesExclus']),
      'produitsExclus': liste(s['produitsExclus']),
      'accordPrealable': liste(s['accordPrealable']),
    });
    afficherModale<void>(ctx,
        titre: 'Exclusions et accords — ${s['nom']}',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NoteSigh(
              'Une ligne exclue est facturée intégralement au patient, avec son motif. Un acte soumis à accord préalable l’est aussi tant que l’accord n’est pas obtenu.'),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    c.magasin.collection('souscripteurs').mettreAJour(s['id'], {
                      'actesExclus': liste(v['actesExclus']),
                      'produitsExclus': liste(v['produitsExclus']),
                      'accordPrealable': liste(v['accordPrealable']),
                    });
                    fermer();
                    ToastsSigh.afficher(ctx, 'Exclusions et accords enregistrés.',
                        type: TypeToast.succes);
                  }),
            ]);
  }

  void _imprimer(BuildContext ctx, Fiche s0) {
    final s = c.magasin.collection('souscripteurs').parId(s0['id']) ?? s0;
    final g = _garantiesDe(s['id']);
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Convention de prise en charge',
            sousTitre: '${s['nom']} — ${s['assureurNom']}',
            cartouche: [
              ('Compagnie', '${s['assureurNom']}'),
              ('N° de police', '${s['police']}'),
              ('Catégorie', '${s['categorie']}'),
              ('Assurés rattachés', nombre(_assuresDe(s['id']).length)),
              (
                'Validité',
                '${dateDe(s['dateDebut'])}${s['dateFin'] != null && '${s['dateFin']}'.isNotEmpty ? ' → ${dateDe(s['dateFin'])}' : ' → en cours'}'
              ),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            tableaux: g.isEmpty
                ? const []
                : [
                    TableauEtat(colonnes: [
                      ColonneEtat(libelle: 'Garantie', valeur: (x) => x['libelle']),
                      ColonneEtat(
                          libelle: 'Catégorie',
                          valeur: (x) => assLibelleCategorie(x['categorie'])),
                      ColonneEtat(
                          libelle: 'Taux', droite: true, valeur: (x) => '${x['taux']} %'),
                      ColonneEtat(
                          libelle: 'Plafond',
                          droite: true,
                          valeur: (x) => x['plafond'] == null ? '—' : m(x['plafond'])),
                      ColonneEtat(
                          libelle: 'Unité',
                          valeur: (x) => x['plafond'] == null
                              ? '—'
                              : assLibelleUnite(x['unitePlafond'])),
                    ], lignes: g)
                  ],
            signatures: [
              const Signature('Pour la clinique', nom: 'La Directrice Administrative'),
              Signature('Pour le souscripteur', nom: '${s['contact'] ?? ''}'),
            ]));
  }
}

// --- Simulateur de répartition ---------------------------------------------------------------------------------------------------

/// Le simulateur applique la CONVENTION RÉELLE de l'assuré choisi, ligne par ligne, avec ses taux, ses plafonds, ses exclusions et la validité de
/// sa carte (`repartir`, RG-09) : c'est exactement le calcul que la facturation appliquera.
class _Simulateur extends StatefulWidget {
  const _Simulateur({required this.c});
  final ContexteEcran c;

  @override
  State<_Simulateur> createState() => _EtatSimulateur();
}

class _EtatSimulateur extends State<_Simulateur> {
  late final ControleurFormulaire _patient;
  late final ControleurFormulaire _montants;
  late final List<Fiche> _assures;

  @override
  void initState() {
    super.initState();
    final c = widget.c;
    _assures = trierPar<Fiche>(assAssures(actives(c, 'patients')), (p) => p['nom']);
    _patient = ControleurFormulaire([
      ChampDef(
          nom: 'assure',
          libelle: 'Assuré',
          type: TypeChamp.select,
          col: ColChamp.plein,
          indicatif: '— Assuré —',
          options: [
            for (final p in _assures)
              OptionChamp('${p['id']}', '${p['nom']} ${p['prenom']}')
          ])
    ], {
      'assure': _assures.isEmpty ? '' : '${_assures.first['id']}'
    });
    _montants = ControleurFormulaire([
      for (var i = 0; i < assLignesSimulateur.length; i++)
        ChampDef(
            nom: 'm$i',
            libelle: '${assLignesSimulateur[i]['libelle']} (FCFA)',
            type: TypeChamp.nombre)
    ], {
      for (var i = 0; i < assLignesSimulateur.length; i++)
        'm$i': '${assLignesSimulateur[i]['montant']}'
    });
    _patient.addListener(_maj);
    _montants.addListener(_maj);
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _patient.dispose();
    _montants.dispose();
    super.dispose();
  }

  Widget _bloc(String libelle, String valeur, Color couleur) => Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(libelle,
                style: const TextStyle(
                    color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
            Text(valeur,
                style: TextStyle(
                    color: couleur,
                    fontSize: 16,
                    height: 24 / 16,
                    fontWeight: FontWeight.w600)),
          ]);

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final p = _assures.where((x) => '${x['id']}' == '${_patient['assure']}').firstOrNull;
    Widget resultat = const SizedBox();
    if (p != null) {
      final lignes = [
        for (var i = 0; i < assLignesSimulateur.length; i++)
          {
            'libelle': assLignesSimulateur[i]['libelle'],
            'categorie': assLignesSimulateur[i]['categorie'],
            'montant': num.tryParse('${_montants['m$i']}'.trim()) ?? 0,
          }
      ];
      final r = repartir(
          patient: p,
          lignes: lignes,
          date: iso(c.aujourdhui),
          couvertures: actives(c, 'couverturesAssurance'),
          souscripteurs: actives(c, 'souscripteurs'),
          garanties: actives(c, 'garanties'));
      final sous = actives(c, 'souscripteurs')
          .where((s) => s['id'] == r.souscripteurId)
          .firstOrNull;
      resultat = CarteSigh(
          titre: 'Répartition ligne par ligne',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DescListeSigh([
              ('Assuré', '${p['nom']} ${p['prenom']} (${p['code']})'),
              ('Compagnie', p['assureurNom'] ?? '—'),
              (
                'Souscripteur',
                sous != null ? '${sous['nom']} — ${sous['police']}' : 'non rattaché'
              ),
              (
                'Carte',
                r.carteValide
                    ? 'valide jusqu’au ${dateDe(p['carteExpiration'])}'
                    : 'NON VALIDE — expirée le ${dateDe(p['carteExpiration'])}'
              ),
              ('Convention', r.grilleSaisie ? 'saisie' : 'à collecter'),
            ]),
            const SizedBox(height: 12),
            MiniTableauSigh(colonnes: [
              ColonneMini('Prestation', (l) => '${l['libelle']}'),
              ColonneMini('Montant', (l) => m(l['montant']), droite: true),
              ColonneMini('Part assureur', (l) => m(l['partAssureur']), droite: true),
              ColonneMini('Part patient', (l) => m(l['partPatient']), droite: true),
              ColonneMini('Motif', (l) => '${l['motif']}',
                  rendu: (l) => Text('${l['motif']}',
                      style: TextStyle(
                          color: n(l['partAssureur']) > 0
                              ? JetonsShell.slate500
                              : JetonsShell.warning700,
                          fontSize: 12,
                          height: 16 / 12))),
            ], lignes: r.lignes),
            const SizedBox(height: 12),
            const Divider(height: 1, color: JetonsShell.slate200),
            const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.end, spacing: 24, children: [
              _bloc('Total', money(r.total), JetonsShell.slate800),
              _bloc('Part assureur', money(r.partAssureur), JetonsShell.info600),
              _bloc('Part patient', money(r.partPatient), JetonsShell.navy900),
            ]),
          ]));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const NoteSigh(
          'Le simulateur applique la convention réelle de l’assuré choisi, ligne par ligne, avec ses taux, ses plafonds, ses exclusions et la validité de sa carte. C’est exactement le calcul que la facturation appliquera.'),
      const SizedBox(height: 16),
      CarteSigh(titre: 'Assuré', child: FormulaireSigh(controleur: _patient)),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Lignes à simuler', child: FormulaireSigh(controleur: _montants)),
      const SizedBox(height: 16),
      resultat,
    ]);
  }
}
