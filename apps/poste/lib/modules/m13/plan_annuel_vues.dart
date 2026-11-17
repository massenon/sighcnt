import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/plan_annuel_poste.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../m14/commun_m14.dart' show libelleRole;
import '../../shell/contexte_ecran.dart';
import '../m4/mat_commun.dart';
import 'adm_commun.dart';

/// m13-plan-annuel (lot PTA, 16/11/2026) : le plan annuel de travail PAR EXERCICE, suivi chiffré, adopté par la Direction, synchronisé. Rien n'est écrit en dur : l'exercice, les axes, les
/// états, le responsable (référence au personnel ou à un poste), les signataires de l'impression et la tolérance de l'alerte se LISENT en base (`plan_annuel_poste.dart`).
class EcranPlanAnnuel extends StatefulWidget with EcranMaquette {
  const EcranPlanAnnuel({super.key});
  @override
  String get titre => 'Plan annuel de travail';
  @override
  String get description => 'Programmation annuelle des activités de la clinique, par exercice, par axe et par trimestre, avec suivi chiffré.';

  @override
  State<EcranPlanAnnuel> createState() => _EcranPlanAnnuelState();
}

class _EcranPlanAnnuelState extends State<EcranPlanAnnuel> {
  int? _annee;

  String _nomEtat(Magasin m, Object? code) => referentielPlan(m, 'etat').where((e) => e['code'] == code).map((e) => '${e['libelle']}').firstOrNull ?? 'État inconnu';
  TonSigh _tonEtat(Magasin m, Object? code) => matTon(referentielPlan(m, 'etat').where((e) => e['code'] == code).map((e) => '${e['ton']}').firstOrNull ?? 'neutral');
  String _nomAxe(Magasin m, Object? code) => referentielPlan(m, 'axe').where((e) => e['code'] == code).map((e) => '${e['libelle']}').firstOrNull ?? 'Axe inconnu';
  String _fcfa(num? v) => v == null ? 'Non renseigné' : money(v, avecDevise: false);
  String _pct(num? v) => v == null ? 'Non renseigné' : '${nombre(v)} %';

  void _refus(BuildContext ctx, RefusPlan r) => ToastsSigh.afficher(ctx, 'Refusé : ${r.code}', type: TypeToast.erreur, detail: '${r.motif} ${r.geste}');

  List<ChampDef> _champs(Magasin m, int annee, String portee) {
    final contenu = portee != 'suivi', suivi = portee != 'contenu';
    return [
      if (contenu) ...[
        const ChampDef(nom: 'action', libelle: 'Action', requis: true, col: ColChamp.plein),
        ChampDef(nom: 'axe', libelle: 'Axe', type: TypeChamp.select, requis: true, options: [for (final a in referentielPlan(m, 'axe')) OptionChamp('${a['code']}', '${a['libelle']}')]),
        ChampDef(nom: 'responsable', libelle: 'Responsable (personnel ou fonction)', type: TypeChamp.select, requis: true, options: [for (final o in optionsResponsablesPlan(m)) OptionChamp(o.$1, o.$2)]),
        ChampDef(nom: 'trimestreDebut', libelle: 'Trimestre de début', type: TypeChamp.select, requis: true, options: [for (var q = 1; q <= 4; q++) OptionChamp('$q', 'T$q')]),
        ChampDef(nom: 'trimestreFin', libelle: 'Trimestre de fin', type: TypeChamp.select, requis: true, options: [for (var q = 1; q <= 4; q++) OptionChamp('$q', 'T$q')]),
        const ChampDef(nom: 'budgetPrevu', libelle: 'Budget prévu (FCFA)', type: TypeChamp.nombre),
        ChampDef(nom: 'budgetId', libelle: 'Ligne du module Budgets', type: TypeChamp.select, options: [
          for (final b in m.collection('budgets').actives) if ('${b['exercice']}' == '$annee') OptionChamp('${b['id']}', '${b['reference']} : ${b['centre']}')
        ]),
        const ChampDef(nom: 'indicateur', libelle: 'Indicateur de résultat'),
        const ChampDef(nom: 'cible', libelle: 'Cible de l’indicateur', type: TypeChamp.nombre),
      ],
      if (suivi) ...[
        ChampDef(nom: 'avancement', libelle: 'État d’avancement', type: TypeChamp.select, requis: true, options: [for (final e in referentielPlan(m, 'etat')) OptionChamp('${e['code']}', '${e['libelle']}')]),
        const ChampDef(nom: 'tauxAvancement', libelle: 'Avancement (%)', type: TypeChamp.nombre, aide: 'De 0 à 100 ; laissé vide : non renseigné (ce n’est pas zéro).'),
        const ChampDef(nom: 'budgetRealise', libelle: 'Budget réalisé (FCFA)', type: TypeChamp.nombre),
        const ChampDef(nom: 'valeurAtteinte', libelle: 'Valeur atteinte de l’indicateur', type: TypeChamp.nombre),
        const ChampDef(nom: 'observations', libelle: 'Observations', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
      ],
    ];
  }

  Fiche _nombres(Fiche v) {
    final f = {...v};
    for (final k in const ['budgetPrevu', 'budgetRealise', 'cible', 'valeurAtteinte', 'tauxAvancement']) {
      if (f.containsKey(k)) f[k] = admNombre(f[k]);
    }
    return f;
  }

  Map<String, Object?> _valeurs(Fiche r) => {
        for (final e in r.entries) e.key: e.value is num ? '${e.value}' : e.value,
        if (r['responsableType'] != null) 'responsable': '${r['responsableType']}:${r['responsableRef']}',
      };

  void _modale(BuildContext ctx, String titre, String sousTitre, List<ChampDef> champs, Map<String, Object?> initiales, String libelle, bool Function(Map<String, Object?>) surValider) {
    final ctl = ControleurFormulaire(champs, initiales);
    afficherModale<void>(ctx,
        titre: titre,
        sousTitre: sousTitre,
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: libelle,
                  icone: LucideIcons.save,
                  onPressed: () {
                    final saisie = ctl.valider();
                    if (saisie == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    if (surValider(saisie)) fermer();
                  }),
            ]);
  }

  void _creer(BuildContext ctx, ContexteEcran c, int annee, bool apresAdoption) {
    final m = c.magasin;
    final planifie = referentielPlan(m, 'etat').where((e) => e['nature'] == 'planifiee').firstOrNull;
    _modale(ctx, apresAdoption ? 'Ajouter une action après adoption' : 'Nouvelle action', 'Exercice $annee. Les champs marqués d’un astérisque sont obligatoires.',
        [..._champs(m, annee, 'tout'), if (apresAdoption) const ChampDef(nom: 'motif', libelle: 'Motif de l’ajout (plan adopté)', requis: true, col: ColChamp.plein)],
        {'avancement': planifie?['code'] ?? ''}, 'Créer', (v) {
      final motif = '${v.remove('motif') ?? ''}';
      final r = ajouterActionPlan(m, _nombres({...v, 'exercice': annee}), motif: motif);
      if (r.refus != null) {
        _refus(ctx, r.refus!);
        return false;
      }
      ToastsSigh.afficher(ctx, 'Action ${r.fiche!['reference']} créée.', type: TypeToast.succes, annuler: r.annuler);
      return true;
    });
  }

  void _suivre(BuildContext ctx, ContexteEcran c, Fiche r, bool figee) {
    final m = c.magasin;
    _modale(ctx, figee ? 'Suivi de l’action' : 'Modifier l’action', '${r['reference']}', _champs(m, (r['exercice'] as num).toInt(), figee ? 'suivi' : 'tout'), _valeurs(r), 'Enregistrer', (v) {
      final patch = <String, Object?>{};
      for (final e in _nombres(v).entries) {
        if (e.value != null && e.value != '') patch[e.key] = e.value;
      }
      final resp = patch.remove('responsable');
      if (resp is String && resp.contains(':')) {
        patch['responsableType'] = resp.substring(0, resp.indexOf(':'));
        patch['responsableRef'] = resp.substring(resp.indexOf(':') + 1);
      }
      for (final k in const ['trimestreDebut', 'trimestreFin']) {
        final n = num.tryParse('${patch[k] ?? ''}');
        if (n != null) patch[k] = n.toInt();
      }
      try {
        final annuler = m.collection('planAnnuel').mettreAJour(r['id'], patch);
        ToastsSigh.afficher(ctx, 'Modifications enregistrées.', type: TypeToast.succes, annuler: annuler);
        return true;
      } on EcritureRefusee catch (e) {
        ToastsSigh.afficher(ctx, 'Écriture refusée.', type: TypeToast.erreur, detail: e.motif);
        return false;
      }
    });
  }

  void _reviser(BuildContext ctx, ContexteEcran c, Fiche r) {
    final m = c.magasin;
    _modale(ctx, 'Réviser l’action', '${r['reference']} : version ${((r['version'] as num?) ?? 1).toInt() + 1}',
        [..._champs(m, (r['exercice'] as num).toInt(), 'contenu'), const ChampDef(nom: 'motif', libelle: 'Motif de la révision', requis: true, col: ColChamp.plein)], _valeurs(r), 'Créer la version', (v) {
      final motif = '${v.remove('motif') ?? ''}';
      final x = reviserActionPlan(m, r['id'], _nombres(v), motif);
      if (x.refus != null) {
        _refus(ctx, x.refus!);
        return false;
      }
      ToastsSigh.afficher(ctx, 'Version ${x.fiche!['version']} créée.', type: TypeToast.succes);
      return true;
    });
  }

  Future<void> _adopter(BuildContext ctx, ContexteEcran c, int annee) async {
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Adopter le plan $annee ?', message: 'L’adoption est datée et journalisée. Ensuite le contenu du plan ne change plus que par version datée.', libelleOk: 'Adopter');
    if (motif == null || !ctx.mounted) return;
    final r = adopterPlan(c.magasin,
        annee: annee, motif: motif, gesteAccorde: c.donnees?.matrice.droitGeste(c.role, paGesteAdopter) ?? false, libelleRole: libelleRole(c.magasin, c.role));
    if (r != null) {
      _refus(ctx, r);
      return;
    }
    ToastsSigh.afficher(ctx, 'Plan $annee adopté.', type: TypeToast.succes);
  }

  void _reconduire(BuildContext ctx, ContexteEcran c, int annee, List<Fiche> precedents) {
    final ctl = ControleurFormulaire([
      ChampDef(nom: 'source', libelle: 'Exercice source', type: TypeChamp.select, requis: true, options: [for (final x in precedents.reversed) OptionChamp('${x['annee']}', 'Exercice ${x['annee']}')])
    ]);
    afficherModale<void>(ctx,
        titre: 'Reconduire dans l’exercice $annee',
        sousTitre: 'Copie datée des actions non réalisées ; l’exercice source n’est jamais réécrit.',
        taille: TailleModale.md,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Reconduire',
                  icone: LucideIcons.copyPlus,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final r = reconduirePlan(c.magasin, v['source'], annee);
                    if (r.refus != null) {
                      _refus(ctx, r.refus!);
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, '${r.copiees.length} action(s) reconduite(s)${r.ignorees.isEmpty ? '.' : ', ${r.ignorees.length} déjà reconduite(s) ou ignorée(s).'}', type: TypeToast.succes);
                  }),
            ]);
  }

  void _signataires(BuildContext ctx, ContexteEcran c) {
    final m = c.magasin;
    final jour = parametreDateIso(c.aujourdhui);
    final cur = signatairesPlan(m, jour);
    final postes = [for (final p in m.collection('postes').actives) OptionChamp('${p['id']}', '${p['poste']}${'${p['titulaire'] ?? ''}'.isEmpty ? '' : ' : ${p['titulaire']}'}')];
    _modale(
        ctx,
        'Signataires de l’impression',
        'Une fonction de l’organigramme ; le titulaire se lit au poste à la date de l’impression.',
        [
          ChampDef(nom: 'p1', libelle: 'Premier signataire (fonction)', type: TypeChamp.select, requis: true, options: postes),
          ChampDef(nom: 'p2', libelle: 'Second signataire (fonction)', type: TypeChamp.select, options: postes),
          const ChampDef(nom: 'dateEffet', libelle: 'Date d’effet', type: TypeChamp.date, requis: true),
          const ChampDef(nom: 'motif', libelle: 'Motif', requis: true, col: ColChamp.plein),
        ],
        {'p1': cur.isNotEmpty ? cur[0].posteId : '', 'p2': cur.length > 1 ? cur[1].posteId : '', 'dateEffet': jour},
        'Enregistrer', (v) {
      final ids = [for (final k in const ['p1', 'p2']) if ('${v[k] ?? ''}'.isNotEmpty) '${v[k]}'];
      final r = definirSignatairesPlan(m,
          posteIds: ids,
          dateEffet: '${v['dateEffet']}'.substring(0, 10),
          motif: '${v['motif'] ?? ''}',
          gesteAccorde: c.donnees?.matrice.droitGeste(c.role, pcGesteRegler) ?? false,
          libelleRole: libelleRole(m, c.role));
      if (r != null) {
        _refus(ctx, r);
        return false;
      }
      ToastsSigh.afficher(ctx, 'Signataires réglés.', type: TypeToast.succes);
      return true;
    });
  }

  List<Signature> _signatures(Magasin m, String jour) =>
      [for (final s in signatairesPlan(m, jour)) Signature(s.fonction ?? 'Fonction introuvable', nom: s.nom ?? 'Poste vacant')];

  void _imprimerPlan(BuildContext ctx, ContexteEcran c, int annee, List<Fiche> rows, TotauxPlan t, Fiche? adoption) {
    final m = c.magasin;
    matImprimer(ctx,
        titre: 'Plan annuel de travail',
        sousTitre: 'Exercice $annee${adoption != null ? ', adopté le ${dateFR(DateTime.parse('${adoption['dateAdoption']}'))}' : ', non adopté'}',
        cartouche: [('Exercice', '$annee'), ('Actions programmées', nombre(t.nb)), ('Réalisées', nombre(t.parNature['realisee'] ?? 0)), ('Date d’édition', dateFR(c.aujourdhui))],
        blocs: [
          BlocTableau(TableauEtat(colonnes: [
            ColonneEtat(libelle: 'N°', valeur: (r) => r['reference']),
            ColonneEtat(libelle: 'Action', valeur: (r) => r['action']),
            ColonneEtat(libelle: 'Axe', valeur: (r) => _nomAxe(m, r['axe'])),
            ColonneEtat(libelle: 'Période', valeur: (r) => 'T${matTexteNombre(r['trimestreDebut'])} à T${matTexteNombre(r['trimestreFin'])}'),
            ColonneEtat(libelle: 'Responsable', valeur: (r) => libelleResponsablePlan(m, r) ?? 'Responsable introuvable'),
            ColonneEtat(libelle: 'Avancement', valeur: (r) => _nomEtat(m, r['avancement'])),
          ], lignes: admTrierPlan(rows))),
        ],
        signatures: _signatures(m, parametreDateIso(c.aujourdhui)));
  }

  void _imprimerBilan(BuildContext ctx, ContexteEcran c, int annee, List<Fiche> rows, TotauxPlan t) {
    final m = c.magasin;
    // Le TOTAL est une ligne CALCULÉE par le domaine (`paTotaux`), jamais fournie : « Non calculable » quand aucune action ne porte le montant (ce n'est pas zéro).
    final lignes = [
      ...admTrierPlan(rows),
      {'reference': 'TOTAL (calculé)', 'action': '', '_total': true}
    ];
    String indic(Fiche r) {
      if (r['_total'] == true) return '';
      final a = paAtteinteIndicateur(r);
      final nom = '${r['indicateur'] ?? ''}';
      return nom.isEmpty ? 'Aucun' : '$nom : ${a.calculable ? '${nombre(a.pct!)} % de la cible' : 'non calculable'}';
    }

    matImprimer(ctx,
        titre: 'Bilan du plan annuel de travail',
        sousTitre: 'Exercice $annee : réalisé contre prévu',
        cartouche: [('Exercice', '$annee'), ('Actions', nombre(t.nb)), ('Réalisées', nombre(t.parNature['realisee'] ?? 0)), ('Date d’édition', dateFR(c.aujourdhui))],
        blocs: [
          BlocTableau(TableauEtat(colonnes: [
            ColonneEtat(libelle: 'N°', valeur: (r) => r['reference']),
            ColonneEtat(libelle: 'Action', valeur: (r) => r['action']),
            ColonneEtat(libelle: 'État', valeur: (r) => r['_total'] == true ? '' : _nomEtat(m, r['avancement'])),
            ColonneEtat(libelle: 'Taux', droite: true, valeur: (r) => r['_total'] == true ? (t.tauxMoyen == null ? 'Non calculable' : _pct(t.tauxMoyen)) : _pct(paPourcentage(r['tauxAvancement']).valeur)),
            ColonneEtat(libelle: 'Budget prévu', droite: true, valeur: (r) => r['_total'] == true ? (t.prevu == null ? 'Non calculable' : _fcfa(t.prevu)) : _fcfa(paNombre(r['budgetPrevu']).valeur)),
            ColonneEtat(libelle: 'Budget réalisé', droite: true, valeur: (r) => r['_total'] == true ? (t.realise == null ? 'Non calculable' : _fcfa(t.realise)) : _fcfa(paNombre(r['budgetRealise']).valeur)),
            ColonneEtat(libelle: 'Indicateur', valeur: indic),
          ], lignes: lignes)),
        ],
        signatures: _signatures(m, parametreDateIso(c.aujourdhui)));
  }

  Widget _gantt(Magasin m, List<Fiche> rows) {
    const entete = TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600);
    Widget h(String t, {bool centre = false}) => Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 10), child: Align(alignment: centre ? Alignment.center : Alignment.centerLeft, child: Text(t, style: entete)));
    Color tonBarre(Object? etat) => switch (referentielPlan(m, 'etat').where((e) => e['code'] == etat).map((e) => '${e['ton']}').firstOrNull) {
          'success' => JetonsShell.success400,
          'info' => JetonsShell.info400,
          _ => JetonsShell.warning400,
        };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 768,
        child: Table(
          columnWidths: const {0: FlexColumnWidth(3.2), 1: FlexColumnWidth(1.6), 2: FlexColumnWidth(0.9), 3: FlexColumnWidth(0.9), 4: FlexColumnWidth(0.9), 5: FlexColumnWidth(0.9), 6: FlexColumnWidth(1.3)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: const TableBorder(horizontalInside: BorderSide(color: JetonsShell.slate100)),
          children: [
            TableRow(decoration: const BoxDecoration(color: JetonsShell.slate50), children: [h('Action'), h('Axe'), h('T1', centre: true), h('T2', centre: true), h('T3', centre: true), h('T4', centre: true), h('Avancement')]),
            for (final r in admTrierPlan(rows))
              TableRow(children: [
                Padding(padding: const EdgeInsets.all(12), child: Text('${r['action'] ?? ''}', style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14))),
                Padding(padding: const EdgeInsets.all(12), child: Align(alignment: Alignment.centerLeft, child: BadgeSigh(_nomAxe(m, r['axe']), ton: TonSigh.navy))),
                for (var q = 1; q <= 4; q++)
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                      child: Container(
                          key: Key('adm:barre:${r['reference']}:T$q'),
                          height: 12,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(9999), color: admTrimestreActif(r, q) ? tonBarre(r['avancement']) : JetonsShell.slate100))),
                Padding(padding: const EdgeInsets.all(12), child: Align(alignment: Alignment.centerLeft, child: BadgeSigh(_nomEtat(m, r['avancement']), ton: _tonEtat(m, r['avancement'])))),
              ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final col = m.collection('planAnnuel');
    final exos = exercicesPlan(m);
    final anneeJour = c.aujourdhui.year;
    final annee = _annee ?? (exos.any((x) => x['annee'] == anneeJour) ? anneeJour : (exos.isEmpty ? anneeJour : (exos.last['annee'] as num).toInt()));
    final geste = c.donnees?.matrice.droitGeste(c.role, paGesteAdopter) ?? false;
    final reglage = c.donnees?.matrice.droitGeste(c.role, pcGesteRegler) ?? false;
    return ListenableBuilder(
        listenable: Listenable.merge([col, m.collection('adoptionsPlan'), m.collection('reglagesPlan'), m.collection('referentielsPlan')]),
        builder: (context, _) {
          final rows = actionsPlan(m, annee);
          final adoption = adoptionPlan(m, annee);
          final figee = adoption != null;
          final t = paTotaux(rows, natureDeEtatPlan(m));
          final jour = parametreDateIso(c.aujourdhui);
          final retards = {for (final a in alertesRetardPlan(m, jour)) '${a.action['id']}'};
          final precedents = [for (final x in exos) if ((x['annee'] as num) < annee) x];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            admLectureSeule(c),
            Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                  width: 190,
                  child: SelecteurSigh(
                      key: const Key('plan:exercice'),
                      libelle: 'Exercice',
                      valeur: exos.any((x) => x['annee'] == annee) ? '$annee' : '',
                      options: [for (final x in exos) OptionChamp('${(x['annee'] as num).toInt()}', 'Exercice ${x['annee']}')],
                      surChange: (v) => setState(() => _annee = int.tryParse(v)))),
              figee ? BadgeSigh('Adopté le ${dateFR(DateTime.parse('${adoption['dateAdoption']}'))} par ${adoption['adoptePar']}', ton: TonSigh.succes) : const BadgeSigh('Plan non adopté', ton: TonSigh.attention),
              if (figee) Text('Motif : ${adoption['motif']}. Le contenu ne change plus que par version datée.', style: const TextStyle(fontSize: 12, color: JetonsShell.slate500)),
            ]),
            const SizedBox(height: 16),
            admKpis([
              AdmKpi('Actions programmées', nombre(t.nb), 'list-checks', 'navy'),
              AdmKpi('Réalisées', nombre(t.parNature['realisee'] ?? 0), 'check-circle-2', 'success'),
              AdmKpi('En cours', nombre(t.parNature['en_cours'] ?? 0), 'loader', 'info'),
              AdmKpi('Planifiées', nombre(t.parNature['planifiee'] ?? 0), 'calendar-clock', 'warning'),
              AdmKpi('En retard', nombre(retards.length), 'triangle-alert', retards.isEmpty ? 'neutral' : 'danger'),
              AdmKpi('Avancement moyen', t.tauxMoyen == null ? 'Non calculable' : '${nombre(t.tauxMoyen!)} %', 'list-checks', 'navy', t.nbSansTaux > 0 ? '${t.nbSansTaux} action(s) sans pourcentage' : null),
              AdmKpi('Budget prévu', t.prevu == null ? 'Non renseigné' : money(t.prevu!, avecDevise: false), 'wallet', 'navy', t.nbSansPrevu > 0 ? '${t.nbSansPrevu} action(s) sans budget' : null),
              AdmKpi('Budget réalisé', t.realise == null ? 'Non renseigné' : money(t.realise!, avecDevise: false), 'wallet', 'info', t.nbSansRealise > 0 ? '${t.nbSansRealise} action(s) sans réalisé' : null),
            ]),
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Plan annuel de travail $annee',
                sansRemplissage: true,
                actions: [
                  if (c.droit.editer && !figee) BoutonSigh(libelle: 'Nouvelle action', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _creer(context, c, annee, false)),
                  if (c.droit.editer && figee)
                    BoutonSigh(libelle: 'Ajouter après adoption', icone: LucideIcons.plus, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _creer(context, c, annee, true)),
                  if (!figee && geste) BoutonSigh(libelle: 'Adopter le plan', icone: LucideIcons.badgeCheck, taille: TailleBouton.sm, onPressed: () => _adopter(context, c, annee)),
                  if (c.droit.editer && !figee && precedents.isNotEmpty)
                    BoutonSigh(
                        libelle: 'Reconduire les actions non réalisées', icone: LucideIcons.copyPlus, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _reconduire(context, c, annee, precedents)),
                  BoutonSigh(libelle: 'Imprimer le plan', icone: LucideIcons.printer, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _imprimerPlan(context, c, annee, rows, t, adoption)),
                  BoutonSigh(libelle: 'Imprimer le bilan', icone: LucideIcons.fileChartColumn, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _imprimerBilan(context, c, annee, rows, t)),
                  if (reglage) BoutonSigh(libelle: 'Signataires de l’impression', icone: LucideIcons.signature, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _signataires(context, c)),
                ],
                child: rows.isEmpty ? Padding(padding: const EdgeInsets.all(16), child: Text('Aucune action programmée pour l’exercice $annee.')) : _gantt(m, rows)),
            const SizedBox(height: 16),
            TableauSigh(
              titre: 'Détail des actions',
              lignes: rows,
              taillePage: 15,
              nomExport: 'plan-annuel',
              filtres: [
                FiltreTableau(nom: 'axe', libelle: 'Axe', options: [for (final a in referentielPlan(m, 'axe')) OptionChamp('${a['code']}', '${a['libelle']}')]),
                FiltreTableau(nom: 'avancement', libelle: 'Avancement', options: [for (final e in referentielPlan(m, 'etat')) OptionChamp('${e['code']}', '${e['libelle']}')]),
              ],
              actionsLigne: (ctx, f) => [
                if (c.droit.editer) BoutonIcone(icone: LucideIcons.pencil, libelle: figee ? 'Suivre l’action' : 'Modifier', onPressed: () => _suivre(ctx, c, f, figee)),
                if (c.droit.editer && figee) BoutonIcone(icone: LucideIcons.gitBranchPlus, libelle: 'Réviser (version datée)', onPressed: () => _reviser(ctx, c, f)),
                if (c.droit.annuler && !figee) BoutonIcone(icone: LucideIcons.archive, libelle: 'Archiver', onPressed: () => admArchiver(ctx, col, f)),
              ],
              colonnes: [
                ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, rendu: (_, r) => matRef('${r['reference']}${((r['version'] as num?) ?? 1) > 1 ? ' v${r['version']}' : ''}')),
                const ColonneTableau(cle: 'action', libelle: 'Action'),
                ColonneTableau(cle: 'axe', libelle: 'Axe', texte: (r) => _nomAxe(m, r['axe']), rendu: (_, r) => BadgeSigh(_nomAxe(m, r['axe']), ton: TonSigh.navy)),
                ColonneTableau(cle: 'trimestreDebut', libelle: 'Période', droite: true, texte: (r) => 'T${matTexteNombre(r['trimestreDebut'])} à T${matTexteNombre(r['trimestreFin'])}'),
                ColonneTableau(cle: 'responsableRef', libelle: 'Responsable', texte: (r) => libelleResponsablePlan(m, r) ?? 'Responsable introuvable'),
                ColonneTableau(
                    cle: 'avancement',
                    libelle: 'Avancement',
                    texte: (r) => _nomEtat(m, r['avancement']),
                    rendu: (_, r) => Wrap(spacing: 4, runSpacing: 4, children: [
                          BadgeSigh(_nomEtat(m, r['avancement']), ton: _tonEtat(m, r['avancement'])),
                          if (retards.contains('${r['id']}')) const BadgeSigh('En retard', ton: TonSigh.danger),
                        ])),
                ColonneTableau(cle: 'tauxAvancement', libelle: 'Taux', droite: true, texte: (r) => _pct(paPourcentage(r['tauxAvancement']).valeur)),
                ColonneTableau(cle: 'budgetPrevu', libelle: 'Budget prévu', droite: true, texte: (r) => _fcfa(paNombre(r['budgetPrevu']).valeur)),
                ColonneTableau(cle: 'budgetRealise', libelle: 'Budget réalisé', droite: true, texte: (r) => _fcfa(paNombre(r['budgetRealise']).valeur)),
                ColonneTableau(
                    cle: 'budgetId',
                    libelle: 'Ligne Budgets',
                    texte: (r) => r['budgetId'] == null ? 'Non rattaché' : '${m.collection('budgets').parId(r['budgetId'])?['reference'] ?? 'Non rattaché'}'),
                ColonneTableau(
                    cle: 'indicateur',
                    libelle: 'Indicateur',
                    texte: (r) {
                      final nom = '${r['indicateur'] ?? ''}';
                      if (nom.isEmpty) return 'Aucun';
                      final a = paAtteinteIndicateur(r);
                      return '$nom : ${a.calculable ? '${nombre(a.pct!)} % de la cible' : 'non calculable (${a.motif})'}';
                    }),
              ],
            ),
          ]);
        });
  }
}
