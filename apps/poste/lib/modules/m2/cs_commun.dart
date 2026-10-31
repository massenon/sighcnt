import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// La consultation (M2, zone 2) : ce que partagent le registre des consultations, les dossiers, la fiche, les ordonnances, les prescriptions
/// et la salle de soins. Toute la décision vit dans `packages/domaine/lib/src/consultation/`, rejouée sur les vecteurs des écrans réels.

bool vrai(Object? v) => v != null && v != '' && v != 0 && v != false;

/// Les écrans de la maquette se passent leurs paramètres par l'adresse (`#onglet=…`, `?id=…`) ou le `sessionStorage` ; la coque du poste ne
/// porte qu'un identifiant d'écran. Ce relais en mémoire est le pendant : posé AVANT `c.aller(...)`, consommé par l'écran appelé.
class CsNav {
  CsNav._();

  /// Le dossier à compléter (`?id=` de `m2-dossier-consultation-nouveau`) ; `null` = un nouveau dossier.
  static String? dossierId;

  /// Le dossier que la fiche récapitule (`#onglet=<id dossier>` de `m2-consultation-fiche`).
  static String? ficheDossierId;

  /// L'écran où revenir après l'enregistrement.
  static String retour = 'm2-dossiers-consultation';

  static void vider() {
    dossierId = null;
    ficheDossierId = null;
    retour = 'm2-dossiers-consultation';
  }
}

/// Le magasin du poste, vu par le moteur du domaine. Une insertion se défait par ARCHIVAGE (RG-14) : la maquette retire la fiche (écart E342).
class StockMagasin implements StockCs {
  StockMagasin(this.m, this._maintenant);
  final Magasin m;
  final DateTime Function() _maintenant;

  static const _prefixes = {
    'consultations': 'CON',
    'dossiersConsultation': 'DOS',
    'ordonnances': 'ORD',
    'demandesAnalyses': 'DEM',
    'demandesImagerie': 'IME',
    'factures': 'FAC',
    'taches': 'TCH',
    'notifications': 'NOT',
    'prescriptions': 'PRS',
    'administrations': 'ADM',
  };

  @override
  List<Fiche> actives(String col) => m.collection(col).actives;
  @override
  List<Fiche> toutes(String col) => m.collection(col).toutes;
  @override
  Fiche? parId(String col, Object? id) => m.collection(col).parId(id);
  @override
  Fiche inserer(String col, Fiche fiche) => m
      .collection(col)
      .inserer({'statut': 'actif', ...fiche}, prefixe: _prefixes[col] ?? 'ID')
      .fiche;
  @override
  void mettreAJour(String col, Object? id, Fiche patch) =>
      m.collection(col).mettreAJour(id, patch);
  @override
  void archiver(String col, Object? id) => m.collection(col).archiver(id);
  @override
  void defaire(String col, Object? id) => m.collection(col).archiver(id);
  @override
  List<Fiche> referentiel(String nom) => m.referentiel(nom);
  @override
  DateTime get maintenant => _maintenant();
}

StockMagasin stockDe(ContexteEcran c) => StockMagasin(c.magasin, () => c.aujourdhui);

/// La session qui agit. Le poste ne porte pas le secteur de session de la maquette (écart E343) : la demande part sans secteur demandeur
/// tant que la prescription n'en désigne pas.
SessionCs sessionDe(ContexteEcran c) => SessionCs(role: c.role, fonction: c.role);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Options de sélection (les référentiels sont ceux du magasin — rien n'est écrit ici)
// ---------------------------------------------------------------------------------------------------------------------------------------------

List<OptionChamp> optionsPatientsCs(Magasin m) => [
      for (final p in trierPar(m.collection('patients').actives, (p) => p['code']))
        OptionChamp('${p['code']}', '${p['code']} — ${p['nom']} ${p['prenom']}')
    ];

List<OptionChamp> optionsMedecinsCs(Magasin m) => [
      for (final e in m.collection('personnel').actives)
        if (e['fonction'] == 'medecin')
          OptionChamp('${e['nomComplet']}', '${e['nomComplet']}')
    ];

List<OptionChamp> optionsPraticiensCs(Magasin m) => [
      for (final e in m.collection('personnel').actives)
        if (['medecin', 'sage_femme', 'chirurgien'].contains(e['fonction']))
          OptionChamp('${e['nomComplet']}', '${e['nomComplet']}')
    ];

List<OptionChamp> optionsMedicamentsCs(Magasin m) => [
      for (final p in m.collection('produits').actives)
        if (p['categorie'] == 'medicament' || p['categorie'] == 'conso_medical')
          OptionChamp('${p['id']}',
              '${p['designation']} — ${money(p['prixAchat'], avecDevise: false)} · stock ${p['stockDetail'] ?? p['stock']}')
    ];

List<OptionChamp> optionsAnalysesCs(Magasin m) => [
      for (final a in m.referentiel('analyses'))
        OptionChamp('${a['code']}',
            '${a['designation']} — ${a['categorie']} · ${money(a['prix'], avecDevise: false)}')
    ];

List<OptionChamp> optionsActesCs(Magasin m) => [
      for (final a in m.collection('actes').actives)
        OptionChamp('${a['code']}',
            '${a['libelle']} — ${a['secteur']}${vrai(a['prix']) ? ' · ${money(a['prix'], avecDevise: false)}' : ' · tarif à valider'}')
    ];

List<OptionChamp> optionsImagerieCs(Magasin m) => [
      for (final x in m.collection('examensImagerie').actives)
        OptionChamp('${x['code']}',
            '${x['label']} — ${modaliteDemandeImagerie(modaliteDemandeDeExamen(m.collection('examensImagerie').actives, x['code'])).libelle}')
    ];

List<OptionChamp> optionsPathologiesCs(Magasin m) => [
      for (final x in m.collection('pathologies').actives)
        OptionChamp('${x['code']}', '${x['libelle']}')
    ];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Petites mises en forme
// ---------------------------------------------------------------------------------------------------------------------------------------------

const styleMonoCs = TextStyle(
    fontFamily: 'LiberationMono', fontSize: 12, color: JetonsShell.slate700);

DateTime? _date(Object? v) => DateTime.tryParse('${v ?? ''}')?.toLocal();

String texteDateCs(Object? v) {
  final d = _date(v);
  return d == null ? '' : dateFR(d);
}

String texteDateHeureCs(Object? v) {
  final d = _date(v);
  return d == null ? '' : dateHeure(d);
}

TonSigh tonCs(Object? ton) => switch ('$ton') {
      'success' => TonSigh.succes,
      'warning' => TonSigh.attention,
      'info' => TonSigh.info,
      'navy' => TonSigh.navy,
      'danger' => TonSigh.danger,
      _ => TonSigh.neutre,
    };

/// La colonne « Patient » des registres : nom au-dessus, code en police fixe.
ColonneTableau colPatientCs() => ColonneTableau(
    cle: 'patient',
    libelle: 'Patient',
    texte: (r) => '${r['patient'] ?? ''} ${r['patientCode'] ?? ''}'.trim(),
    rendu: (_, r) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${r['patient'] ?? ''}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: JetonsShell.slate800,
                      fontSize: 14,
                      height: 20 / 14,
                      fontWeight: FontWeight.w500)),
              Text('${r['patientCode'] ?? ''}',
                  style: const TextStyle(
                      fontFamily: 'LiberationMono',
                      fontSize: 12,
                      color: JetonsShell.slate400)),
            ]));

/// `K.miniTable(['Rubrique','Contenu'], lignes)` : colonnes chaînes, lignes-tableaux de valeurs.
Widget miniPaires(List<String> entetes, List<List<String>> lignes,
        {String vide = 'Aucune donnée.'}) =>
    MiniTableauSigh(colonnes: [
      for (var i = 0; i < entetes.length; i++)
        ColonneMini(entetes[i], (f) => '${f['$i']}')
    ], lignes: [
      for (final l in lignes) {for (var i = 0; i < l.length; i++) '$i': l[i]}
    ], vide: vide);

Widget espace([double h = 16]) => SizedBox(height: h);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Un bloc repliable EST une carte (`repliable`)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le corps d'un bloc replié reste CONSTRUIT (hauteur nulle) : le texte existe comme dans le DOM d'un `<details>` fermé, et un champ saisi ne se perd
/// pas au repli. Le focus clavier n'y entre pas tant qu'il est fermé.
class RepliableSigh extends StatefulWidget {
  const RepliableSigh(
      {super.key,
      required this.titre,
      required this.icone,
      required this.contenu,
      this.ouvert = false,
      this.extra,
      this.cle});
  final String titre;
  final IconData icone;
  final Widget contenu;
  final bool ouvert;
  final Widget? extra;
  final String? cle;

  @override
  State<RepliableSigh> createState() => RepliableSighState();
}

class RepliableSighState extends State<RepliableSigh> {
  late bool ouvert = widget.ouvert;

  void deplier() => setState(() => ouvert = true);

  @override
  Widget build(BuildContext context) => Container(
        key: widget.cle == null ? null : Key('cs:repliable:${widget.cle}'),
        decoration: decorationCarte(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            InkWell(
              onTap: () => setState(() => ouvert = !ouvert),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: ouvert
                    ? const BoxDecoration(
                        border: Border(bottom: BorderSide(color: JetonsShell.slate200)))
                    : null,
                child: Row(children: [
                  Icon(widget.icone, size: 16, color: JetonsShell.navy700),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(widget.titre,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: JetonsShell.slate900,
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight: FontWeight.w600))),
                  if (widget.extra != null) widget.extra!,
                ]),
              ),
            ),
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: ouvert ? 1 : 0,
                child: ExcludeFocus(
                  excluding: !ouvert,
                  child: Padding(
                      padding: const EdgeInsets.all(20), child: widget.contenu),
                ),
              ),
            ),
          ]),
        ),
      );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les constantes de la zone 1 — LUES, JAMAIS RESSAISIES
// ---------------------------------------------------------------------------------------------------------------------------------------------

Widget blocConstantes(
    ({Map<String, Object?> valeurs, String source})? c) {
  if (c == null) {
    return const NoteSigh(
        'Aucun relevé de constantes de l’accueil pour ce patient. Les constantes se relèvent à l’accueil (« Constantes à l’arrivée ») — elles ne se saisissent pas ici.',
        ton: TonSigh.attention,
        icone: LucideIcons.thermometer);
  }
  final v = c.valeurs;
  final origine = c.source == 'ancienne'
      ? 'Constantes portées par le dossier (saisie antérieure à la refonte).'
      : (c.source == 'copie'
          ? 'Relevé de l’accueil du ${texteDateCs(v['dateHeure'])} ${_heure(v['dateHeure'])}, figé à l’enregistrement du dossier — lecture seule.'
          : 'Relevé de l’accueil du ${texteDateCs(v['dateHeure'])} ${_heure(v['dateHeure'])}${vrai(v['releveePar']) ? ' par ${v['releveePar']}' : ''} — saisi et verrouillé par l’accueil, lecture seule.');
  String u(Object? x, String unite) => x != null ? '$x $unite' : '—';
  final cases = [
    ('Température', u(v['temperature'], '°C')),
    ('TA', vrai(v['tension']) ? '${v['tension']}' : '—'),
    ('Pouls', u(v['pouls'], 'bpm')),
    ('SpO₂', u(v['spo2'], '%')),
    ('Poids', u(v['poids'], 'kg')),
    ('Taille', u(v['taille'], 'cm')),
    ('IMC', v['imc'] != null ? '${v['imc']}' : '—'),
  ];
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Wrap(spacing: 8, runSpacing: 8, children: [
      for (final x in cases)
        Container(
          width: 112,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: JetonsShell.slate50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: JetonsShell.slate200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(x.$1.toUpperCase(),
                style: const TextStyle(
                    color: JetonsShell.slate500, fontSize: 11, letterSpacing: 0.4)),
            Text(x.$2,
                style: const TextStyle(
                    color: JetonsShell.slate800,
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
    ]),
    const SizedBox(height: 8),
    Row(children: [
      const Icon(LucideIcons.lock, size: 14, color: JetonsShell.slate500),
      const SizedBox(width: 4),
      Expanded(
          child: Text(origine,
              style: const TextStyle(
                  color: JetonsShell.slate500, fontSize: 12, height: 16 / 12))),
    ]),
  ]);
}

String _heure(Object? v) {
  final d = _date(v);
  return d == null ? '' : heure(d);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le récapitulatif du dossier — une mécanique, trois portes (tiroir du registre, fiche de consultation, impression)
// ---------------------------------------------------------------------------------------------------------------------------------------------

String? antecedentsObstetricauxLisibles(Map<String, Object?>? o) {
  if (o == null) return null;
  final t = <String>[];
  if (o['gestite'] != null) t.add('G${o['gestite']}');
  if (o['parite'] != null) t.add('P${o['parite']}');
  if (o['enfantsVivants'] != null) t.add('${o['enfantsVivants']} enfant(s) vivant(s)');
  if (vrai(o['faussesCouches'])) t.add('${o['faussesCouches']} fausse(s) couche(s)');
  if (vrai(o['enfantsDecedes'])) t.add('${o['enfantsDecedes']} enfant(s) décédé(s)');
  if (o['ageDerniereGrossesse'] != null) {
    t.add('dernière grossesse à ${o['ageDerniereGrossesse']} ans');
  }
  if (vrai(o['ddr'])) t.add('DDR ${texteDateCs(o['ddr'])}');
  final p = (o['pathologies'] as List? ?? const []);
  if (p.isNotEmpty) t.add('pathologies antérieures : ${p.join(', ')}');
  if (vrai(o['procreateur'])) t.add('procréateur : ${o['procreateur']}');
  return t.isEmpty ? null : t.join(' · ');
}

List<(String, String)> examenObstetricalLisible(Map<String, Object?>? o) => [
      if (o != null)
        for (final x in csExamenObstetrical)
          if (o[x['code']] != null && o[x['code']] != '')
            ('${x['label']}', '${o[x['code']]}')
    ];

List<Fiche> fichesDuDossier(Magasin m, Fiche d) => [
      for (final c in m.collection('consultations').actives)
        if (c['dossierConsultationId'] == d['id']) c
    ];

const _libChir = {
  'actesChirurgicaux': 'Actes chirurgicaux',
  'indicationOperatoire': 'Indication opératoire',
  'blocPrevu': 'Programmation au bloc',
  'risqueOperatoire': 'Risque opératoire'
};

Widget recapDossier(Magasin m, Fiche d,
    {Fiche? releve, bool sansFiches = false}) {
  final etat = csEtatDossier(d['etat']);
  final age = d['age'];
  final c = csConstantesDuDossier(d) ??
      (releve != null
          ? (valeurs: csCopieReleve(releve)!, source: 'accueil')
          : null);
  final ant = [
    for (final cat in csCategoriesAntecedent)
      ['${cat['label']}', vrai(d['ant_${cat['code']}']) ? '${d['ant_${cat['code']}']}' : '—']
  ];
  final obst =
      antecedentsObstetricauxLisibles((d['antecedentsObstetricaux'] as Map?)?.cast());
  if (obst != null) ant.add(['Antécédents obstétricaux (structurés)', obst]);
  final prealables = [
    ('Allergies', d['allergies']),
    ('Allergies médicamenteuses', d['allergiesMedicamenteuses']),
    ('Statut vaccinal', d['statutVaccinal']),
    ('Groupe sanguin', d['groupeSanguin']),
    ('Électrophorèse de l’hémoglobine', d['electrophoreseHb']),
    ('Dépistage', d['depistage']),
    ('Enquête sociale', d['enqueteSociale']),
  ].where((x) => vrai(x.$2)).toList();
  final synth = csSyntheseExamen(csExamensPhysiquesDe(d));
  final lignesExamen = [
    [
      'État général',
      '${csLibelleEtatGeneral(d['etatGeneral'])}${vrai(d['etatGeneralPrecision']) ? ' — ${d['etatGeneralPrecision']}' : ''}'
    ],
    for (final s in synth) [s.label, s.texte],
  ];
  final obsEx = examenObstetricalLisible((d['examenObstetrical'] as Map?)?.cast());
  final chir = csRubriquesChirurgicales.where((r) => vrai(d[r])).toList();
  final fiches = sansFiches ? <Fiche>[] : fichesDuDossier(m, d);
  fiches.sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
  final enfants = <Widget>[
    DescListeSigh([
      ('Dossier', vrai(d['reference']) ? d['reference'] : d['id']),
      ('Patient', '${d['patient'] ?? '—'} — ${d['patientCode'] ?? d['nip'] ?? ''}'),
      (
        'Âge · sexe',
        '${age != null ? '$age ans' : '—'} · ${d['sexe'] == 'F' ? 'Féminin' : (d['sexe'] == 'M' ? 'Masculin' : '—')}'
      ),
      ('Couverture', vrai(d['assureur']) ? d['assureur'] : 'Non assuré'),
      (
        'Venue',
        '${csLibelleTypeVenue(d['typeVenue'])} — ${texteDateCs(d['dateArrivee'])}${vrai(d['heureArrivee']) ? ' ${d['heureArrivee']}' : ''}'
      ),
      ('Motif', vrai(d['motifVenue']) ? d['motifVenue'] : '—'),
      ('Praticien', vrai(d['soignant']) ? d['soignant'] : '—'),
      ('État du dossier', BadgeSigh('${etat['label']}', ton: tonCs(etat['couleur']))),
    ]),
    SectionSigh(
        titre: 'Zone 1 — constantes de l’accueil',
        child: Padding(padding: const EdgeInsets.all(16), child: blocConstantes(c))),
    SectionSigh(
        titre: 'Anamnèse',
        child: miniPaires(['Rubrique', 'Contenu'], [
          ['Histoire de la maladie', vrai(d['histoire']) ? '${d['histoire']}' : '—'],
          [
            'Traitements en cours / habituels',
            vrai(d['traitementEnCours']) ? '${d['traitementEnCours']}' : '—'
          ],
        ])),
    SectionSigh(
        titre: 'Antécédents — trois catégories strictes',
        child: miniPaires(['Catégorie', 'Contenu'], ant)),
    if (prealables.isNotEmpty)
      SectionSigh(
          titre: 'Données préalables',
          child: miniPaires(['Rubrique', 'Contenu'],
              [for (final x in prealables) [x.$1, '${x.$2}']])),
    if (vrai(d['allergiesMedicamenteuses']))
      NoteSigh(
          'Allergie médicamenteuse déclarée : ${d['allergiesMedicamenteuses']}. À vérifier avant toute prescription.',
          ton: TonSigh.danger,
          icone: LucideIcons.triangleAlert),
    SectionSigh(
        titre: 'Examen clinique (IPPOA)',
        child: (synth.isNotEmpty || vrai(d['etatGeneral']))
            ? miniPaires(['Appareil', 'Constatations'], lignesExamen)
            : const VideSigh('Aucun examen clinique consigné.',
                icone: LucideIcons.stethoscope)),
    if (obsEx.isNotEmpty)
      SectionSigh(
          titre: 'Examen obstétrical',
          child: miniPaires(['Élément', 'Constatation'],
              [for (final x in obsEx) [x.$1, x.$2]])),
    if (chir.isNotEmpty)
      SectionSigh(
          titre: 'Actes chirurgicaux et bloc (chirurgien)',
          child: miniPaires(['Rubrique', 'Contenu'],
              [for (final r in chir) [_libChir[r] ?? r, '${d[r]}']])),
    if (vrai(d['diagnostic']) || vrai(d['traitement']) || vrai(d['analysesDemandees']))
      SectionSigh(
          titre: 'Décisions portées au dossier (saisie antérieure à la refonte)',
          child: miniPaires(['Rubrique', 'Contenu'], [
            ['Diagnostic', vrai(d['diagnostic']) ? '${d['diagnostic']}' : '—'],
            ['Analyses demandées', vrai(d['analysesDemandees']) ? '${d['analysesDemandees']}' : '—'],
            ['Traitement', vrai(d['traitement']) ? '${d['traitement']}' : '—'],
            ['Conduite à tenir', vrai(d['conduite']) ? '${d['conduite']}' : '—'],
          ])),
    if (!sansFiches)
      SectionSigh(
          titre: 'Fiches de consultation établies sur ce dossier',
          child: fiches.isEmpty
              ? const VideSigh(
                  'Aucune fiche encore — la synthèse et la prescription se font à la fiche de consultation.',
                  icone: LucideIcons.clipboardList)
              : MiniTableauSigh(colonnes: [
                  ColonneMini('Date', (f) => texteDateCs(f['date'])),
                  ColonneMini('Diagnostic retenu',
                      (f) => vrai(f['diagnostic']) ? '${f['diagnostic']}' : '—'),
                  ColonneMini(
                      'Orientation',
                      (f) => vrai(f['orientationLabel'])
                          ? '${f['orientationLabel']}'
                          : (vrai(f['orientation']) ? '${f['orientation']}' : '—')),
                  ColonneMini('Ordonnance',
                      (f) => vrai(f['ordonnanceNumero']) ? '${f['ordonnanceNumero']}' : '—'),
                ], lignes: fiches)),
  ];
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    for (var i = 0; i < enfants.length; i++) ...[
      if (i > 0) const SizedBox(height: 16),
      enfants[i],
    ]
  ]);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les pièces imprimées
// ---------------------------------------------------------------------------------------------------------------------------------------------

String _ref(ContexteEcran c) =>
    PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero());

/// L'ordonnance médicale — imprimée depuis l'ordonnance ENREGISTRÉE : le papier doit dire ce qui est parti dans le logiciel.
PieceA4 pieceOrdonnance(ContexteEcran c, Fiche r) {
  final meds = [for (final l in (r['medicaments'] as List? ?? const [])) (l as Map).cast<String, Object?>()];
  final ana = [for (final l in (r['analyses'] as List? ?? const [])) (l as Map).cast<String, Object?>()];
  final act = [for (final l in (r['actes'] as List? ?? const [])) (l as Map).cast<String, Object?>()];
  return PieceA4(
    titre: 'Ordonnance médicale',
    sousTitre: '${r['numero']}',
    reference: _ref(c),
    utilisateur: c.utilisateur,
    edite: c.aujourdhui,
    cartouche: [
      ('Patient', '${r['patient']}'),
      ('Dossier', '${r['patientCode']}'),
      ('Date', texteDateCs(r['date'])),
      ('Prescripteur', '${r['medecin']}'),
      ('Diagnostic', vrai(r['diagnostic']) ? '${r['diagnostic']}' : '—'),
      ('Règlement', r['statutPaiement'] == 'soldee' ? 'Réglée' : 'En attente'),
    ],
    blocs: [
      if (meds.isNotEmpty)
        BlocTableau(TableauEtat(colonnes: [
          ColonneEtat(libelle: 'Désignation', valeur: (l) => l['produit']),
          ColonneEtat(libelle: 'Posologie', valeur: (l) => l['posologie']),
          ColonneEtat(
              libelle: 'Quantité',
              droite: true,
              valeur: (l) => '${l['quantite']} ${l['unite'] ?? ''}'.trim()),
          // On ne totalise PAS le prix unitaire : additionner des prix unitaires ne produit aucune grandeur.
          ColonneEtat(
              libelle: 'Prix unitaire',
              droite: true,
              valeur: (l) => money(l['prix'], avecDevise: false)),
          ColonneEtat(
              libelle: 'Montant',
              droite: true,
              valeur: (l) => money(l['total'], avecDevise: false),
              somme: (l) => nombreOuZero(l['total'])),
        ], lignes: meds)),
      if (ana.isNotEmpty) ...[
        const BlocTexte('Analyses demandées', gras: true),
        BlocTableau(TableauEtat(colonnes: [
          ColonneEtat(libelle: 'Analyse demandée', valeur: (l) => l['designation']),
          ColonneEtat(libelle: 'Échantillon', valeur: (l) => l['echantillon']),
          ColonneEtat(
              libelle: 'Tarif',
              droite: true,
              valeur: (l) => money(l['prix'], avecDevise: false),
              somme: (l) => nombreOuZero(l['prix'])),
        ], lignes: ana)),
      ],
      if (act.isNotEmpty) ...[
        const BlocTexte('Actes prescrits', gras: true),
        BlocTableau(TableauEtat(colonnes: [
          ColonneEtat(libelle: 'Acte prescrit', valeur: (l) => l['libelle']),
          ColonneEtat(libelle: 'Secteur', valeur: (l) => l['secteur']),
          ColonneEtat(
              libelle: 'Tarif',
              droite: true,
              valeur: (l) => vrai(l['prix']) ? money(l['prix'], avecDevise: false) : 'à valider',
              somme: (l) => nombreOuZero(l['prix'])),
        ], lignes: act)),
      ],
      if (meds.isEmpty && ana.isEmpty && act.isEmpty)
        const BlocTexte('Cette ordonnance ne porte aucune ligne.', italique: true),
    ],
    signatures: [
      Signature('Le Médecin prescripteur', nom: '${r['medecin']}', mention: 'Signature et cachet'),
      const Signature('Le Pharmacien', mention: 'Dispensation'),
    ],
  );
}

/// Le bulletin d'analyses bio-médicales — la pièce que le patient porte à la caisse puis à la salle de prélèvement.
PieceA4 pieceBulletin(ContexteEcran c, Fiche r) {
  final pat = c.magasin
      .collection('patients')
      .actives
      .where((x) => x['code'] == r['patientCode'] || x['id'] == r['patientId'])
      .firstOrNull;
  final examens = c.magasin.collection('examensLabo').actives;
  final lignes = <Fiche>[
    for (final a in (r['analyses'] as List? ?? const []))
      () {
        final x = (a as Map).cast<String, Object?>();
        final ex = examens.where((e) => e['code'] == x['code']).firstOrNull;
        return <String, Object?>{
          'section': ex != null ? (ex['section'] ?? x['categorie'] ?? '—') : (x['categorie'] ?? '—'),
          'designation': vrai(x['designation']) ? x['designation'] : (ex?['designation'] ?? x['code']),
          'echantillon': vrai(x['echantillon']) ? x['echantillon'] : (ex?['echantillon'] ?? '—'),
          'prix': x['prix'],
        };
      }()
  ];
  final nais = _date(pat?['dateNaissance']);
  return PieceA4(
    titre: 'Bulletin d’analyses bio-médicales',
    sousTitre: '${r['numero']}',
    reference: _ref(c),
    utilisateur: c.utilisateur,
    edite: c.aujourdhui,
    cartouche: [
      ('Patient', '${r['patient']}'),
      ('Dossier', '${r['patientCode']}'),
      ('Âge', nais != null ? '${(c.aujourdhui.difference(nais).inDays / 365.25).floor()} ans' : '—'),
      ('Sexe', pat == null ? '—' : (pat['sexe'] == 'F' ? 'Féminin' : 'Masculin')),
      ('Date', texteDateCs(r['date'])),
      ('Prescripteur', '${r['medecin']}'),
      ('Indication', vrai(r['diagnostic']) ? '${r['diagnostic']}' : '—'),
      ('Service demandeur', '${_ou(r['serviceDemandeur'], _ou(r['secteurDemandeur'], '—'))}'),
      ('Priorité', vrai(r['urgent']) ? 'URGENT' : 'Courant'),
      ('Règlement', r['statutPaiement'] == 'soldee' ? 'Réglé' : 'À régler à la caisse'),
    ],
    blocs: [
      if (lignes.isNotEmpty)
        BlocTableau(TableauEtat(colonnes: [
          ColonneEtat(libelle: 'Section', valeur: (l) => l['section']),
          ColonneEtat(libelle: 'Examen demandé', valeur: (l) => l['designation']),
          ColonneEtat(libelle: 'Échantillon', valeur: (l) => l['echantillon']),
          ColonneEtat(
              libelle: 'Tarif',
              droite: true,
              valeur: (l) => money(l['prix'], avecDevise: false),
              somme: (l) => nombreOuZero(l['prix'])),
        ], lignes: lignes))
      else
        const BlocTexte('Aucune analyse demandée sur cette ordonnance.', italique: true),
      const BlocTexte(
          'Ce bulletin accompagne le patient à la caisse puis à la salle de prélèvement, et suit ensuite l’échantillon jusqu’au laboratoire. Le résultat est transmis au clinicien prescripteur ; il est remis directement au patient lorsque celui-ci est adressé de l’extérieur.',
          italique: true),
    ],
    signatures: [
      Signature('Le Médecin prescripteur', nom: '${r['medecin']}', mention: 'Signature et cachet'),
      const Signature('Le Préleveur', mention: 'Heure de prélèvement'),
    ],
  );
}

Object? _ou(Object? a, Object? b) => vrai(a) ? a : b;

Future<void> imprimerOrdonnance(BuildContext ctx, Fiche r) =>
    afficherApercu(ctx, pieceOrdonnance(ContexteEcran.of(ctx), r));
Future<void> imprimerBulletin(BuildContext ctx, Fiche r) =>
    afficherApercu(ctx, pieceBulletin(ContexteEcran.of(ctx), r));

/// Le dossier de consultation imprimé.
Future<void> imprimerDossier(BuildContext ctx, Fiche d) {
  final c = ContexteEcran.of(ctx);
  final cv = csConstantesDuDossier(d)?.valeurs ?? const <String, Object?>{};
  final blocs = <BlocPiece>[];
  void titre(String t) => blocs.add(BlocTexte(t.toUpperCase(), gras: true));
  void rub(String t, Object? v) {
    blocs.add(BlocTexte('$t :', gras: true));
    blocs.add(BlocTexte(vrai(v) ? '$v' : '—'));
  }

  titre('Anamnèse');
  rub('Motif de consultation', d['motifVenue']);
  rub('Histoire de la maladie', d['histoire']);
  rub('Traitements en cours et habituels', d['traitementEnCours']);
  titre('Antécédents');
  for (final cat in csCategoriesAntecedent) {
    rub('${cat['label']}', d['ant_${cat['code']}']);
  }
  final obst = antecedentsObstetricauxLisibles((d['antecedentsObstetricaux'] as Map?)?.cast());
  if (obst != null) rub('Antécédents obstétricaux', obst);
  if (vrai(d['allergies']) || vrai(d['allergiesMedicamenteuses'])) {
    rub('Allergies', [
      d['allergies'],
      if (vrai(d['allergiesMedicamenteuses'])) 'médicamenteuses : ${d['allergiesMedicamenteuses']}'
    ].where(vrai).join(' — '));
  }
  titre('Examen clinique');
  rub('État général',
      '${csLibelleEtatGeneral(d['etatGeneral'])}${vrai(d['etatGeneralPrecision']) ? ' — ${d['etatGeneralPrecision']}' : ''}');
  for (final s in csSyntheseExamen(csExamensPhysiquesDe(d))) {
    rub(s.label, s.texte);
  }
  for (final x in examenObstetricalLisible((d['examenObstetrical'] as Map?)?.cast())) {
    rub(x.$1, x.$2);
  }
  final constantes = [
    if (cv['temperature'] != null) 'T° ${cv['temperature']}',
    if (vrai(cv['tension'])) 'TA ${cv['tension']}',
    if (cv['pouls'] != null) 'Pouls ${cv['pouls']}',
    if (cv['spo2'] != null) 'SpO₂ ${cv['spo2']}',
    if (cv['imc'] != null) 'IMC ${cv['imc']}',
  ].join('   ');
  return afficherApercu(
      ctx,
      PieceA4(
        titre: 'DOSSIER DE CONSULTATION',
        sousTitre: '${_ou(d['reference'], d['id'])} — ${d['patient']}',
        reference: _ref(c),
        utilisateur: c.utilisateur,
        edite: c.aujourdhui,
        cartouche: [
          ('Patient', '${d['patient']}'),
          ('NIP', '${_ou(d['patientCode'], d['nip'])}'),
          ('Âge', d['age'] != null ? '${d['age']} ans' : '—'),
          ('Sexe', '${_ou(d['sexe'], '—')}'),
          ('Venue', '${csLibelleTypeVenue(d['typeVenue'])} du ${texteDateCs(d['dateArrivee'])}'),
          ('Couverture', '${_ou(d['assureur'], 'Non assuré')}'),
          ('Constantes (accueil)', constantes.isEmpty ? '—' : constantes),
          ('État du dossier', '${csEtatDossier(d['etat'])['label']}'),
        ],
        blocs: blocs,
        signatures: [
          Signature('Le praticien', nom: '${d['soignant'] ?? ''}', mention: 'Signature et cachet')
        ],
      ));
}
