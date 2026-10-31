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

/// Le formulaire « Nouveau » / « Modifier » (`cfg.fields`).
final champsCompagnie = <ChampDef>[
  const ChampDef(nom: 'code', libelle: 'Code', requis: true),
  const ChampDef(
      nom: 'nom', libelle: 'Raison sociale', requis: true, col: ColChamp.plein),
  const ChampDef(
      nom: 'email', libelle: 'Adresse électronique', type: TypeChamp.email),
  ChampDef(
      nom: 'convention',
      libelle: 'État de la convention',
      type: TypeChamp.select,
      options: [for (final x in assConventions) OptionChamp(x)]),
  const ChampDef(nom: 'contact', libelle: 'Personne de contact'),
  const ChampDef(
      nom: 'observations',
      libelle: 'Observations',
      type: TypeChamp.textarea,
      lignes: 2,
      col: ColChamp.plein),
];

/// `m9-compagnies` — « Compagnies d’assurance partenaires » : référentiel, convention, assurés et créances (calculés, jamais saisis).
class EcranCompagnies extends StatelessWidget with EcranMaquette {
  const EcranCompagnies({super.key});

  @override
  String get titre => 'Compagnies d’assurance partenaires';

  @override
  String get description =>
      'Référentiel des compagnies conventionnées avec la clinique : coordonnées, convention, assurés et créances.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecoute(c, ['patients', 'factures', 'couverturesAssurance']),
      builder: (context, _) {
        final assures = assAssures(actives(c, 'patients'));
        final fa = assFacturesAssurance(actives(c, 'factures'));
        final auj = c.aujourdhui;
        num creance(Fiche a) => assCreance(fa, '${a['code']}');
        int nbAssures(Fiche a) =>
            assures.where((p) => p['assureur'] == a['code']).length;

        bool filtre(String nom, Fiche a, String v) => assFiltreCompagnie(
            nom, v, a,
            assures: assures,
            facturesAssurance: fa,
            carteValide: (p) => carteValideLe(c, p),
            auj: auj);

        return CrudFormulaireSigh(
          collection: c.magasin.collection('assureurs'),
          entite: 'compagnie',
          entiteP: 'compagnies',
          prefixeId: 'ASS',
          triInitial: 'n',
          taillePage: 15,
          provenance:
              'Liste et contacts des assurances partenaires de la Clinique NASSIERA TOO.',
          champs: champsCompagnie,
          valeursCreation: const {'convention': 'Signée'},
          versFiche: _versFiche,
          colonnes: [
            const ColonneTableau(
                cle: 'n', libelle: 'N°', droite: true, sansCoupure: true),
            ColonneTableau(
                cle: 'code',
                libelle: 'Code',
                sansCoupure: true,
                texte: (a) => '${a['code'] ?? ''}',
                rendu: (_, a) => Text('${a['code'] ?? ''}',
                    style: mono.copyWith(
                        color: JetonsShell.navy800,
                        fontWeight: FontWeight.w600))),
            const ColonneTableau(cle: 'nom', libelle: 'Compagnie'),
            ColonneTableau(
                cle: 'tel',
                libelle: 'Téléphones',
                texte: (a) => ((a['tel'] as List?) ?? const []).join(' / '),
                rendu: (_, a) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final t in (a['tel'] as List?) ?? const [])
                        Text('$t',
                            style: mono.copyWith(color: JetonsShell.slate600))
                    ])),
            ColonneTableau(
                cle: 'email',
                libelle: 'Adresse électronique',
                texte: (a) => '${a['email'] ?? ''}',
                rendu: (_, a) => Text('${a['email'] ?? ''}',
                    style: const TextStyle(
                        color: JetonsShell.slate600,
                        fontSize: 12,
                        height: 16 / 12))),
            ColonneTableau(
                cle: 'convention',
                libelle: 'Convention',
                texte: (a) => assConvention(a),
                rendu: (_, a) =>
                    BadgeSigh(assConvention(a), ton: TonSigh.succes)),
            ColonneTableau(
                cle: 'nbAssures',
                libelle: 'Assurés',
                droite: true,
                valeur: nbAssures,
                texte: (a) => '${nbAssures(a)}'),
            ColonneTableau(
                cle: 'creance',
                libelle: 'Créances',
                droite: true,
                valeur: creance,
                texte: (a) => money(creance(a), avecDevise: false),
                rendu: (_, a) => creance(a) > 0
                    ? montantFort(creance(a))
                    : tiret()),
          ],
          filtres: [
            FiltreTableau(
                nom: 'convention',
                libelle: 'Convention',
                options: [for (final x in assConventions) OptionChamp(x)],
                correspond: (a, v) => filtre('convention', a, v)),
            FiltreTableau(
                nom: 'creanceEtat',
                libelle: 'Créances',
                options: [
                  OptionChamp('avec', 'Avec créance ouverte'),
                  OptionChamp('sans', 'Sans créance'),
                  OptionChamp('grosse', 'Créance > 500 000 F'),
                ],
                correspond: (a, v) => filtre('creanceEtat', a, v)),
            FiltreTableau(
                nom: 'anciennete',
                libelle: 'Ancienneté de la dette',
                options: [
                  OptionChamp('plus90', 'Au-delà de 90 jours'),
                  OptionChamp('30a90', 'De 30 à 90 jours'),
                  OptionChamp('moins30', 'Moins de 30 jours'),
                ],
                correspond: (a, v) => filtre('anciennete', a, v)),
            FiltreTableau(
                nom: 'portefeuille',
                libelle: 'Portefeuille d’assurés',
                options: [
                  OptionChamp('aucun', 'Aucun assuré rattaché'),
                  OptionChamp('petit', '1 à 9 assurés'),
                  OptionChamp('grand', '10 assurés et plus'),
                ],
                correspond: (a, v) => filtre('portefeuille', a, v)),
            FiltreTableau(
                nom: 'carte',
                libelle: 'Cartes des assurés',
                options: [
                  OptionChamp('expiree', 'Au moins une carte expirée'),
                  OptionChamp('toutes', 'Toutes les cartes valides'),
                ],
                correspond: (a, v) => filtre('carte', a, v)),
          ],
          kpis: (rows) => [
            KpiSigh(
                libelle: 'Compagnies partenaires',
                valeur: nombre(rows.length),
                icone: LucideIcons.building2),
            KpiSigh(
                libelle: 'Conventions actives',
                valeur: nombre(
                    rows.where((a) => assConvention(a) == 'Signée').length),
                icone: LucideIcons.fileCheck2,
                ton: TonSigh.succes),
            KpiSigh(
                libelle: 'Assurés couverts',
                valeur: nombre(assures.length),
                icone: LucideIcons.users,
                ton: TonSigh.info),
            KpiSigh(
                libelle: 'Créances totales',
                valeur: money(rows.fold<num>(0, (s, a) => s + creance(a))),
                icone: LucideIcons.handCoins,
                ton: TonSigh.attention),
          ],
          titreDetail: (a) => '${a['code']}',
          sousTitreDetail: (a) => '${a['nom']}',
          detail: (a) => _detail(c, a, assures, fa),
          etat: (ctx, a) {
            final e = ContexteEcran.of(ctx);
            final mes = assures.where((p) => p['assureur'] == a['code']).toList();
            afficherApercu(
                ctx,
                pieceM9(e,
                    titre: 'Fiche compagnie d’assurance',
                    sousTitre: '${a['nom']}',
                    cartouche: [
                      ('Code', '${a['code']}'),
                      ('Raison sociale', '${a['nom']}'),
                      ('Téléphones', ((a['tel'] as List?) ?? const []).join(' / ')),
                      ('Courriel', '${a['email'] ?? ''}'),
                      ('Convention', assConvention(a)),
                      ('Assurés', nombre(mes.length)),
                    ],
                    tableaux: mes.isEmpty
                        ? const []
                        : [
                            TableauEtat(colonnes: [
                              ColonneEtat(
                                  libelle: 'Dossier', valeur: (p) => p['code']),
                              ColonneEtat(
                                  libelle: 'Assuré',
                                  valeur: (p) => '${p['nom']} ${p['prenom']}'),
                              ColonneEtat(
                                  libelle: 'N° police',
                                  valeur: (p) => p['numeroPolice']),
                              ColonneEtat(
                                  libelle: 'Taux',
                                  droite: true,
                                  valeur: (p) => '${p['tauxPriseEnCharge']} %'),
                              ColonneEtat(
                                  libelle: 'Expiration',
                                  valeur: (p) => dateDe(p['carteExpiration'])),
                            ], lignes: mes)
                          ],
                    blocs: mes.isEmpty
                        ? const [BlocTexte('Aucun assuré rattaché.', italique: true)]
                        : const [],
                    signatures: const [signDaf]));
          },
        );
      },
    );
  }

  /// `transform` : les champs saisis ; le téléphone et le numéro d'ordre déjà portés par la fiche ne sont pas touchés (le formulaire ne les porte pas).
  static Fiche _versFiche(Map<String, Object?> s) => {
        'code': s['code'],
        'nom': s['nom'],
        'email': s['email'] ?? '',
        'convention': s['convention'] ?? '',
        'contact': s['contact'] ?? '',
        'observations': s['observations'] ?? '',
      };

  /// La fiche en tiroir : deux KPI, puis trois onglets (coordonnées, assurés, factures).
  static Widget _detail(
      ContexteEcran c, Fiche a, List<Fiche> assures, List<Fiche> fa) {
    final mes = assures.where((p) => p['assureur'] == a['code']).toList();
    final mesF = fa.where((f) => f['assureur'] == a['code']).toList();
    final facturesTriees =
        trierPar<Fiche>(mesF, (f) => f['date'], descendant: true);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(colonnes: 2, kpis: [
        KpiSigh(
            libelle: 'Assurés',
            valeur: nombre(mes.length),
            icone: LucideIcons.users),
        KpiSigh(
            libelle: 'Créances',
            valeur: money(assCreance(fa, '${a['code']}')),
            icone: LucideIcons.handCoins,
            ton: TonSigh.attention),
      ]),
      const SizedBox(height: 16),
      OngletsSigh(onglets: [
        OngletDef(
            id: 'infos',
            libelle: 'Coordonnées',
            construire: (_) => DescListeSigh([
                  ('Code', a['code']),
                  ('Raison sociale', a['nom']),
                  ('Téléphones', ((a['tel'] as List?) ?? const []).join(' / ')),
                  ('Adresse électronique', a['email']),
                  ('Convention',
                      BadgeSigh(assConvention(a), ton: TonSigh.succes)),
                  ('Personne de contact', a['contact'] ?? '—'),
                ])),
        OngletDef(
            id: 'assures',
            libelle: 'Assurés',
            compte: mes.length,
            construire: (_) => mes.isEmpty
                ? const VideSigh('Aucun assuré rattaché à cette compagnie.',
                    icone: LucideIcons.users)
                : MiniTableauSigh(colonnes: [
                    ColonneMini('Dossier', (p) => '${p['code']}',
                        rendu: (p) => monoTexte(p['code'])),
                    ColonneMini('Assuré', (p) => '${p['nom']} ${p['prenom']}'),
                    ColonneMini('Police', (p) => '${p['numeroPolice'] ?? ''}'),
                    ColonneMini('Taux', (p) => '${p['tauxPriseEnCharge']} %',
                        droite: true),
                    ColonneMini('Carte', (p) => '',
                        rendu: (p) => carteValideLe(c, p)
                            ? const BadgeSigh('Valide', ton: TonSigh.succes)
                            : const BadgeSigh('Expirée', ton: TonSigh.danger)),
                  ], lignes: mes.take(25).toList())),
        OngletDef(
            id: 'factures',
            libelle: 'Factures',
            compte: mesF.length,
            construire: (_) => mesF.isEmpty
                ? const VideSigh('Aucune facture avec prise en charge.',
                    icone: LucideIcons.receipt)
                : MiniTableauSigh(colonnes: [
                    ColonneMini('N°', (f) => '${f['numero']}',
                        rendu: (f) => monoTexte(f['numero'])),
                    ColonneMini('Date', (f) => dateDe(f['date'])),
                    ColonneMini('Patient', (f) => '${f['patient'] ?? ''}'),
                    ColonneMini('Total', (f) => m(f['montantTTC']),
                        droite: true),
                    ColonneMini('Part assureur', (f) => m(f['partAssurance']),
                        droite: true),
                  ], lignes: facturesTriees.take(25).toList())),
      ]),
    ]);
  }
}
