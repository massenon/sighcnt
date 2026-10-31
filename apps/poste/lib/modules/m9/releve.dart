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
import 'commun.dart';

/// `m9-factures-assureur` — « Relevé & facture mensuelle assureur » : les deux pièces que la clinique émet réellement chaque mois et qui vont
/// ensemble. Le RELEVÉ détaille, souscripteur par souscripteur, ce qu'a consommé chaque patient ; la FACTURE MENSUELLE récapitule par souscripteur
/// et sert de demande de règlement. Deux vues du même mois : l'écran contrôle qu'elles se recoupent avant transmission.
///
/// Le sélecteur d'exercice de l'en-tête n'est pas porté : l'année est celle de l'horloge du poste.
class EcranReleveAssureur extends StatefulWidget with EcranMaquette {
  const EcranReleveAssureur({super.key});

  @override
  String get titre => 'Relevé & facture mensuelle assureur';

  @override
  String get description =>
      'Relevé détaillé des prestations par souscripteur et facture consolidée transmise à la compagnie.';

  @override
  String get regle =>
      'Deux pièces, une seule vérité : le relevé détaille patient par patient, la facture mensuelle récapitule par souscripteur. L’écran contrôle qu’elles se recoupent avant transmission. L’échange reste fondé sur l’édition de pièces — aucun interfaçage automatisé avec les systèmes des compagnies n’est au périmètre.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Conventions',
          icone: LucideIcons.fileSignature,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m9-conventions')),
      BoutonSigh(
          libelle: 'Créances',
          icone: LucideIcons.hourglass,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m9-creances')),
    ];
  }

  @override
  State<EcranReleveAssureur> createState() => _EtatReleve();
}

class _EtatReleve extends State<EcranReleveAssureur> {
  ControleurFormulaire? _compagnie, _mois;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_compagnie != null) return;
    final c = ContexteEcran.of(context);
    final annee = c.aujourdhui.year;
    final assureurs = actives(c, 'assureurs');
    _compagnie = champUnique(
        ChampDef(
            nom: 'compagnie',
            libelle: 'Compagnie',
            type: TypeChamp.select,
            col: ColChamp.plein,
            options: [
              for (final a in assureurs) OptionChamp('${a['code']}', '${a['nom']}')
            ]),
        assureurs.isEmpty ? '' : '${assureurs.first['code']}');
    _mois = champUnique(
        ChampDef(
            nom: 'mois',
            libelle: 'Mois',
            type: TypeChamp.select,
            col: ColChamp.plein,
            options: [
              for (var i = 0; i < 12; i++)
                OptionChamp('$i', moisAnnee(DateTime(annee, i + 1)))
            ]),
        '${c.aujourdhui.month - 1}');
    _compagnie!.addListener(_surChangement);
    _mois!.addListener(_surChangement);
  }

  void _surChangement() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_compagnie != null) {
      _compagnie!.removeListener(_surChangement);
      _mois!.removeListener(_surChangement);
      _compagnie!.dispose();
      _mois!.dispose();
    }
    super.dispose();
  }

  String get _code => '${_compagnie!['compagnie']}';
  int get _moisChoisi => int.tryParse('${_mois!['mois']}') ?? 0;

  List<AssGroupeSouscripteur> _groupes(ContexteEcran c) => assReleveSouscripteurs(
      facturesAssurance: assFacturesAssurance(actives(c, 'factures')),
      patients: actives(c, 'patients'),
      souscripteurs: actives(c, 'souscripteurs'),
      code: _code,
      mois: _moisChoisi,
      annee: c.aujourdhui.year);

  static String _mt(num v) => v != 0 ? m(v) : '—';

  // --- Éditions ----------------------------------------------------------------------------------------------------------

  void _imprimerReleve(BuildContext ctx, ContexteEcran c) {
    final groupes = _groupes(c);
    if (groupes.isEmpty) {
      ToastsSigh.afficher(ctx, 'Aucune prestation à relever sur ce mois.',
          type: TypeToast.attention);
      return;
    }
    final nomC = assNomAssureur(_code, actives(c, 'assureurs'));
    final periode = moisAnnee(DateTime(c.aujourdhui.year, _moisChoisi + 1));
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Relevé des prestations de la clinique',
            sousTitre: '$nomC — $periode',
            cartouche: [
              ('Compagnie', nomC),
              ('Période', periode),
              ('Souscripteurs', nombre(groupes.length)),
              (
                'Assurés',
                nombre(groupes.fold<int>(0, (a, g) => a + g.patients.length))
              ),
              ('Total facturé', money(groupes.fold<num>(0, (a, g) => a + g.total))),
              (
                'Part assureur',
                money(groupes.fold<num>(0, (a, g) => a + g.assureur))
              ),
            ],
            // Le relevé est la pièce opposée à la compagnie : ses totaux sont ceux de son propre détail (chaque colonne refait sa somme).
            blocs: [
              for (final g in groupes) ...[
                BlocTexte('${g.nom} — police ${g.police}', gras: true),
                BlocTableau(TableauEtat(colonnes: [
                  ColonneEtat(libelle: 'Dossier', valeur: (r) => r['patientCode']),
                  ColonneEtat(libelle: 'Patient', valeur: (r) => r['patient']),
                  ColonneEtat(
                      libelle: 'Dates',
                      valeur: (r) => ((r['dates'] as List).cast<String>()).join(', ')),
                  ColonneEtat(
                      libelle: 'Consultations',
                      droite: true,
                      valeur: (r) => n(r['consultation']) != 0 ? m(r['consultation']) : '',
                      somme: (r) => n(r['consultation'])),
                  ColonneEtat(
                      libelle: 'Analyses',
                      droite: true,
                      valeur: (r) => n(r['analyse']) != 0 ? m(r['analyse']) : '',
                      somme: (r) => n(r['analyse'])),
                  ColonneEtat(
                      libelle: 'Soins',
                      droite: true,
                      valeur: (r) => n(r['soin']) != 0 ? m(r['soin']) : '',
                      somme: (r) => n(r['soin'])),
                  ColonneEtat(
                      libelle: 'Total',
                      droite: true,
                      valeur: (r) => m(r['total']),
                      somme: (r) => n(r['total'])),
                  ColonneEtat(
                      libelle: 'Assuré',
                      droite: true,
                      valeur: (r) => m(r['assure']),
                      somme: (r) => n(r['assure'])),
                  ColonneEtat(
                      libelle: 'Assureur',
                      droite: true,
                      valeur: (r) => m(r['assureur']),
                      somme: (r) => n(r['assureur'])),
                ], lignes: [
                  for (final p in g.patients) _ligne(p)
                ], libelleTotal: 'TOTAL')),
              ],
            ],
            signatures: const [
              signDaf,
              Signature('Pour la compagnie', mention: 'Réception')
            ]));
  }

  static Fiche _ligne(AssLignePatient p) => {
        'patientCode': p.patientCode,
        'patient': p.patient,
        'dates': p.dates,
        'consultation': p.consultation,
        'analyse': p.analyse,
        'soin': p.soin,
        'total': p.total,
        'assure': p.assure,
        'assureur': p.assureur,
      };

  void _imprimerFacture(BuildContext ctx, ContexteEcran c) {
    final groupes = _groupes(c);
    if (groupes.isEmpty) {
      ToastsSigh.afficher(ctx, 'Aucune prestation à facturer sur ce mois.',
          type: TypeToast.attention);
      return;
    }
    final annee = c.aujourdhui.year;
    final nomC = assNomAssureur(_code, actives(c, 'assureurs'));
    final numero = assNumeroFactureMensuelle(groupes.length, _moisChoisi, annee);
    final totalAssureur = groupes.fold<num>(0, (a, g) => a + g.assureur);
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Facture — prestations de santé',
            sousTitre: '$numero — $nomC',
            cartouche: [
              ('Facture n°', numero),
              ('Compagnie', nomC),
              ('Période', moisAnnee(DateTime(annee, _moisChoisi + 1))),
              ('Souscripteurs', nombre(groupes.length)),
              (
                'Assurés concernés',
                nombre(groupes.fold<int>(0, (a, g) => a + g.patients.length))
              ),
              ('RCCM', IdentiteClinique.rccm),
            ],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Souscripteur', valeur: (g) => g['nom']),
                ColonneEtat(libelle: 'Police', valeur: (g) => g['police']),
                ColonneEtat(
                    libelle: 'Assurés',
                    droite: true,
                    valeur: (g) => '${g['nb']}',
                    somme: (g) => n(g['nb'])),
                ColonneEtat(
                    libelle: 'Consultations',
                    droite: true,
                    valeur: (g) => m(g['consultation']),
                    somme: (g) => n(g['consultation'])),
                ColonneEtat(
                    libelle: 'Analyses',
                    droite: true,
                    valeur: (g) => m(g['analyse']),
                    somme: (g) => n(g['analyse'])),
                ColonneEtat(
                    libelle: 'Soins',
                    droite: true,
                    valeur: (g) => m(g['soin']),
                    somme: (g) => n(g['soin'])),
                ColonneEtat(
                    libelle: 'Total',
                    droite: true,
                    valeur: (g) => m(g['total']),
                    somme: (g) => n(g['total'])),
                ColonneEtat(
                    libelle: 'Assuré',
                    droite: true,
                    valeur: (g) => m(g['assure']),
                    somme: (g) => n(g['assure'])),
                // La part assureur est le montant réclamé : elle se refait depuis les souscripteurs imprimés.
                ColonneEtat(
                    libelle: 'Assureur',
                    droite: true,
                    valeur: (g) => m(g['assureur']),
                    somme: (g) => n(g['assureur'])),
              ], lignes: [
                for (final g in groupes) _groupe(g)
              ])
            ],
            blocs: [
              BlocTexte(
                  '${IdentiteClinique.formuleArrete} : ${montantEnLettres(totalAssureur)}.',
                  gras: true),
              const BlocTexte(
                  'Le relevé détaillé des prestations, patient par patient, accompagne la présente facture.'),
            ],
            signatures: const [
              signDaf,
              Signature('Le Directeur Médical', nom: 'BASSONGUI Chabi Séko')
            ]));
  }

  static Fiche _groupe(AssGroupeSouscripteur g) => {
        'nom': g.nom,
        'police': g.police,
        'nb': g.patients.length,
        'consultation': g.consultation,
        'analyse': g.analyse,
        'soin': g.soin,
        'total': g.total,
        'assure': g.assure,
        'assureur': g.assureur,
      };

  // --- L'écran -----------------------------------------------------------------------------------------------------------

  Widget _tableauReleve(AssGroupeSouscripteur g) => TableauSigh(
        titre: '${g.nom} — police ${g.police}',
        lignes: [for (final p in g.patients) _ligne(p)],
        taillePage: 12,
        recherche: g.patients.length > 12,
        nomExport: 'releve-${g.id}',
        colonnes: [
          ColonneTableau(
              cle: 'patientCode',
              libelle: 'Dossier',
              sansCoupure: true,
              texte: (r) => '${r['patientCode']}',
              rendu: (_, r) => monoTexte(r['patientCode'])),
          const ColonneTableau(cle: 'patient', libelle: 'Patient'),
          ColonneTableau(
              cle: 'dates',
              libelle: 'Dates',
              sansCoupure: true,
              texte: (r) => ((r['dates'] as List).cast<String>()).join(', '),
              rendu: (_, r) {
                final d = (r['dates'] as List).cast<String>();
                return Text(
                    d.length > 2
                        ? '${d.take(2).join(', ')} +${d.length - 2}'
                        : d.join(', '),
                    style: const TextStyle(
                        color: JetonsShell.slate500, fontSize: 12, height: 16 / 12));
              }),
          for (final (cle, lib) in const [
            ('consultation', 'Consultations'),
            ('analyse', 'Analyses'),
            ('soin', 'Soins')
          ])
            ColonneTableau(
                cle: cle,
                libelle: lib,
                droite: true,
                texte: (r) => _mt(n(r[cle])),
                rendu: (_, r) => n(r[cle]) != 0
                    ? Text(m(r[cle]),
                        style: const TextStyle(
                            color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))
                    : const Text('—',
                        style: TextStyle(
                            color: JetonsShell.slate300, fontSize: 14, height: 20 / 14))),
          ColonneTableau(
              cle: 'total',
              libelle: 'Total',
              droite: true,
              texte: (r) => m(r['total']),
              rendu: (_, r) => Text(m(r['total']),
                  style: const TextStyle(
                      color: JetonsShell.slate800,
                      fontSize: 14,
                      height: 20 / 14,
                      fontWeight: FontWeight.w600))),
          ColonneTableau(
              cle: 'assure',
              libelle: 'Assuré',
              droite: true,
              texte: (r) => _mt(n(r['assure']))),
          ColonneTableau(
              cle: 'assureur',
              libelle: 'Assureur',
              droite: true,
              texte: (r) => m(r['assureur']),
              rendu: (_, r) => montantFort(n(r['assureur']))),
        ],
      );

  Widget _ongletReleve(List<AssGroupeSouscripteur> groupes) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const NoteSigh(
                'Un tableau par souscripteur, patient par patient, avec la date de consultation — structure du relevé réellement transmis aux compagnies.'),
            for (final g in groupes) ...[
              const SizedBox(height: 16),
              _tableauReleve(g),
            ],
          ]);

  Widget _ongletFacture(
      ContexteEcran c, List<AssGroupeSouscripteur> groupes) {
    final ecarts = assEcartsReleve(groupes);
    final nomC = assNomAssureur(_code, actives(c, 'assureurs'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ecarts.isNotEmpty
          ? NoteSigh(
              '${ecarts.length} souscripteur(s) en écart entre le relevé et la facture : ${ecarts.map((g) => g.nom).join(', ')}. Ne pas transmettre avant correction.',
              ton: TonSigh.danger,
              icone: LucideIcons.triangleAlert)
          : NoteSigh(
              'Relevé et facture se recoupent pour les ${groupes.length} souscripteur(s) du mois : ventilation, total et répartition concordent. La pièce peut être transmise.',
              ton: TonSigh.succes,
              icone: LucideIcons.checkCircle2),
      const SizedBox(height: 16),
      TableauSigh(
        titre:
            'Facture mensuelle — $nomC, ${moisAnnee(DateTime(c.aujourdhui.year, _moisChoisi + 1))}',
        lignes: [for (final g in groupes) {'id': g.id, ..._groupe(g)}],
        taillePage: 20,
        nomExport: 'facture-mensuelle',
        colonnes: [
          ColonneTableau(
              cle: 'nom',
              libelle: 'Souscripteur',
              texte: (g) => '${g['nom']} ${g['police']}',
              rendu: (_, g) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${g['nom']}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: JetonsShell.slate800,
                                fontSize: 14,
                                height: 20 / 14,
                                fontWeight: FontWeight.w500)),
                        Text('${g['police']}',
                            style: mono.copyWith(color: JetonsShell.slate400)),
                      ])),
          const ColonneTableau(cle: 'nb', libelle: 'Assurés', droite: true),
          for (final (cle, lib) in const [
            ('consultation', 'Consultations'),
            ('analyse', 'Analyses'),
            ('soin', 'Soins')
          ])
            ColonneTableau(
                cle: cle,
                libelle: lib,
                droite: true,
                texte: (g) => m(g[cle])),
          ColonneTableau(
              cle: 'total',
              libelle: 'Total',
              droite: true,
              texte: (g) => m(g['total']),
              rendu: (_, g) => Text(m(g['total']),
                  style: const TextStyle(
                      color: JetonsShell.slate800,
                      fontSize: 14,
                      height: 20 / 14,
                      fontWeight: FontWeight.w600))),
          ColonneTableau(
              cle: 'assure',
              libelle: 'Assuré',
              droite: true,
              texte: (g) => m(g['assure'])),
          ColonneTableau(
              cle: 'assureur',
              libelle: 'Assureur',
              droite: true,
              texte: (g) => m(g['assureur']),
              rendu: (_, g) => montantFort(n(g['assureur']))),
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecoute(c, ['assureurs', 'patients', 'factures', 'souscripteurs']),
      builder: (context, _) {
        final groupes = _groupes(c);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CarteSigh(
                  child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                    commande(_compagnie!, largeur: 280),
                    commande(_mois!, largeur: 200),
                    BoutonSigh(
                        libelle: 'Éditer le relevé',
                        icone: LucideIcons.printer,
                        variante: VarianteBouton.secondaire,
                        onPressed: () => _imprimerReleve(context, c)),
                    BoutonSigh(
                        libelle: 'Éditer la facture mensuelle',
                        icone: LucideIcons.fileText,
                        onPressed: () => _imprimerFacture(context, c)),
                  ])),
              const SizedBox(height: 16),
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Souscripteurs du mois',
                    valeur: nombre(groupes.length),
                    icone: LucideIcons.fileSignature),
                KpiSigh(
                    libelle: 'Assurés concernés',
                    valeur: nombre(groupes.fold<int>(0, (a, g) => a + g.patients.length)),
                    icone: LucideIcons.users,
                    ton: TonSigh.info),
                KpiSigh(
                    libelle: 'Montant total facturé',
                    valeur: money(groupes.fold<num>(0, (a, g) => a + g.total)),
                    icone: LucideIcons.calculator,
                    ton: TonSigh.neutre),
                KpiSigh(
                    libelle: 'Réclamé à la compagnie',
                    valeur: money(groupes.fold<num>(0, (a, g) => a + g.assureur)),
                    icone: LucideIcons.handCoins,
                    ton: TonSigh.attention),
              ]),
              const SizedBox(height: 16),
              if (groupes.isEmpty)
                const VideSigh(
                    'Aucune prestation assurée pour cette compagnie sur le mois choisi.',
                    icone: LucideIcons.files)
              else
                OngletsSigh(onglets: [
                  OngletDef(
                      id: 'releve',
                      libelle: 'Relevé des prestations',
                      compte: groupes.length,
                      construire: (_) => _ongletReleve(groupes)),
                  OngletDef(
                      id: 'facture',
                      libelle: 'Facture mensuelle',
                      construire: (_) => _ongletFacture(c, groupes)),
                ]),
            ]);
      },
    );
  }
}
