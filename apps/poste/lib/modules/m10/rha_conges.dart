import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m4/mat_commun.dart';
import '../m4/mat_crud.dart';
import 'rha_commun.dart';

/// `m10-conges` — demandes, validation et suivi des congés. Un congé qui finit AUJOURD'HUI n'est plus « en cours » (la fin est lue à minuit) ; refus
/// nommé si la fin précède le début ; la lecture graphique vient APRÈS le tableau. La référence suit la série du registre (E620).
class EcranConges extends StatelessWidget with EcranMaquette {
  const EcranConges({super.key});
  @override
  String get titre => 'Congés';
  @override
  String get description => 'Demandes, validation et suivi des congés annuels et exceptionnels.';
  @override
  String? get regle => 'Le régime observé prévoit 2 jours de repos hebdomadaire et 10 jours de congés annuels.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('conges');
    Fiche fiche(BuildContext ctx, Map<String, Object?> v, Fiche? existante) => rhaCongeEnregistrable(
        {...v}, rhaAgentPar(c.magasin, v['employeId']),
        reference: '${existante?['reference'] ?? ''}'.isNotEmpty ? '${existante!['reference']}' : admReferenceSuivante('CG-', 4, col.toutes));

    return ListenableBuilder(
        listenable: col,
        builder: (context, _) => CrudMat(
              collection: col,
              entite: 'congé',
              entiteP: 'congés',
              prefixeId: 'CNG',
              triInitial: 'dateDebut',
              sensInitial: 'desc',
              taillePage: 15,
              apresTableau: (ctx) => Padding(padding: const EdgeInsets.only(top: 16), child: _graphiques(col.actives)),
              colonnes: [
                ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, rendu: (_, r) => matRef(r['reference'])),
                const ColonneTableau(cle: 'employe', libelle: 'Agent'),
                const ColonneTableau(cle: 'service', libelle: 'Service'),
                ColonneTableau(cle: 'nature', libelle: 'Nature', rendu: (_, r) => BadgeSigh('${r['nature']}', ton: TonSigh.navy)),
                ColonneTableau(cle: 'dateDebut', libelle: 'Du', sansCoupure: true, texte: (r) => rhaDateFR(r['dateDebut'])),
                ColonneTableau(cle: 'dateFin', libelle: 'Au', sansCoupure: true, texte: (r) => rhaDateFR(r['dateFin'])),
                const ColonneTableau(cle: 'duree', libelle: 'Jours', droite: true),
                const ColonneTableau(cle: 'remplacant', libelle: 'Remplaçant'),
                ColonneTableau(
                    cle: 'statutConge',
                    libelle: 'Décision',
                    texte: (r) => rhaDecisionsConge['${r['statutConge']}']?.$1 ?? '—',
                    rendu: (_, r) {
                      final x = rhaDecisionsConge['${r['statutConge']}'] ?? ('—', 'neutral');
                      return BadgeSigh(x.$1, ton: matTon(x.$2));
                    }),
              ],
              champs: (m) => [
                ChampDef(nom: 'employeId', libelle: 'Agent', type: TypeChamp.select, requis: true, options: rhaOptionsEmployes(m), col: ColChamp.plein),
                ChampDef(nom: 'nature', libelle: 'Nature du congé', type: TypeChamp.select, requis: true, options: rhaOptions(rhaNaturesConge)),
                const ChampDef(nom: 'dateDebut', libelle: 'Date de début', type: TypeChamp.date, requis: true),
                const ChampDef(nom: 'dateFin', libelle: 'Date de fin', type: TypeChamp.date, requis: true),
                ChampDef(
                    nom: 'remplacant',
                    libelle: 'Remplaçant désigné',
                    type: TypeChamp.select,
                    // `personnel().map(...)` : l'ordre de la collection, pas un tri.
                    options: [for (final e in m.collection('personnel').actives) OptionChamp('${e['nomComplet']}')]),
                ChampDef(nom: 'statutConge', libelle: 'Décision', type: TypeChamp.select, requis: true, options: [
                  for (final k in const ['en_attente', 'valide', 'refuse']) OptionChamp(k, rhaDecisionsConge[k]!.$1),
                ]),
                const ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
              ],
              valeursInitiales: () => {'statutConge': 'en_attente', 'nature': 'Congé annuel', 'dateDebut': iso(c.aujourdhui)},
              refuser: (v) => rhaRefuserConge(v['dateDebut'], v['dateFin']),
              transformer: (ctx, v) => fiche(ctx, v, null),
              transformerExistante: fiche,
              referenceToast: (f) => '${f['reference'] ?? ''}',
              filtres: [
                FiltreTableau(nom: 'nature', libelle: 'Nature', options: rhaOptions(rhaNaturesConge)),
                const FiltreTableau(nom: 'statutConge', libelle: 'Décision', options: [OptionChamp('valide', 'Accordé'), OptionChamp('en_attente', 'En attente'), OptionChamp('refuse', 'Refusé')]),
              ],
              kpis: (ctx, rows) => rhaKpisW(rhaKpisConges(rows, c.aujourdhui), const [LucideIcons.calendarOff, LucideIcons.plane, LucideIcons.hourglass, LucideIcons.calendarCheck]),
              etat: (ctx, r) => matImprimer(ctx,
                  titre: 'Décision de congé',
                  sousTitre: '${r['reference']}',
                  cartouche: [
                    ('Agent', '${r['employe']}'),
                    ('Matricule', '${r['matricule']}'),
                    ('Service', '${r['service']}'),
                    ('Nature', '${r['nature']}'),
                    ('Période', '${rhaDateFR(r['dateDebut'])} au ${rhaDateFR(r['dateFin'])}'),
                    ('Durée', '${r['duree']} jour(s)'),
                  ],
                  blocs: [for (final t in rhaTexteDecisionConge(r)) BlocTexte(t, italique: t.startsWith('Motif : '))],
                  signatures: [Signature('L’Agent', nom: '${r['employe']}'), rhaSignDa]),
            ));
  }

  /// Le kit place ce bloc sous le tableau : la lecture graphique vient APRÈS les données, jamais à leur place.
  Widget _graphiques(List<Fiche> rows) {
    if (rows.isEmpty) return const CarteSigh(titre: 'Statistiques des congés', child: VideSigh('Aucun congé enregistré.', icone: LucideIcons.plane));
    final st = rhaStatsConges(rows);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      rhaCartes(colonnes: 3, [
        CarteSigh(
            titre: 'Congés par service',
            child: GraphiqueBarres(
                horizontal: true,
                etiquettes: [for (final x in st.parService) x.$1],
                series: [SerieGraphique('Congés', [for (final x in st.parService) x.$2], couleur: JetonsShell.navy900)])),
        CarteSigh(titre: 'Répartition par nature', child: GraphiqueAnneau(trou: 0, etiquettes: [for (final x in st.parNature) x.$1], valeurs: [for (final x in st.parNature) x.$2])),
        CarteSigh(
            titre: 'Décisions',
            child: GraphiqueAnneau(
                etiquettes: [for (final x in st.parDecision) x.$1],
                valeurs: [for (final x in st.parDecision) x.$2],
                couleurs: const [JetonsShell.success500, JetonsShell.warning500, JetonsShell.danger500])),
      ]),
      if (st.moisLibelles.isNotEmpty) ...[
        const SizedBox(height: 16),
        CarteSigh(
            titre: 'Jours de congé accordés par mois',
            child: GraphiqueLigne(hauteur: 240, etiquettes: st.moisLibelles, series: [SerieGraphique('Jours', st.moisJours, couleur: JetonsShell.navy600)])),
      ],
      const SizedBox(height: 16),
      const NoteSigh(
          'La répartition par nature distingue le congé annuel des congés de maternité et de maladie : ces derniers ne s’imputent pas sur le solde annuel et ne se compensent pas de la même manière au planning.'),
    ]);
  }
}
