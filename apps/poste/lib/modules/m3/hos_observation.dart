import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m2/cs_commun.dart' show sessionDe, stockDe;
import '../m6/stock_commun.dart' show tonDeBadge;
import 'hos_commun.dart';

/// `m3-observation` — « Mise en observation » : surveillance de COURTE durée (24 h de référence), DISTINCTE de l'hospitalisation. Admission en unité
/// d'observation, feuille de constantes horodatée, prescriptions ciblées, décision d'orientation. Un séjour qui dépasse la durée de référence est
/// signalé : il appelle une décision, pas un oubli. L'orientation « hospitalisation complète » ouvre une admission (`hosAdmissionDepuisObservation`)
/// et les deux restent séparées au dossier. Règles : `packages/domaine/lib/src/hospitalisation/hos_regles.dart`.
///
/// Les écritures (mettre en observation, relever, décider, prescrire) sont des commandes gardées par le droit d'écrire : ABSENTES de qui ne fait que
/// lire (E372). Le kit n'a pas de champ date-heure : une heure se saisit en deux champs, date et `HH:mm` (E367).
class EcranObservation extends StatelessWidget with EcranMaquette {
  const EcranObservation({super.key});

  @override
  String get titre => 'Mise en observation';

  @override
  String get description =>
      'Surveillance de courte durée : admission en unité d’observation, feuille de constantes, prescriptions ciblées et orientation de sortie.';

  @override
  String get regle =>
      'L’observation est une hospitalisation de courte durée — vingt-quatre heures de référence en médecine générale — destinée à surveiller un état, '
      'poser un diagnostic ou attendre l’évolution des symptômes. Elle se termine par une décision d’orientation : sortie définitive, hospitalisation '
      'complète, transfert ou bloc. Un séjour qui dépasse la durée de référence est signalé — il appelle une décision, pas un oubli.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Plan des lits',
          icone: LucideIcons.layoutGrid,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m3-plan-lits')),
      BoutonSigh(
          libelle: 'Feuille de soins',
          icone: LucideIcons.heartPulse,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m3-soins')),
      if (c.droit.editer)
        BoutonSigh(
            libelle: 'Mettre en observation',
            icone: LucideIcons.userPlus,
            onPressed: () => admettre(context)),
    ];
  }

  // ------------------------------------------------------------------------------------------------------------------------------ lectures

  static List<Fiche> enObservation(Iterable<Fiche> obs) => [
        for (final o in obs)
          if (o['statutObservation'] == 'en_cours') o
      ];

  static List<Fiche> constantesTriees(Fiche o) => trierPar(
      [for (final x in (o['constantes'] as List? ?? const [])) (x as Map).cast<String, Object?>()],
      (x) => hosVersDate(x['heure'])?.millisecondsSinceEpoch);

  /// « 15/08/2026 à 09h00 » (heure locale du poste).
  static String dateALHeure(Object? v) {
    final d = dateHosLocale(v);
    return d == null ? '' : '${dateFR(d)} à ${heure(d)}';
  }

  /// La durée d'un séjour, en toutes lettres d'unité : « 25 h ».
  static String heures(Fiche o, DateTime maintenant) => '${hosHeuresEcoulees(o, maintenant)} h';

  static String _num(Object? v) => v is num ? hosNum(v) : '${v ?? ''}';

  static Fiche? _patient(Magasin m, Object? code) {
    for (final p in m.collection('patients').actives) {
      if (p['code'] == code) return p;
    }
    return null;
  }

  // ------------------------------------------------------------------------------------------------------------------------------ admission

  /// Les champs de l'admission en observation ; l'unité annonce ses places libres.
  static List<ChampDef> champsAdmission(Magasin m) {
    final en = enObservation(m.collection('observations').actives);
    return [
      ChampDef(
          nom: 'patientCode',
          libelle: 'Dossier patient',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: optionsPatientsHos(m)),
      const ChampDef(
          nom: 'motif',
          libelle: 'Motif de surveillance',
          requis: true,
          col: ColChamp.plein,
          aide: 'Douleur thoracique, traumatisme crânien léger, malaise…'),
      ChampDef(nom: 'unite', libelle: 'Unité d’observation', type: TypeChamp.select, requis: true, options: [
        for (final u in hosUnitesObservation)
          OptionChamp(u.id,
              '${u.label} (${(u.places - en.where((o) => o['unite'] == u.id).length).clamp(0, u.places)} place(s) libre(s))')
      ]),
      const ChampDef(nom: 'place', libelle: 'Place occupée', aide: 'Identifiant de la place dans l’unité.'),
      const ChampDef(nom: 'dateEntree', libelle: 'Date d’entrée', type: TypeChamp.date, requis: true),
      const ChampDef(
          nom: 'heureEntree',
          libelle: 'Heure d’entrée',
          requis: true,
          indicatif: 'HH:mm',
          valider: validerHeure),
      ChampDef(
          nom: 'medecin',
          libelle: 'Médecin responsable',
          type: TypeChamp.select,
          requis: true,
          options: optionsMedecinsHos(m)),
      ChampDef(
          nom: 'infirmier',
          libelle: 'Infirmier de surveillance',
          type: TypeChamp.select,
          options: optionsInfirmiersNom(m)),
    ];
  }

  /// La fiche d'observation enregistrée à l'admission (`colObs().insert`) ; `reference` : « OBS-2026- » + rang (le millésime est celui de la maquette, E373).
  static Fiche construireObservation(Map<String, Object?> v, Magasin m, int rang) {
    final p = _patient(m, v['patientCode'])!;
    final u = hosUnitesObservation.firstWhere((x) => x.id == v['unite'], orElse: () => HosUnite('${v['unite']}', '${v['unite']}', 0));
    final entree = versHorodatage(v['dateEntree'], v['heureEntree'])!;
    return {
      'reference': 'OBS-2026-${rang.toString().padLeft(4, '0')}',
      'patientId': p['id'],
      'patient': '${p['nom']} ${p['prenom']}',
      'patientCode': p['code'],
      'unite': v['unite'],
      'uniteLabel': u.label,
      if ('${v['place'] ?? ''}'.isNotEmpty) 'place': v['place'],
      'motif': v['motif'],
      'dateEntree': entree.toUtc().toIso8601String(),
      'medecin': v['medecin'],
      if ('${v['infirmier'] ?? ''}'.isNotEmpty) 'infirmier': v['infirmier'],
      'constantes': <Object?>[],
      'statutObservation': 'en_cours',
    };
  }

  static void admettre(BuildContext ctx) {
    final c = ContexteEcran.of(ctx);
    final col = c.magasin.collection('observations');
    final maintenant = c.aujourdhui;
    final ctl = ControleurFormulaire(champsAdmission(c.magasin), {
      'dateEntree': iso(maintenant),
      'heureEntree': hhmm(maintenant),
    });
    afficherModale<void>(ctx,
        titre: 'Mettre un patient en observation',
        taille: TailleModale.lg,
        corps: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NoteSigh(
              'L’heure d’entrée est tracée : c’est elle qui fait courir la durée de référence et déclenche l’alerte au-delà de $hosDureeObservationReference heures.',
              ton: TonSigh.info),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Mettre en observation',
                  icone: LucideIcons.activity,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    fermer();
                    final fiche = construireObservation(v, c.magasin, col.toutes.length + 1);
                    final r = col.inserer({
                      'statut': 'actif',
                      ...fiche,
                      '_creePar': c.utilisateur,
                      '_creeLe': maintenant.toUtc().toIso8601String(),
                    }, prefixe: 'OBS');
                    final u = hosUnitesObservation.where((x) => x.id == v['unite']).firstOrNull;
                    ToastsSigh.afficher(ctx, '${fiche['patient']} mis(e) en observation.',
                        type: TypeToast.succes,
                        detail: '${u?.label ?? ''} — entrée à ${heureDe(fiche['dateEntree'])}',
                        annuler: r.annuler);
                  }),
            ]);
  }

  // ------------------------------------------------------------------------------------------------------------------------------ relevé

  /// Le relevé ajouté à la feuille de surveillance : nombres lus comme `Number(...)`, saturation absente → `null`.
  static Map<String, Object?> construireReleve(Map<String, Object?> v) {
    num? n(Object? x) {
      final s = '${x ?? ''}'.trim().replaceAll(',', '.');
      return s.isEmpty ? null : num.tryParse(s);
    }

    return {
      'heure': versHorodatage(v['date'], v['heure'])!.toUtc().toIso8601String(),
      'temperature': n(v['temperature']),
      'tension': v['tension'],
      'pouls': n(v['pouls']),
      'spo2': (n(v['spo2']) == null || n(v['spo2']) == 0) ? null : n(v['spo2']),
      'observation': v['observation'] ?? '',
      'par': v['par'],
    };
  }

  static void relever(BuildContext ctx, Fiche o) {
    final c = ContexteEcran.of(ctx);
    final col = c.magasin.collection('observations');
    final maintenant = c.aujourdhui;
    final ctl = ControleurFormulaire(const [
      ChampDef(nom: 'date', libelle: 'Date du relevé', type: TypeChamp.date, requis: true),
      ChampDef(nom: 'heure', libelle: 'Heure du relevé', requis: true, indicatif: 'HH:mm', valider: validerHeure),
      ChampDef(nom: 'temperature', libelle: 'Température (°C)', type: TypeChamp.nombre, requis: true),
      ChampDef(nom: 'tension', libelle: 'Tension artérielle', requis: true, indicatif: '12/8'),
      ChampDef(nom: 'pouls', libelle: 'Pouls (bpm)', type: TypeChamp.nombre, requis: true),
      ChampDef(nom: 'spo2', libelle: 'Saturation SpO₂ (%)', type: TypeChamp.nombre),
      ChampDef(
          nom: 'observation',
          libelle: 'Observation clinique',
          type: TypeChamp.textarea,
          lignes: 2,
          col: ColChamp.plein),
      ChampDef(nom: 'par', libelle: 'Relevé par', requis: true),
    ], {
      'date': iso(maintenant),
      'heure': hhmm(maintenant),
      'par': c.utilisateur,
    });
    afficherModale<void>(ctx,
        titre: 'Relevé de constantes — ${o['patient']}',
        sousTitre: '${o['reference']} · ${hosHeuresEcoulees(o, maintenant)} h d’observation',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer le relevé',
                  icone: LucideIcons.thermometer,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    fermer();
                    final releve = construireReleve(v);
                    final suite = [...(o['constantes'] as List? ?? const []), releve];
                    final annuler = col.mettreAJour(o['id'], {'constantes': suite});
                    ToastsSigh.afficher(ctx, 'Constantes relevées à ${heureDe(releve['heure'])}.',
                        type: TypeToast.succes,
                        detail: '${_num(releve['temperature'])} °C · ${releve['tension']} · ${_num(releve['pouls'])} bpm',
                        annuler: annuler);
                  }),
            ]);
  }

  // ------------------------------------------------------------------------------------------------------------------------------ orientation

  static void orienter(BuildContext ctx, Fiche o) {
    final c = ContexteEcran.of(ctx);
    final col = c.magasin.collection('observations');
    final adm = c.magasin.collection('admissions');
    final maintenant = c.aujourdhui;
    final ctl = ControleurFormulaire([
      ChampDef(
          nom: 'orientation',
          libelle: 'Décision d’orientation',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [for (final x in hosOrientations) OptionChamp(x.id, x.label)]),
      const ChampDef(nom: 'conclusion', libelle: 'Conclusion de la surveillance', requis: true, col: ColChamp.plein),
      const ChampDef(nom: 'dateSortie', libelle: 'Date de sortie d’observation', type: TypeChamp.date, requis: true),
      const ChampDef(
          nom: 'heureSortie',
          libelle: 'Heure de sortie d’observation',
          requis: true,
          indicatif: 'HH:mm',
          valider: validerHeure),
      const ChampDef(nom: 'medecin', libelle: 'Décision prise par', requis: true),
      const ChampDef(
          nom: 'destination',
          libelle: 'Établissement de destination',
          col: ColChamp.plein,
          aide: 'À renseigner en cas de transfert.'),
    ], {
      'dateSortie': iso(maintenant),
      'heureSortie': hhmm(maintenant),
      'medecin': o['medecin'],
    });
    afficherModale<void>(ctx,
        titre: 'Orientation à l’issue de l’observation',
        sousTitre: '${o['patient']} — ${hosHeuresEcoulees(o, maintenant)} h de surveillance',
        taille: TailleModale.lg,
        corps: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Motif de surveillance', o['motif']),
            ('Unité', o['uniteLabel']),
            ('Entrée', dateALHeure(o['dateEntree'])),
            ('Relevés de constantes', nombre((o['constantes'] as List? ?? const []).length)),
          ]),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
          const SizedBox(height: 12),
          const NoteSigh(
              'Une hospitalisation complète ouvre une admission dans le module M3 : l’observation se termine, le séjour commence, et les deux restent distincts au dossier.',
              ton: TonSigh.info),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer la décision',
                  icone: LucideIcons.logOut,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    fermer();
                    final sortie = versHorodatage(v['dateSortie'], v['heureSortie'])!;
                    final or = hosOrientation(v['orientation']);
                    final annulerObs = col.mettreAJour(o['id'], {
                      'statutObservation': 'clos',
                      'orientation': v['orientation'],
                      'orientationLabel': or?.label ?? v['orientation'],
                      'conclusion': v['conclusion'],
                      'dateSortie': sortie.toUtc().toIso8601String(),
                      'decidePar': v['medecin'],
                      if ('${v['destination'] ?? ''}'.isNotEmpty) 'destination': v['destination'],
                    });
                    // L'hospitalisation complète ouvre une admission : la place d'observation se libère, le séjour est un autre objet.
                    ({Fiche fiche, VoidCallback annuler})? suite;
                    if (v['orientation'] == 'hospitalisation') {
                      suite = adm.inserer({
                        'statut': 'actif',
                        ...hosAdmissionDepuisObservation(o, sortie, '${v['conclusion']}',
                            referenceSuivante('H', 5, adm.toutes)),
                        '_creePar': c.utilisateur,
                        '_creeLe': maintenant.toUtc().toIso8601String(),
                      }, prefixe: 'ADM');
                    }
                    c.magasin.journaliser('Orientation d’observation', 'M3', 'Observation', '${o['reference']}',
                        {'statut': 'en_cours'}, {'orientation': v['orientation'], 'duree': '${hosHeuresEcoulees(o, maintenant)} h'});
                    ToastsSigh.afficher(ctx, 'Orientation enregistrée — ${or?.label ?? v['orientation']}.',
                        type: TypeToast.succes,
                        duree: const Duration(seconds: 6),
                        detail: suite != null ? 'Admission ${suite.fiche['reference']} ouverte en hospitalisation.' : null,
                        annuler: () {
                          annulerObs();
                          suite?.annuler();
                        });
                  }),
            ]);
  }

  // ------------------------------------------------------------------------------------------------------------------------------ prescription

  static List<ChampDef> champsPrescription(Magasin m) => [
        ChampDef(
            nom: 'analyses',
            libelle: 'Examens biologiques',
            type: TypeChamp.multiselect,
            col: ColChamp.plein,
            aide: 'Bilans de contrôle demandés pendant la surveillance.',
            options: [
              for (final a in m.referentiel('analyses')) OptionChamp('${a['code']}', '${a['designation']}')
            ]),
        ChampDef(
            nom: 'actes',
            libelle: 'Soins rapides',
            type: TypeChamp.multiselect,
            col: ColChamp.plein,
            options: [
              for (final a in m.collection('actes').actives)
                if (RegExp(r'Soins|Médecine générale').hasMatch('${a['secteur']}'))
                  OptionChamp('${a['code']}', '${a['libelle']}')
            ]),
      ];

  static void prescrire(BuildContext ctx, Fiche o) {
    final c = ContexteEcran.of(ctx);
    final ctl = ControleurFormulaire(champsPrescription(c.magasin));
    afficherModale<void>(ctx,
        titre: 'Prescrire pendant l’observation',
        sousTitre: '${o['patient']}',
        taille: TailleModale.lg,
        corps: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NoteSigh(
              'Prescriptions ciblées : bilans de contrôle et soins rapides, adressés immédiatement au laboratoire et à la salle de soins comme toute prescription.',
              ton: TonSigh.info),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Prescrire et transmettre',
                  icone: LucideIcons.send,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final analyses = [for (final x in (v['analyses'] as List? ?? const [])) '$x'];
                    final actes = [for (final x in (v['actes'] as List? ?? const [])) '$x'];
                    if (analyses.isEmpty && actes.isEmpty) {
                      ToastsSigh.afficher(ctx, 'Choisir au moins un examen ou un soin.', type: TypeToast.attention);
                      return;
                    }
                    final ResultatPrescription res;
                    try {
                      res = csPrescrire(
                          stockDe(c),
                          {
                            'patientCode': o['patientCode'],
                            'medecin': o['medecin'],
                            'diagnostic': 'Observation — ${o['motif']}',
                            'analyses': analyses,
                            'actes': actes,
                            'medicaments': const [],
                            // Le secteur prescripteur est porté par la demande : l'unité d'observation (RBAC métier).
                            'secteurDemandeur': o['uniteLabel'],
                          },
                          sessionDe(c));
                    } on RefusCs catch (e) {
                      ToastsSigh.afficher(ctx, 'Prescription impossible : ${e.message}', type: TypeToast.erreur);
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Prescription ${res.ordonnance['numero']} transmise.',
                        type: TypeToast.succes,
                        duree: const Duration(seconds: 6),
                        detail:
                            '${res.demandes.length} examen(s) au laboratoire · facture ${res.facture['numero']} à la caisse');
                  }),
            ]);
  }

  // ------------------------------------------------------------------------------------------------------------------------------ impression

  static List<ColonneEtat> _colonnesReleve() => [
        ColonneEtat(libelle: 'Heure', valeur: (x) => dateHeureCourte(x['heure'])),
        ColonneEtat(libelle: 'Température', droite: true, valeur: (x) => '${_num(x['temperature'])} °C'),
        ColonneEtat(libelle: 'Tension', droite: true, valeur: (x) => x['tension']),
        ColonneEtat(libelle: 'Pouls', droite: true, valeur: (x) => '${_num(x['pouls'])} bpm'),
        ColonneEtat(
            libelle: 'SpO₂',
            droite: true,
            valeur: (x) => (x['spo2'] == null || x['spo2'] == 0 || x['spo2'] == '') ? '—' : '${_num(x['spo2'])} %'),
        ColonneEtat(libelle: 'Observation', valeur: (x) => x['observation']),
        ColonneEtat(libelle: 'Relevé par', valeur: (x) => x['par']),
      ];

  static PieceA4 feuille(ContexteEcran c, Fiche o) {
    final cs = constantesTriees(o);
    return PieceA4(
        titre: 'Feuille de mise en observation',
        sousTitre: '${o['reference']} — ${o['patient']}',
        cartouche: [
          ('Patient', '${o['patient']}'),
          ('Dossier', '${o['patientCode']}'),
          ('Motif de surveillance', '${o['motif']}'),
          ('Unité', '${o['uniteLabel']}'),
          ('Entrée', dateALHeure(o['dateEntree'])),
          ('Durée de surveillance', heures(o, c.aujourdhui)),
          ('Médecin responsable', '${o['medecin']}'),
          ('Issue', '${o['orientationLabel'] ?? 'Surveillance en cours'}'),
        ],
        blocs: [
          if (cs.isNotEmpty)
            BlocTableau(TableauEtat(colonnes: _colonnesReleve(), lignes: cs))
          else
            const BlocTexte('Aucun relevé de constantes enregistré.', italique: true),
          if ((o['conclusion'] ?? '') != '') BlocTexte('Conclusion : ${o['conclusion']}'),
        ],
        signatures: [
          Signature('L’infirmier de surveillance', nom: '${o['infirmier'] ?? ''}'),
          Signature('Le médecin responsable', nom: '${o['medecin']}'),
        ],
        reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
        utilisateur: c.utilisateur,
        edite: c.aujourdhui);
  }

  // ------------------------------------------------------------------------------------------------------------------------------ fiche

  static void fiche(BuildContext ctx, Fiche o) {
    final c = ContexteEcran.of(ctx);
    final maintenant = c.aujourdhui;
    final cs = constantesTriees(o);
    final enCours = o['statutObservation'] == 'en_cours';
    final depasse = hosDepasse(o, maintenant);
    afficherTiroir<void>(ctx,
        titre: '${o['reference']}',
        sousTitre: '${o['patient']} — ${o['uniteLabel']}',
        largeurMax: 768,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Référence', o['reference']),
            ('Patient', o['patient']),
            ('Dossier', o['patientCode']),
            ('Motif de surveillance', o['motif']),
            ('Unité', o['uniteLabel']),
            ('Place', o['place']),
            ('Entrée', dateALHeure(o['dateEntree'])),
            ('Durée', '${heures(o, maintenant)}${depasse && enCours ? ' — au-delà de la référence' : ''}'),
            ('Médecin responsable', o['medecin']),
            ('Infirmier de surveillance', o['infirmier']),
            ('Issue', o['orientationLabel'] ?? 'en cours'),
          ]),
          const SizedBox(height: 16),
          CarteSigh(
              titre: 'Feuille de surveillance',
              actions: [
                if (enCours && c.droit.editer)
                  BoutonSigh(
                      libelle: 'Relever les constantes',
                      icone: LucideIcons.thermometer,
                      taille: TailleBouton.sm,
                      onPressed: () => relever(ctx, o)),
              ],
              sansRemplissage: cs.isNotEmpty,
              child: cs.isNotEmpty
                  ? MiniTableauSigh(colonnes: [
                      ColonneMini('Heure', (x) => dateHeureCourte(x['heure'])),
                      ColonneMini('T°', (x) => '${_num(x['temperature'])} °C', droite: true),
                      ColonneMini('TA', (x) => '${x['tension'] ?? ''}', droite: true),
                      ColonneMini('Pouls', (x) => '${_num(x['pouls'])} bpm', droite: true),
                      ColonneMini(
                          'SpO₂', (x) => (x['spo2'] == null || x['spo2'] == 0) ? '—' : '${_num(x['spo2'])} %',
                          droite: true),
                      ColonneMini('Observation', (x) => '${x['observation'] ?? ''}'),
                      ColonneMini('Relevé par', (x) => '${x['par'] ?? ''}'),
                    ], lignes: cs)
                  : const VideSigh('Aucun relevé enregistré.', icone: LucideIcons.thermometer)),
          if (cs.length > 1) ...[
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Évolution',
                child: GraphiqueLigne(etiquettes: [
                  for (final x in cs) heureDe(x['heure'])
                ], series: [
                  SerieGraphique('Température (°C)', [for (final x in cs) _nombre(x['temperature'])]),
                  SerieGraphique('Pouls (bpm)', [for (final x in cs) _nombre(x['pouls'])], aire: false),
                ])),
          ],
        ]),
        pied: (fermer) => [
              if (enCours && c.droit.editer)
                BoutonSigh(
                    libelle: 'Prescrire',
                    icone: LucideIcons.filePlus,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => prescrire(ctx, o)),
              BoutonSigh(
                  libelle: 'Imprimer la feuille',
                  icone: LucideIcons.printer,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => afficherApercu(ctx, feuille(ContexteEcran.of(ctx), o))),
              if (enCours && c.droit.editer)
                BoutonSigh(
                    libelle: 'Décider de l’orientation',
                    icone: LucideIcons.logOut,
                    onPressed: () => orienter(ctx, o)),
            ]);
  }

  static num _nombre(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

  // ------------------------------------------------------------------------------------------------------------------------------ écran

  Widget _table(BuildContext context, List<Fiche> rows, {required bool actives}) {
    final c = ContexteEcran.of(context);
    final maintenant = c.aujourdhui;
    return TableauSigh(
      lignes: rows,
      nomExport: 'observations',
      taillePage: 12,
      triInitial: 'dateEntree',
      sensInitial: 'desc',
      messageVide: actives ? 'Aucun patient en observation.' : 'Aucun séjour clos.',
      alClicLigne: (o) => fiche(context, o),
      filtres: [
        FiltreTableau(nom: 'unite', libelle: 'Unité', options: [
          for (final u in hosUnitesObservation) OptionChamp(u.id, u.label)
        ])
      ],
      colonnes: [
        ColonneTableau(
            cle: 'reference',
            libelle: 'N°',
            sansCoupure: true,
            rendu: (_, o) => texteMono('${o['reference']}')),
        ColonneTableau(
            cle: 'patient',
            libelle: 'Patient',
            texte: (o) => '${o['patient']} ${o['patientCode']}',
            rendu: (_, o) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('${o['patient']}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)),
                  texteMono('${o['patientCode']}', couleur: JetonsShell.slate400),
                ])),
        const ColonneTableau(cle: 'motif', libelle: 'Motif de surveillance'),
        ColonneTableau(
            cle: 'uniteLabel',
            libelle: 'Unité',
            texte: (o) => '${o['uniteLabel']}'.replaceAll('Salle d’observation — ', ''),
            rendu: (_, o) => BadgeSigh('${o['uniteLabel']}'.replaceAll('Salle d’observation — ', ''), ton: TonSigh.navy)),
        ColonneTableau(
            cle: 'dateEntree',
            libelle: 'Entrée',
            sansCoupure: true,
            valeur: (o) => hosVersDate(o['dateEntree'])?.millisecondsSinceEpoch,
            texte: (o) => dateHeureCourte(o['dateEntree']),
            rendu: (_, o) {
              final d = dateHosLocale(o['dateEntree']);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(d == null ? '' : dateFR(d),
                    style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
                Text(d == null ? '' : heure(d),
                    style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
              ]);
            }),
        ColonneTableau(
            cle: 'duree',
            libelle: 'Durée',
            droite: true,
            valeur: (o) => hosHeuresEcoulees(o, maintenant),
            texte: (o) => heures(o, maintenant),
            rendu: (_, o) {
              final rouge = hosDepasse(o, maintenant) && o['statutObservation'] == 'en_cours';
              return Text(heures(o, maintenant),
                  style: TextStyle(
                      fontSize: 14,
                      height: 20 / 14,
                      color: rouge ? JetonsShell.danger600 : JetonsShell.slate600,
                      fontWeight: rouge ? FontWeight.w600 : FontWeight.w400));
            }),
        ColonneTableau(
            cle: 'constantes',
            libelle: 'Constantes',
            droite: true,
            valeur: (o) => (o['constantes'] as List? ?? const []).length,
            texte: (o) => '${(o['constantes'] as List? ?? const []).length} relevé(s)'),
        ColonneTableau(
            cle: 'orientation',
            libelle: 'Issue',
            texte: (o) => '${o['orientationLabel'] ?? 'en cours'}',
            rendu: (_, o) {
              if (o['statutObservation'] == 'en_cours') return const BadgeSigh('En observation', ton: TonSigh.info);
              final or = hosOrientation(o['orientation']);
              return or != null
                  ? BadgeSigh(or.label.split(' — ').first, ton: tonDeBadge(or.ton))
                  : const BadgeSigh('Clos');
            }),
      ],
      actionsLigne: (ctx, o) => [
        if (o['statutObservation'] == 'en_cours' && c.droit.editer) ...[
          BoutonIcone(
              icone: LucideIcons.thermometer,
              libelle: 'Relever les constantes',
              onPressed: () => relever(context, o)),
          BoutonIcone(
              icone: LucideIcons.logOut,
              libelle: 'Décider de l’orientation',
              onPressed: () => orienter(context, o)),
        ],
        BoutonIcone(
            icone: LucideIcons.printer,
            libelle: 'Imprimer la feuille',
            onPressed: () => afficherApercu(context, feuille(ContexteEcran.of(context), o))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('observations');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final maintenant = c.aujourdhui;
        final toutes = col.actives;
        final actives = enObservation(toutes);
        final depassements = [for (final o in actives) if (hosDepasse(o, maintenant)) o];
        final clos = [for (final o in toutes) if (o['statutObservation'] != 'en_cours') o];
        final moyenne = actives.isEmpty
            ? '—'
            : '${arrondiJs(actives.fold<int>(0, (n, o) => n + hosHeuresEcoulees(o, maintenant)) / actives.length).toInt()} h';
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(
                libelle: 'Patients en observation',
                valeur: nombre(actives.length),
                icone: LucideIcons.activity,
                ton: TonSigh.navy),
            KpiSigh(
                libelle: 'Au-delà de $hosDureeObservationReference h',
                valeur: nombre(depassements.length),
                icone: LucideIcons.alarmClock,
                ton: depassements.isNotEmpty ? TonSigh.danger : TonSigh.succes,
                indice: depassements.isNotEmpty ? 'Décision d’orientation attendue' : 'Aucun dépassement'),
            KpiSigh(libelle: 'Durée moyenne', valeur: moyenne, icone: LucideIcons.clock, ton: TonSigh.info),
            KpiSigh(
                libelle: 'Séjours clos',
                valeur: nombre(toutes.length - actives.length),
                icone: LucideIcons.circleCheck,
                ton: TonSigh.neutre),
          ]),
          if (depassements.isNotEmpty) ...[
            const SizedBox(height: 16),
            NoteSigh(
                '${depassements.length} patient(s) en observation depuis plus de $hosDureeObservationReference heures. L’observation n’est pas une hospitalisation : au-delà de la durée de référence, une orientation doit être décidée — sortie, hospitalisation complète ou transfert.',
                ton: TonSigh.danger,
                icone: LucideIcons.alarmClock),
          ],
          const SizedBox(height: 16),
          CarteSigh(
              titre: 'Occupation des unités d’observation',
              sansRemplissage: true,
              child: MiniTableauSigh(colonnes: [
                ColonneMini('Unité', (r) => '${r['unite']}'),
                ColonneMini('Occupées', (r) => '${r['occupees']}', droite: true),
                ColonneMini('Places', (r) => '${r['places']}', droite: true),
                ColonneMini('Disponibilité', (r) => '', rendu: (r) {
                  final libres = r['libres'] as int;
                  return libres > 0
                      ? BadgeSigh('$libres libre(s)', ton: TonSigh.succes)
                      : const BadgeSigh('Complète', ton: TonSigh.danger);
                }),
              ], lignes: [
                for (final u in hosUnitesObservation)
                  () {
                    final n = actives.where((o) => o['unite'] == u.id).length;
                    return <String, Object?>{
                      'unite': u.label,
                      'occupees': n,
                      'places': u.places,
                      'libres': (u.places - n) < 0 ? 0 : u.places - n,
                    };
                  }()
              ])),
          const SizedBox(height: 16),
          OngletsSigh(onglets: [
            OngletDef(
                id: 'encours',
                libelle: 'En observation',
                compte: actives.length,
                construire: (ctx) => _table(ctx, actives, actives: true)),
            OngletDef(
                id: 'clos',
                libelle: 'Séjours clos',
                compte: clos.length,
                construire: (ctx) => _table(ctx, clos, actives: false)),
          ]),
        ]);
      },
    );
  }
}
