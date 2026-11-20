import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun.dart';

/// Le geste « Mettre à jour la couverture » : la couverture en cours n'est PAS écrasée, elle est close à la veille de la date d'effet et reste
/// lisible sur les factures déjà émises. Même mécanisme que la grille des primes et les plages par lot de réactif.
List<ChampDef> champsCouverture(Fiche p, List<Fiche> assureurs) => [
      const ChampDef(
          nom: 'dateEffet',
          libelle: 'Date d’effet du changement',
          type: TypeChamp.date,
          requis: true,
          aide: 'La couverture précédente est close la veille de cette date.'),
      const ChampDef(
          nom: 'motif',
          libelle: 'Motif du changement',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [
            OptionChamp('Changement d’employeur'),
            OptionChamp('Changement de compagnie par l’assuré'),
            OptionChamp('Convention non reconduite'),
            OptionChamp('Renouvellement de carte'),
            OptionChamp('Changement de police'),
            OptionChamp('Fin de couverture — patient redevenu non assuré'),
            OptionChamp('Correction d’une saisie erronée'),
          ]),
      const ChampDef.section('Nouvelle couverture'),
      ChampDef(
          nom: 'assureur',
          libelle: 'Compagnie',
          type: TypeChamp.select,
          col: ColChamp.plein,
          options: [
            const OptionChamp('', '— Aucune : patient non assuré —'),
            for (final a in assureurs)
              OptionChamp('${a['code']}', '${a['code']} — ${a['nom']}')
          ]),
      const ChampDef(nom: 'numeroPolice', libelle: 'Numéro de police'),
      ChampDef(
          nom: 'categorieAssurance',
          libelle: 'Catégorie',
          type: TypeChamp.select,
          options: [
            for (final x in assCategoriesAssurance) OptionChamp(x.$1, x.$2)
          ]),
      const ChampDef(
          nom: 'tauxPriseEnCharge',
          libelle: 'Taux de prise en charge (%)',
          type: TypeChamp.nombre),
      const ChampDef(
          nom: 'carteExpiration',
          libelle: 'Expiration de la nouvelle carte',
          type: TypeChamp.date),
    ];

/// Applique le résultat de `assChangerCouverture` aux collections : la reprise du dossier ancien, la clôture, la nouvelle ligne, la fiche du dossier.
void appliquerChangement(ContexteEcran c, Fiche p, AssChangement r) {
  final cou = c.magasin.collection('couverturesAssurance');
  if (r.reprise != null) cou.inserer(r.reprise!, prefixe: 'COU');
  final f = r.fermer;
  if (f != null && f.id != null) cou.mettreAJour(f.id, {'fin': f.fin});
  cou.inserer(r.nouvelle!, prefixe: 'COU');
  c.magasin.collection('patients').mettreAJour(p['id'], r.majPatient!);
}

/// La modale de mise à jour de la couverture (écriture : appelée seulement si `droit.editer`).
void majCouverture(BuildContext ctx, Fiche p) {
  final c = ContexteEcran.of(ctx);
  final assureurs = actives(c, 'assureurs');
  final ctl = ControleurFormulaire(champsCouverture(p, assureurs), {
    'dateEffet': iso(c.aujourdhui),
    'assureur': p['assureur'] ?? '',
    'numeroPolice': p['numeroPolice'] ?? '',
    'categorieAssurance': p['categorieAssurance'] ?? 'entreprise',
    'tauxPriseEnCharge': '${p['tauxPriseEnCharge'] ?? 0}',
    'carteExpiration': p['carteExpiration'] ?? '',
  });
  afficherModale<void>(ctx,
      titre: 'Mettre à jour la couverture',
      sousTitre: '${p['nom']} ${p['prenom']} — ${p['code']}',
      taille: TailleModale.lg,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const NoteSigh(
            'La couverture actuelle n’est pas écrasée : elle est close à la veille de la date d’effet et reste lisible sur les factures déjà émises. C’est le même mécanisme que la grille des primes et les plages par lot de réactif.',
            icone: LucideIcons.history),
        const SizedBox(height: 12),
        FormulaireSigh(controleur: ctl),
      ]),
      pied: (fermer) => [
            BoutonSigh(
                libelle: 'Annuler',
                variante: VarianteBouton.secondaire,
                onPressed: fermer),
            BoutonSigh(
                libelle: 'Enregistrer le changement',
                icone: LucideIcons.save,
                onPressed: () {
                  final v = ctl.valider();
                  if (v == null) {
                    ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.',
                        type: TypeToast.erreur);
                    return;
                  }
                  final code = '${v['assureur'] ?? ''}';
                  final comp = assureurs.where((a) => a['code'] == code).firstOrNull;
                  final hist = actives(c, 'couverturesAssurance')
                      .where((x) => x['patientId'] == p['id'])
                      .toList();
                  final r = assChangerCouverture(
                      p,
                      hist,
                      {
                        'dateEffet': v['dateEffet'],
                        'motif': v['motif'],
                        'assureur': code.isEmpty ? null : code,
                        'assureurNom': comp?['nom'],
                        'numeroPolice': v['numeroPolice'],
                        'categorieAssurance': v['categorieAssurance'],
                        'tauxPriseEnCharge': v['tauxPriseEnCharge'],
                        'carteExpiration': v['carteExpiration'],
                        'souscripteurId': p['souscripteurId'],
                      },
                      c.aujourdhui);
                  if (!r.ok) {
                    ToastsSigh.afficher(ctx, r.motif!, type: TypeToast.erreur);
                    return;
                  }
                  appliquerChangement(c, p, r);
                  fermer();
                  ToastsSigh.afficher(ctx,
                      'Couverture mise à jour — l’historique conserve la précédente.',
                      type: TypeToast.succes);
                }),
          ]);
}

/// L'historique, tel qu'il se relit : la période, la compagnie, le motif.
Widget tableHistorique(ContexteEcran c, Fiche p) {
  final hist = trierPar<Fiche>(
      actives(c, 'couverturesAssurance')
          .where((x) => x['patientId'] == p['id'])
          .toList(),
      (x) => '${x['debut'] ?? '0000-00-00'}',
      descendant: true);
  if (hist.isEmpty) {
    return const NoteSigh(
        'Aucun changement enregistré : la couverture portée par le dossier vaut depuis son ouverture. L’historique commence au premier changement — il ne peut pas inventer une date d’effet que personne n’a saisie.',
        icone: LucideIcons.history);
  }
  return MiniTableauSigh(colonnes: [
    ColonneMini('Période', (x) {
      final d = x['debut'] != null && '${x['debut']}'.isNotEmpty
          ? 'Depuis le ${dateDe(x['debut'])}'
          : 'Depuis l’ouverture du dossier';
      final f = x['fin'] != null && '${x['fin']}'.isNotEmpty
          ? ' au ${dateDe(x['fin'])}'
          : ' — en cours';
      return d + f;
    }),
    ColonneMini('Compagnie', (x) => '',
        rendu: (x) => x['assureur'] != null && '${x['assureur']}'.isNotEmpty
            ? BadgeSigh('${x['assureurNom'] ?? x['assureur']}', ton: TonSigh.navy)
            : const BadgeSigh('Non assuré', ton: TonSigh.neutre)),
    ColonneMini('Police', (x) => '${x['numeroPolice'] ?? '—'}',
        rendu: (x) => monoTexte(x['numeroPolice'] ?? '—')),
    ColonneMini('Taux', (x) => '${x['tauxPriseEnCharge'] ?? 0} %', droite: true),
    ColonneMini('Carte jusqu’au',
        (x) => x['carteExpiration'] != null && '${x['carteExpiration']}'.isNotEmpty
            ? dateDe(x['carteExpiration'])
            : '—'),
    ColonneMini('Motif', (x) => '${x['motif'] ?? ''}'),
    ColonneMini('État', (x) => '',
        rendu: (x) => x['fin'] != null && '${x['fin']}'.isNotEmpty
            ? const BadgeSigh('Close', ton: TonSigh.neutre)
            : const BadgeSigh('En cours', ton: TonSigh.succes)),
  ], lignes: hist);
}

/// `m9-assures` — « Assurés & cartes » : fiche assuré, validité de la carte (RG-09), changement de couverture daté, attestation.
class EcranAssures extends StatelessWidget with EcranMaquette {
  const EcranAssures({super.key});

  @override
  String get titre => 'Assurés & cartes';

  @override
  String get description =>
      'Fiche assuré : compagnie, numéro de police, catégorie de carte, taux et date d’expiration.';

  @override
  String get regle =>
      'RG-09 — la prise en charge n’est appliquée que si la carte est valide au moment de la facturation. À défaut, la facturation est intégrale au patient.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecoute(c, [
        'assureurs',
        'patients',
        'factures',
        'couverturesAssurance'
      ]),
      builder: (context, _) {
        final assureurs = actives(c, 'assureurs');
        final rows = assAssures(actives(c, 'patients'));
        final fa = assFacturesAssurance(actives(c, 'factures'));
        final auj = c.aujourdhui;
        bool valide(Fiche p) => carteValideLe(c, p);
        final expirees = rows.where((p) => !valide(p)).toList();
        String nomCompagnie(Fiche p) =>
            '${p['assureurNom'] ?? assNomAssureur('${p['assureur']}', assureurs)}';

        void verifier(Fiche p) {
          final ok = valide(p);
          final mesF = trierPar<Fiche>(
              fa.where((f) => f['patientId'] == p['id']).toList(),
              (f) => f['date'],
              descendant: true);
          afficherTiroir<void>(context,
              titre: 'Vérification de carte',
              sousTitre: '${p['nom']} ${p['prenom']} — ${p['assureur']}',
              largeurMax: 672,
              corps: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: ok
                              ? JetonsShell.success50
                              : JetonsShell.danger50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: ok
                                  ? JetonsShell.success200
                                  : JetonsShell.danger200)),
                      child: Row(children: [
                        Icon(ok ? LucideIcons.shieldCheck : LucideIcons.shieldX,
                            size: 24,
                            color: ok
                                ? JetonsShell.success700
                                : JetonsShell.danger700),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(
                                  ok
                                      ? 'Carte valide — prise en charge applicable'
                                      : 'Carte expirée — prise en charge refusée',
                                  style: TextStyle(
                                      color: ok
                                          ? JetonsShell.success900
                                          : JetonsShell.danger900,
                                      fontSize: 14,
                                      height: 20 / 14,
                                      fontWeight: FontWeight.w600)),
                              Text(
                                  ok
                                      ? 'Taux applicable : ${p['tauxPriseEnCharge']} % — expire le ${dateDe(p['carteExpiration'])}'
                                      : 'Expirée depuis le ${dateDe(p['carteExpiration'])}. Facturation intégrale au patient (RG-09).',
                                  style: TextStyle(
                                      color: ok
                                          ? JetonsShell.success700
                                          : JetonsShell.danger700,
                                      fontSize: 12,
                                      height: 16 / 12)),
                            ])),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    DescListeSigh([
                      ('Bénéficiaire', '${p['nom']} ${p['prenom']}'),
                      ('Dossier', monoTexte(p['code'])),
                      (
                        'Date de naissance',
                        p['dateNaissance'] != null &&
                                '${p['dateNaissance']}'.isNotEmpty
                            ? dateDe(p['dateNaissance'])
                            : 'Inconnue — ${ageTexte(p, auj)}'
                      ),
                      ('Sexe', p['sexe'] == 'F' ? 'Féminin' : 'Masculin'),
                      ('Compagnie', nomCompagnie(p)),
                      ('Numéro de police', p['numeroPolice']),
                      (
                        'Taux de prise en charge',
                        '${p['tauxPriseEnCharge']} %'
                      ),
                      ('Date d’expiration', dateDe(p['carteExpiration'])),
                    ]),
                    const SizedBox(height: 16),
                    CarteSigh(
                        titre: 'Historique des couvertures',
                        child: tableHistorique(c, p)),
                    if (mesF.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      CarteSigh(
                          titre: 'Prises en charge accordées',
                          child: MiniTableauSigh(colonnes: [
                            ColonneMini('Facture', (f) => '${f['numero']}',
                                rendu: (f) => monoTexte(f['numero'])),
                            ColonneMini('Date', (f) => dateDe(f['date'])),
                            ColonneMini('Total', (f) => m(f['montantTTC']),
                                droite: true),
                            ColonneMini(
                                'Part assureur', (f) => m(f['partAssurance']),
                                droite: true),
                          ], lignes: mesF.take(10).toList())),
                    ],
                  ]),
              pied: (fermer) => [
                    if (c.droit.editer)
                      BoutonSigh(
                          libelle: 'Mettre à jour la couverture',
                          icone: LucideIcons.idCard,
                          variante: VarianteBouton.secondaire,
                          onPressed: () {
                            fermer();
                            majCouverture(context, p);
                          }),
                    BoutonSigh(
                        libelle: 'Attestation',
                        icone: LucideIcons.printer,
                        onPressed: () => attestation(context, p)),
                  ]);
        }

        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Assurés enregistrés',
                    valeur: nombre(rows.length),
                    icone: LucideIcons.idCard),
                KpiSigh(
                    libelle: 'Cartes valides',
                    valeur: nombre(rows.length - expirees.length),
                    icone: LucideIcons.shieldCheck,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Cartes expirées',
                    valeur: nombre(expirees.length),
                    indice: 'Facturation intégrale (RG-09)',
                    icone: LucideIcons.shieldAlert,
                    ton: TonSigh.danger),
                KpiSigh(
                    libelle: 'Taux moyen',
                    valeur: pourcent(rows.isEmpty
                        ? 0
                        : assSomme(rows, 'tauxPriseEnCharge') / rows.length),
                    icone: LucideIcons.percent,
                    ton: TonSigh.info),
              ]),
              if (expirees.isNotEmpty) ...[
                const SizedBox(height: 16),
                NoteSigh(
                    '${expirees.length} carte(s) expirée(s) — la caisse doit facturer intégralement ces patients jusqu’au renouvellement de leur carte.',
                    ton: TonSigh.danger,
                    icone: LucideIcons.shieldAlert),
              ],
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Fiches assurés',
                lignes: rows,
                taillePage: 15,
                nomExport: 'assures',
                alClicLigne: verifier,
                filtres: [
                  FiltreTableau(nom: 'assureur', libelle: 'Compagnie', options: [
                    for (final a in assureurs)
                      OptionChamp('${a['code']}', '${a['nom']}')
                  ]),
                  FiltreTableau(
                      nom: 'categorieAssurance',
                      libelle: 'Catégorie',
                      options: [
                        for (final x in assCategoriesAssurance)
                          OptionChamp(x.$1, x.$2)
                      ]),
                  FiltreTableau(
                      nom: 'validite',
                      libelle: 'Validité de la carte',
                      options: [
                        OptionChamp('valide', 'Cartes valides'),
                        OptionChamp('expiree', 'Cartes expirées')
                      ],
                      correspond: (p, v) => v == 'valide' ? valide(p) : !valide(p)),
                ],
                colonnes: [
                  ColonneTableau(
                      cle: 'code',
                      libelle: 'Dossier',
                      sansCoupure: true,
                      texte: (p) => '${p['code'] ?? ''}',
                      rendu: (_, p) => monoTexte(p['code'])),
                  ColonneTableau(
                      cle: 'nom',
                      libelle: 'Bénéficiaire',
                      valeur: (p) => '${p['nom']} ${p['prenom']}',
                      texte: (p) => '${p['nom']} ${p['prenom']}',
                      rendu: (_, p) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${p['nom']} ${p['prenom']}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: JetonsShell.slate800,
                                        fontSize: 14,
                                        height: 20 / 14,
                                        fontWeight: FontWeight.w500)),
                                Text(
                                    '${p['sexe'] == 'F' ? 'Femme' : 'Homme'} — né(e) le ${dateDe(p['dateNaissance'])}',
                                    style: const TextStyle(
                                        color: JetonsShell.slate400,
                                        fontSize: 12,
                                        height: 16 / 12)),
                              ])),
                  ColonneTableau(
                      cle: 'assureur',
                      libelle: 'Compagnie',
                      texte: nomCompagnie,
                      rendu: (_, p) =>
                          BadgeSigh('${p['assureur']}', ton: TonSigh.navy)),
                  ColonneTableau(
                      cle: 'souscripteur',
                      libelle: 'Souscripteur',
                      texte: (p) => '${p['souscripteur'] ?? ''}',
                      rendu: (_, p) => p['souscripteur'] == null ||
                              '${p['souscripteur']}'.isEmpty
                          ? const Text('non rattaché',
                              style: TextStyle(
                                  color: JetonsShell.warning600,
                                  fontSize: 12,
                                  height: 16 / 12))
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                  Text('${p['souscripteur']}',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: JetonsShell.slate700,
                                          fontSize: 14,
                                          height: 20 / 14)),
                                  Text('${p['numeroPolice'] ?? ''}',
                                      style: mono.copyWith(
                                          color: JetonsShell.slate400)),
                                ])),
                  ColonneTableau(
                      cle: 'categorieAssurance',
                      libelle: 'Catégorie',
                      texte: (p) => '${p['categorieAssurance'] ?? ''}',
                      rendu: (_, p) {
                        const mp = {
                          'entreprise': ('Entreprise', TonSigh.info),
                          'particulier': ('Particulier', TonSigh.neutre),
                          'personnel': ('Personnel', TonSigh.succes)
                        };
                        final x = mp['${p['categorieAssurance']}'];
                        return x == null
                            ? const Text('—',
                                style: TextStyle(
                                    color: JetonsShell.slate300,
                                    fontSize: 12,
                                    height: 16 / 12))
                            : BadgeSigh(x.$1, ton: x.$2);
                      }),
                  ColonneTableau(
                      cle: 'numeroPolice',
                      libelle: 'N° police',
                      sansCoupure: true,
                      texte: (p) => '${p['numeroPolice'] ?? ''}',
                      rendu: (_, p) => monoTexte(p['numeroPolice'])),
                  ColonneTableau(
                      cle: 'tauxPriseEnCharge',
                      libelle: 'Taux',
                      droite: true,
                      texte: (p) => '${p['tauxPriseEnCharge']} %',
                      rendu: (_, p) => Text('${p['tauxPriseEnCharge']} %',
                          style: const TextStyle(
                              color: JetonsShell.slate700,
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight: FontWeight.w600))),
                  ColonneTableau(
                      cle: 'carteExpiration',
                      libelle: 'Expiration',
                      sansCoupure: true,
                      texte: (p) => dateDe(p['carteExpiration'])),
                  ColonneTableau(
                      cle: 'validite',
                      libelle: 'Validité (RG-09)',
                      valeur: (p) => valide(p) ? 'valide' : 'expiree',
                      texte: (p) => valide(p) ? 'Valide' : 'Expirée',
                      rendu: (_, p) {
                        final t =
                            assValidite(p, valide: valide(p), auj: auj);
                        return badgeValidite(t, valide(p));
                      }),
                ],
                actionsLigne: (ctx, p) => [
                  BoutonSigh(
                      libelle: 'Vérifier la carte',
                      icone: LucideIcons.scanLine,
                      taille: TailleBouton.sm,
                      variante: VarianteBouton.secondaire,
                      onPressed: () => verifier(p)),
                  // Une commande d'ÉCRITURE se déclare comme telle : refusée, elle est ABSENTE et non grisée.
                  if (c.droit.editer)
                    BoutonIcone(
                        icone: LucideIcons.idCard,
                        libelle: 'Mettre à jour la couverture',
                        onPressed: () => majCouverture(context, p)),
                  BoutonIcone(
                      icone: LucideIcons.printer,
                      libelle: 'Attestation de prise en charge',
                      onPressed: () => attestation(context, p)),
                ],
              ),
            ]);
      },
    );
  }

  /// L'attestation de prise en charge (pièce A4) : la validité est lue au jour de l'édition.
  static void attestation(BuildContext ctx, Fiche p) {
    final c = ContexteEcran.of(ctx);
    final ok = carteValideLe(c, p);
    final nom = '${p['assureurNom'] ?? assNomAssureur('${p['assureur']}', actives(c, 'assureurs'))}';
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Attestation de prise en charge',
            sousTitre: nom,
            cartouche: [
              ('Bénéficiaire', '${p['nom']} ${p['prenom']}'),
              ('Dossier', '${p['code']}'),
              ('Âge', ageTexte(p, c.aujourdhui)),
              ('Compagnie', nom),
              ('N° police', '${p['numeroPolice']}'),
              ('Taux', '${p['tauxPriseEnCharge']} %'),
            ],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Rubrique', valeur: (r) => r['k']),
                ColonneEtat(libelle: 'Information', valeur: (r) => r['v']),
              ], lignes: [
                {'k': 'Compagnie d’assurance', 'v': nom},
                {'k': 'Numéro de police', 'v': p['numeroPolice']},
                {'k': 'Taux de prise en charge', 'v': '${p['tauxPriseEnCharge']} %'},
                {
                  'k': 'Date d’expiration de la carte',
                  'v': dateDe(p['carteExpiration'])
                },
                {
                  'k': 'Validité au ${dateFR(c.aujourdhui)}',
                  'v': ok ? 'CARTE VALIDE' : 'CARTE EXPIRÉE'
                },
              ]),
            ],
            blocs: [
              BlocTexte(
                  ok
                      ? 'La prise en charge est appliquée au taux ci-dessus pour les prestations réalisées jusqu’à la date d’expiration de la carte.'
                      : 'La carte étant expirée, aucune prise en charge ne peut être appliquée : la facturation est intégrale au patient (règle RG-09).',
                  italique: true),
            ],
            signatures: const [Signature('Le Caissier'), signDaf]));
  }
}
