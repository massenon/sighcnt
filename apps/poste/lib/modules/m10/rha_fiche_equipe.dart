import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m4/mat_commun.dart';
import '../m9/commun.dart' show ecoute;
import 'plan_indiv.dart';
import 'rhb_circuit.dart' show rhbPlanningPoste;
import 'rhb_planning.dart' show rhbVacationCompte;
import 'rha_commun.dart';

/// `m10-fiche-equipe` (lot SURV, Direction 16/11/2026, section AQ point 37) : la fiche du personnel de SON ÉQUIPE, en LECTURE RESTREINTE, ouverte par le geste réservé
/// `ouvrir_fiche_personnel_equipe` (fiche RBAC, défaut : le Surveillant). Ni salaire, ni catégorie, ni date d'embauche, ni numéro CNSS, ni assurance, ni primes (RG-13) :
/// l'écran ne lit JAMAIS la fiche du personnel, il lit la projection à liste blanche du domaine (`ficheEquipe`, `equipeDeLaSession`). Les commandes sont celles de l'onglet
/// « Planning personnalisé » : absentes sans leur geste, et le moteur refuse un agent hors de l'équipe.
class EcranFicheEquipe extends StatefulWidget with EcranMaquette {
  const EcranFicheEquipe({super.key});
  @override
  String get titre => 'Fiche de mon équipe';
  @override
  String get description => 'Lecture restreinte des agents de votre équipe : identité, fonction, service et planning.';

  @override
  State<EcranFicheEquipe> createState() => _EcranFicheEquipeState();
}

class _EcranFicheEquipeState extends State<EcranFicheEquipe> {
  ControleurFormulaire? _ctl;
  String? _equipeDe;

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
        listenable: ecoute(c, ['personnel', 'planning', 'planningsPersonnalises']),
        builder: (context, _) {
          final eq = rhbPlanningPoste(c).equipeDeLaSession();
          if (eq['ok'] != true) return NoteSigh('${eq['motif']} ${eq['geste']}', ton: TonSigh.danger);
          final agents = trierPar([for (final a in (eq['agents'] as List)) (a as Map).cast<String, Object?>()], (e) => e['matricule']);
          final portee = '${eq['portee']}';
          final cle = agents.map((a) => a['id']).join('|');
          if (_ctl == null || _equipeDe != cle) {
            _ctl?.dispose();
            _equipeDe = cle;
            _ctl = ControleurFormulaire([
              ChampDef(nom: 'agent', libelle: 'Agent de l’équipe', type: TypeChamp.select, recherche: true, options: [for (final e in agents) OptionChamp('${e['id']}', '${e['nomComplet']}')])
            ], {'agent': agents.isEmpty ? '' : '${agents.first['id']}'});
            _ctl!.addListener(() => setState(() {}));
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            NoteSigh('Lecture restreinte : aucune donnée de paie. '
                '${portee == 'equipe' ? 'Périmètre : votre service, sans vous-même.' : 'Périmètre : tout le personnel (vous le lisez déjà en entier).'}'),
            const SizedBox(height: 8),
            Text('Équipe : ${agents.length} agent(s).', style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
            const SizedBox(height: 16),
            if (agents.isEmpty)
              const VideSigh('Aucun agent dans votre équipe.', icone: LucideIcons.users)
            else ...[
              CarteSigh(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 512), child: FormulaireSigh(controleur: _ctl!))),
              const SizedBox(height: 16),
              CarteSigh(child: _fiche(context, c, '${_ctl!['agent']}')),
            ],
          ]);
        });
  }

  Widget _fiche(BuildContext context, ContexteEcran c, String id) {
    final r = rhbPlanningPoste(c).ficheEquipe(id);
    if (r['ok'] != true) return NoteSigh('${r['motif']} ${r['geste']}', ton: TonSigh.danger);
    final f = (r['fiche'] as Map).cast<String, Object?>();
    final auj = c.aujourdhui;
    final vac = trierPar(rhaVacations(c.magasin.collection('planning').actives.where(rhbVacationCompte), f['id'], auj.year, auj.month), (p) => p['date']);
    final gardes = rhaCompter(vac, 'garde'), permanences = rhaCompter(vac, 'permanence');
    return Column(key: ValueKey('fiche-equipe-$id'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: JetonsShell.navy50, borderRadius: BorderRadius.circular(8)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: JetonsShell.navy900, shape: BoxShape.circle),
              child: Text(rhaInitiales(f['nomComplet']), style: const TextStyle(color: Colors.white, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${f['nomComplet']}', style: const TextStyle(color: JetonsShell.slate900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
            Text('${f['poste'] ?? ''}', style: const TextStyle(color: JetonsShell.navy700, fontSize: 12, height: 16 / 12)),
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('Matricule ${f['matricule']} · ${f['service']}', style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12))),
          ])),
        ]),
      ),
      const SizedBox(height: 16),
      OngletsSigh(onglets: [
        OngletDef(
            id: 'infos',
            libelle: 'Informations',
            construire: (_) => Padding(
                padding: const EdgeInsets.only(top: 16),
                child: DescListeSigh([
                  ('Matricule', '${f['matricule']}'),
                  ('Nom et prénoms', '${f['nomComplet']}'),
                  ('Sexe', f['sexe'] == 'F' ? 'Féminin' : 'Masculin'),
                  ('Fonction', rhaFonctionLabel(f['fonction'])),
                  ('Poste', f['poste'] as String?),
                  ('Service', f['service'] as String?),
                ]))),
        OngletDef(id: 'planning-perso', libelle: 'Planning personnalisé', construire: (_) => planOngletPlanningPerso(context, c, f)),
        OngletDef(
            id: 'planning',
            libelle: 'Planning du mois',
            construire: (_) => vac.isEmpty
                ? const Padding(padding: EdgeInsets.only(top: 16), child: VideSigh('Aucune vacation programmée ce mois-ci.', icone: LucideIcons.calendar))
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      KpiGrilleSigh(colonnes: 2, kpis: [
                        KpiSigh(libelle: 'Gardes', valeur: nombre(gardes), icone: LucideIcons.moon, ton: TonSigh.danger),
                        KpiSigh(libelle: 'Permanences', valeur: nombre(permanences), icone: LucideIcons.sun, ton: TonSigh.attention),
                      ]),
                      const SizedBox(height: 12),
                      MiniTableauSigh(colonnes: [
                        ColonneMini('Date', (p) => dateJour(rhaDate(p['date'])!)),
                        ColonneMini('Vacation', (p) => rhaTypePlanningLabel(p['type']), rendu: (p) => BadgeSigh(rhaTypePlanningLabel(p['type']), ton: matTon(rhaTypePlanningTon(p['type'])))),
                        ColonneMini('Statut', (p) => p['statut'] == 'validee' ? 'Validée' : 'Brouillon', rendu: (p) => rhaBadgeStatut(p['statut'] == 'validee' ? 'validee' : 'brouillon')),
                      ], lignes: vac),
                    ]))),
      ]),
    ]);
  }
}
