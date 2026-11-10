import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/planning_rh_poste.dart';
import '../../impression/apercu.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m13/adm_commun.dart';
import 'rhb_circuit.dart';
import 'rhb_commun.dart';

const _etats = [OptionChamp('present', 'Présent'), OptionChamp('retard', 'Retard'), OptionChamp('absent', 'Absent'), OptionChamp('conge', 'Congé')];

/// Le retard se mesure depuis le début des vacations du jour, 08:00 (le seul repère horaire documenté : E2331 point 4).
const _debutVacations = '08:00';

int? _minutesDe(Object? h) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch('${h ?? ''}');
  return m == null ? null : int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

int _retardMinutes(Fiche r) {
  if (r['etat'] != 'retard') return 0;
  final a = _minutesDe(r['heureArrivee']);
  return a == null ? 0 : math.max(0, a - _minutesDe(_debutVacations)!);
}

/// `m10-presences` — « Présences & absences » : pointage quotidien, validé selon le circuit réglé au poste (surveillant seul par défaut, lot L5). Un pointage
/// non validé est visible mais NE COMPTE PAS (retards, absences, taux de présence) ; un pointage validé ne se modifie pas : il se RÉGULARISE (motif, date et
/// auteur consignés). Le registre couvre ~25 jours par agent, soit plus de mille lignes : onze critères de filtre avancé, appliqués au geste (les champs de
/// date se règlent et s'appliquent d'eux-mêmes), et l'état imprimé retrace les filtres en force.
class EcranPresences extends StatefulWidget with EcranMaquette {
  const EcranPresences({super.key});

  @override
  String get description => 'Pointage quotidien, retards et absences, avec incidence sur l’évaluation mensuelle.';

  @override
  String get regle =>
      'Un pointage est validé selon le circuit réglé au poste (surveillant seul par défaut). Tant qu’il ne l’est pas, il est visible mais ne compte pas dans les retards, les absences ni le taux de présence. Un pointage validé ne se modifie pas : il se régularise (motif, date et auteur consignés).';

  @override
  State<EcranPresences> createState() => _EtatPresences();
}

class _EtatPresences extends State<EcranPresences> {
  RhbFiltre? _du, _au, _q, _agent, _matricule, _service, _etat, _motif, _retard, _hDe, _hA, _validation, _validePar;
  List<RhbFiltre> _tous = const [];
  bool _prepare = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prepare) return;
    _prepare = true;
    final c = ContexteEcran.of(context);
    final agents = rhbPersonnelTrie(c);
    final validateurs = <String>{for (final r in rhbActives(c, 'presences')) if (r['validePar'] != null && r['validePar'] != '') '${r['validePar']}'}.toList()..sort();
    ChampDef liste(String nom, String libelle, String vide, List<OptionChamp> options) => ChampDef(nom: nom, libelle: libelle, type: TypeChamp.select, options: [OptionChamp('', vide), ...options]);
    _du = RhbFiltre(const ChampDef(nom: 'pr_f_du', libelle: 'Du', type: TypeChamp.date), iso(ajouterJours(c.aujourdhui, -30)));
    _au = RhbFiltre(const ChampDef(nom: 'pr_f_au', libelle: 'Au', type: TypeChamp.date), iso(c.aujourdhui));
    _q = RhbFiltre(const ChampDef(nom: 'pr_f_q', libelle: 'Recherche', indicatif: 'Agent, matricule, motif'));
    _agent = RhbFiltre(liste('pr_f_agent', 'Agent', 'Tous les agents', [for (final e in agents) OptionChamp('${e['id']}', '${e['nomComplet']}')]));
    _matricule = RhbFiltre(liste('pr_f_matricule', 'Matricule', 'Tous les matricules', [for (final e in agents) OptionChamp('${e['matricule']}', '${e['matricule']} · ${e['nomComplet']}')]));
    _service = RhbFiltre(liste('pr_f_service', 'Service', 'Tous les services', [for (final s in rhbServices) OptionChamp(s)]));
    _etat = RhbFiltre(liste('pr_f_etat', 'État', 'Tous les états', _etats));
    _motif = RhbFiltre(liste('pr_f_motif', 'Motif codé', 'Tous les motifs', [for (final m in motifsAbsenceRh) OptionChamp(m.id, m.libelle), const OptionChamp('__aucun', 'Sans motif codé')]));
    _retard = RhbFiltre(const ChampDef(nom: 'pr_f_retard', libelle: 'Retard minimal (minutes après 08:00)', type: TypeChamp.nombre));
    _hDe = RhbFiltre(const ChampDef(nom: 'pr_f_hde', libelle: 'Arrivée de', indicatif: 'hh:mm'));
    _hA = RhbFiltre(const ChampDef(nom: 'pr_f_ha', libelle: 'Arrivée à', indicatif: 'hh:mm'));
    _validation = RhbFiltre(liste('pr_f_validation', 'Validation', 'Validées ou non', [for (final e in rhbEtatsValidation.entries) OptionChamp(e.key, e.value.$1)]));
    _validePar = RhbFiltre(liste('pr_f_validepar', 'Validé par', 'Tous les validateurs', [for (final n in validateurs) OptionChamp(n), const OptionChamp('__aucun', 'Validation non renseignée (avant le circuit)')]));
    _tous = [_du!, _au!, _q!, _agent!, _matricule!, _service!, _etat!, _motif!, _retard!, _hDe!, _hA!, _validation!, _validePar!];
    for (final f in _tous) {
      f.controleur.addListener(_maj);
    }
  }

  @override
  void dispose() {
    for (final f in _tous) {
      f.controleur.removeListener(_maj);
      f.controleur.dispose();
    }
    super.dispose();
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  bool get _enForce => _tous.where((f) => f != _du && f != _au).any((f) => f.valeur.isNotEmpty);

  void _poserPlage(String du, String au) {
    _du!.controleur.removeListener(_maj);
    _au!.controleur.removeListener(_maj);
    _du!.poser(du);
    _au!.poser(au);
    _du!.controleur.addListener(_maj);
    _au!.controleur.addListener(_maj);
    setState(() {});
  }

  void _effacer(ContexteEcran c) {
    for (final f in _tous) {
      f.controleur.removeListener(_maj);
    }
    for (final f in _tous) {
      f.poser('');
    }
    _du!.poser(iso(ajouterJours(c.aujourdhui, -30)));
    _au!.poser(iso(c.aujourdhui));
    for (final f in _tous) {
      f.controleur.addListener(_maj);
    }
    setState(() {});
  }

  /// Les lignes retenues par tous les filtres avancés (le registre, l'export et l'état imprimé lisent la même liste).
  List<Fiche> _filtrees(ContexteEcran c) {
    final q = _q!.valeur.trim().toLowerCase();
    return [
      for (final r in rhbActives(c, 'presences'))
        if (_retenue(r, q)) r
    ];
  }

  bool _retenue(Fiche r, String q) {
    final d = '${r['date']}';
    if (_du!.valeur.isNotEmpty && d.compareTo(_du!.valeur) < 0) return false;
    if (_au!.valeur.isNotEmpty && d.compareTo(_au!.valeur) > 0) return false;
    if (_agent!.valeur.isNotEmpty && r['employeId'] != _agent!.valeur) return false;
    if (_matricule!.valeur.isNotEmpty && r['matricule'] != _matricule!.valeur) return false;
    if (_service!.valeur.isNotEmpty && r['service'] != _service!.valeur) return false;
    if (_etat!.valeur.isNotEmpty && r['etat'] != _etat!.valeur) return false;
    if (_motif!.valeur.isNotEmpty) {
      final code = r['motifCode'] == null || r['motifCode'] == '' ? null : '${r['motifCode']}';
      if (_motif!.valeur == '__aucun' ? code != null : code != _motif!.valeur) return false;
    }
    if (_retard!.valeur.isNotEmpty && _retardMinutes(r) < (num.tryParse(_retard!.valeur.replaceAll(',', '.')) ?? 0)) return false;
    final a = _minutesDe(r['heureArrivee']);
    if (_hDe!.valeur.isNotEmpty && (a == null || a < (_minutesDe(_hDe!.valeur) ?? 0))) return false;
    if (_hA!.valeur.isNotEmpty && (a == null || a > (_minutesDe(_hA!.valeur) ?? 0))) return false;
    if (_validation!.valeur.isNotEmpty && etatValidationRh('presences', r) != _validation!.valeur) return false;
    if (_validePar!.valeur.isNotEmpty && ((r['validePar'] == null || r['validePar'] == '') ? '__aucun' : '${r['validePar']}') != _validePar!.valeur) return false;
    if (q.isNotEmpty && !'${r['employe'] ?? ''} ${r['matricule'] ?? ''} ${r['motif'] ?? ''} ${r['justificatif'] ?? ''}'.toLowerCase().contains(q)) return false;
    return true;
  }

  List<ChampDef> _champs(ContexteEcran c) => [
        ChampDef(nom: 'employeId', libelle: 'Agent', type: TypeChamp.select, requis: true, col: ColChamp.plein, options: [
          for (final e in rhbPersonnelTrie(c)) OptionChamp('${e['id']}', '${e['matricule']} — ${e['nomComplet']} (${e['poste']})')
        ]),
        const ChampDef(nom: 'date', libelle: 'Date du pointage', type: TypeChamp.date, requis: true),
        const ChampDef(nom: 'etat', libelle: 'État', type: TypeChamp.select, requis: true, options: _etats),
        admChampHeure('heureArrivee', 'Heure d’arrivée', requis: false),
        admChampHeure('heureDepart', 'Heure de départ', requis: false),
        ChampDef(nom: 'motifCode', libelle: 'Motif codé', type: TypeChamp.select, options: [
          const OptionChamp('', 'Aucun (non justifié)'),
          for (final m in motifsAbsenceRh) OptionChamp(m.id, m.libelle),
        ]),
        const ChampDef(nom: 'justificatif', libelle: 'Justificatif (référence du document)', aide: 'Certificat médical, ordre de mission, décision de congé'),
        const ChampDef(nom: 'motif', libelle: 'Motif / justification', col: ColChamp.plein),
      ];

  /// `transform` de la maquette : le pointage porte le nom, le matricule et le service de l'agent désigné ; UN POINTAGE NAÎT À VALIDER : visible, il ne compte
  /// qu'une fois tranché par le circuit.
  Fiche _fiche(ContexteEcran c, Map<String, Object?> v, Fiche? existante) {
    final e = rhbActives(c, 'personnel').where((x) => x['id'] == v['employeId']).firstOrNull;
    return {
      ...v,
      if (e != null) ...{'employe': e['nomComplet'], 'matricule': e['matricule'], 'service': e['service']},
      if (existante == null) ...rhbPlanningPoste(c).naissance(),
    };
  }

  void _saisir(BuildContext ctx, ContexteEcran c, {Fiche? existante}) => admSaisir(ctx,
      col: c.magasin.collection('presences'),
      champs: _champs(c),
      fiche: (v, e) => _fiche(c, v, e),
      existante: existante,
      titreCreation: 'Nouveau pointage',
      entite: 'Pointage',
      prefixeId: 'PRS',
      libelleCreer: 'Créer',
      initiales: {'date': iso(c.aujourdhui), 'etat': 'present', 'heureArrivee': '07:45', 'motifCode': ''});

  @override
  Widget build(BuildContext context) => RhbEcoute(collections: const ['presences', 'personnel', 'parametres'], construire: _corps);

  Widget _corps(BuildContext context, ContexteEcran c) {
    final tous = _filtrees(c);
    final p = rhbPlanningPoste(c);
    final comptees = [for (final r in tous) if (compteRh('presences', r)) r];
    int n(String e) => comptees.where((r) => r['etat'] == e).length;
    String f(String s) => DateTime.tryParse(s) == null ? 'NaN/NaN/NaN' : dateFR(DateTime.parse(s));
    final col = c.magasin.collection('presences');
    final aValider = tous.where((r) {
      final e = etatValidationRh('presences', r);
      return e == 'a_valider' || e == 'valide_surveillant';
    }).length;
    return rhbEspace([
      const RhbCarteReglages(),
      CarteSigh(
          titre: 'Filtres avancés des présences',
          child: LayoutBuilder(builder: (_, k) {
            final nc = k.maxWidth >= 1024 ? 4 : (k.maxWidth >= 768 ? 3 : 1);
            final l = (k.maxWidth - 12 * (nc - 1)) / nc;
            return Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
              for (final x in _tous) SizedBox(width: l, child: FormulaireSigh(key: Key('rhb:filtre:${x.def.nom}'), controleur: x.controleur)),
              Wrap(spacing: 8, runSpacing: 8, children: [
                BoutonSigh(
                    libelle: 'Mois en cours',
                    icone: LucideIcons.calendar,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => _poserPlage(iso(DateTime(c.aujourdhui.year, c.aujourdhui.month, 1)), iso(c.aujourdhui))),
                BoutonSigh(
                    libelle: 'Sept derniers jours',
                    icone: LucideIcons.calendarDays,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => _poserPlage(iso(ajouterJours(c.aujourdhui, -6)), iso(c.aujourdhui))),
                BoutonSigh(libelle: 'Effacer les filtres', icone: LucideIcons.filterX, variante: VarianteBouton.secondaire, onPressed: () => _effacer(c)),
              ]),
            ]);
          })),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        KpiGrilleSigh(kpis: [
          KpiSigh(libelle: 'Pointages comptés', valeur: nombre(comptees.length), icone: LucideIcons.clipboardCheck, ton: TonSigh.navy, indice: 'validés seulement'),
          KpiSigh(libelle: 'Présences', valeur: nombre(n('present')), icone: LucideIcons.circleCheck, ton: TonSigh.succes),
          KpiSigh(libelle: 'Retards', valeur: nombre(n('retard')), icone: LucideIcons.clockAlert, ton: TonSigh.attention, indice: 'Critère NS 131'),
          KpiSigh(libelle: 'Absences', valeur: nombre(n('absent')), icone: LucideIcons.userX, ton: TonSigh.danger),
          KpiSigh(libelle: 'À valider', valeur: nombre(aValider), icone: LucideIcons.hourglass, ton: TonSigh.attention, indice: 'visibles, ne comptent pas'),
        ]),
        const SizedBox(height: 8),
        const NoteSigh(
            'Les retards et absences validés et non justifiés alimentent le critère « Ponctualité et assiduité » du barème NS 131, avec incidence directe sur la fiche d’évaluation et le solde du mois. Un pointage à valider est visible mais ne compte pas.'),
      ]),
      TableauSigh(
          titre: 'Registre des présences — ${f(_du!.valeur)} au ${f(_au!.valeur)}${_enForce ? ' (filtré)' : ''}',
          taillePage: 20,
          triInitial: 'date',
          sensInitial: 'desc',
          nomExport: 'presences',
          selectionnable: true,
          recherche: true,
          lignes: tous,
          actions: [
            if (c.droit.editer) BoutonSigh(libelle: 'Ajouter un pointage', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _saisir(context, c)),
            BoutonSigh(libelle: 'Imprimer l’état', icone: LucideIcons.printer, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _imprimer(context, c, tous)),
          ],
          actionsLigne: (ctx, r) => [
                ...rhbCommandesValidation(ctx, c, 'presences', r),
                if (etatValidationRh('presences', r) == 'valide' && const ['surveillant', 'da', 'admin'].contains(c.role))
                  BoutonIcone(icone: LucideIcons.penLine, libelle: 'Régulariser ce pointage', onPressed: () => _regulariser(ctx, c, p, r)),
                ...admActionsLigne(ctx, c, col, r, modifier: (x) => _saisir(ctx, c, existante: x)),
              ],
          colonnes: [
            ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (r) => f('${r['date']}'), rendu: (_, r) => Text(f('${r['date']}'))),
            const ColonneTableau(cle: 'matricule', libelle: 'Mat.', droite: true, sansCoupure: true),
            const ColonneTableau(cle: 'employe', libelle: 'Agent'),
            const ColonneTableau(cle: 'service', libelle: 'Service'),
            ColonneTableau(
                cle: 'etat',
                libelle: 'État',
                texte: (r) => switch (r['etat']) { 'present' => 'Présent', 'retard' => 'Retard', 'absent' => 'Absent', 'conge' => 'Congé', var x => '$x' },
                rendu: (_, r) => switch (r['etat']) {
                      'present' => const BadgeSigh('Présent', ton: TonSigh.succes),
                      'retard' => const BadgeSigh('Retard', ton: TonSigh.attention),
                      'absent' => const BadgeSigh('Absent', ton: TonSigh.danger),
                      'conge' => const BadgeSigh('Congé', ton: TonSigh.info),
                      var x => BadgeSigh('$x', ton: TonSigh.neutre),
                    }),
            const ColonneTableau(cle: 'heureArrivee', libelle: 'Arrivée', droite: true),
            const ColonneTableau(cle: 'heureDepart', libelle: 'Départ', droite: true),
            ColonneTableau(
                cle: 'motif',
                libelle: 'Motif',
                texte: (r) => _motifTexte(r),
                rendu: (_, r) {
                  final cod = motifsAbsenceRh.where((x) => x.id == r['motifCode']).map((x) => x.libelle).firstOrNull;
                  if (cod == null) return Text('${r['motif'] ?? ''}');
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    BadgeSigh(cod, ton: TonSigh.neutre),
                    if (r['justificatif'] != null && r['justificatif'] != '') Text('${r['justificatif']}', style: rhbPetit),
                  ]);
                }),
            ColonneTableau(
                cle: 'validation',
                libelle: 'Validation',
                valeur: (r) => etatValidationRh('presences', r),
                texte: (r) => rhbEtatsValidation[etatValidationRh('presences', r)]?.$1 ?? '—',
                rendu: (_, r) {
                  final reg = (r['regularisations'] as List?)?.length ?? 0;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    rhbBadgeValidation('presences', r),
                    if (reg > 0) Text('Régularisé $reg fois', style: rhbPetit),
                  ]);
                }),
          ]),
      ..._graphes(comptees),
    ]);
  }

  static String _motifTexte(Fiche r) {
    final cod = motifsAbsenceRh.where((x) => x.id == r['motifCode']).map((x) => x.libelle).firstOrNull;
    return cod != null ? '$cod ${r['justificatif'] ?? ''}'.trim() : '${r['motif'] ?? ''}';
  }

  void _regulariser(BuildContext ctx, ContexteEcran c, PlanningRhPoste p, Fiche r) {
    final ctl = ControleurFormulaire([
      const ChampDef(nom: 'etat', libelle: 'Nouvel état', type: TypeChamp.select, requis: true, options: _etats),
      ChampDef(nom: 'motifCode', libelle: 'Motif codé', type: TypeChamp.select, options: [const OptionChamp('', 'Aucun (non justifié)'), for (final m in motifsAbsenceRh) OptionChamp(m.id, m.libelle)]),
      const ChampDef(nom: 'justificatif', libelle: 'Justificatif (référence du document)', col: ColChamp.plein),
      const ChampDef(nom: 'motif', libelle: 'Motif de la régularisation', type: TypeChamp.textarea, lignes: 2, requis: true, col: ColChamp.plein),
    ], {'etat': r['etat'], 'motifCode': r['motifCode'] ?? '', 'justificatif': r['justificatif'] ?? ''});
    afficherModale<void>(ctx,
        titre: 'Régulariser le pointage',
        sousTitre: '${r['employe']} · ${dateFR(DateTime.parse('${r['date']}'))}',
        taille: TailleModale.md,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const NoteSigh('La régularisation est datée et porte son auteur et son motif : l’état d’avant reste lisible au journal.'),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Régulariser',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final res = p.regulariser(r['id'], {'etat': v['etat'], 'motifCode': v['motifCode'], 'justificatif': v['justificatif'], 'motif': v['motif']});
                    if (res['ok'] != true) {
                      rhbToastRefus(ctx, res);
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Pointage régularisé.', type: TypeToast.succes, annuler: res['annuler'] as VoidCallback);
                  }),
            ]);
  }

  /// Les filtres EN FORCE, déclarés un à un : les heures et le seuil de retard ne sont pas des listes que la page relèverait toute seule.
  List<(String, String)> _filtresEtat() {
    String lib(RhbFiltre x) => x.def.options.where((o) => o.valeur == x.valeur).map((o) => o.libelle).firstOrNull ?? x.valeur;
    final f = <(String, String)>[('Période', '${dateFR(DateTime.parse(_du!.valeur))} au ${dateFR(DateTime.parse(_au!.valeur))}')];
    for (final (x, nom) in [
      (_agent!, 'Agent'), (_matricule!, 'Matricule'), (_service!, 'Service'), (_etat!, 'État'), (_motif!, 'Motif codé'), (_validation!, 'Validation'), (_validePar!, 'Validé par'),
    ]) {
      if (x.valeur.isNotEmpty) f.add((nom, lib(x)));
    }
    for (final (x, nom) in [(_retard!, 'Retard minimal (minutes)'), (_hDe!, 'Arrivée de'), (_hA!, 'Arrivée à'), (_q!, 'Recherche')]) {
      if (x.valeur.isNotEmpty) f.add((nom, x.valeur));
    }
    return f;
  }

  void _imprimer(BuildContext ctx, ContexteEcran c, List<Fiche> tous) {
    final rows = trierPar(tous, (r) => '${r['date']}', descendant: true);
    const lib = {'present': 'Présent', 'retard': 'Retard', 'absent': 'Absent', 'conge': 'Congé'};
    afficherApercu(
        ctx,
        rhbPiece(c,
            titre: 'État des présences et absences',
            sousTitre: '${dateFR(DateTime.parse(_du!.valeur))} au ${dateFR(DateTime.parse(_au!.valeur))}',
            filtres: _filtresEtat(),
            cartouche: [
              ('Pointages retenus', nombre(rows.length)),
              ('Dont validés', nombre(rows.where((r) => compteRh('presences', r)).length)),
              ('Établi par', acteur(c).nom),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Date', valeur: (r) => dateFR(DateTime.parse('${r['date']}'))),
                ColonneEtat(libelle: 'Mat.', valeur: (r) => r['matricule']),
                ColonneEtat(libelle: 'Agent', valeur: (r) => r['employe']),
                ColonneEtat(libelle: 'Service', valeur: (r) => r['service']),
                ColonneEtat(libelle: 'État', valeur: (r) => lib[r['etat']] ?? r['etat']),
                ColonneEtat(libelle: 'Arrivée', valeur: (r) => r['heureArrivee'] ?? ''),
                ColonneEtat(libelle: 'Motif', valeur: (r) => motifsAbsenceRh.where((x) => x.id == r['motifCode']).map((x) => x.libelle).firstOrNull ?? '${r['motif'] ?? ''}'),
                ColonneEtat(libelle: 'Justificatif', valeur: (r) => r['justificatif'] ?? ''),
                ColonneEtat(libelle: 'Validation', valeur: (r) => rhbEtatsValidation[etatValidationRh('presences', r)]?.$1 ?? '—'),
                ColonneEtat(libelle: 'Validé par', valeur: (r) => r['validePar'] ?? ''),
              ], lignes: rows)
            ],
            signatures: const [rhbSignSurveillant, rhbSignDaf]));
  }

  List<Widget> _graphes(List<Fiche> m) {
    if (m.isEmpty) {
      return const [CarteSigh(titre: 'Statistiques', child: VideSigh('Aucun pointage validé sur la plage et les filtres retenus.', icone: LucideIcons.calendarX))];
    }
    final parService = rhbGrouper(m, (r) => '${r['service']}');
    int n(String e) => m.where((r) => r['etat'] == e).length;
    final parJour = rhbGrouper(m, (r) => '${r['date']}');
    final jours = parJour.keys.toList()..sort();
    final rang = trierPar([
      for (final e in parService.entries)
        (e.key, arrondiJs(e.value.where((r) => r['etat'] == 'present').length / e.value.length * 100).toInt())
    ], (e) => e.$2, descendant: true);
    return [
      rhbTroisCartes([
        CarteSigh(titre: 'Taux de présence par service', child: RhbClassement([for (final e in rang) (libelle: e.$1, valeur: e.$2)])),
        CarteSigh(
            titre: 'Répartition des pointages',
            child: GraphiqueAnneau(
                etiquettes: const ['Présences', 'Retards', 'Absences'],
                valeurs: [n('present'), n('retard'), n('absent')],
                couleurs: const [rhbTonVert, rhbTonOrange, rhbTonRouge])),
        CarteSigh(
            titre: 'Volume de pointages par service',
            child: GraphiqueBarres(
                horizontal: true,
                hauteur: 260,
                etiquettes: parService.keys.toList(),
                series: [SerieGraphique('Pointages', [for (final l in parService.values) l.length], couleur: rhbTonNavy)])),
      ]),
      if (jours.length > 1)
        CarteSigh(
            titre: 'Retards et absences au fil des jours',
            child: GraphiqueLigne(hauteur: 240, etiquettes: [
              for (final j in jours) dateFR(DateTime.parse(j))
            ], series: [
              SerieGraphique('Retards', [for (final j in jours) parJour[j]!.where((r) => r['etat'] == 'retard').length], couleur: rhbTonOrange, aire: false),
              SerieGraphique('Absences', [for (final j in jours) parJour[j]!.where((r) => r['etat'] == 'absent').length], couleur: rhbTonRouge, aire: false),
            ])),
    ];
  }
}

/// `K.ranking` avec `format: v + ' %'` : un classement en barres horizontales.
class RhbClassement extends StatelessWidget {
  const RhbClassement(this.lignes, {super.key, this.suffixe = ' %', this.couleur = JetonsShell.success500});
  final List<({String libelle, num valeur})> lignes;
  final String suffixe;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    if (lignes.isEmpty) return const VideSigh('Aucune donnée.');
    final max = lignes.fold<num>(0, (a, l) => l.valeur > a ? l.valeur : a);
    return Column(children: [
      for (final l in lignes)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(l.libelle, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
              Text('${nombre(l.valeur)}$suffixe', style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: max == 0 ? 0 : (l.valeur / max).toDouble(), minHeight: 8, backgroundColor: JetonsShell.slate100, color: couleur)),
          ]),
        ),
    ]);
  }
}
