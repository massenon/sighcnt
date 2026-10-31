import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cs_commun.dart';
import 'cs_dossiers.dart' show chaineParcours;
import 'cs_fiche.dart' show EditeurMedicamentsCs, EditeurMedicamentsCsState;

const _plein = ColChamp.plein;

List<Fiche> _lignes(Object? v) => [
      for (final x in (v as List? ?? const [])) (x as Map).cast<String, Object?>()
    ];

/// `m2-ordonnances` — « Ordonnances » : les prescriptions émises, le suivi de leur dispensation en pharmacie et leur réédition. Prescrire engage
/// quatre services d'un seul geste : la demande d'analyse part au laboratoire, les médicaments sont annoncés à la pharmacie, la facture attend à
/// la caisse. Rien n'est délivré ni prélevé avant l'encaissement. RG-02 — médicaments au prix d'achat, sans marge.
class EcranOrdonnances extends StatelessWidget with EcranMaquette {
  const EcranOrdonnances({super.key});

  @override
  String get titre => 'Ordonnances';

  @override
  String get description =>
      'Prescriptions émises, suivi de leur dispensation en pharmacie et réédition.';

  @override
  String get regle =>
      'Prescrire engage quatre services d’un seul geste : la demande d’analyse part au laboratoire, les médicaments sont annoncés à la pharmacie, la facture attend à la caisse. Rien n’est délivré ni prélevé avant l’encaissement. RG-02 — médicaments au prix d’achat, sans marge.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.maybeOf(context);
    if (c == null) return const [];
    return [
      BoutonSigh(
          libelle: 'File d’attente caisse',
          icone: LucideIcons.coins,
          taille: TailleBouton.sm,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m8-caisse')),
      BoutonSigh(
          libelle: 'Demandes d’analyses',
          icone: LucideIcons.flaskConical,
          taille: TailleBouton.sm,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m5-demandes')),
      if (c.droit.editer)
        BoutonSigh(
            libelle: 'Nouvelle ordonnance',
            icone: LucideIcons.filePlus,
            taille: TailleBouton.sm,
            onPressed: () => _nouvelle(c)),
    ];
  }

  static void _nouvelle(ContexteEcran c) {
    CsNav.retour = 'm2-ordonnances';
    c.aller('m2-ordonnance-nouvelle');
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('ordonnances');
    return ListenableBuilder(
        listenable: col, builder: (ctx, _) => _Registre(c: c, ecran: ctx, rows: col.actives));
  }
}

class _Registre extends StatelessWidget {
  const _Registre({required this.c, required this.ecran, required this.rows});
  final ContexteEcran c;
  final BuildContext ecran;
  final List<Fiche> rows;

  void _suivre(Fiche r) {
    final m = c.magasin;
    final facture = vrai(r['factureId']) ? m.collection('factures').parId(r['factureId']) : null;
    final demandes = [
      for (final d in m.collection('demandesAnalyses').toutes)
        if (d['ordonnanceId'] == r['id']) d
    ];
    final mouvements = [
      for (final d in m.collection('mouvements').toutes)
        if (d['ordonnanceId'] == r['id']) d
    ];
    final meds = _lignes(r['medicaments']);
    final ana = _lignes(r['analyses']);
    final act = _lignes(r['actes']);
    final etapes = <(String, String, String, TonSigh)>[
      (
        'Prescription établie',
        'Par ${r['medecin']} — ${money(r['montant'], avecDevise: false)}',
        texteDateCs(r['date']),
        TonSigh.succes
      ),
      if (demandes.isNotEmpty)
        (
          '${demandes.length} demande(s) d’analyse créée(s) d’office',
          'Transmises au laboratoire — module M5',
          texteDateCs(r['date']),
          TonSigh.info
        ),
      (
        r['statutPaiement'] == 'soldee'
            ? 'Encaissement validé par la caisse'
            : 'En attente d’encaissement',
        facture != null
            ? '${facture['numero']} — ${money(facture['partPatient'], avecDevise: false)} à la charge du patient'
            : '—',
        r['statutPaiement'] == 'soldee' ? texteDateCs(r['date']) : '—',
        r['statutPaiement'] == 'soldee' ? TonSigh.succes : TonSigh.attention
      ),
      if (r['statutDispensation'] != 'sans_objet')
        (
          r['statutDispensation'] == 'servie' ? 'Médicaments délivrés' : 'Délivrance en attente',
          r['statutDispensation'] == 'servie'
              ? '${mouvements.length} sortie(s) de stock — justificatif ${r['numero']}'
              : 'La pharmacie ne peut servir qu’après encaissement (RG-03)',
          vrai(r['dispenseLe']) ? texteDateCs(r['dispenseLe']) : '—',
          r['statutDispensation'] == 'servie' ? TonSigh.succes : TonSigh.attention
        ),
    ];
    afficherTiroir<void>(ecran,
        titre: '${r['numero']}',
        sousTitre: '${r['patient']} — ${texteDateCs(r['date'])}',
        largeurMax: 768,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Patient', '${r['patient']}'),
            ('Dossier', '${r['patientCode']}'),
            ('Prescripteur', '${r['medecin']}'),
            ('Diagnostic', vrai(r['diagnostic']) ? r['diagnostic'] : '—'),
            ('Date', texteDateCs(r['date'])),
            ('Facture', facture != null ? facture['numero'] : '—'),
          ]),
          if (meds.isNotEmpty) ...[
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Médicaments prescrits',
                sansRemplissage: true,
                child: MiniTableauSigh(colonnes: [
                  ColonneMini('Produit', (l) => '${l['produit']}'),
                  ColonneMini('Posologie', (l) => '${l['posologie'] ?? ''}'),
                  ColonneMini('Quantité', (l) => '${l['quantite']} ${l['unite'] ?? ''}'.trim(), droite: true),
                  ColonneMini('Montant', (l) => money(l['total'], avecDevise: false), droite: true),
                ], lignes: meds)),
          ],
          if (ana.isNotEmpty) ...[
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Analyses demandées',
                sansRemplissage: true,
                child: MiniTableauSigh(colonnes: [
                  ColonneMini('Analyse', (l) => '${l['designation']}'),
                  ColonneMini('Échantillon', (l) => '${l['echantillon'] ?? ''}'),
                  ColonneMini('État', (l) {
                    final dem = demandes.where((x) => x['analyseCode'] == l['code']).firstOrNull;
                    if (dem == null) return '—';
                    return vrai(dem['bloqueParPaiement']) ? 'Attente caisse' : '${dem['etatAnalyse']}';
                  }),
                  ColonneMini('Tarif', (l) => money(l['prix'], avecDevise: false), droite: true),
                ], lignes: ana)),
          ],
          if (act.isNotEmpty) ...[
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Actes prescrits',
                sansRemplissage: true,
                child: MiniTableauSigh(colonnes: [
                  ColonneMini('Acte', (l) => '${l['libelle']}'),
                  ColonneMini('Secteur', (l) => '${l['secteur'] ?? ''}'),
                  ColonneMini('Tarif',
                      (l) => vrai(l['prix']) ? money(l['prix'], avecDevise: false) : 'à valider',
                      droite: true),
                ], lignes: act)),
          ],
          const SizedBox(height: 16),
          CarteSigh(titre: 'Suivi inter-modules', child: chaineParcours(etapes)),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Imprimer l’ordonnance',
                  icone: LucideIcons.printer,
                  onPressed: () => imprimerOrdonnance(ecran, r)),
            ]);
  }

  @override
  Widget build(BuildContext context) {
    final k = csKpisOrdonnances(rows);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        KpiSigh(
            libelle: 'Ordonnances émises',
            valeur: nombre(k.emises),
            icone: LucideIcons.fileText,
            ton: TonSigh.navy),
        KpiSigh(
            libelle: 'En attente d’encaissement',
            valeur: nombre(k.enAttente),
            icone: LucideIcons.coins,
            ton: TonSigh.attention),
        KpiSigh(
            libelle: 'À délivrer en pharmacie',
            valeur: nombre(k.aDelivrer),
            icone: LucideIcons.pill,
            ton: TonSigh.info),
        KpiSigh(
            libelle: 'Valeur prescrite',
            valeur: money(k.valeur),
            icone: LucideIcons.coins,
            ton: TonSigh.succes,
            indice: 'Au prix d’achat (RG-02)'),
      ]),
      const SizedBox(height: 16),
      TableauSigh(
        titre: 'Ordonnances',
        lignes: rows,
        taillePage: 12,
        triInitial: 'date',
        sensInitial: 'desc',
        nomExport: 'ordonnances',
        filtres: const [
          FiltreTableau(nom: 'statutDispensation', libelle: 'Dispensation', options: [
            OptionChamp('en_attente', 'À délivrer'),
            OptionChamp('servie', 'Servie'),
            OptionChamp('sans_objet', 'Sans médicament')
          ]),
          FiltreTableau(nom: 'statutPaiement', libelle: 'Règlement', options: [
            OptionChamp('impayee', 'Impayée'),
            OptionChamp('soldee', 'Réglée')
          ]),
        ],
        colonnes: [
          ColonneTableau(
              cle: 'numero',
              libelle: 'N° ordonnance',
              sansCoupure: true,
              texte: (r) => '${r['numero']}${vrai(r['urgent']) ? ' Urgent' : ''}',
              rendu: (_, r) => Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${r['numero']}', style: styleMonoCs),
                    if (vrai(r['urgent'])) ...[
                      const SizedBox(width: 4),
                      const BadgeSigh('Urgent', ton: TonSigh.danger)
                    ],
                  ])),
          ColonneTableau(
              cle: 'date',
              libelle: 'Date',
              sansCoupure: true,
              texte: (r) => texteDateCs(r['date'])),
          colPatientCs(),
          const ColonneTableau(cle: 'medecin', libelle: 'Prescripteur'),
          ColonneTableau(
              cle: 'lignes',
              libelle: 'Contenu',
              valeur: (r) =>
                  _lignes(r['medicaments']).length +
                  _lignes(r['analyses']).length +
                  _lignes(r['actes']).length,
              texte: (r) => [
                    if (_lignes(r['medicaments']).isNotEmpty) '${_lignes(r['medicaments']).length} médic.',
                    if (_lignes(r['analyses']).isNotEmpty) '${_lignes(r['analyses']).length} analyse(s)',
                    if (_lignes(r['actes']).isNotEmpty) '${_lignes(r['actes']).length} acte(s)',
                  ].join(' '),
              rendu: (_, r) => Wrap(spacing: 4, runSpacing: 4, children: [
                    if (_lignes(r['medicaments']).isNotEmpty)
                      BadgeSigh('${_lignes(r['medicaments']).length} médic.', ton: TonSigh.info),
                    if (_lignes(r['analyses']).isNotEmpty)
                      BadgeSigh('${_lignes(r['analyses']).length} analyse(s)', ton: TonSigh.navy),
                    if (_lignes(r['actes']).isNotEmpty)
                      BadgeSigh('${_lignes(r['actes']).length} acte(s)', ton: TonSigh.neutre),
                  ])),
          ColonneTableau(
              cle: 'montant',
              libelle: 'Montant',
              droite: true,
              texte: (r) => money(r['montant'], avecDevise: false)),
          ColonneTableau(
              cle: 'statutPaiement',
              libelle: 'Caisse',
              texte: (r) => r['statutPaiement'] == 'soldee' ? 'Réglée' : 'À encaisser',
              rendu: (_, r) => r['statutPaiement'] == 'soldee'
                  ? const BadgeSigh('Réglée', ton: TonSigh.succes)
                  : const BadgeSigh('À encaisser', ton: TonSigh.attention)),
          ColonneTableau(
              cle: 'statutDispensation',
              libelle: 'Pharmacie',
              texte: (r) => switch (r['statutDispensation']) {
                    'servie' => 'Servie',
                    'en_attente' => 'À délivrer',
                    _ => '—'
                  },
              rendu: (_, r) => switch (r['statutDispensation']) {
                    'servie' => const BadgeSigh('Servie', ton: TonSigh.succes),
                    'en_attente' => const BadgeSigh('À délivrer', ton: TonSigh.attention),
                    _ => const BadgeSigh('—', ton: TonSigh.neutre),
                  }),
        ],
        alClicLigne: _suivre,
        actions: [
          if (c.droit.editer)
            BoutonSigh(
                libelle: 'Nouvelle ordonnance',
                icone: LucideIcons.plus,
                taille: TailleBouton.sm,
                onPressed: () => EcranOrdonnances._nouvelle(c)),
        ],
        actionsLigne: (context, r) => [
          BoutonIcone(
              icone: LucideIcons.printer,
              libelle: 'Imprimer',
              onPressed: () => imprimerOrdonnance(ecran, r)),
          BoutonIcone(
              icone: LucideIcons.eye,
              libelle: 'Suivre le parcours',
              onPressed: () => _suivre(r)),
        ],
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// m2-ordonnance-nouvelle
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `m2-ordonnance-nouvelle` — « Nouvelle ordonnance » : médicaments, analyses et actes d'une même ordonnance, transmise d'un seul geste à la caisse,
/// à la pharmacie et au laboratoire. La prescription passe par le MOTEUR du parcours (`csPrescrire`) ; les tâches d'aval naissent BLOQUÉES.
class EcranOrdonnanceNouvelle extends StatefulWidget with EcranMaquette {
  const EcranOrdonnanceNouvelle({super.key});

  @override
  String get titre => 'Nouvelle ordonnance';

  @override
  String get description =>
      'Médicaments, analyses et actes d’une même ordonnance — transmise d’un seul geste à la caisse, à la pharmacie et au laboratoire.';

  @override
  String get regle =>
      'La prescription passe par le moteur du parcours : elle engendre l’ordonnance, les demandes d’analyses, la facture et les files d’attente des postes concernés. Les tâches d’aval naissent bloquées — l’encaissement seul les libère (RG-03).';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.maybeOf(context);
    if (c == null || !c.droit.editer) return const [];
    return [
      BoutonSigh(
          libelle: 'Prescrire et transmettre',
          icone: LucideIcons.send,
          taille: TailleBouton.sm,
          onPressed: () => _EtatOrdonnanceNouvelle._courant?.valider()),
    ];
  }

  @override
  State<EcranOrdonnanceNouvelle> createState() => _EtatOrdonnanceNouvelle();
}

class _EtatOrdonnanceNouvelle extends State<EcranOrdonnanceNouvelle> {
  static _EtatOrdonnanceNouvelle? _courant;
  bool _pret = false;
  late ControleurFormulaire _entete, _complements;
  final _editeur = GlobalKey<EditeurMedicamentsCsState>();
  String _retour = 'm2-ordonnances';

  @override
  void initState() {
    super.initState();
    _courant = this;
  }

  @override
  void dispose() {
    if (_courant == this) _courant = null;
    if (_pret) {
      _entete.dispose();
      _complements.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pret) return;
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    _retour = CsNav.retour == 'm2-dossiers-consultation' ? 'm2-ordonnances' : CsNav.retour;
    final d = c.aujourdhui;
    _entete = ControleurFormulaire([
      ChampDef(
          nom: 'patientCode',
          libelle: 'Dossier patient',
          type: TypeChamp.select,
          requis: true,
          col: _plein,
          options: optionsPatientsCs(m)),
      ChampDef(
          nom: 'medecin',
          libelle: 'Médecin prescripteur',
          type: TypeChamp.select,
          requis: true,
          options: optionsMedecinsCs(m)),
      const ChampDef(
          nom: 'date',
          libelle: 'Date et heure',
          requis: true,
          indicatif: 'AAAA-MM-JJThh:mm'),
      const ChampDef(nom: 'diagnostic', libelle: 'Diagnostic', col: _plein),
      const ChampDef(
          nom: 'urgent', libelle: 'Prescription urgente', type: TypeChamp.case_),
    ], {
      'date':
          '${iso(d)}T${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
    });
    _complements = ControleurFormulaire([
      ChampDef(
          nom: 'analyses',
          libelle: 'Analyses de laboratoire',
          type: TypeChamp.multiselect,
          col: _plein,
          options: optionsAnalysesCs(m),
          aide: 'Chaque analyse cochée engendre sa demande au laboratoire, sans ressaisie.'),
      ChampDef(
          nom: 'actes',
          libelle: 'Actes et soins',
          type: TypeChamp.multiselect,
          col: _plein,
          options: optionsActesCs(m),
          aide: 'Catalogue des activités par secteur — document « Répartition des activités » de la clinique.'),
    ]);
    _pret = true;
  }

  String _total(ContexteEcran c) {
    final m = c.magasin;
    double mMed = 0, mAna = 0, mAct = 0;
    for (final l in _editeur.currentState?.collecter() ?? const <Map<String, Object?>>[]) {
      mMed += nombreOuZero(m.collection('produits').parId(l['produitId'])?['prixAchat']) *
          nombreOuZero(l['quantite']);
    }
    for (final code in (_complements['analyses'] as List? ?? const [])) {
      mAna += nombreOuZero(
          m.referentiel('analyses').where((x) => x['code'] == code).firstOrNull?['prix']);
    }
    for (final code in (_complements['actes'] as List? ?? const [])) {
      mAct += nombreOuZero(
          m.collection('actes').actives.where((x) => x['code'] == code).firstOrNull?['prix']);
    }
    return '${money(mMed + mAna + mAct)}  (médicaments ${money(mMed, avecDevise: false)} · analyses ${money(mAna, avecDevise: false)} · actes ${money(mAct, avecDevise: false)})';
  }

  void valider() {
    if (!mounted || !_pret) return;
    final c = ContexteEcran.of(context);
    if (!c.droit.editer) return;
    final v = _entete.valider();
    if (v == null) return;
    final comp = _complements.valider() ?? const <String, Object?>{};
    final med = _editeur.currentState?.collecter() ?? const <Map<String, Object?>>[];
    final analyses = [for (final x in (comp['analyses'] as List? ?? const [])) '$x'];
    final actes = [for (final x in (comp['actes'] as List? ?? const [])) '$x'];
    if (med.isEmpty && analyses.isEmpty && actes.isEmpty) {
      ToastsSigh.afficher(context, 'Une ordonnance doit porter au moins un médicament, une analyse ou un acte.',
          type: TypeToast.attention);
      return;
    }
    final date = DateTime.tryParse('${v['date']}'.replaceFirst(' ', 'T'));
    if (date == null) {
      ToastsSigh.afficher(context, 'Date et heure invalides : saisir AAAA-MM-JJThh:mm.',
          type: TypeToast.erreur);
      return;
    }
    final ResultatPrescription res;
    try {
      res = csPrescrire(
          stockDe(c),
          {
            'patientCode': v['patientCode'],
            'medecin': v['medecin'],
            'diagnostic': v['diagnostic'],
            'date': date.toUtc().toIso8601String(),
            'urgent': v['urgent'] == true,
            'medicaments': med,
            'analyses': analyses,
            'actes': actes,
          },
          sessionDe(c));
    } on RefusCs catch (e) {
      ToastsSigh.afficher(context, 'Prescription impossible : ${e.message}', type: TypeToast.erreur);
      return;
    }
    final envois = [
      if (res.demandes.isNotEmpty) '${res.demandes.length} demande(s) au laboratoire',
      if (med.isNotEmpty) 'pharmacie informée',
      'facture ${res.facture['numero']} en attente à la caisse',
    ];
    ToastsSigh.afficher(context, 'Ordonnance ${res.ordonnance['numero']} transmise.',
        type: TypeToast.succes, detail: envois.join(' · '), duree: const Duration(seconds: 9));
    CsNav.vider();
    c.aller(_retour);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    if (!c.droit.editer) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const NoteSigh(
            'Votre profil consulte les ordonnances sans en établir. La prescription appartient au médecin et à la sage-femme (RG-13).',
            ton: TonSigh.attention,
            icone: LucideIcons.lock),
        const SizedBox(height: 12),
        BoutonSigh(
            libelle: 'Revenir au registre',
            variante: VarianteBouton.secondaire,
            icone: LucideIcons.arrowLeft,
            onPressed: () => c.aller(_retour)),
      ]);
    }
    return ListenableBuilder(
        listenable: Listenable.merge([_entete, _complements]),
        builder: (ctx, _) {
          final principal = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CarteSigh(titre: 'Patient et prescripteur', child: FormulaireSigh(controleur: _entete)),
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Médicaments',
                child: EditeurMedicamentsCs(
                    key: _editeur,
                    magasin: c.magasin,
                    peutEditer: true,
                    alChangement: () {
                      if (mounted) setState(() {});
                    })),
            const SizedBox(height: 16),
            CarteSigh(titre: 'Analyses et actes', child: FormulaireSigh(controleur: _complements)),
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Récapitulatif',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Total de la prescription',
                      style: TextStyle(color: JetonsShell.slate500, fontSize: 12)),
                  Text(_total(c),
                      style: const TextStyle(
                          color: JetonsShell.slate800,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ])),
          ]);
          final aside = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CarteSigh(titre: 'Enchaînement du parcours', child: chaineParcours(const [
              ('Prescription', 'Médicaments, analyses et actes d’une même ordonnance', 'Étape 1', TonSigh.navy),
              ('Caisse', 'Une facture GLOBALE, part assureur et part patient (M8)', 'Étape 2', TonSigh.attention),
              ('Pharmacie', 'Dispensation débloquée par l’encaissement, sortie de stock (M6)', 'Étape 3', TonSigh.info),
              ('Laboratoire', 'Prélèvement autorisé une fois l’examen réglé (M5)', 'Étape 4', TonSigh.info),
              ('Résultats', 'Rendus au prescripteur après validation biologique', 'Étape 5', TonSigh.neutre),
            ])),
            const SizedBox(height: 16),
            const CarteSigh(
                titre: 'Rappels de facturation',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  NoteSigh('RG-02 — les médicaments sont facturés au prix d’achat, sans marge.'),
                  SizedBox(height: 12),
                  NoteSigh(
                      'RG-03 — les tâches d’aval naissent bloquées : seul l’encaissement les libère, ligne par ligne.',
                      ton: TonSigh.attention,
                      icone: LucideIcons.lock),
                  SizedBox(height: 12),
                  NoteSigh(
                      'RG-09 — la prise en charge ne s’applique que si la carte est valide à la date de facturation.',
                      ton: TonSigh.attention,
                      icone: LucideIcons.shieldAlert),
                ])),
          ]);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LayoutBuilder(builder: (_, w) {
              if (w.maxWidth >= 1024) {
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 2, child: principal),
                  const SizedBox(width: 16),
                  Expanded(child: aside),
                ]);
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [principal, const SizedBox(height: 16), aside]);
            }),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.only(top: 16),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: JetonsShell.slate200))),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                BoutonSigh(
                    libelle: 'Annuler',
                    icone: LucideIcons.x,
                    variante: VarianteBouton.secondaire,
                    onPressed: () {
                      CsNav.vider();
                      c.aller(_retour);
                    }),
                const SizedBox(width: 8),
                BoutonSigh(
                    libelle: 'Prescrire et transmettre',
                    icone: LucideIcons.send,
                    onPressed: valider),
              ]),
            ),
          ]);
        });
  }
}
