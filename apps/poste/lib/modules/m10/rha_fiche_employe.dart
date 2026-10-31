import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m13/adm_commun.dart';
import '../m4/mat_commun.dart';
import 'rha_commun.dart';

/// `ficheEmploye(e)` de la maquette : le bandeau de l'agent puis SIX onglets — informations, planning du mois, primes NS 132, présences & congés,
/// évaluations & sanctions, assurances du personnel. Servie par le tiroir de `m10-personnel` ET par la page `m10-employe-profil`.
/// Le contexte de l'écran est passé explicitement : le tiroir et les modales vivent AU-DESSUS de la coque.
class FicheEmploye extends StatelessWidget {
  const FicheEmploye({super.key, required this.agent, required this.c, required this.ctx});
  final Fiche agent;
  final ContexteEcran c;

  /// Le contexte de l'écran (celui qui peut ouvrir une modale de saisie).
  final BuildContext ctx;

  static const _col = 'assurancesPersonnel';

  @override
  Widget build(BuildContext context) {
    final e = agent;
    final auj = c.aujourdhui;
    final vac = trierPar(rhaVacations(c.magasin.collection('planning').actives, e['id'], auj.year, auj.month), (p) => p['date']);
    final gardes = rhaCompter(vac, 'garde'), permanences = rhaCompter(vac, 'permanence');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: JetonsShell.navy50, borderRadius: BorderRadius.circular(8)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: JetonsShell.navy900, shape: BoxShape.circle),
              child: Text(rhaInitiales(e['nomComplet']), style: const TextStyle(color: Colors.white, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e['nomComplet']}', style: const TextStyle(color: JetonsShell.slate900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
            Text('${e['poste'] ?? ''}', style: const TextStyle(color: JetonsShell.navy700, fontSize: 12, height: 16 / 12)),
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Matricule ${e['matricule']} — ${e['service']} — catégorie ${e['categorie']}',
                    style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12))),
          ])),
        ]),
      ),
      const SizedBox(height: 16),
      OngletsSigh(onglets: [
        OngletDef(id: 'infos', libelle: 'Informations', construire: (_) => _infos(e, auj)),
        OngletDef(id: 'planning', libelle: 'Planning du mois', construire: (_) => _planning(vac, gardes, permanences)),
        OngletDef(id: 'primes', libelle: 'Primes (NS 132)', construire: (_) => _primes(e, gardes, permanences)),
        OngletDef(id: 'presences', libelle: 'Présences & congés', construire: (_) => _presences(e)),
        OngletDef(id: 'evaluations', libelle: 'Évaluations & sanctions', construire: (_) => _evaluations(e)),
        OngletDef(id: 'assurances', libelle: 'Assurances', construire: (_) => _assurances(e)),
      ]),
    ]);
  }

  Widget _infos(Fiche e, DateTime auj) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: DescListeSigh([
          ('Matricule', '${e['matricule']}'),
          ('Nom et prénoms', '${e['nomComplet']}'),
          ('Sexe', e['sexe'] == 'F' ? 'Féminin' : 'Masculin'),
          ('Fonction', rhaFonctionLabel(e['fonction'])),
          ('Poste', e['poste'] as String?),
          ('Service', e['service'] as String?),
          ('Catégorie / échelon', e['categorie'] as String?),
          ('Date d’embauche', rhaDateFR(e['dateEmbauche'])),
          ('Ancienneté', rhaAncienneteLongue(e['dateEmbauche'], auj)),
          ('Numéro CNSS', e['cnss'] as String?),
          ('Téléphone', e['telephone'] as String?),
          ('Situation matrimoniale', e['situation'] as String?),
          ('Salaire de base', money(e['salaireBase'])),
        ]),
      );

  Widget _planning(List<Fiche> vac, int gardes, int permanences) {
    if (vac.isEmpty) return const Padding(padding: EdgeInsets.only(top: 16), child: VideSigh('Aucune vacation programmée ce mois-ci.', icone: LucideIcons.calendar));
    return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(colonnes: 2, kpis: [
            KpiSigh(libelle: 'Gardes', valeur: nombre(gardes), icone: LucideIcons.moon, ton: TonSigh.danger),
            KpiSigh(libelle: 'Permanences', valeur: nombre(permanences), icone: LucideIcons.sun, ton: TonSigh.attention),
          ]),
          const SizedBox(height: 12),
          MiniTableauSigh(colonnes: [
            ColonneMini('Date', (p) => dateJour(rhaDate(p['date'])!)),
            ColonneMini('Vacation', (p) => rhaTypePlanningLabel(p['type']),
                rendu: (p) => BadgeSigh(rhaTypePlanningLabel(p['type']), ton: matTon(rhaTypePlanningTon(p['type'])))),
            ColonneMini('Statut', (p) => p['statut'] == 'validee' ? 'Validée' : 'Brouillon', rendu: (p) => rhaBadgeStatut(p['statut'] == 'validee' ? 'validee' : 'brouillon')),
          ], lignes: vac),
        ]));
  }

  Widget _primes(Fiche e, int gardes, int permanences) {
    final lignes = rhaPrimesAgent(c.magasin.collection('grillePrimes').actives, e['fonction'], gardes, permanences);
    if (lignes.isEmpty) return const Padding(padding: EdgeInsets.only(top: 16), child: VideSigh('Aucune prime prévue pour cette fonction par la note NS 132.', icone: LucideIcons.gift));
    return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NoteSigh('Grille issue de la note de service ${admNs132.reference}, en vigueur depuis le ${rhaDateFR(admNs132.dateEffet)}.'),
          const SizedBox(height: 12),
          MiniTableauSigh(colonnes: [
            ColonneMini('Prime', (l) => '${l['prime']}'),
            ColonneMini('Mode', (l) => '${l['mode']}'),
            ColonneMini('Montant unitaire', (l) => money(l['montant'], avecDevise: false), droite: true),
            ColonneMini('Nombre', (l) => '${l['nb']}', droite: true),
            ColonneMini('Total du mois', (l) => money(l['total'], avecDevise: false),
                droite: true, rendu: (l) => Text(money(l['total'], avecDevise: false), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: JetonsShell.slate800))),
          ], lignes: [
            for (final l in lignes) {'prime': l.prime, 'mode': l.mode, 'montant': l.montant, 'nb': l.nb, 'total': l.total}
          ]),
        ]));
  }

  Widget _presences(Fiche e) {
    final pres = [for (final x in c.magasin.collection('presences').actives) if (x['employeId'] == e['id']) x];
    final cong = [for (final x in c.magasin.collection('conges').actives) if (x['employeId'] == e['id']) x];
    final presTri = trierPar(pres, (x) => x['date'], descendant: true).take(15).toList();
    final congTri = trierPar(cong, (x) => x['dateDebut'], descendant: true);
    return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CarteSigh(
              titre: 'Présences et absences',
              child: pres.isEmpty
                  ? const VideSigh('Aucun relevé de présence.', icone: LucideIcons.calendarCheck)
                  : MiniTableauSigh(colonnes: [
                      ColonneMini('Date', (x) => rhaDateFR(x['date'])),
                      ColonneMini('État', (x) => rhaStatutBadge(x['etat'] ?? x['statutPresence'] ?? 'valide').$1, rendu: (x) => rhaBadgeStatut(x['etat'] ?? x['statutPresence'] ?? 'valide')),
                      ColonneMini('Arrivée', (x) => rhaVrai(x['heureArrivee']) ? '${x['heureArrivee']}' : '—'),
                      ColonneMini('Observation', (x) => rhaVrai(x['observation']) ? '${x['observation']}' : '—'),
                    ], lignes: presTri)),
          const SizedBox(height: 12),
          CarteSigh(
              titre: 'Congés',
              child: cong.isEmpty
                  ? const VideSigh('Aucun congé enregistré.', icone: LucideIcons.palmtree)
                  : MiniTableauSigh(colonnes: [
                      // E621 : les congés portent `nature` et `duree` — la maquette lisait `type` et `jours` (« — » partout) ; corrigé à la source.
                      ColonneMini('Type', (x) => '${x['nature'] ?? x['type'] ?? x['typeConge'] ?? '—'}'),
                      ColonneMini('Du', (x) => rhaDateFR(x['dateDebut'])),
                      ColonneMini('Au', (x) => rhaDateFR(x['dateFin'])),
                      ColonneMini('Jours', (x) => rhaVrai(x['duree'] ?? x['jours']) ? '${x['duree'] ?? x['jours']}' : '—', droite: true),
                      ColonneMini('État', (x) => rhaStatutBadge(x['statutConge'] ?? 'valide').$1, rendu: (x) => rhaBadgeStatut(x['statutConge'] ?? 'valide')),
                    ], lignes: congTri)),
        ]));
  }

  Widget _evaluations(Fiche e) {
    final evs = [for (final x in c.magasin.collection('evaluations').actives) if (x['employeId'] == e['id']) x];
    if (evs.isEmpty) return const Padding(padding: EdgeInsets.only(top: 16), child: VideSigh('Aucune évaluation NS 131 enregistrée.', icone: LucideIcons.clipboardCheck));
    final sanctions = evs.where((x) => rhaNum(x['prelevementPct']) > 0).length;
    return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          sanctions > 0
              ? NoteSigh('$sanctions évaluation(s) ayant entraîné une retenue. La retenue découle du barème NS 131 ; elle se corrige en modifiant l’évaluation.',
                  ton: TonSigh.attention, icone: LucideIcons.triangleAlert)
              : const NoteSigh('Aucune retenue sur la période — évaluations conformes au barème NS 131.', ton: TonSigh.succes, icone: LucideIcons.circleCheck),
          const SizedBox(height: 12),
          MiniTableauSigh(colonnes: [
            ColonneMini('Période', (x) => rhaVrai(x['periode']) ? '${x['periode']}' : rhaDateFR(x['date'])),
            ColonneMini('Note', (x) => '${x['note'] ?? '—'} / 20', droite: true),
            ColonneMini('Retenue', (x) => rhaNum(x['prelevementPct']) > 0 ? '${x['prelevementPct']} %' : 'Aucune', droite: true,
                rendu: (x) => rhaNum(x['prelevementPct']) > 0
                    ? Text('${x['prelevementPct']} %', style: const TextStyle(color: JetonsShell.danger600, fontWeight: FontWeight.w600, fontSize: 14))
                    : const BadgeSigh('Aucune', ton: TonSigh.succes)),
            ColonneMini('Évaluateur', (x) => rhaVrai(x['evaluateur']) ? '${x['evaluateur']}' : '—'),
          ], lignes: trierPar(evs, (x) => x['date'], descendant: true).take(12).toList()),
        ]));
  }

  List<ChampDef> get _champsAss => [
        ChampDef(nom: 'type', libelle: 'Type de couverture', type: TypeChamp.select, requis: true, options: rhaOptions(rhaTypesCouverture)),
        const ChampDef(nom: 'organisme', libelle: 'Organisme', requis: true, col: ColChamp.plein),
        const ChampDef(nom: 'numeroAdhesion', libelle: 'N° d’adhésion', requis: true),
        const ChampDef(nom: 'taux', libelle: 'Taux de couverture (%)', type: TypeChamp.nombre),
        const ChampDef(nom: 'dateDebut', libelle: 'Début de validité', type: TypeChamp.date, requis: true),
        const ChampDef(nom: 'dateFin', libelle: 'Fin de validité', type: TypeChamp.date),
        const ChampDef(nom: 'beneficiaires', libelle: 'Ayants droit couverts', type: TypeChamp.nombre),
        const ChampDef(nom: 'observation', libelle: 'Observation', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
      ];

  /// Les couvertures du personnel relèvent du DOSSIER RH : aucune écriture comptable, aucune recette (vague 20).
  Widget _assurances(Fiche e) {
    final col = c.magasin.collection(_col);
    return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: ListenableBuilder(
            listenable: col,
            builder: (context, _) {
              final rows = [for (final x in col.actives) if (x['employeId'] == e['id']) x];
              Fiche transformer(Map<String, Object?> v, Fiche? ex) {
                final f = {...v, 'taux': admNombre(v['taux']), 'beneficiaires': admNombre(v['beneficiaires'])};
                if (ex == null) {
                  f['employeId'] = e['id'];
                  f['agent'] = e['nomComplet'];
                }
                return matSansNuls(f);
              }

              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const NoteSigh('Couvertures de l’agent — dossier RH. Elles ne figurent pas dans les recettes de la clinique.', icone: LucideIcons.shieldCheck),
                const SizedBox(height: 12),
                TableauSigh(
                  colonnes: [
                    ColonneTableau(cle: 'type', libelle: 'Couverture', rendu: (_, x) => BadgeSigh('${x['type']}', ton: TonSigh.navy)),
                    const ColonneTableau(cle: 'organisme', libelle: 'Organisme'),
                    ColonneTableau(cle: 'numeroAdhesion', libelle: 'N° d’adhésion', sansCoupure: true, rendu: (_, x) => matRef(x['numeroAdhesion'])),
                    ColonneTableau(cle: 'taux', libelle: 'Taux', droite: true, texte: (x) => x['taux'] != null ? '${x['taux']} %' : '—'),
                    ColonneTableau(
                        cle: 'dateDebut',
                        libelle: 'Validité',
                        sansCoupure: true,
                        texte: (x) => '${rhaDateFR(x['dateDebut'])}${rhaVrai(x['dateFin']) ? ' → ${rhaDateFR(x['dateFin'])}' : ' → en cours'}',
                        rendu: (_, x) {
                          final d = rhaDate(x['dateFin']);
                          final expire = d != null && d.isBefore(c.aujourdhui);
                          return Text('${rhaDateFR(x['dateDebut'])}${rhaVrai(x['dateFin']) ? ' → ${rhaDateFR(x['dateFin'])}' : ' → en cours'}',
                              style: TextStyle(
                                  color: expire ? JetonsShell.danger600 : JetonsShell.slate600, fontSize: 12, height: 16 / 12, fontWeight: expire ? FontWeight.w600 : FontWeight.w400));
                        }),
                    ColonneTableau(cle: 'beneficiaires', libelle: 'Ayants droit', droite: true, texte: (x) => x['beneficiaires'] != null ? '${x['beneficiaires']}' : '—'),
                  ],
                  lignes: rows,
                  taillePage: 8,
                  nomExport: 'assurances-personnel',
                  messageVide: 'Aucune couverture enregistrée pour cet agent.',
                  actions: [
                    if (c.droit.editer)
                      BoutonSigh(
                          libelle: 'Nouveau',
                          icone: LucideIcons.plus,
                          taille: TailleBouton.sm,
                          onPressed: () => admSaisir(ctx,
                              col: col,
                              champs: _champsAss,
                              titreCreation: 'Nouvelle couverture',
                              entite: 'Couverture',
                              prefixeId: 'ASP',
                              initiales: {'dateDebut': iso(c.aujourdhui), 'taux': '80', 'beneficiaires': '0'},
                              fiche: transformer)),
                  ],
                  actionsLigne: (context, x) => admActionsLigne(ctx, c, col, x,
                      modifier: (f) => admSaisir(ctx, col: col, champs: _champsAss, titreCreation: '', entite: 'Couverture', existante: f, fiche: transformer)),
                ),
              ]);
            }));
  }
}
