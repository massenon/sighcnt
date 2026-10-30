import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m5/res_commun.dart' show ClassementLabo;
import 'ag_commun.dart';

/// `m2-agenda` — la vue calendaire des rendez-vous, par jour : une plage de dates (31 jours au plus), les rendez-vous À VENIR de chaque jour (l'honoré a
/// quitté l'agenda), la prise de rendez-vous qui étend la fenêtre jusqu'à lui, le rappel des échéances à l'ouverture.
class EcranAgenda extends StatefulWidget with EcranMaquette {
  const EcranAgenda({super.key});

  @override
  String get titre => 'Agenda';

  @override
  String get description =>
      'Vue calendaire des rendez-vous et consultations, par praticien et par jour.';

  @override
  String get regle =>
      'L’agenda ne montre pas que la semaine en cours : une plage de dates permet de retrouver les semaines passées ou à venir. Un rendez-vous se prend depuis cet écran, par praticien et par jour, et déclenche la notification du praticien concerné.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Rendez-vous',
          icone: LucideIcons.calendarCheck,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m2-rendezvous')),
      if (c.droit.editer)
        BoutonSigh(
            libelle: 'Passage sans rendez-vous',
            icone: LucideIcons.userCheck,
            onPressed: () => passageSansRendezVousAg(context)),
    ];
  }

  @override
  State<EcranAgenda> createState() => _EtatAgenda();
}

class _EtatAgenda extends State<EcranAgenda> {
  ControleurFormulaire? _du, _au;
  Timer? _rappel;
  bool _rappelFait = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_du == null) {
      final c = ContexteEcran.of(context);
      final p = agFenetreParDefaut(c.aujourdhui);
      _du = ControleurFormulaire(
          const [ChampDef(nom: 'du', libelle: 'Du', type: TypeChamp.date)],
          {'du': p.debut})
        ..addListener(() => setState(() {}));
      _au = ControleurFormulaire(
          const [ChampDef(nom: 'au', libelle: 'Au', type: TypeChamp.date)],
          {'au': p.fin})
        ..addListener(() => setState(() {}));
    }
    if (!_rappelFait) {
      _rappelFait = true;
      final ecran = context;
      // Le rappel se déclenche 900 ms après l'ouverture, sans action de l'agent.
      _rappel = minuteurUneFois(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        final c = ContexteEcran.of(ecran);
        final cons = c.magasin.collection('consultations').actives;
        final auj = iso(c.aujourdhui);
        final reunions = c.magasin
            .collection('reunions')
            .actives
            .where((r) => agJour(r['date']) == auj)
            .length;
        final r = agRappelEcheances(cons, reunions, c.aujourdhui);
        if (r != null) {
          ToastsSigh.afficher(ecran, r.message, type: TypeToast.info, detail: r.detail);
        }
      });
    }
  }

  @override
  void dispose() {
    _rappel?.cancel();
    _du?.dispose();
    _au?.dispose();
    super.dispose();
  }

  void _etendreJusquA(String dateRdv) {
    final f = agEtendreFenetre('${_du!['du']}', '${_au!['au']}', dateRdv);
    _du!.poser('du', f.debut);
    _au!.poser('au', f.fin);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('consultations');
    return ListenableBuilder(
        listenable: Listenable.merge([col, c.magasin.collection('personnel')]),
        builder: (context, _) {
          final cons = col.actives;
          final jours = agJoursFenetre('${_du!['du']}', '${_au!['au']}', c.aujourdhui);
          final grille = agGrille(cons, jours, c.aujourdhui);
          final k = agKpisAgenda(cons, medecinsAg(c).length, c.aujourdhui);
          final charge = agChargeParPraticien(cons, c.aujourdhui);
          final rep = agRepartitionParType(cons);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(kpis: [
              kpiAg(k[0], LucideIcons.calendarCheck, TonSigh.navy),
              kpiAg(k[1], LucideIcons.calendarDays, TonSigh.info),
              kpiAg(k[2], LucideIcons.clock, TonSigh.attention),
              kpiAg(k[3], LucideIcons.userRound, TonSigh.neutre),
            ]),
            const SizedBox(height: 16),
            CarteSigh(
                child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                  SizedBox(width: 170, child: FormulaireSigh(controleur: _du!)),
                  SizedBox(width: 170, child: FormulaireSigh(controleur: _au!)),
                  BoutonSigh(
                      libelle: 'Semaine en cours',
                      icone: LucideIcons.calendarDays,
                      variante: VarianteBouton.secondaire,
                      onPressed: () {
                        final p = agFenetreParDefaut(c.aujourdhui);
                        _du!.poser('du', p.debut);
                        _au!.poser('au', p.fin);
                      }),
                  if (c.droit.editer)
                    BoutonSigh(
                        libelle: 'Nouveau rendez-vous',
                        icone: LucideIcons.plus,
                        onPressed: () => _nouveau(context, c)),
                ])),
            const SizedBox(height: 16),
            CarteSigh(
                titre: agTitreFenetre(jours),
                actions: [
                  lienVers('Gérer les rendez-vous', () => c.aller('m2-rendezvous'))
                ],
                child: LayoutBuilder(builder: (_, w) {
                  final n = w.maxWidth >= 1024 ? 7 : (w.maxWidth >= 768 ? 4 : 1);
                  final l = (w.maxWidth - 12 * (n - 1)) / n;
                  return Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final g in grille)
                      SizedBox(width: l - 0.01, child: _CarteJour(g, (r) => _fiche(context, r)))
                  ]);
                })),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (_, w) {
              final deux = w.maxWidth >= 1024;
              final a = CarteSigh(
                  titre: 'Charge par praticien (30 derniers jours)',
                  child: ClassementLabo([for (final e in charge) (e.libelle, e.valeur)]));
              final b = CarteSigh(
                  titre: 'Répartition par type',
                  child: GraphiqueAnneau(etiquettes: rep.libelles, valeurs: rep.valeurs));
              return deux
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: a),
                      const SizedBox(width: 16),
                      Expanded(child: b)
                    ])
                  : Column(children: [a, const SizedBox(height: 16), b]);
            }),
          ]);
        });
  }

  /// La fiche d'un rendez-vous : consulter, puis agir au même endroit (les trois suites, l'édition, l'annulation) — commandes ABSENTES sans le droit.
  void _fiche(BuildContext ecran, Fiche r) {
    final c = ContexteEcran.of(ecran);
    final d = agDate(r['date']);
    afficherTiroir<void>(ecran,
        titre: '${r['patient']}',
        sousTitre: '${r['patientCode']} — ${d == null ? 'NaN/NaN/NaN' : dateFR(d)}',
        largeurMax: 576,
        corps: detailRendezVousAg(ecran, r),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Imprimer',
                  icone: LucideIcons.printer,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => imprimerConsultationAg(ecran, r)),
              if (c.droit.editer) ...[
                BoutonSigh(
                    libelle: 'Éditer le rendez-vous',
                    icone: LucideIcons.pencil,
                    onPressed: () {
                      fermer();
                      formulaireRendezVousAg(ecran, record: r);
                    }),
                BoutonSigh(
                    libelle: 'Marquer honoré',
                    icone: LucideIcons.circleCheck,
                    variante: VarianteBouton.secondaire,
                    onPressed: () {
                      fermer();
                      marquerHonoreAg(ecran, r);
                    }),
                BoutonSigh(
                    libelle: 'Reporter',
                    icone: LucideIcons.calendarClock,
                    variante: VarianteBouton.secondaire,
                    onPressed: () {
                      fermer();
                      reporterAg(ecran, r);
                    }),
                BoutonSigh(
                    libelle: 'Non honoré',
                    icone: LucideIcons.userX,
                    variante: VarianteBouton.secondaire,
                    onPressed: () {
                      fermer();
                      marquerNonHonoreAg(ecran, r);
                    }),
              ],
              if (c.droit.annuler)
                BoutonSigh(
                    libelle: 'Annuler le rendez-vous',
                    icone: LucideIcons.archive,
                    variante: VarianteBouton.danger,
                    onPressed: () {
                      fermer();
                      archiverRendezVousAg(ecran, r);
                    }),
            ]);
  }

  void _nouveau(BuildContext ecran, ContexteEcran c) {
    final liste = <ChampDef>[
      ChampDef(
          nom: 'patientCode',
          libelle: 'Dossier patient',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: optionsPatientsAg(c)),
      ChampDef(
          nom: 'medecin',
          libelle: 'Praticien',
          type: TypeChamp.select,
          requis: true,
          options: optionsMedecinsAg(c)),
      const ChampDef(
          nom: 'type',
          libelle: 'Nature',
          type: TypeChamp.select,
          requis: true,
          options: [OptionChamp('Consultation'), OptionChamp('Contrôle'), OptionChamp('Urgence')]),
      const ChampDef(
          nom: 'date', libelle: 'Date et heure', type: TypeChamp.dateHeure, requis: true),
      const ChampDef(nom: 'motif', libelle: 'Motif', requis: true, col: ColChamp.plein),
      const ChampDef(nom: 'tarif', libelle: 'Tarif prévu (FCFA)', type: TypeChamp.nombre),
      const ChampDef(nom: 'notifier', libelle: 'Notifier le praticien', type: TypeChamp.case_),
    ];
    final ctl = ControleurFormulaire(
        liste, {'date': agIsoLocal(c.aujourdhui), 'notifier': true});
    afficherModale<void>(ecran,
        titre: 'Nouveau rendez-vous',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NoteSigh(
              'Le rendez-vous est enregistré au nom du praticien choisi et apparaît immédiatement dans son agenda du jour. La notification sonore prévient le poste concerné.'),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer le rendez-vous',
                  icone: LucideIcons.calendarCheck,
                  onPressed: () {
                    final brut = ctl.valider();
                    if (brut == null) {
                      ToastsSigh.afficher(ecran, 'Le formulaire comporte des erreurs.',
                          type: TypeToast.erreur);
                      return;
                    }
                    final v = collecterAg(liste, brut);
                    final notifier = agVrai(v['notifier']);
                    final m = c.magasin.collection('consultations');
                    final r = agNouveauRendezVous(v,
                        patients: patientsAg(c), existantes: m.toutes);
                    final ins = m.inserer(r, prefixe: 'CON');
                    fermer();
                    _etendreJusquA('${r['date']}');
                    if (notifier) {
                      final t = agMessageTransmis(r);
                      ToastsSigh.afficher(ecran, t.message,
                          type: TypeToast.succes, detail: t.detail, annuler: ins.annuler);
                    } else {
                      final t = agMessageEnregistre(r);
                      ToastsSigh.afficher(ecran, t.message,
                          type: TypeToast.succes, detail: t.detail, annuler: ins.annuler);
                    }
                  }),
            ]);
  }
}

/// Un jour de la grille : l'en-tête, le mois, puis au plus six rendez-vous à venir (heure, patient, motif) ; « Aucun » sinon.
class _CarteJour extends StatelessWidget {
  const _CarteJour(this.g, this.surClic);
  final AgJour g;
  final void Function(Fiche) surClic;

  @override
  Widget build(BuildContext context) => Container(
        key: Key('ag:jour:${iso(g.jour)}'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: g.aujourdhui ? JetonsShell.navy400 : JetonsShell.slate200,
                width: g.aujourdhui ? 2 : 1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(g.entete.toUpperCase(),
              style: TextStyle(
                  color: g.aujourdhui ? JetonsShell.navy800 : JetonsShell.slate500,
                  fontSize: 12,
                  height: 16 / 12,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600)),
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(g.mois,
                  style: const TextStyle(
                      color: JetonsShell.slate400, fontSize: 11, height: 1.4))),
          if (g.rendezVous.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                    child: Text('Aucun',
                        style: TextStyle(color: JetonsShell.slate300, fontSize: 12))))
          else ...[
            for (final r in g.rendezVous)
              Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                      onTap: () => surClic(r),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: JetonsShell.slate200)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    agDate(r['date']) == null
                                        ? 'NaNhNaN'
                                        : heure(agDate(r['date'])!),
                                    style: const TextStyle(
                                        color: JetonsShell.navy800,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                                Text('${r['patient']}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: JetonsShell.slate600, fontSize: 11)),
                                Text('${r['motif']}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: JetonsShell.slate400, fontSize: 10)),
                              ])))),
            if (g.autres > 0)
              Center(
                  child: Text('+ ${g.autres} autre(s)',
                      style: const TextStyle(color: JetonsShell.slate400, fontSize: 10))),
          ],
        ]),
      );
}
