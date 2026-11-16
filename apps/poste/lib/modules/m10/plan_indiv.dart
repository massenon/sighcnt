import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rhb_circuit.dart';

/// Lot PLAN-INDIV (16/11/2026) : les VALEURS D'ATTENTE de la fiche du personnel et l'onglet « Planning personnalisé ». Aucune règle ici : le contrôle du modèle, l'aperçu de
/// l'application à une période et la confirmation d'une valeur sont ceux du domaine (`planning_rh.dart`, vecteurs de la maquette), appelés par `PlanningRhPoste`. Les commandes
/// réservées sont des GESTES de la fiche RBAC (jamais un nom de rôle) : absentes sans le droit, et le moteur refuse aussi.

bool _geste(ContexteEcran c, String g) => c.donnees?.matrice.droitGeste(c.role, g) ?? false;

/// La valeur d'un champ du personnel, avec sa mention « valeur d'attente » et, avec le droit, le bouton « Confirmer ».
Widget planValeurAttente(BuildContext ctx, ContexteEcran c, Fiche e, String cle, String? texte) {
  final p = rhbPlanningPoste(c);
  if (!p.valeursAttente(e['id']).contains(cle)) return Text(texte == null || texte.isEmpty ? '—' : texte, style: _styleValeur);
  return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
    Text(texte == null || texte.isEmpty ? '—' : texte, style: _styleValeur),
    const BadgeSigh('Valeur d’attente', ton: TonSigh.attention),
    if (_geste(c, gesteValeurAttenteRh))
      BoutonSigh(libelle: 'Confirmer', taille: TailleBouton.sm, onPressed: () => _confirmer(ctx, c, e, cle)),
  ]);
}

const _styleValeur = TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500);

void _confirmer(BuildContext ctx, ContexteEcran c, Fiche e, String cle) {
  final ctl = ControleurFormulaire(const [
    ChampDef(nom: 'motif', libelle: 'Motif (document ou décision qui arrête la valeur)', type: TypeChamp.textarea, lignes: 2, requis: true, col: ColChamp.plein),
  ]);
  afficherModale<void>(ctx,
      titre: 'Confirmer : ${libelleChampAttenteRh(cle)}',
      sousTitre: '${e['nomComplet']} · ${e['matricule']}',
      taille: TailleModale.md,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const NoteSigh('La valeur est gardée telle quelle et ne porte plus la mention « valeur d’attente ». Le geste est journalisé (RG-12).'),
        const SizedBox(height: 12),
        FormulaireSigh(controleur: ctl),
      ]),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: 'Confirmer la valeur',
                icone: LucideIcons.check,
                onPressed: () {
                  final v = ctl.valider();
                  if (v == null) return;
                  final r = rhbPlanningPoste(c).confirmerValeurAttente(employeId: e['id'], champ: cle, motif: v['motif'] as String?);
                  if (r['ok'] != true) {
                    rhbToastRefus(ctx, r);
                    return;
                  }
                  fermer();
                  ToastsSigh.afficher(ctx, 'Valeur confirmée.', type: TypeToast.succes, detail: libelleChampAttenteRh(cle));
                }),
          ]);
}

const _libEtat = {
  'a_poser': 'À poser',
  'occupe': 'Jour occupé (conservé)',
  'refuse': 'Refusé',
  'libre': 'Libre (hors modèle)',
  'sans_modele': 'Avant le modèle',
};

/// L'onglet « Planning personnalisé » de la fiche : la version courante, l'historique, et (gestes réservés) définir une version, l'appliquer à une période.
Widget planOngletPlanningPerso(BuildContext ctx, ContexteEcran c, Fiche e) => ListenableBuilder(
      listenable: Listenable.merge([c.magasin.collection('planningsPersonnalises'), c.magasin.collection('planning')]),
      builder: (context, _) {
        final p = rhbPlanningPoste(c);
        final h = p.historiquePlanningPerso(e['id']);
        final peutDefinir = _geste(c, gestePlanningPersonnaliseRh);
        final peutAppliquer = peutPoserPlanningRh(c.role) == null && h.isNotEmpty;
        Widget tableJours(Map<String, Object?> v) {
          final mensuel = v['periodicite'] == 'mensuel';
          return MiniTableauSigh(colonnes: [
            ColonneMini(mensuel ? 'Jour du mois' : 'Jour', (j) => mensuel ? '${j['jour']}' : joursSemaineRh[(j['jour'] as num).toInt() - 1]),
            ColonneMini('Vacation', (j) => rhbTypePlanningLabel(j['type']), rendu: (j) => BadgeSigh(rhbTypePlanningLabel(j['type']))),
          ], lignes: [for (final j in (v['jours'] as List)) (j as Map).cast<String, Object?>()], vide: 'Aucun jour.');
        }

        final v = h.isEmpty ? null : h.last;
        return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const NoteSigh(
                  'Le planning personnalisé est un modèle (une semaine type ou un mois type). Il ne compte pour aucune prime : seules les vacations validées du planning comptent (RG-11). « Appliquer à une période » pose des vacations, jamais sur un jour occupé.'),
              if (peutDefinir || peutAppliquer) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (peutDefinir) BoutonSigh(libelle: 'Définir une version', icone: LucideIcons.calendarPlus, taille: TailleBouton.sm, onPressed: () => _definir(ctx, c, e)),
                  if (peutAppliquer)
                    BoutonSigh(
                        libelle: 'Appliquer à une période',
                        icone: LucideIcons.calendarCheck,
                        variante: VarianteBouton.secondaire,
                        taille: TailleBouton.sm,
                        onPressed: () => _appliquer(ctx, c, e)),
                ]),
              ],
              const SizedBox(height: 12),
              if (v == null)
                const VideSigh('Aucun planning personnalisé : cet agent suit la grille de son régime.', icone: LucideIcons.calendar)
              else ...[
                Text('Version ${v['version']} (${v['periodicite'] == 'mensuel' ? 'mensuel' : 'hebdomadaire'}) à compter du ${dateFR(DateTime.parse('${v['dateEffet']}'))}',
                    style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                tableJours(v),
                const SizedBox(height: 12),
                const Text('Historique des versions', style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                MiniTableauSigh(colonnes: [
                  ColonneMini('Version', (x) => '${x['version']}', droite: true),
                  ColonneMini('Date d’effet', (x) => dateFR(DateTime.parse('${x['dateEffet']}'))),
                  ColonneMini('Périodicité', (x) => x['periodicite'] == 'mensuel' ? 'Mensuel' : 'Hebdomadaire'),
                  ColonneMini('Jours', (x) => '${(x['jours'] as List).length}', droite: true),
                  ColonneMini('Motif', (x) => '${x['motif'] == null || x['motif'] == '' ? '—' : x['motif']}'),
                  ColonneMini('Défini par', (x) => '${x['creePar'] ?? '—'}${x['creeLe'] != null && x['creeLe'] != '' ? ' le ${dateFR(DateTime.parse('${x['creeLe']}'))}' : ''}'),
                ], lignes: h),
              ],
            ]));
      },
    );

void _definir(BuildContext ctx, ContexteEcran c, Fiche e) {
  final types = [OptionChamp('', 'Libre'), for (final t in rhbTypesPlanning) OptionChamp(t.id, t.label)];
  final ctl = ControleurFormulaire([
    const ChampDef(nom: 'periodicite', libelle: 'Périodicité', type: TypeChamp.select, requis: true, options: [OptionChamp('hebdomadaire', 'Hebdomadaire'), OptionChamp('mensuel', 'Mensuel')]),
    const ChampDef(nom: 'dateEffet', libelle: 'Date d’effet', type: TypeChamp.date, requis: true),
    const ChampDef.section('Jours du modèle (laisser « Libre » pour un jour sans vacation)'),
    for (var i = 1; i <= 31; i++)
      ChampDef(
          nom: 'j$i',
          libelle: i <= 7 ? 'Jour $i (${joursSemaineRh[i - 1]} en semaine type)' : 'Jour $i',
          type: TypeChamp.select,
          options: types,
          condition: i <= 7 ? null : (controle: 'periodicite', quand: const ['mensuel'])),
    const ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.textarea, lignes: 2, requis: true, col: ColChamp.plein),
  ], {'periodicite': 'hebdomadaire', 'dateEffet': iso(c.aujourdhui)});
  afficherModale<void>(ctx,
      titre: 'Planning personnalisé',
      sousTitre: '${e['nomComplet']} · une version datée : elle ne se réécrit pas.',
      taille: TailleModale.lg,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const NoteSigh('Le modèle est contrôlé comme la grille : type permis par le régime de l’agent à la date d’effet, repos entre deux gardes (la semaine est lue en boucle).'),
        const SizedBox(height: 12),
        FormulaireSigh(controleur: ctl),
      ]),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: 'Enregistrer la version',
                icone: LucideIcons.save,
                onPressed: () {
                  final v = ctl.valider();
                  if (v == null) return;
                  final n = v['periodicite'] == 'mensuel' ? 31 : 7;
                  final jours = [
                    for (var i = 1; i <= n; i++)
                      if ('${v['j$i'] ?? ''}'.isNotEmpty) {'jour': i, 'type': v['j$i']}
                  ];
                  final r = rhbPlanningPoste(c).definirPlanningPerso(
                      employeId: e['id'], periodicite: v['periodicite'] as String?, dateEffet: v['dateEffet'] as String?, motif: v['motif'] as String?, jours: jours);
                  if (r['ok'] != true) {
                    rhbToastRefus(ctx, r);
                    return;
                  }
                  fermer();
                  ToastsSigh.afficher(ctx, 'Planning personnalisé enregistré.', type: TypeToast.succes, detail: 'Version ${r['version']} à compter du ${dateFR(DateTime.parse('${v['dateEffet']}'))}');
                }),
          ]);
}

void _appliquer(BuildContext ctx, ContexteEcran c, Fiche e) {
  final ctl = ControleurFormulaire(const [
    ChampDef(nom: 'du', libelle: 'Du', type: TypeChamp.date, requis: true),
    ChampDef(nom: 'au', libelle: 'Au', type: TypeChamp.date, requis: true),
  ], {'du': iso(c.aujourdhui), 'au': iso(c.aujourdhui.add(const Duration(days: 27)))});
  final bilan = ValueNotifier<Map<String, Object?>?>(null);
  void montrer(Map<String, Object?> r) => bilan.value = r;
  afficherModale<void>(ctx,
      titre: 'Appliquer le planning personnalisé',
      sousTitre: '${e['nomComplet']}',
      taille: TailleModale.lg,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const NoteSigh('L’aperçu n’écrit rien. Un jour déjà occupé n’est jamais écrasé ; chaque jour passe par le contrôle de la grille (repos, double affectation).'),
        const SizedBox(height: 12),
        FormulaireSigh(controleur: ctl),
        const SizedBox(height: 12),
        ValueListenableBuilder<Map<String, Object?>?>(
            valueListenable: bilan,
            builder: (context, r, _) {
              if (r == null) return const SizedBox.shrink();
              if (r['ok'] != true) return NoteSigh('${r['motif']} ${r['geste']}');
              final lignes = [for (final l in (r['lignes'] as List)) (l as Map).cast<String, Object?>()].where((l) => l['etat'] != 'libre').toList();
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${r['apercu'] == true ? 'Aperçu' : 'Appliqué'} : ${r['aPoser']} à poser, ${r['occupes']} jour(s) occupé(s) conservé(s), ${r['refuses']} refusé(s), ${r['libres']} libre(s).',
                    style: const TextStyle(color: JetonsShell.slate600, fontSize: 12, height: 16 / 12)),
                const SizedBox(height: 8),
                MiniTableauSigh(vide: 'Rien à poser sur cette période.', colonnes: [
                  ColonneMini('Date', (l) => dateFR(DateTime.parse('${l['date']}'))),
                  ColonneMini('État', (l) => '${_libEtat[l['etat']] ?? l['etat']}${l['code'] != null ? ' (${l['code']})' : ''}'),
                  ColonneMini('Vacation', (l) => l['type'] == null ? '—' : rhbTypePlanningLabel(l['type'])),
                ], lignes: lignes),
              ]);
            }),
      ]),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: 'Aperçu',
                icone: LucideIcons.eye,
                variante: VarianteBouton.secondaire,
                onPressed: () {
                  final v = ctl.valider();
                  if (v == null) return;
                  montrer(rhbPlanningPoste(c).appliquerPlanningPerso(employeId: e['id'], du: v['du'] as String?, au: v['au'] as String?));
                }),
            BoutonSigh(
                libelle: 'Appliquer',
                icone: LucideIcons.check,
                onPressed: () {
                  final v = ctl.valider();
                  if (v == null) return;
                  final r = rhbPlanningPoste(c).appliquerPlanningPerso(employeId: e['id'], du: v['du'] as String?, au: v['au'] as String?, ecrire: true);
                  montrer(r);
                  if (r['ok'] == true) ToastsSigh.afficher(ctx, '${r['poses']} vacation(s) posée(s).', type: TypeToast.succes, detail: '${r['occupes']} jour(s) occupé(s) conservé(s)');
                }),
          ]);
}
