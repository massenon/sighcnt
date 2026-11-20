import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'pv_crud.dart';

num _n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);
String _m(Object? v) => money(v, avecDevise: false);
String _date(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : dateFR(d);
}

const _mono = TextStyle(
    fontFamily: 'LiberationMono',
    color: JetonsShell.slate800,
    fontSize: 12,
    height: 16 / 12);

/// Les champs du formulaire « Nouveau » / « Modifier » (`cfg.fields`).
final champsFournisseur = <ChampDef>[
  const ChampDef(nom: 'code', libelle: 'Code fournisseur', requis: true),
  const ChampDef(
      nom: 'nom',
      libelle: 'Raison sociale',
      requis: true,
      col: ColChamp.plein),
  ChampDef(
      nom: 'type',
      libelle: 'Type',
      type: TypeChamp.select,
      requis: true,
      options: [for (final t in typesFournisseur) OptionChamp(t)]),
  const ChampDef(nom: 'ville', libelle: 'Ville'),
  const ChampDef(nom: 'tel', libelle: 'Téléphone', type: TypeChamp.tel),
  const ChampDef(
      nom: 'delai',
      libelle: 'Délai de livraison (jours)',
      type: TypeChamp.nombre),
  const ChampDef(
      nom: 'habilite',
      libelle: 'Habilité pour les retours de produits périmés',
      type: TypeChamp.case_,
      col: ColChamp.plein),
];

/// L'état imprimé : la fiche et l'historique complet des commandes, TOTAL calculé depuis les lignes imprimées.
PieceA4 pieceFournisseur(Fiche f, List<Fiche> commandes,
    {required String utilisateur,
    required DateTime edite,
    required String reference}) {
  final cmds = trierPar(commandesDuFournisseur('${f['code']}', commandes),
      (c) => c['date'],
      descendant: true);
  return PieceA4(
    titre: 'Fiche fournisseur',
    sousTitre: '${f['nom']}',
    reference: reference,
    utilisateur: utilisateur,
    edite: edite,
    cartouche: [
      ('Code', '${f['code']}'),
      ('Raison sociale', '${f['nom']}'),
      ('Type', '${f['type']}'),
      ('Ville', '${f['ville'] ?? ''}'),
      ('Téléphone', '${f['tel'] ?? ''}'),
      ('Délai', '${f['delai']} jours'),
    ],
    blocs: [
      if (cmds.isNotEmpty)
        BlocTableau(TableauEtat(colonnes: [
          ColonneEtat(libelle: 'N° commande', valeur: (c) => c['reference']),
          ColonneEtat(libelle: 'Date', valeur: (c) => _date(c['date'])),
          ColonneEtat(
              libelle: 'Articles',
              valeur: (c) => ((c['lignes'] as List?) ?? const []).length,
              droite: true),
          ColonneEtat(
              libelle: 'Montant',
              valeur: (c) => _m(c['montant']),
              droite: true,
              somme: (c) => _n(c['montant'])),
          ColonneEtat(libelle: 'Statut', valeur: (c) => c['statutCommande']),
        ], lignes: cmds))
      else
        const BlocTexte('Aucune commande enregistrée auprès de ce fournisseur.',
            italique: true),
    ],
    signatures: const [
      Signature('Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri')
    ],
  );
}

/// La fiche en tiroir (`detail`).
Widget detailFournisseur(Fiche f, List<Fiche> commandesActives) {
  final cmds = commandesDuFournisseur('${f['code']}', commandesActives);
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    DescListeSigh([
      ('Code', '${f['code']}'),
      ('Raison sociale', f['nom']),
      ('Type', f['type']),
      ('Adresse', f['adresse'] ?? f['ville']),
      ('Téléphone', f['tel']),
      (
        'IFU',
        f['ifu'] != null && '${f['ifu']}'.isNotEmpty
            ? Text('${f['ifu']}', style: _mono.copyWith(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500))
            : '—'
      ),
      ('Délai de livraison', '${f['delai']} jours'),
      ('Code client chez le fournisseur', f['codeClient'] ?? '—'),
      (
        'Domiciliation bancaire',
        f['banque'] != null && '${f['banque']}'.isNotEmpty
            ? '${f['banque']} — compte ${f['compte']} (clé ${f['cleRib']})'
            : '—'
      ),
      ('Certifications', f['certification'] ?? '—'),
      (
        'Retours de périmés',
        f['habilite'] == true
            ? const BadgeSigh('Habilité', ton: TonSigh.succes)
            : const BadgeSigh('Non habilité', ton: TonSigh.neutre)
      ),
      (
        'Provenance',
        f['source'] != null && '${f['source']}'.isNotEmpty
            ? Text('${f['source']}',
                style: const TextStyle(
                    color: JetonsShell.slate500, fontSize: 12, height: 16 / 12))
            : '—'
      ),
    ]),
    const SizedBox(height: 16),
    KpiGrilleSigh(colonnes: 2, kpis: [
      KpiSigh(
          libelle: 'Commandes passées',
          valeur: nombre(cmds.length),
          icone: LucideIcons.truck),
      KpiSigh(
          libelle: 'Volume cumulé',
          valeur: money(cmds.fold<num>(0, (a, c) => a + _n(c['montant']))),
          icone: LucideIcons.wallet,
          ton: TonSigh.info),
    ]),
    const SizedBox(height: 16),
    if (cmds.isNotEmpty)
      CarteSigh(
          titre: 'Historique des commandes',
          sansRemplissage: true,
          child: MiniTableauSigh(colonnes: [
            ColonneMini('N°', (c) => '${c['reference']}',
                rendu: (c) => Text('${c['reference']}',
                    style: const TextStyle(
                        fontFamily: 'LiberationMono',
                        fontSize: 12,
                        height: 16 / 12,
                        color: JetonsShell.slate800))),
            ColonneMini('Date', (c) => _date(c['date'])),
            ColonneMini('Montant', (c) => _m(c['montant']), droite: true),
            ColonneMini('Statut', (c) => '${c['statutCommande'] ?? ''}',
                rendu: (c) =>
                    BadgeSigh('${c['statutCommande'] ?? ''}', ton: TonSigh.navy)),
          ], lignes: historiqueDuTiroir(cmds)))
    else
      const VideSigh('Aucune commande enregistrée.', icone: LucideIcons.truck),
  ]);
}

/// `m7-fournisseurs` — « Fournisseurs » : référentiel, habilitation aux retours de produits périmés, historique des commandes.
class EcranFournisseurs extends StatelessWidget with EcranMaquette {
  const EcranFournisseurs({super.key});

  @override
  String get titre => 'Fournisseurs';

  @override
  String get description =>
      'Référentiel des fournisseurs, habilitation pour les retours de produits périmés et historique des commandes.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final commandes = c.magasin.collection('commandes');
    // Les commandes pèsent sur le nombre de commandes, les KPI et le tiroir : l'écran se redessine quand elles bougent.
    return ListenableBuilder(
      listenable: commandes,
      builder: (context, _) {
        final cmds = commandes.actives;
        return CrudFormulaireSigh(
          collection: c.magasin.collection('fournisseurs'),
          entite: 'fournisseur',
          entiteP: 'fournisseurs',
          prefixeId: 'FRN',
          triInitial: 'nom',
          provenance:
              'Facture fournisseur SoBAPS et retours CAME identifiés au cadrage.',
          champs: champsFournisseur,
          versFiche: valeursFournisseur,
          colonnes: [
            ColonneTableau(
                cle: 'code',
                libelle: 'Code',
                sansCoupure: true,
                texte: (f) => '${f['code'] ?? ''}',
                rendu: (_, f) => Text('${f['code'] ?? ''}',
                    style: _mono.copyWith(fontWeight: FontWeight.w600))),
            const ColonneTableau(cle: 'nom', libelle: 'Raison sociale'),
            ColonneTableau(
                cle: 'type',
                libelle: 'Type',
                texte: (f) => '${f['type'] ?? ''}',
                rendu: (_, f) =>
                    BadgeSigh('${f['type'] ?? ''}', ton: TonSigh.navy)),
            const ColonneTableau(cle: 'ville', libelle: 'Ville'),
            const ColonneTableau(
                cle: 'tel', libelle: 'Téléphone', sansCoupure: true),
            const ColonneTableau(cle: 'delai', libelle: 'Délai (j)', droite: true),
            ColonneTableau(
                cle: 'habilite',
                libelle: 'Retours périmés',
                texte: (f) => f['habilite'] == true ? 'Habilité' : 'Non habilité',
                rendu: (_, f) => f['habilite'] == true
                    ? const BadgeSigh('Habilité', ton: TonSigh.succes)
                    : const Text('Non habilité',
                        style: TextStyle(
                            color: JetonsShell.slate400,
                            fontSize: 12,
                            height: 16 / 12))),
            ColonneTableau(
                cle: 'commandes',
                libelle: 'Commandes',
                droite: true,
                triable: false,
                valeur: (f) =>
                    commandesDuFournisseur('${f['code']}', cmds).length,
                texte: (f) =>
                    '${commandesDuFournisseur('${f['code']}', cmds).length}'),
          ],
          kpis: (rows) {
            final k = kpisFournisseurs(rows, cmds);
            return [
              KpiSigh(
                  libelle: 'Fournisseurs référencés',
                  valeur: nombre(k.references),
                  icone: LucideIcons.truck),
              KpiSigh(
                  libelle: 'Habilités aux retours',
                  valeur: nombre(k.habilites),
                  icone: LucideIcons.shieldCheck,
                  ton: TonSigh.succes),
              KpiSigh(
                  libelle: 'Volume d’achats',
                  valeur: money(k.volumeAchats),
                  icone: LucideIcons.wallet,
                  ton: TonSigh.info),
              KpiSigh(
                  libelle: 'Délai moyen',
                  valeur: '${k.delaiMoyen} j',
                  icone: LucideIcons.clock,
                  ton: TonSigh.neutre),
            ];
          },
          titreDetail: (f) => '${f['code'] ?? f['id']}',
          sousTitreDetail: (f) => '${f['code'] ?? ''}',
          detail: (f) => detailFournisseur(f, cmds),
          etat: (ctx, f) {
            final e = ContexteEcran.of(ctx);
            afficherApercu(
                ctx,
                pieceFournisseur(f, e.magasin.collection('commandes').actives,
                    utilisateur: e.utilisateur,
                    edite: e.aujourdhui,
                    reference: PieceA4.reference_(
                        e.aujourdhui, ImpressionPoste.prochainNumero())));
          },
        );
      },
    );
  }
}
