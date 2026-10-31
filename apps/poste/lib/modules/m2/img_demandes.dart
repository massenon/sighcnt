import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'img_commun.dart';

bool _vrai(Object? v) => v != null && v != '' && v != 0 && v != false;

/// « Saisir le CR » / « Poursuivre le CR » : la saisie des VARIABLES du compte rendu (`saisirCR`, par examen) n'est pas portée avec ces trois
/// écrans ; la commande reste offerte aux profils qui ont le droit d'écrire et DIT ce qu'il en est (écart E108) — jamais un compte rendu à moitié écrit.
void saisirCompteRendu(BuildContext ctx, Fiche demande) => ToastsSigh.afficher(
    ctx, 'La saisie du compte rendu n’est pas encore portée sur ce poste.',
    type: TypeToast.info,
    detail:
        'Demande ${demande['reference']} — ${demande['examen']} : la saisie des variables de l’examen reste à la maquette.',
    duree: const Duration(seconds: 8));

/// `rendreCR(r, apres)` : la conclusion est obligatoire ; la confirmation précède l'écriture ; la demande passe à « validée », le poste du
/// prescripteur est notifié.
Future<void> rendreCompteRenduEcran(BuildContext ctx, Fiche cr) async {
  final c = ContexteEcran.of(ctx);
  final m = c.magasin;
  final maintenant = c.aujourdhui.toIso8601String();
  final RenduImagerie r;
  try {
    r = rendreCompteRendu(cr, maintenant: maintenant);
  } on RefusImagerie catch (e) {
    ToastsSigh.afficher(ctx, e.message, type: TypeToast.erreur);
    return;
  }
  final ok = await confirmerSigh(ctx,
      titre: 'Rendre le compte rendu au prescripteur ?',
      message:
          'Le compte rendu ${cr['reference']} sera transmis à ${cr['prescripteur']}. Une correction ultérieure devra être signalée comme telle.',
      libelleOk: 'Rendre');
  if (!ok || !ctx.mounted) return;
  m.collection('resultatsImagerie').mettreAJour(cr['id'], r.patchCompteRendu);
  if (r.patchDemande != null) {
    m.collection('demandesImagerie')
        .mettreAJour(cr['demandeImagerieId'], r.patchDemande!);
  }
  m
      .collection('notifications')
      .inserer({'id': nouvelIdImagerie('NOT'), ...r.notification}, prefixe: 'NOT');
  ToastsSigh.afficher(ctx, 'Compte rendu rendu au prescripteur.',
      type: TypeToast.succes, detail: '${cr['reference']}');
}

/// Les rubriques rédigées d'un compte rendu : l'échographie garde la Conclusion ; les autres modalités suivent le plan radiologique.
List<(String, String)> rubriquesLibres(String modalite) => modalite ==
        'echographie'
    ? const [('conclusion', 'Conclusion')]
    : const [
        ('resultats', 'Résultats — description rédigée'),
        ('conclusion', 'Conclusion'),
        ('recommandation', 'Recommandation')
      ];

/// `detailCR(r)` — l'en-tête et les rubriques rédigées. Le tableau « Résultats » (variables de l'examen) n'est pas porté (écart E108).
Widget detailCompteRendu(Fiche r, List<Fiche> catalogue) {
  final modalite = modaliteDemandeDeExamen(catalogue, r['examenCode']);
  final age = r['age'];
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    DescListeSigh([
      ('Référence', r['reference']),
      ('Examen', r['examen']),
      ('Patient', '${r['patient']} — ${r['patientCode']}'),
      ('Âge', age != null ? '$age ans' : '—'),
      ('Indication', r['indication']),
      ('DDR', _vrai(r['ddr']) ? r['ddr'] : '—'),
      ('Provenance', _vrai(r['provenance']) ? r['provenance'] : '—'),
      ('Condition de l’examen', _vrai(r['condition']) ? r['condition'] : '—'),
      ('Prescripteur', r['prescripteur']),
      ('Réalisé par', r['realisateur']),
      ('État', r['statut'] == 'rendu' ? 'Rendu au prescripteur' : 'En rédaction'),
    ]),
    for (final (code, libelle) in rubriquesLibres(modalite))
      if (_vrai(r[code])) ...[
        const SizedBox(height: 16),
        SectionSigh(
            titre: libelle,
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('${r[code]}',
                    style: TextStyle(
                        color: code == 'conclusion'
                            ? JetonsShell.slate800
                            : JetonsShell.slate600,
                        fontSize: 14,
                        height: 20 / 14,
                        fontWeight: code == 'conclusion'
                            ? FontWeight.w500
                            : FontWeight.w400)))),
      ],
  ]);
}

/// `m2-imagerie-demandes` — « Demandes d’imagerie médicale » : le registre des examens demandés, aux mêmes états que le laboratoire
/// (demandé, payé, exécuté, validé). Toute la décision vit dans `packages/domaine` (`img_demandes_*`), rejouée sur les vecteurs de l'écran réel.
class EcranDemandesImagerie extends StatelessWidget with EcranMaquette {
  const EcranDemandesImagerie({super.key});

  @override
  String get titre => 'Demandes d’imagerie médicale';

  @override
  String get description =>
      'Le registre des examens demandés, aux mêmes états que le laboratoire : demandé, payé, exécuté, validé.';

  @override
  String get regle =>
      'La demande naît bloquée par le paiement : c’est l’encaissement de SA ligne qui la rend exécutable — la caisse encaisse des examens nommés. Le compte rendu ne se saisit que sur une demande payée, et sa validation (rendu au prescripteur) clôt le circuit. Un examen sans tarif validé est refusé en le nommant — un tiret n’est pas un zéro.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final dems = m.collection('demandesImagerie');
    final crs = m.collection('resultatsImagerie');
    return ListenableBuilder(
      listenable: Listenable.merge([dems, crs, m.collection('examensImagerie')]),
      builder: (context, _) {
        final catalogue = catalogueExamens(m);
        final actives = dems.actives;
        final comptes = comptesParEtat(actives);
        const icones = {
          'demandee': LucideIcons.wallet,
          'payee': LucideIcons.scanLine,
          'executee': LucideIcons.pencil,
          'validee': LucideIcons.fileCheck2,
        };
        // La modalité se lit au catalogue ; posée sur la ligne affichée pour que le filtre la trouve, jamais écrite au magasin.
        final lignes = [
          for (final d in actives)
            {
              ...d,
              'modalite': _vrai(d['modalite'])
                  ? d['modalite']
                  : modaliteDemandeDeExamen(catalogue, d['examenCode'])
            }
        ];
        String modLibelle(Fiche r) =>
            modaliteDemandeImagerie(modaliteDemandeDeExamen(catalogue, r['examenCode']))
                .libelle;
        // OUVRIR une demande est un acte de PRESCRIPTION : l'échographiste exécute et saisit le CR, mais ne prescrit pas.
        final peutOuvrir = c.droit.editer && c.role != 'echographiste';
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                for (final e in etatsImagerie)
                  KpiSigh(
                      libelle: e.libelle,
                      valeur: nombre(comptes[e.id]!),
                      icone: icones[e.id],
                      ton: comptes[e.id]! > 0
                          ? tonImagerie(e.ton)
                          : TonSigh.neutre),
              ]),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Registre des demandes',
                taillePage: 12,
                triInitial: 'dateHeure',
                sensInitial: 'desc',
                nomExport: 'demandes-imagerie',
                messageVide:
                    'Aucune demande d’imagerie. Une demande s’ouvre ici ou naît d’une consultation.',
                lignes: lignes,
                filtres: [
                  FiltreTableau(nom: 'modalite', libelle: 'Modalité', options: [
                    for (final x in modalitesDemandeImagerie)
                      OptionChamp(x.code, x.libelle)
                  ]),
                  FiltreTableau(nom: 'statut', libelle: 'État', options: [
                    for (final e in etatsImagerie)
                      OptionChamp(e.id, e.libelle)
                  ]),
                ],
                colonnes: [
                  ColonneTableau(
                      cle: 'reference',
                      libelle: 'N°',
                      texte: (r) =>
                          '${r['reference']} ${r['factureNumero'] ?? ''}'.trim(),
                      rendu: (_, r) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${r['reference']}', style: styleMono),
                                if (_vrai(r['factureNumero']))
                                  Text('${r['factureNumero']}',
                                      style: const TextStyle(
                                          fontFamily: 'LiberationMono',
                                          fontSize: 10,
                                          color: JetonsShell.slate400)),
                              ])),
                  ColonneTableau(
                      cle: 'dateHeure',
                      libelle: 'Date',
                      texte: (r) => texteDate(r['dateHeure'])),
                  ColonneTableau(
                      cle: 'patient',
                      libelle: 'Patient',
                      texte: (r) =>
                          '${r['patient']} — ${_vrai(r['patientCode']) ? r['patientCode'] : '—'}'),
                  const ColonneTableau(cle: 'examen', libelle: 'Examen'),
                  ColonneTableau(
                      cle: 'modalite',
                      libelle: 'Modalité',
                      valeur: modLibelle,
                      texte: modLibelle,
                      rendu: (_, r) =>
                          BadgeSigh(modLibelle(r), ton: TonSigh.navy)),
                  const ColonneTableau(
                      cle: 'prescripteur', libelle: 'Prescripteur'),
                  ColonneTableau(
                      cle: 'prix',
                      libelle: 'Tarif',
                      droite: true,
                      texte: (r) => money(r['prix'], avecDevise: false)),
                  ColonneTableau(
                      cle: 'statut',
                      libelle: 'État',
                      valeur: (r) => etatImagerie(r['statut']).libelle,
                      texte: (r) => etatImagerie(r['statut']).libelle,
                      rendu: (_, r) {
                        final e = etatImagerie(r['statut']);
                        return BadgeSigh(e.libelle, ton: tonImagerie(e.ton));
                      }),
                ],
                alClicLigne: (r) => _consulter(context, c, r, catalogue),
                actionsLigne: (ctx, r) {
                  final cr = compteRenduDeDemande(r, crs.actives);
                  return [
                    if (r['statut'] == 'demandee')
                      // Verrouillé et non masqué : la balle est à la caisse.
                      Opacity(
                          opacity: 0.5,
                          child: BoutonSigh(
                              libelle: 'Saisir le CR',
                              icone: LucideIcons.lock,
                              taille: TailleBouton.sm,
                              variante: VarianteBouton.secondaire,
                              onPressed: () => ToastsSigh.afficher(
                                  ctx, 'Saisie impossible : examen non réglé.',
                                  type: TypeToast.erreur,
                                  detail:
                                      'La caisse doit encaisser la pièce ${r['factureNumero'] ?? ''} d’abord.'))),
                    if ((r['statut'] == 'payee' || r['statut'] == 'executee') &&
                        c.droit.editer)
                      BoutonSigh(
                          libelle: r['statut'] == 'payee'
                              ? 'Saisir le CR'
                              : 'Poursuivre le CR',
                          icone: LucideIcons.filePenLine,
                          taille: TailleBouton.sm,
                          onPressed: () => saisirCompteRendu(ctx, r)),
                    if (r['statut'] == 'executee' && cr != null && c.droit.editer)
                      BoutonSigh(
                          libelle: 'Rendre',
                          icone: LucideIcons.send,
                          taille: TailleBouton.sm,
                          variante: VarianteBouton.secondaire,
                          onPressed: () => rendreCompteRenduEcran(ctx, cr)),
                  ];
                },
                actions: [
                  if (peutOuvrir)
                    BoutonSigh(
                        libelle: 'Nouvelle demande',
                        icone: LucideIcons.plus,
                        taille: TailleBouton.sm,
                        onPressed: () => _ouvrirDemande(context, c)),
                ],
              ),
            ]);
      },
    );
  }

  void _consulter(
      BuildContext ctx, ContexteEcran c, Fiche r, List<Fiche> catalogue) {
    final cr = compteRenduDeDemande(r, c.magasin.collection('resultatsImagerie').actives);
    afficherTiroir<void>(ctx,
        titre: '${r['examen']}',
        sousTitre: '${r['patient']} — ${r['reference']}',
        corps: cr != null
            ? detailCompteRendu(cr, catalogue)
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DescListeSigh([
                  ('Référence', r['reference']),
                  ('Date', texteDate(r['dateHeure'])),
                  ('Patient', r['patient']),
                  ('Examen', r['examen']),
                  ('Prescripteur', r['prescripteur']),
                  ('Indication', _vrai(r['indication']) ? r['indication'] : '—'),
                  ('Tarif', money(r['prix'])),
                  ('Facture', _vrai(r['factureNumero']) ? r['factureNumero'] : '—'),
                  ('État', etatImagerie(r['statut']).libelle),
                ]),
                if (r['statut'] == 'demandee') ...[
                  const SizedBox(height: 16),
                  NoteSigh(
                      'L’examen attend son règlement : la balle est à la caisse (${_vrai(r['factureNumero']) ? r['factureNumero'] : 'pièce à émettre'}).',
                      ton: TonSigh.attention,
                      icone: LucideIcons.wallet),
                ],
              ]));
  }

  void _ouvrirDemande(BuildContext ctx, ContexteEcran c) => afficherModale<void>(
      ctx,
      titre: 'Nouvelle demande d’imagerie',
      taille: TailleModale.lg,
      corps: _ModaleDemande(contexte: c, ecran: ctx),
      pied: null);
}

class _ModaleDemande extends StatefulWidget {
  const _ModaleDemande({required this.contexte, required this.ecran});
  final ContexteEcran contexte;

  /// Le contexte de l'ÉCRAN : une modale vit au-dessus de la coque, hors du `ContexteEcran` — les messages passent par lui.
  final BuildContext ecran;
  @override
  State<_ModaleDemande> createState() => _EtatModaleDemande();
}

class _EtatModaleDemande extends State<_ModaleDemande> {
  late final ControleurFormulaire _f;

  @override
  void initState() {
    super.initState();
    final m = widget.contexte.magasin;
    final prescripteurs = [
      for (final s in m.collection('soignants').actives)
        if (_vrai(s['prescrit']))
          OptionChamp('${s['nomComplet']}', '${s['nomComplet']} — ${s['poste']}')
    ];
    // Patient du répertoire OU adressé de l'extérieur : une échographie prescrite ailleurs se pratique ici comme une analyse prescrite ailleurs.
    _f = ControleurFormulaire([
      ChampDef(
          nom: 'patientCode',
          libelle: 'Patient (dossier du répertoire)',
          type: TypeChamp.select,
          col: ColChamp.plein,
          options: optionsPatientsImagerie(m),
          aide:
              'Laisser vide pour un patient ADRESSÉ DE L’EXTÉRIEUR — renseigner alors son identité ci-dessous.'),
      const ChampDef.section('Ou patient adressé de l’extérieur (dossier créé ici)'),
      const ChampDef(nom: 'nom', libelle: 'Nom', col: ColChamp.tiers),
      const ChampDef(nom: 'prenom', libelle: 'Prénom(s)', col: ColChamp.tiers),
      const ChampDef(
          nom: 'sexe',
          libelle: 'Sexe',
          type: TypeChamp.select,
          col: ColChamp.tiers,
          options: [OptionChamp('F', 'Féminin'), OptionChamp('M', 'Masculin')]),
      const ChampDef(
          nom: 'naissanceConnue',
          libelle: 'Date de naissance',
          type: TypeChamp.select,
          requis: true,
          recherche: false,
          options: [
            OptionChamp('date', 'Connue — la saisir'),
            OptionChamp('age', 'Inconnue — indiquer l’âge déclaré')
          ]),
      ChampDef(
          nom: 'dateNaissance',
          libelle: 'Date de naissance',
          type: TypeChamp.date,
          condition: (controle: 'naissanceConnue', quand: ['date']),
          valider: (v, _) {
            final d = DateTime.tryParse('$v');
            return d != null && d.isAfter(widget.contexte.aujourdhui)
                ? 'La date ne peut pas être dans le futur.'
                : null;
          }),
      ChampDef(
          nom: 'age',
          libelle: 'Âge déclaré (ans)',
          type: TypeChamp.nombre,
          condition: (controle: 'naissanceConnue', quand: ['age']),
          valider: (v, _) {
            final n = num.tryParse('$v');
            return n == null || n < 0 || n > 120
                ? 'Âge compris entre 0 et 120 ans.'
                : null;
          }),
      const ChampDef(nom: 'telephone', libelle: 'Téléphone', type: TypeChamp.tel),
      const ChampDef(nom: 'residence', libelle: 'Quartier / résidence'),
      const ChampDef.section('L’examen demandé'),
      ChampDef(
          nom: 'examens',
          libelle: 'Examens demandés',
          type: TypeChamp.multiselect,
          requis: true,
          col: ColChamp.tiers,
          options: [
            for (final x in catalogueExamens(m))
              OptionChamp('${x['code']}', '${x['label']}')
          ]),
      ChampDef(
          nom: 'prescripteur',
          libelle: 'Prescripteur',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.tiers,
          options: [
            ...prescripteurs,
            const OptionChamp(prescripteurExterneImagerie,
                '— Prescripteur extérieur à la clinique —')
          ]),
      const ChampDef(
          nom: 'prescripteurExterne',
          libelle: 'Prescripteur extérieur — nom, qualification et structure',
          col: ColChamp.tiers,
          condition: (controle: 'prescripteur', quand: [prescripteurExterneImagerie]),
          aide:
              'Ex. : Dr SALIFOU Aminou, médecin généraliste, Centre de santé de Perma. C’est ce qui permet de lui renvoyer le compte rendu.'),
      const ChampDef(
          nom: 'indication',
          libelle: 'Indication',
          type: TypeChamp.textarea,
          requis: true,
          col: ColChamp.plein,
          lignes: 2),
      const ChampDef(
          nom: 'urgent',
          libelle: 'Examen urgent',
          type: TypeChamp.case_,
          col: ColChamp.plein),
    ], {
      'naissanceConnue': 'date'
    });
  }

  @override
  void dispose() {
    _f.dispose();
    super.dispose();
  }

  void _emettre() {
    final c = widget.contexte;
    final m = c.magasin;
    final v = _f.valider();
    if (v == null) {
      ToastsSigh.afficher(widget.ecran, 'Le formulaire comporte des erreurs.',
          type: TypeToast.erreur);
      return;
    }
    final code = '${v['patientCode'] ?? ''}';
    final pt = code.isEmpty
        ? null
        : m
            .collection('patients')
            .actives
            .where((x) => x['code'] == code)
            .firstOrNull;
    if (code.isNotEmpty && pt == null) {
      ToastsSigh.afficher(widget.ecran, 'Patient introuvable.',
          type: TypeToast.erreur);
      return;
    }
    if (pt == null &&
        ('${v['nom'] ?? ''}'.trim().isEmpty ||
            '${v['prenom'] ?? ''}'.trim().isEmpty)) {
      // Un refus qui NOMME ce qui manque : sans identité, le compte rendu ne peut être ni remis ni retrouvé.
      ToastsSigh.afficher(widget.ecran, refusIdentiteImagerie,
          type: TypeToast.erreur);
      return;
    }
    final patients = m.collection('patients');
    final demandes = m.collection('demandesImagerie');
    final maintenant = c.aujourdhui.toIso8601String();
    final OuvertureImagerie r;
    try {
      r = ouvrirDemandeImagerie(
        examens: [for (final x in (v['examens'] as List)) '$x'],
        catalogue: catalogueExamens(m),
        patients: patients.toutes,
        couvertures: m.collection('couverturesAssurance').actives,
        demandesExistantes: demandes.toutes,
        nbFactures: m.collection('factures').toutes.length,
        prixDe: prixDepuisMagasin(m),
        nouvelId: nouvelIdImagerie,
        date: maintenant,
        maintenant: maintenant,
        patientId: pt == null ? null : '${pt['id']}',
        nom: v['nom'] as String?,
        prenom: v['prenom'] as String?,
        sexe: v['sexe'] as String?,
        dateNaissance: v['naissanceConnue'] == 'date' ? v['dateNaissance'] as String? : null,
        age: v['naissanceConnue'] == 'age' ? v['age'] : null,
        telephone: v['telephone'] as String?,
        residence: v['residence'] as String?,
        prescripteur: nomPrescripteurImagerie(v['prescripteur'], v['prescripteurExterne']),
        indication: v['indication'] as String?,
        urgent: v['urgent'] == true,
        origine: pt != null ? 'consultation' : 'externe',
      );
    } on RefusImagerie catch (e) {
      // Les demandes déjà créées sont écrites puis ARCHIVÉES (RG-14) : le numéro qu'elles ont consommé ne se réutilise pas.
      for (final a in e.archivees) {
        demandes.inserer({...a, 'statut': 'actif'}, prefixe: 'IME');
        demandes.archiver(a['id']);
      }
      ToastsSigh.afficher(widget.ecran, e.message, type: TypeToast.erreur);
      return;
    }
    if (r.dossierCree) patients.inserer(r.patient, prefixe: 'PAT');
    for (final d in r.demandes) {
      demandes.inserer(d, prefixe: 'IME');
    }
    m.collection('factures').inserer(r.facture, prefixe: 'FAC');
    m.collection('taches').inserer(r.tacheEncaissement, prefixe: 'TCH');
    m.collection('taches').inserer(r.tacheExamen, prefixe: 'TCH');
    m.collection('notifications').inserer(r.notification, prefixe: 'NOT');
    final t = messageDemandeEmise(
        examens: r.demandes.length,
        facture: '${r.facture['numero']}',
        dossier: pt == null ? '${r.patient['code']}' : null);
    Navigator.of(context).pop();
    ToastsSigh.afficher(widget.ecran, t.message,
        type: TypeToast.succes,
        detail: t.detail,
        duree: const Duration(seconds: 8));
  }

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FormulaireSigh(controleur: _f),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          BoutonSigh(
              libelle: 'Annuler',
              variante: VarianteBouton.secondaire,
              onPressed: () => Navigator.of(context).pop()),
          const SizedBox(width: 8),
          BoutonSigh(
              libelle: 'Émettre la demande',
              icone: LucideIcons.send,
              onPressed: _emettre),
        ]),
      ]);
}
