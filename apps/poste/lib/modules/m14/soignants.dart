import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// `m14-soignants` — « Prescripteurs & exécutants de soins » : qui prescrit, qui exécute les soins, et dans quels secteurs.
///
/// LES FICHES SONT DÉRIVÉES DU PERSONNEL, jamais ressaisies : une seconde liste de noms divergerait du dossier RH au premier recrutement. La fiche ne
/// porte que ce que le dossier RH ne dit pas. DEUX DROITS DISTINCTS sur une même fiche (`prescrit`, `execute`) parce que la sage-femme les cumule.
/// Le contrôle de qui peut prescrire ou exécuter est appliqué par le moteur de parcours (ordonnances, soins), pas par cet écran.
class EcranSoignants extends StatelessWidget with EcranMaquette {
  const EcranSoignants({super.key});

  @override
  String get description => 'Qui prescrit, qui exécute les soins, et dans quels secteurs.';

  @override
  String get regle =>
      'Seuls médecins et sages-femmes prescrivent ; seuls infirmiers et sages-femmes exécutent les soins. La sage-femme cumule les deux. Le contrôle est appliqué par le moteur de parcours et non par l’écran : une prescription venue d’ailleurs serait refusée de la même façon.';

  @override
  Widget build(BuildContext context) => const _VueSoignants();
}

class _VueSoignants extends StatefulWidget {
  const _VueSoignants();
  @override
  State<_VueSoignants> createState() => _VueSoignantsState();
}

class _VueSoignantsState extends State<_VueSoignants> {
  CollectionMagasin? _col;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final col = ContexteEcran.of(context).magasin.collection('soignants');
    if (!identical(col, _col)) {
      _col?.removeListener(_maj);
      _col = col..addListener(_maj);
    }
  }

  @override
  void dispose() {
    _col?.removeListener(_maj);
    super.dispose();
  }

  void _maj() => setState(() {});

  List<ChampDef> _champs(Magasin m) => [
        ChampDef(
            nom: 'personnelId',
            libelle: 'Agent',
            type: TypeChamp.select,
            requis: true,
            aide: 'La fiche est dérivée du dossier RH : le nom ne se ressaisit pas ici.',
            options: [
              for (final a in m.collection('personnel').actives)
                OptionChamp('${a['id']}',
                    '${a['nomComplet']} — ${a['poste'] ?? a['fonction']}')
            ]),
        ChampDef(
            nom: 'qualite',
            libelle: 'Qualité',
            type: TypeChamp.select,
            requis: true,
            options: [for (final q in secQualitesSoignant) OptionChamp('${q['code']}', '${q['label']}')]),
        const ChampDef(nom: 'prescrit', libelle: 'Habilité à prescrire', type: TypeChamp.case_),
        const ChampDef(nom: 'execute', libelle: 'Habilité à exécuter les soins', type: TypeChamp.case_),
        const ChampDef(
            nom: 'supervise',
            libelle: 'Supervise les soins sans les exécuter',
            type: TypeChamp.case_,
            aide: 'C’est le rôle de l’Infirmier Général, tel que sa description de poste le définit.'),
        ChampDef(
            nom: 'secteurs',
            libelle: 'Secteurs d’exercice',
            type: TypeChamp.multiselect,
            requis: true,
            options: [for (final s in secSecteursSoins) OptionChamp('${s['code']}', '${s['label']}')]),
      ];

  /// `K.creer` : « Habiliter un soignant » ; le formulaire en erreur ne dit que « Le formulaire comporte des erreurs. ».
  void _creer(BuildContext ctx) {
    final c = ContexteEcran.of(ctx);
    final m = c.magasin;
    final champs = _champs(m);
    final ctl = ControleurFormulaire(champs, const {});
    afficherModale<void>(ctx,
        titre: 'Habiliter un soignant',
        sousTitre: 'Les champs marqués d’un astérisque sont obligatoires.',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Créer',
                  icone: LucideIcons.plus,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.',
                          type: TypeToast.erreur);
                      return;
                    }
                    final agent = m.collection('personnel').parId(v['personnelId']);
                    final r = m.collection('soignants').inserer(
                        secTransformerSoignant(v, agent)..['statut'] = 'actif',
                        prefixe: 'SOI');
                    fermer();
                    ToastsSigh.afficher(ctx, 'Soignant créé.',
                        type: TypeToast.succes,
                        annuler: r.annuler,
                        messageAnnulation: 'Création annulée — la fiche est archivée.');
                  }),
            ]);
  }

  /// `modifier()` de `K.actionsLigne` : la fiche s'écrit telle que saisie (le nom et le poste ne sont pas re-dérivés à la modification).
  void _modifier(BuildContext ctx, Fiche r) {
    final m = ContexteEcran.of(ctx).magasin;
    final champs = _champs(m);
    final ctl = ControleurFormulaire(champs, {
      for (final c in champs)
        if (c.nom.isNotEmpty)
          c.nom: c.type == TypeChamp.case_
              ? r[c.nom] == true
              : (c.type == TypeChamp.multiselect
                  ? [for (final x in (r[c.nom] as List? ?? const [])) '$x']
                  : '${r[c.nom] ?? ''}'),
    });
    afficherModale<void>(ctx,
        titre: 'Modifier l’enregistrement',
        sousTitre: '${r['id']}',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.',
                          type: TypeToast.erreur);
                      return;
                    }
                    final annuler = m.collection('soignants').mettreAJour(r['id'], v);
                    fermer();
                    ToastsSigh.afficher(ctx, 'Modifications enregistrées.',
                        type: TypeToast.succes, annuler: annuler);
                  }),
            ]);
  }

  Future<void> _archiver(BuildContext ctx, Fiche r) async {
    final m = ContexteEcran.of(ctx).magasin;
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Archiver cet enregistrement ?',
        message: 'Archivage logique (RG-14) : la donnée reste consultable et l’opération est annulable.',
        libelleOk: 'Archiver',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    final annuler = m.collection('soignants').archiver(r['id']);
    m.journaliser('Motif d’archivage', 'M14', 'soignant', '${r['id']}', null, {'motif': motif});
    ToastsSigh.afficher(ctx, 'Enregistrement archivé.',
        type: TypeToast.succes, annuler: annuler, messageAnnulation: 'Archivage annulé.');
  }

  void _detail(BuildContext ctx, Fiche r) {
    final q = secQualite(r['qualite']);
    afficherTiroir<void>(ctx,
        titre: '${r['nomComplet']}',
        largeurMax: 672,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Agent', r['nomComplet']),
            ('Poste', r['poste'] ?? '—'),
            ('Qualité', q != null ? q['label'] : r['qualite']),
            ('Prescrit', secVrai(r['prescrit']) ? 'Oui' : 'Non'),
            ('Exécute les soins', secVrai(r['execute']) ? 'Oui' : 'Non'),
            ('Supervise', secVrai(r['supervise']) ? 'Oui' : 'Non'),
            ('Réalise l’imagerie', secVrai(r['realiseImagerie']) ? 'Oui' : 'Non'),
            ('Origine de la fiche', r['source'] ?? '—'),
          ]),
          if (q != null) ...[
            const SizedBox(height: 16),
            NoteSigh('${q['note']}', ton: TonSigh.info),
          ],
        ]));
  }

  Widget _tableau(BuildContext ctx, List<Fiche> rows) {
    final c = ContexteEcran.of(ctx);
    final tries = [...rows]
      ..sort((a, b) => '${a['nomComplet']}'.compareTo('${b['nomComplet']}'));
    Widget oui(Object? v) => secVrai(v)
        ? const BadgeSigh('Oui', ton: TonSigh.succes)
        : const BadgeSigh('Non');
    return TableauSigh(
      lignes: tries,
      recherche: false,
      messageVide: 'Aucun soignant enregistré.',
      nomExport: 'soignants',
      actions: [
        if (c.droit.editer)
          BoutonSigh(
              libelle: 'Nouveau soignant',
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              onPressed: () => _creer(ctx)),
      ],
      colonnes: [
        const ColonneTableau(cle: 'nomComplet', libelle: 'Agent'),
        const ColonneTableau(cle: 'poste', libelle: 'Poste'),
        ColonneTableau(
            cle: 'qualite',
            libelle: 'Qualité',
            texte: (r) => '${secQualite(r['qualite'])?['label'] ?? r['qualite'] ?? ''}'),
        ColonneTableau(
            cle: 'prescrit',
            libelle: 'Prescrit',
            texte: (r) => secVrai(r['prescrit']) ? 'Oui' : 'Non',
            rendu: (_, r) => oui(r['prescrit'])),
        ColonneTableau(
            cle: 'execute',
            libelle: 'Exécute',
            texte: (r) => secVrai(r['execute']) ? 'Oui' : 'Non',
            rendu: (_, r) => oui(r['execute'])),
        ColonneTableau(
            cle: 'secteurs', libelle: 'Secteurs', texte: (r) => secSecteursEnTexte(r['secteurs'])),
      ],
      actionsLigne: (context, r) => [
        BoutonIcone(
            icone: LucideIcons.eye, libelle: 'Consulter', onPressed: () => _detail(ctx, r)),
        if (c.droit.editer)
          BoutonIcone(
              icone: LucideIcons.pencil, libelle: 'Modifier', onPressed: () => _modifier(ctx, r)),
        if (c.droit.annuler)
          BoutonIcone(
              icone: LucideIcons.archive, libelle: 'Archiver', onPressed: () => _archiver(ctx, r)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _col!.actives;
    final presc = rows.where((x) => secVrai(x['prescrit'])).toList();
    final exec = rows.where((x) => secVrai(x['execute'])).toList();
    final k = secCompteSoignants(rows);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        KpiSigh(
            libelle: 'Soignants',
            valeur: nombre(k.total),
            icone: LucideIcons.usersRound,
            ton: TonSigh.navy),
        KpiSigh(
            libelle: 'Prescripteurs',
            valeur: nombre(k.prescripteurs),
            icone: LucideIcons.clipboardPlus,
            ton: TonSigh.info,
            indice: 'médecins et sages-femmes'),
        KpiSigh(
            libelle: 'Exécutants de soins',
            valeur: nombre(k.executants),
            icone: LucideIcons.syringe,
            ton: TonSigh.succes,
            indice: 'infirmiers et sages-femmes'),
        KpiSigh(
            libelle: 'Cumulent les deux',
            valeur: nombre(k.cumul),
            icone: LucideIcons.shuffle,
            ton: TonSigh.neutre,
            indice: 'les sages-femmes'),
      ]),
      const SizedBox(height: 16),
      const NoteSigh(
          'Les effectifs énoncés par la Direction — 3 médecins, 3 sages-femmes, 7 infirmiers — se retrouvent exactement dès lors qu’on met à part les deux agents qui ne sont ni prescripteurs ni exécutants : l’Infirmier — Surveillant Général, qui supervise les soins (c’est l’IG de la description de poste du 26/10/2023), et l’Échographiste, qui réalise des examens sans prescrire.',
          ton: TonSigh.info,
          icone: LucideIcons.users),
      const SizedBox(height: 16),
      OngletsSigh(onglets: [
        OngletDef(
            id: 'tous',
            libelle: 'Tous',
            compte: rows.length,
            construire: (ctx) => _tableau(ctx, rows)),
        OngletDef(
            id: 'prescripteurs',
            libelle: 'Prescripteurs',
            compte: presc.length,
            construire: (ctx) => _tableau(ctx, presc)),
        OngletDef(
            id: 'executants',
            libelle: 'Exécutants',
            compte: exec.length,
            construire: (ctx) => _tableau(ctx, exec)),
      ]),
    ]);
  }
}
