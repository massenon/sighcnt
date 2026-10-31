import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'img_commun.dart' show styleMono, tonImagerie;

/// Accueil M2 (agenda, rendez-vous, files) : ce que partagent les écrans. Les règles vivent dans `packages/domaine/lib/src/consultation/ag_*.dart`,
/// rejouées sur des vecteurs tirés des écrans réels ; ici, ce que l'agent VOIT.

TonSigh tonAg(String t) => tonImagerie(t);

/// « 16/08/2026 à 09h00 » ; une date illisible s'écrit comme en JavaScript.
String texteDateHeureAg(Object? v) {
  final d = agDate(v);
  return d == null ? 'NaN/NaN/NaN à NaNhNaN' : dateHeure(d);
}

KpiSigh kpiAg(AgKpi k, IconData icone, TonSigh ton) => KpiSigh(
    libelle: k.libelle, valeur: k.valeur, icone: icone, ton: ton, indice: k.indice);

// --- les listes du formulaire --------------------------------------------------------------------------------------------------------

List<Fiche> patientsAg(ContexteEcran c) => c.magasin.collection('patients').actives;

/// `optionsPatients()` : `code — nom prénom`, triés par code.
List<OptionChamp> optionsPatientsAg(ContexteEcran c) => [
      for (final p in trierPar(patientsAg(c), (p) => p['code']))
        OptionChamp('${p['code']}', '${p['code']} — ${p['nom']} ${p['prenom']}')
    ];

List<Fiche> medecinsAg(ContexteEcran c) => [
      for (final e in c.magasin.collection('personnel').actives)
        if (e['fonction'] == 'medecin') e
    ];

List<OptionChamp> optionsMedecinsAg(ContexteEcran c) =>
    [for (final m in medecinsAg(c)) OptionChamp('${m['nomComplet']}')];

/// La valeur de départ d'un champ à partir d'une fiche (édition) : une date-heure ISO se relit à l'heure locale (E328).
Map<String, Object?> valeursInitialesAg(Fiche r, List<ChampDef> champs) => {
      for (final f in champs)
        if (f.type != TypeChamp.section)
          f.nom: switch (f.type) {
            TypeChamp.dateHeure => agIsoLocal(r[f.nom]),
            TypeChamp.case_ => agVrai(r[f.nom]),
            TypeChamp.multiselect => r[f.nom] ?? <String>[],
            _ => r[f.nom] == null
                ? ''
                : (r[f.nom] is num && (r[f.nom] as num) == (r[f.nom] as num).truncate()
                    ? '${(r[f.nom] as num).truncate()}'
                    : '${r[f.nom]}'),
          }
    };

/// Ce que `U.form().collect()` livre : les nombres deviennent des nombres (vide = `null`), le reste reste tel que saisi.
Fiche collecterAg(List<ChampDef> champs, Map<String, Object?> v) => {
      for (final f in champs)
        if (f.type != TypeChamp.section && v.containsKey(f.nom))
          f.nom: f.type == TypeChamp.nombre
              ? ('${v[f.nom]}'.trim().isEmpty ? null : num.tryParse('${v[f.nom]}'))
              : v[f.nom]
    };

// --- les champs des rendez-vous ------------------------------------------------------------------------------------------------------

/// `champsRendezVous()` : un dossier du répertoire, OU une personne non enregistrée (quatre champs) ; les six natures de venue ; les cinq états.
List<ChampDef> champsRendezVousAg(ContexteEcran c) => [
      const ChampDef.section('Patient et praticien'),
      ChampDef(
          nom: 'patientCode',
          libelle: 'Dossier patient',
          type: TypeChamp.select,
          col: ColChamp.plein,
          options: optionsPatientsAg(c),
          aide:
              'Laisser vide pour une personne non enregistrée — renseigner alors son identité ci-dessous.'),
      const ChampDef.section('Ou personne NON enregistrée (sans dossier)'),
      const ChampDef(
          nom: 'visiteurNom',
          libelle: 'Nom',
          aide: 'Visiteur, accompagnant, client, affaire privée.'),
      const ChampDef(nom: 'visiteurPrenom', libelle: 'Prénom(s)'),
      const ChampDef(nom: 'visiteurQuartier', libelle: 'Quartier / résidence'),
      const ChampDef(
          nom: 'visiteurTelephone', libelle: 'Numéro de téléphone', type: TypeChamp.tel),
      ChampDef(
          nom: 'medecin',
          libelle: 'Praticien',
          type: TypeChamp.select,
          requis: true,
          options: optionsMedecinsAg(c)),
      ChampDef(
          nom: 'type',
          libelle: 'Type',
          type: TypeChamp.select,
          requis: true,
          options: [for (final t in agTypesRdv) OptionChamp(t)]),
      const ChampDef.section('Rendez-vous'),
      const ChampDef(
          nom: 'date',
          libelle: 'Date et heure',
          type: TypeChamp.dateHeure,
          requis: true),
      const ChampDef(nom: 'motif', libelle: 'Motif', requis: true, col: ColChamp.plein),
      const ChampDef(
          nom: 'diagnostic',
          libelle: 'Diagnostic',
          type: TypeChamp.textarea,
          lignes: 2,
          col: ColChamp.plein),
      const ChampDef(nom: 'tarif', libelle: 'Tarif (FCFA)', type: TypeChamp.nombre),
      const ChampDef(
          nom: 'statut',
          libelle: 'Statut',
          type: TypeChamp.select,
          requis: true,
          options: [
            OptionChamp('planifiee', 'Planifiée'),
            OptionChamp('en_cours', 'En cours'),
            OptionChamp('reporte', 'Reporté'),
            OptionChamp('non_honore', 'Non honoré'),
            OptionChamp('terminee', 'Terminée'),
          ]),
    ];

// --- la modale de formulaire (création / édition) --------------------------------------------------------------------------------------

/// La modale `Nouveau … / Modifier …` du kit de la maquette : le formulaire, le contrôle de l'écran (`avant`), la transformation, l'écriture, le message.
Future<void> ouvrirFormulaireAg(BuildContext ecran,
    {required String collection,
    required String entite,
    required List<ChampDef> Function() champs,
    required Fiche initial,
    Fiche? record,
    String? Function(Fiche valeurs)? avant,
    required Fiche Function(Fiche valeurs, Fiche? record) transformer,
    TailleModale taille = TailleModale.lg,
    String prefixe = 'CON'}) {
  final c = ContexteEcran.of(ecran);
  final liste = champs();
  final ctl = ControleurFormulaire(
      liste, record != null ? valeursInitialesAg(record, liste) : initial);
  return afficherModale<void>(ecran,
      titre: record != null ? 'Modifier l’enregistrement' : 'Nouveau $entite',
      sousTitre: record != null
          ? '${record['code'] ?? record['reference'] ?? record['numero'] ?? record['id']}'
          : 'Les champs marqués d’un astérisque sont obligatoires.',
      taille: taille,
      corps: FormulaireSigh(controleur: ctl),
      pied: (fermer) => [
            BoutonSigh(
                libelle: 'Annuler',
                variante: VarianteBouton.secondaire,
                onPressed: fermer),
            BoutonSigh(
                libelle: record != null ? 'Enregistrer' : 'Créer',
                icone: record != null ? LucideIcons.save : LucideIcons.plus,
                onPressed: () {
                  final brut = ctl.valider();
                  if (brut == null) {
                    ToastsSigh.afficher(ecran, 'Le formulaire comporte des erreurs.',
                        type: TypeToast.erreur);
                    return;
                  }
                  var v = collecterAg(liste, brut);
                  final refus = avant?.call(v);
                  if (refus != null) {
                    ToastsSigh.afficher(ecran, refus, type: TypeToast.erreur);
                    return;
                  }
                  v = transformer(v, record);
                  final col = c.magasin.collection(collection);
                  final VoidCallback annuler;
                  final Fiche ecrite;
                  if (record != null) {
                    annuler = col.mettreAJour(record['id'], v);
                    ecrite = col.parId(record['id']) ?? v;
                  } else {
                    final r = col.inserer(v, prefixe: prefixe);
                    annuler = r.annuler;
                    ecrite = r.fiche;
                  }
                  fermer();
                  ToastsSigh.afficher(
                      ecran,
                      record != null
                          ? 'Modifications enregistrées.'
                          : 'Nouveau $entite créé.',
                      type: TypeToast.succes,
                      detail: '${ecrite['code'] ?? ecrite['reference'] ?? ecrite['numero'] ?? ''}'
                              .isEmpty
                          ? null
                          : '${ecrite['code'] ?? ecrite['reference'] ?? ecrite['numero']}',
                      annuler: annuler);
                }),
          ]);
}

/// Le formulaire de rendez-vous : création ou édition (la référence est gardée à l'édition).
Future<void> formulaireRendezVousAg(BuildContext ecran, {Fiche? record}) {
  final c = ContexteEcran.of(ecran);
  final m = c.magasin;
  return ouvrirFormulaireAg(ecran,
      collection: 'consultations',
      entite: 'rendez-vous',
      champs: () => champsRendezVousAg(c),
      initial: const {'statut': 'planifiee', 'type': 'Consultation', 'tarif': '3000'},
      record: record,
      avant: agValiderVenue,
      transformer: (v, rec) => agCompleterVenue(v,
          record: rec,
          patients: patientsAg(c),
          existantes: m.collection('consultations').toutes));
}

// --- les suites d'un rendez-vous ------------------------------------------------------------------------------------------------------

void marquerHonoreAg(BuildContext ecran, Fiche r) {
  final c = ContexteEcran.of(ecran);
  c.magasin.collection('consultations').mettreAJour(r['id'], agPatchHonore(c.aujourdhui));
  ToastsSigh.afficher(
      ecran, 'Rendez-vous honoré — il passe à l’onglet « Honorés » et quitte l’agenda.',
      type: TypeToast.succes);
}

Future<void> marquerNonHonoreAg(BuildContext ecran, Fiche r) async {
  final c = ContexteEcran.of(ecran);
  final motif = await confirmerAvecMotif(ecran,
      titre: 'Marquer ce rendez-vous non honoré ?',
      message:
          'Le rendez-vous reste dans l’agenda, signalé comme non honoré : c’est ce qui permet de rappeler le patient et de mesurer l’absentéisme. Le motif est conservé (RG-12).',
      libelleOk: 'Marquer non honoré');
  if (motif == null) return;
  c.magasin.collection('consultations').mettreAJour(r['id'], agPatchNonHonore(motif, c.aujourdhui));
  if (ecran.mounted) {
    ToastsSigh.afficher(ecran, 'Rendez-vous marqué non honoré.', type: TypeToast.succes);
  }
}

Future<void> reporterAg(BuildContext ecran, Fiche r) {
  final c = ContexteEcran.of(ecran);
  final ctl = ControleurFormulaire(const [
    ChampDef(
        nom: 'nouvelleDate',
        libelle: 'Nouvelle date et heure',
        type: TypeChamp.dateHeure,
        requis: true,
        col: ColChamp.plein),
    ChampDef(
        nom: 'motifReport',
        libelle: 'Motif du report',
        type: TypeChamp.select,
        requis: true,
        col: ColChamp.plein,
        options: [
          OptionChamp('Indisponibilité du praticien'),
          OptionChamp('Demande du patient'),
          OptionChamp('Urgence prioritaire'),
          OptionChamp('Examen non disponible'),
          OptionChamp('Patient absent — nouvelle date convenue'),
          OptionChamp('Autre motif'),
        ]),
  ]);
  final d = agDate(r['date']);
  return afficherModale<void>(ecran,
      titre: 'Reporter le rendez-vous',
      sousTitre:
          '${r['patient']} — ${d == null ? 'NaN/NaN/NaN' : dateFR(d)} à ${d == null ? 'NaNhNaN' : heure(d)}',
      taille: TailleModale.md,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const NoteSigh(
            'La date initiale reste écrite sur la fiche : un report dont on ne voit plus la date d’origine ne se distingue pas d’une saisie corrigée.',
            icone: LucideIcons.calendarClock),
        const SizedBox(height: 12),
        FormulaireSigh(controleur: ctl),
      ]),
      pied: (fermer) => [
            BoutonSigh(
                libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: 'Reporter',
                icone: LucideIcons.calendarClock,
                onPressed: () {
                  final v = ctl.valider();
                  if (v == null) {
                    ToastsSigh.afficher(ecran, 'Le formulaire comporte des erreurs.',
                        type: TypeToast.erreur);
                    return;
                  }
                  c.magasin.collection('consultations').mettreAJour(
                      r['id'],
                      agPatchReport(r, '${v['nouvelleDate']}', '${v['motifReport']}',
                          c.aujourdhui));
                  fermer();
                  final n = agDate(v['nouvelleDate']);
                  ToastsSigh.afficher(ecran,
                      'Rendez-vous reporté au ${n == null ? 'NaN/NaN/NaN' : dateFR(n)}.',
                      type: TypeToast.succes);
                }),
          ]);
}

Future<void> archiverRendezVousAg(BuildContext ecran, Fiche r) async {
  final c = ContexteEcran.of(ecran);
  final motif = await confirmerAvecMotif(ecran,
      titre: 'Annuler ce rendez-vous ?',
      message:
          'Le rendez-vous est archivé (RG-14), pas supprimé : il reste consultable et l’opération est annulable.',
      libelleOk: 'Annuler le rendez-vous',
      dangereux: true);
  if (motif == null) return;
  final col = c.magasin.collection('consultations');
  col.mettreAJour(r['id'], {'_motifArchivage': motif});
  final undo = col.archiver(r['id']);
  if (ecran.mounted) {
    ToastsSigh.afficher(ecran, 'Rendez-vous annulé.', type: TypeToast.succes, annuler: undo);
  }
}

// --- le détail d'un rendez-vous ---------------------------------------------------------------------------------------------------------

/// `detail(r)` : la fiche, les notes (report, non honoré, à statuer), la suite, le motif et le diagnostic, la couverture.
Widget detailRendezVousAg(BuildContext ecran, Fiche r) {
  final c = ContexteEcran.of(ecran);
  final p = patientsAg(c).where((x) => x['id'] == r['patientId']).firstOrNull;
  final d = agDate(r['date']);
  final suites = <Widget>[
    if (c.droit.editer && r['statut'] != 'terminee')
      BoutonSigh(
          libelle: 'Marquer honoré',
          icone: LucideIcons.circleCheck,
          taille: TailleBouton.sm,
          onPressed: () {
            Navigator.of(ecran, rootNavigator: true).pop();
            marquerHonoreAg(ecran, r);
          }),
    if (c.droit.editer && r['statut'] != 'terminee')
      BoutonSigh(
          libelle: 'Reporter',
          icone: LucideIcons.calendarClock,
          taille: TailleBouton.sm,
          variante: VarianteBouton.secondaire,
          onPressed: () {
            Navigator.of(ecran, rootNavigator: true).pop();
            reporterAg(ecran, r);
          }),
    if (c.droit.editer && r['statut'] != 'terminee' && r['statut'] != 'non_honore')
      BoutonSigh(
          libelle: 'Marquer non honoré',
          icone: LucideIcons.userX,
          taille: TailleBouton.sm,
          variante: VarianteBouton.secondaire,
          onPressed: () {
            Navigator.of(ecran, rootNavigator: true).pop();
            marquerNonHonoreAg(ecran, r);
          }),
  ];
  final assurance = agNoteAssurance(p);
  Widget bloc(String libelle, String valeur) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(libelle,
                style: const TextStyle(
                    color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
            Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(valeur,
                    style: const TextStyle(
                        color: JetonsShell.slate800, fontSize: 14, height: 20 / 14))),
          ]);
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    DescListeSigh([
      ('Référence', Text('${r['reference'] ?? r['id']}', style: styleMono)),
      ('Date', d == null ? 'NaN/NaN/NaN à NaNhNaN' : '${dateFR(d)} à ${heure(d)}'),
      (
        'Patient',
        agVrai(r['nonPatient'])
            ? Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${r['patient']}'),
                const BadgeSigh('individu non enregistré', ton: TonSigh.info)
              ])
            : '${r['patient']}'
      ),
      (
        'Dossier',
        Text(agVrai(r['nonPatient']) ? '— (sans dossier)' : '${r['patientCode']}',
            style: styleMono)
      ),
      ('Praticien', '${r['medecin'] ?? ''}'),
      ('Type', '${r['type'] ?? ''}'),
      ('Statut', statutBadge(r['statut'])),
      ('Tarif', money(r['tarif'] ?? 0)),
    ]),
    for (final n in agNotesDetail(r, c.aujourdhui)) ...[
      const SizedBox(height: 16),
      NoteSigh(n.texte,
          ton: tonAg(n.ton),
          icone: n.ton == 'danger' ? LucideIcons.userX : LucideIcons.triangleAlert),
    ],
    if (suites.isNotEmpty) ...[
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Suite du rendez-vous',
          child: Wrap(spacing: 8, runSpacing: 8, children: suites)),
    ],
    const SizedBox(height: 16),
    CarteSigh(
        titre: 'Motif et diagnostic',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          bloc('Motif de consultation', agVrai(r['motif']) ? '${r['motif']}' : '—'),
          const SizedBox(height: 12),
          bloc('Diagnostic', agVrai(r['diagnostic']) ? '${r['diagnostic']}' : 'Non renseigné'),
        ])),
    if (assurance != null) ...[
      const SizedBox(height: 16),
      NoteSigh(assurance, icone: LucideIcons.shieldCheck),
    ],
  ]);
}

/// `etatConsultation(r)` : le compte rendu de consultation imprimable.
Future<void> imprimerConsultationAg(BuildContext ecran, Fiche r) {
  final c = ContexteEcran.of(ecran);
  final p = patientsAg(c).where((x) => x['id'] == r['patientId']).firstOrNull;
  final d = agDate(r['date']);
  return afficherApercu(
      ecran,
      PieceA4(
        titre: 'Compte rendu de consultation',
        sousTitre: '${r['type']} du ${d == null ? 'NaN/NaN/NaN' : dateFR(d)}',
        reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
        utilisateur: c.utilisateur,
        edite: c.aujourdhui,
        cartouche: [
          ('Patient', '${r['patient']}'),
          ('Dossier', '${r['patientCode']}'),
          ('Âge', ageTexte(p, c.aujourdhui)),
          ('Praticien', '${r['medecin'] ?? ''}'),
          ('Référence', '${r['reference'] ?? r['id']}'),
          ('Type', '${r['type'] ?? ''}'),
        ],
        blocs: [
          BlocTexte('Motif de consultation : ${agVrai(r['motif']) ? r['motif'] : '—'}'),
          BlocTexte('Diagnostic retenu : ${agVrai(r['diagnostic']) ? r['diagnostic'] : '—'}'),
          const BlocTexte(
              'Observations et conduite à tenir — (Espace réservé à la rédaction manuscrite ou à la saisie)',
              italique: true),
        ],
        signatures: [Signature('Le Médecin traitant', nom: '${r['medecin'] ?? ''}')],
      ));
}

// --- le passage sans rendez-vous -----------------------------------------------------------------------------------------------------------

/// `nouvelleVisite()` : un patient du répertoire, OU une personne non enregistrée (nom, prénom, quartier, téléphone) — jamais de dossier ni de code CNT.
Future<void> passageSansRendezVousAg(BuildContext ecran) {
  final c = ContexteEcran.of(ecran);
  final m = c.magasin;
  final liste = <ChampDef>[
    ChampDef(
        nom: 'patientCode',
        libelle: 'Patient (dossier du répertoire)',
        type: TypeChamp.select,
        col: ColChamp.plein,
        options: optionsPatientsAg(c),
        aide:
            'Laisser vide si la personne n’est pas un patient — remplir alors les champs ci-dessous.'),
    const ChampDef.section('Ou personne NON enregistrée (sans dossier)'),
    const ChampDef(
        nom: 'visiteurNom',
        libelle: 'Nom',
        aide: 'Visiteur, accompagnant, client, affaire privée.'),
    const ChampDef(nom: 'visiteurPrenom', libelle: 'Prénom(s)'),
    const ChampDef(nom: 'visiteurQuartier', libelle: 'Quartier / résidence'),
    const ChampDef(
        nom: 'visiteurTelephone', libelle: 'Numéro de téléphone', type: TypeChamp.tel),
    const ChampDef.section('Le passage'),
    const ChampDef(
        nom: 'date', libelle: 'Heure d’arrivée', type: TypeChamp.dateHeure, requis: true),
    const ChampDef(
        nom: 'motif', libelle: 'Motif du passage', requis: true, col: ColChamp.plein),
    const ChampDef(
        nom: 'type',
        libelle: 'Nature',
        type: TypeChamp.select,
        requis: true,
        options: [OptionChamp('Consultation'), OptionChamp('Urgence'), OptionChamp('Contrôle')]),
    ChampDef(
        nom: 'orientation',
        libelle: 'Orientation',
        type: TypeChamp.select,
        requis: true,
        options: [for (final o in agOrientations) OptionChamp(o)],
        aide: 'Service vers lequel le patient est dirigé après l’accueil.'),
    ChampDef(
        nom: 'medecin',
        libelle: 'Praticien pressenti',
        type: TypeChamp.select,
        options: optionsMedecinsAg(c)),
    const ChampDef(nom: 'priorite', libelle: 'Passage prioritaire', type: TypeChamp.case_),
    const ChampDef(
        nom: 'tarif', libelle: 'Tarif de la consultation (FCFA)', type: TypeChamp.nombre),
  ];
  final ctl = ControleurFormulaire(liste, {'date': agIsoLocal(c.aujourdhui)});
  return afficherModale<void>(ecran,
      titre: 'Enregistrer un passage sans rendez-vous',
      taille: TailleModale.lg,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const NoteSigh(
            'L’heure d’arrivée est tracée : c’est elle qui mesure l’attente à l’accueil. L’orientation dirige le patient vers le service compétent et prépare sa prise en charge.'),
        const SizedBox(height: 12),
        const NoteSigh(
            'Deux voies, et une seule à la fois : sélectionner un patient du répertoire, ou renseigner nom, prénom, quartier et téléphone d’une personne non enregistrée. Cette seconde voie n’ouvre aucun dossier médical et ne consomme aucun code CNT (RG-01).',
            icone: LucideIcons.userPlus),
        const SizedBox(height: 12),
        FormulaireSigh(controleur: ctl),
      ]),
      pied: (fermer) => [
            BoutonSigh(
                libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: 'Enregistrer le passage',
                icone: LucideIcons.userCheck,
                onPressed: () {
                  final brut = ctl.valider();
                  if (brut == null) {
                    ToastsSigh.afficher(ecran, 'Le formulaire comporte des erreurs.',
                        type: TypeToast.erreur);
                    return;
                  }
                  final v = collecterAg(liste, brut);
                  final refus = agValiderVenue(v);
                  if (refus != null) {
                    ToastsSigh.afficher(ecran, refus, type: TypeToast.erreur);
                    return;
                  }
                  final prioritaire = agVrai(v['priorite']);
                  final r = agPassage(v,
                      patients: patientsAg(c),
                      existantes: m.collection('consultations').toutes);
                  final ins = m.collection('consultations').inserer(r, prefixe: 'CON');
                  fermer();
                  final msg = agMessagePassage(r, prioritaire);
                  ToastsSigh.afficher(ecran, msg.message,
                      type: prioritaire ? TypeToast.attention : TypeToast.succes,
                      detail: msg.detail,
                      annuler: prioritaire ? null : ins.annuler);
                }),
          ]);
}

// --- la barre de plage de dates -----------------------------------------------------------------------------------------------------------

/// `plageDates` du kit de la maquette : un FILTRE du/au (jamais un tri), avec ses trois raccourcis. Vide, la plage laisse tout passer.
class BarrePlageAg extends StatefulWidget {
  const BarrePlageAg({super.key, required this.aujourdhui, required this.alChanger});
  final DateTime aujourdhui;
  final void Function(String du, String au) alChanger;
  @override
  State<BarrePlageAg> createState() => _EtatBarrePlage();
}

class _EtatBarrePlage extends State<BarrePlageAg> {
  final _du = ControleurFormulaire(
      const [ChampDef(nom: 'du', libelle: 'Du', type: TypeChamp.date)]);
  final _au = ControleurFormulaire(
      const [ChampDef(nom: 'au', libelle: 'Au', type: TypeChamp.date)]);

  @override
  void initState() {
    super.initState();
    _du.addListener(_signaler);
    _au.addListener(_signaler);
  }

  void _signaler() => widget.alChanger('${_du['du'] ?? ''}', '${_au['au'] ?? ''}');

  void _poser(String du, String au) {
    _du.removeListener(_signaler);
    _au.removeListener(_signaler);
    _du.poser('du', du);
    _au.poser('au', au);
    _du.addListener(_signaler);
    _au.addListener(_signaler);
    _signaler();
  }

  @override
  void dispose() {
    _du.dispose();
    _au.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.aujourdhui;
    return CarteSigh(
        child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
          SizedBox(width: 170, child: FormulaireSigh(controleur: _du)),
          SizedBox(width: 170, child: FormulaireSigh(controleur: _au)),
          BoutonSigh(
              key: const Key('ag:aujourdhui'),
              libelle: 'Aujourd’hui',
              icone: LucideIcons.calendar,
              variante: VarianteBouton.secondaire,
              onPressed: () => _poser(iso(a), iso(a))),
          BoutonSigh(
              key: const Key('ag:sept-jours'),
              libelle: 'Sept derniers jours',
              icone: LucideIcons.calendarDays,
              variante: VarianteBouton.secondaire,
              onPressed: () => _poser(iso(ajouterJours(a, -6)), iso(a))),
          BoutonSigh(
              key: const Key('ag:toute-periode'),
              libelle: 'Toute la période',
              icone: LucideIcons.calendarOff,
              variante: VarianteBouton.secondaire,
              onPressed: () => _poser('', '')),
        ]));
  }
}

/// Un minuteur à usage unique que l'écran libère à son démontage (le rappel des échéances).
Timer? minuteurUneFois(Duration d, VoidCallback f) => Timer(d, f);
