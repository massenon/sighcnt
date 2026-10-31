import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m13/adm_commun.dart';
import '../m3/surv_commun.dart' show sectionDetail;
import 'pai_commun.dart';

/// `m11-prets-etudes` — « Prêts-études et avances » : les décaissements consentis au personnel, recouvrés par retenue sur salaire. Dispositif relevé sur la
/// description de poste de l'Assistant de Direction (« suivre les décaissements et les recouvrements des prêts-études »).
///
/// LA RÈGLE QUI COMPTE : une échéance est retenue au bulletin du SEUL MOIS de son échéance — la porter chaque mois la prélèverait autant de fois qu'il y a
/// de bulletins (le piège des redevances ORTB et des participations aux événements). Un prêt ne se supprime pas : il s'ARCHIVE (RG-14) avec son motif ; ces
/// sommes TRANSITENT — ni charge ni recette, une créance sur l'agent. L'échéancier est CALCULÉ, jamais saisi : le total vaut le montant accordé au franc
/// près, le reliquat d'arrondi tombe sur la dernière échéance.
///
/// Écart porté (E689) : le calcul de la paie (`m11-calcul`) NE LIT PAS cette collection — aucune échéance n'y est retenue au bulletin, et le champ `retenues`
/// n'est alimenté que par le jeu de démonstration. L'écran dit « retenue effectuée » sur la foi de ce champ.
class EcranPretsEtudes extends StatelessWidget with EcranMaquette {
  const EcranPretsEtudes({super.key});

  @override
  String get titre => 'Prêts-études et avances';

  @override
  String get description => 'Décaissements consentis au personnel et recouvrement par retenue sur salaire.';

  @override
  String get regle =>
      'Une échéance est retenue au bulletin du seul mois de son échéance. La porter chaque mois la prélèverait autant de fois qu’il y a de bulletins — c’est le piège déjà rencontré sur les redevances ORTB et les participations aux événements. Un prêt s’archive, il ne se supprime pas : les échéances déjà retenues l’ont été sur des bulletins émis.';

  static List<ChampDef> _champs(Magasin mag) => [
        ChampDef(
            nom: 'employeId',
            libelle: 'Agent bénéficiaire',
            type: TypeChamp.select,
            requis: true,
            options: [for (final a in mag.collection('personnel').actives) OptionChamp('${a['id']}', '${a['nomComplet']}')]),
        const ChampDef(nom: 'nature', libelle: 'Nature', type: TypeChamp.select, requis: true, options: [
          OptionChamp('pret_etudes', 'Prêt-études'),
          OptionChamp('avance', 'Avance sur salaire'),
          OptionChamp('pret_social', 'Prêt social'),
        ]),
        const ChampDef(nom: 'objet', libelle: 'Objet', requis: true),
        const ChampDef(nom: 'montant', libelle: 'Montant accordé (FCFA)', type: TypeChamp.nombre, requis: true),
        const ChampDef(nom: 'dateAccord', libelle: 'Date d’accord', type: TypeChamp.date, requis: true),
        ChampDef(
            nom: 'premiereEcheance',
            libelle: 'Premier mois de retenue',
            requis: true,
            indicatif: 'AAAA-MM',
            valider: (v, _) => RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch('$v'.trim()) ? null : 'Mois attendu au format AAAA-MM.'),
        const ChampDef(
            nom: 'nbEcheances',
            libelle: 'Nombre d’échéances mensuelles',
            type: TypeChamp.nombre,
            requis: true,
            aide: 'Le montant est réparti à parts égales ; le dernier arrondi porte le reliquat.'),
        const ChampDef(nom: 'autorisePar', libelle: 'Autorisé par', requis: true),
      ];

  /// Les nombres du formulaire sont des NOMBRES dans la fiche (`type: 'money'` / `'number'` de la maquette).
  static Fiche _chiffres(Map<String, Object?> v) => {
        ...v,
        'montant': admNombre(v['montant']),
        'nbEcheances': admNombre(v['nbEcheances']),
        'premiereEcheance': '${v['premiereEcheance']}'.trim(),
      };

  static String _moisLisible(String mois) {
    final d = DateTime(int.parse(mois.substring(0, 4)), int.parse(mois.substring(5, 7)), 1);
    return moisAnnee(d);
  }

  Widget _detail(Fiche r) {
    final e = paiEcheancier(r);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DescListeSigh([
        ('Référence', '${r['reference']}'),
        ('Agent', '${r['agent']}'),
        ('Matricule', r['matricule'] == null ? '—' : '${r['matricule']}'),
        ('Nature', paiNaturePret(r['nature'])),
        ('Objet', '${r['objet']}'),
        ('Montant accordé', money(r['montant'])),
        ('Date d’accord', dateFR(DateTime.parse('${r['dateAccord']}'))),
        ('Autorisé par', '${r['autorisePar']}'),
        ('Reste à recouvrer', money(paiSoldePret(r))),
      ]),
      sectionDetail(
          'Échéancier',
          MiniTableauSigh(colonnes: [
            ColonneMini('Rang', (x) => '${x['rang']}'),
            ColonneMini('Mois de retenue', (x) => '${x['mois']}'),
            ColonneMini('Montant', (x) => '${x['montant']}'),
            ColonneMini('État', (x) => '${x['etat']}'),
          ], lignes: [
            for (final x in e) {'rang': '${x.rang}', 'mois': _moisLisible(x.mois), 'montant': money(x.montant), 'etat': x.retenue ? 'Retenue effectuée' : 'À retenir'}
          ])),
      const SizedBox(height: 16),
      const NoteSigh('Chaque échéance figure au bulletin du seul mois indiqué. La porter tous les mois la prélèverait autant de fois qu’il y a de bulletins.',
          ton: TonSigh.info, icone: LucideIcons.calendarCheck),
    ]);
  }

  void _consulter(BuildContext ctx, Fiche r) => afficherTiroir<void>(ctx, titre: '${r['reference']} — ${r['agent']}', sousTitre: '', largeurMax: 672, corps: _detail(r));

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('pretsEtudes');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final rows = col.actives;
        final enCours = rows.where((r) => paiSoldePret(r) > 0);
        final encours = rows.fold<num>(0, (a, r) => a + paiSoldePret(r));
        final accorde = rows.fold<num>(0, (a, r) => a + n(r['montant']));
        // `C.sortBy(rows, 'dateAccord').reverse()` : le plus récent d'abord.
        final lignes = trierPar(rows, (r) => r['dateAccord']).reversed.toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Prêts et avances', valeur: nombre(rows.length), icone: LucideIcons.graduationCap),
            KpiSigh(
                libelle: 'En cours de remboursement',
                valeur: nombre(enCours.length),
                icone: LucideIcons.clock,
                ton: enCours.isNotEmpty ? TonSigh.attention : TonSigh.succes),
            KpiSigh(libelle: 'Total accordé', valeur: money(accorde), icone: LucideIcons.handCoins, ton: TonSigh.info),
            KpiSigh(libelle: 'Reste à recouvrer', valeur: money(encours), icone: LucideIcons.wallet, ton: encours != 0 ? TonSigh.attention : TonSigh.succes),
          ]),
          const SizedBox(height: 16),
          const NoteSigh(
              'Ces sommes transitent : un prêt n’est ni une charge ni une recette, c’est une créance sur l’agent. Elle se solde par des retenues, chacune portée au bulletin du seul mois de son échéance.',
              ton: TonSigh.info,
              icone: LucideIcons.arrowLeftRight),
          const SizedBox(height: 16),
          TableauSigh(
            lignes: lignes,
            nomExport: 'export',
            messageVide: 'Aucun prêt ni avance enregistré.',
            actions: [
              if (c.droit.editer)
                BoutonSigh(
                    libelle: 'Nouveau prêt ou avance',
                    icone: LucideIcons.plus,
                    taille: TailleBouton.sm,
                    onPressed: () => admSaisir(context,
                        col: col,
                        champs: _champs(c.magasin),
                        titreCreation: 'Prêt-études ou avance sur salaire',
                        entite: 'Prêt',
                        prefixeId: 'PRT',
                        fiche: (v, _) {
                          final a = c.magasin.collection('personnel').actives.where((x) => x['id'] == v['employeId']).firstOrNull;
                          return paiPretTransform(_chiffres(v), a, reference: paiReferenceSuivante('PRT-', 4, col.toutes));
                        })),
            ],
            colonnes: [
              const ColonneTableau(cle: 'reference', libelle: 'Référence'),
              const ColonneTableau(cle: 'agent', libelle: 'Agent'),
              ColonneTableau(cle: 'nature', libelle: 'Nature', texte: (r) => paiNaturePret(r['nature']), rendu: (_, r) => cellTexte(paiNaturePret(r['nature']))),
              const ColonneTableau(cle: 'objet', libelle: 'Objet'),
              ColonneTableau(cle: 'montant', libelle: 'Accordé', droite: true, texte: (r) => money(r['montant']), rendu: (_, r) => cellTexte(money(r['montant']))),
              ColonneTableau(
                  cle: 'solde',
                  libelle: 'Reste dû',
                  droite: true,
                  valeur: paiSoldePret,
                  texte: (r) => paiSoldePret(r) != 0 ? money(paiSoldePret(r)) : 'soldé',
                  rendu: (_, r) => paiSoldePret(r) != 0 ? cellTexte(money(paiSoldePret(r)), couleur: const Color(0xFFB45309), poids: FontWeight.w600) : const BadgeSigh('soldé', ton: TonSigh.succes)),
              ColonneTableau(
                  cle: 'avancement',
                  libelle: 'Échéances',
                  valeur: (r) => paiEcheancier(r).where((x) => x.retenue).length,
                  texte: (r) => '${paiEcheancier(r).where((x) => x.retenue).length} / ${paiEcheancier(r).length}',
                  rendu: (_, r) => Center(child: cellTexte('${paiEcheancier(r).where((x) => x.retenue).length} / ${paiEcheancier(r).length}'))),
            ],
            actionsLigne: (ctx, r) => admActionsLigne(context, c, col, r,
                avant: [BoutonIcone(icone: LucideIcons.eye, libelle: 'Consulter', onPressed: () => _consulter(context, r))],
                modifier: (f) => admSaisir(context,
                    col: col,
                    existante: f,
                    champs: _champs(c.magasin),
                    titreCreation: 'Prêt-études ou avance sur salaire',
                    entite: 'Prêt',
                    fiche: (v, e) => _chiffres(v))),
          ),
        ]);
      },
    );
  }
}
