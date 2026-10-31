import '../format/format_fr.dart';
import '../format/js.dart' show nombreOuZero;
import '../maternite/mat_regles.dart';

/// RÈGLES DE LECTURE DES TABLEAUX DE BORD « B » — dash-ambulancier, dash-aide-soignant, dash-echographiste, dash-surveillant, dash-assistant-comptable,
/// dash-chirurgien, dash-anesthesiste, dash-aide-comptable, dash-maternite, dash-patient. Portées de `prototype_html/assets/js/modules/dashboards.js` et
/// rejouées sur les vecteurs `test/vecteurs/tbb_dash.json` (engendrés par `prototype_html/build/vecteurs-dash-b.js` : les écrans RÉELS pilotés dans Chrome).
///
/// Un tableau de bord est une LECTURE : rien n'est fourni, tout est compté depuis les registres. Chaque compteur lit le champ que l'écran propriétaire de
/// la collection écrit (« un compteur qui lit le mauvais champ se trompe dans les deux sens »). Symboles préfixés `tbb` / `Tbb`.

typedef TbbFiche = Map<String, Object?>;

/// Le premier regard : UNE question, son compte, le lien qui y mène. `vide` (obligatoire, positif) est la phrase quand le compte est nul.
class TbbRegard {
  const TbbRegard({
    required this.valeur,
    required this.unite,
    required this.question,
    required this.vide,
    required this.ton,
    required this.icone,
    required this.ecran,
    required this.lienLabel,
    required this.note,
  });
  final num valeur;
  final String unite, question, vide, ton, icone, ecran, lienLabel, note;

  /// Le texte de la ligne, comme `innerText` du bandeau de la maquette : `<valeur> <unité> — <question>` ou la phrase du vide.
  String get ligne => valeur == 0 ? vide : '${nombre(valeur)} $unite — $question';
}

class TbbKpi {
  const TbbKpi(this.libelle, this.valeur, this.icone, this.ton, {this.indice});
  final String libelle, valeur, icone, ton;
  final String? indice;
}

/// Un tableau de bord lu : le premier regard et les indicateurs.
class TbbReleve {
  const TbbReleve(this.regard, this.kpis);
  final TbbRegard regard;
  final List<TbbKpi> kpis;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Outils de lecture
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `C.toDate` : une date, jamais une exception — `null` quand le champ n'est pas une date. Une heure UTC (`…Z`) se lit en heure LOCALE, comme `new Date()`.
DateTime? tbbDate(Object? v) {
  if (v is DateTime) return v;
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? null : (d.isUtc ? d.toLocal() : d);
}

String tbbIso(Object? v) {
  final d = tbbDate(v);
  return d == null ? '' : iso(d);
}

/// Les fiches non archivées (`col.active()`).
List<TbbFiche> tbbActives(Iterable<TbbFiche> rows) => [
      for (final r in rows)
        if (r['statut'] != 'archive') r
    ];

/// `duMois(rows, key)` : les fiches dont la date tombe dans le MOIS de `auj`.
List<TbbFiche> tbbDuMois(Iterable<TbbFiche> rows, String cle, DateTime auj) => [
      for (final r in rows)
        if (tbbDate(r[cle]) case final d? when d.year == auj.year && d.month == auj.month) r
    ];

/// `duJour(rows, key)` : les fiches dont la date (`C.iso`) est celle d'`auj`.
List<TbbFiche> tbbDuJour(Iterable<TbbFiche> rows, String cle, DateTime auj) => [
      for (final r in rows)
        if (tbbIso(r[cle]) == iso(auj)) r
    ];

/// `C.sum(rows, key)` : `Number(x) || 0`.
num tbbSomme(Iterable<TbbFiche> rows, String cle) =>
    rows.fold<num>(0, (a, r) => a + nombreOuZero(r[cle]));

String _t(Object? v) => '${v ?? ''}';
String _jour(Object? v) {
  final s = _t(v);
  return s.length > 10 ? s.substring(0, 10) : s;
}

/// `!x` de JavaScript : faux, 0, '' et null sont « faux ».
bool tbbVrai(Object? v) => !(v == null || v == false || v == 0 || v == '');

/// `Math.round` de JavaScript : la demie arrondit vers +∞.
int tbbArrondiJs(num x) => (x + 0.5).floor();

/// `C.daysBetween(a, b)` : `Math.round((b − a) / 86 400 000)` — l'heure compte, comme dans la maquette (de 12 h à minuit, un terme à venir perd un jour).
int tbbJoursEntre(DateTime a, DateTime b) => tbbArrondiJs(b.difference(a).inMilliseconds / 86400000);

/// `litsOccupes()` : les admissions `en_cours` — à ne pas confondre avec « sans date de sortie » (aide-soignante) : ce sont deux lectures du même registre.
List<TbbFiche> tbbLitsOccupes(Iterable<TbbFiche> admissions) => [
      for (final a in tbbActives(admissions))
        if (a['statut'] == 'en_cours') a
    ];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Ambulance
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Interventions demandées ou en cours (le premier regard de l'ambulancier : il attend une demande).
List<TbbFiche> tbbInterventionsOuvertes(Iterable<TbbFiche> ambulance) => [
      for (final x in tbbActives(ambulance))
        if (x['etat'] == 'demandee' || x['etat'] == 'en_cours') x
    ];

/// Les consultations à domicile (`type === 'Domicile'`), dans l'ordre du registre.
List<TbbFiche> tbbDomicile(Iterable<TbbFiche> consultations) => [
      for (final c in tbbActives(consultations))
        if (c['type'] == 'Domicile') c
    ];

TbbReleve tbbAmbulancier(
    {required Iterable<TbbFiche> ambulance, required Iterable<TbbFiche> consultations, required DateTime auj}) {
  final toutes = tbbActives(ambulance);
  final mois = tbbDuMois(toutes, 'dateHeure', auj);
  final demandees = [
    for (final x in toutes)
      if (x['etat'] == 'demandee') x
  ];
  final ouvertes = tbbInterventionsOuvertes(ambulance);
  return TbbReleve(
    TbbRegard(
      valeur: ouvertes.length,
      unite: 'intervention(s)',
      question: 'sont demandées ou en cours',
      vide: 'Aucune intervention en cours.',
      ton: 'danger',
      icone: 'ambulance',
      ecran: 'm13-ambulance',
      lienLabel: 'Interventions',
      note: 'La fiche de référence porte les heures de départ et d’arrivée : c’est vous qui les renseignez, et elles font foi.',
    ),
    [
      TbbKpi('Interventions du mois', nombre(mois.length), 'ambulance', 'danger'),
      TbbKpi('Transports programmés', nombre(demandees.length), 'calendar-clock', 'warning'),
      TbbKpi('Soins à domicile', nombre(tbbDomicile(consultations).length), 'house-plus', 'info'),
      TbbKpi('Kilométrage du mois', '${nombre(tbbSomme(mois, 'kilometrage'))} km', 'route', 'neutral'),
    ],
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Aide-soignante
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Elle ne consulte AUCUN résultat d'analyse : son tableau montre les hospitalisés, jamais un résultat. Hospitalisé = admission sans date de sortie.
TbbReleve tbbAideSoignant(
    {required Iterable<TbbFiche> admissions,
    required Iterable<TbbFiche> releves,
    required Iterable<TbbFiche> visites,
    required DateTime auj}) {
  final adm = [
    for (final a in tbbActives(admissions))
      if (!tbbVrai(a['dateSortie'])) a
  ];
  final rel = [
    for (final r in tbbActives(releves))
      if (r['date'] == iso(auj)) r
  ];
  final vis = [
    for (final v in tbbActives(visites))
      if (_jour(v['date']) == iso(auj)) v
  ];
  return TbbReleve(
    TbbRegard(
      valeur: adm.length,
      unite: 'patient(s) hospitalisé(s)',
      question: 'sont présents dans le service',
      vide: 'Aucun patient hospitalisé actuellement.',
      ton: 'navy',
      icone: 'bed-double',
      ecran: 'm3-admissions',
      lienLabel: 'Voir les admissions',
      note: 'Votre profil ne consulte aucun résultat d’analyse : c’est la règle métier posée par la Direction pour cette fonction, et l’écran des '
          'résultats vous est fermé.',
    ),
    [
      TbbKpi('Patients hospitalisés', nombre(adm.length), 'bed-double', 'navy'),
      TbbKpi('Relevés de constantes du jour', nombre(rel.length), 'thermometer', 'info'),
      TbbKpi('Visites reçues aujourd’hui', nombre(vis.length), 'users-round', 'success'),
      TbbKpi('Lits occupés', nombre(adm.length), 'layout-grid', 'neutral'),
    ],
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Technicien d'échographie — AUCUN accès financier : son tableau ne porte aucun montant.
// ---------------------------------------------------------------------------------------------------------------------------------------------

TbbReleve tbbEchographiste(
    {required Iterable<TbbFiche> resultats, required int examensAuCatalogue, required DateTime auj}) {
  final tous = tbbActives(resultats);
  final rendus = [
    for (final r in tous)
      if (r['statut'] == 'rendu') r
  ];
  final aRendre = [
    for (final r in tous)
      if (r['statut'] != 'rendu') r
  ];
  final moisIso = iso(auj).substring(0, 7);
  final mois = [
    for (final r in tous)
      if (_t(r['date']).length >= 7 && _t(r['date']).substring(0, 7) == moisIso) r
  ];
  return TbbReleve(
    TbbRegard(
      valeur: aRendre.length,
      unite: 'compte(s) rendu(s)',
      question: 'restent à terminer et à rendre',
      vide: 'Aucun compte rendu en attente.',
      ton: 'warning',
      icone: 'scan-line',
      ecran: 'm2-imagerie',
      lienLabel: 'Imagerie médicale',
      note: 'La conclusion est obligatoire avant de rendre : c’est elle que le prescripteur lit.',
    ),
    [
      TbbKpi('Comptes rendus au total', nombre(tous.length), 'scan-line', 'navy'),
      TbbKpi('Rendus au prescripteur', nombre(rendus.length), 'send', 'success'),
      TbbKpi('Ce mois-ci', nombre(mois.length), 'calendar', 'info'),
      TbbKpi('Examens au catalogue', nombre(examensAuCatalogue), 'list', 'neutral'),
    ],
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Surveillant — missions 1 et 5 de la description de poste de l'Infirmier Général (retards, planning du personnel paramédical).
// ---------------------------------------------------------------------------------------------------------------------------------------------

const tbbFonctionsParamedicales = ['infirmier', 'sage_femme', 'aide_soignant'];

TbbReleve tbbSurveillant(
    {required Iterable<TbbFiche> presences,
    required Iterable<TbbFiche> planning,
    required Iterable<TbbFiche> conges,
    required Iterable<TbbFiche> personnel,
    required DateTime auj}) {
  final j = iso(auj);
  final pres = [
    for (final x in tbbActives(presences))
      if (_jour(x['date']) == j) x
  ];
  // Un retard est un ÉTAT du pointage (`etat === 'retard'`, le champ que m10-presences écrit et compte).
  final retards = [
    for (final x in pres)
      if (x['etat'] == 'retard') x
  ];
  final plan = [
    for (final x in tbbActives(planning))
      if (_jour(x['date']) == j) x
  ];
  // Un agent est « en congé » quand la décision est ACCORDÉE et que la date tombe dans [dateDebut, dateFin] (même définition que m10-conges).
  final cong = [
    for (final x in tbbActives(conges))
      if (x['statutConge'] == 'valide' && _t(x['dateDebut']).compareTo(j) <= 0 && _t(x['dateFin']).compareTo(j) >= 0) x
  ];
  final param = [
    for (final a in tbbActives(personnel))
      if (tbbFonctionsParamedicales.contains(a['fonction'])) a
  ];
  return TbbReleve(
    TbbRegard(
      valeur: retards.length,
      unite: 'retard(s)',
      question: 'constatés aujourd’hui',
      vide: 'Aucun retard constaté aujourd’hui.',
      ton: 'warning',
      icone: 'clock-alert',
      ecran: 'm10-presences',
      lienLabel: 'Présences du jour',
      note: 'Indicateur de votre description de poste : 95 % des retards constatés et notifiés. Constater ne suffit pas — c’est la notification '
          'qui compte.',
    ),
    [
      TbbKpi('Présences pointées aujourd’hui', nombre(pres.length), 'user-check', 'success'),
      TbbKpi('Vacations planifiées', nombre(plan.length), 'calendar-clock', 'navy'),
      TbbKpi('Agents en congé', nombre(cong.length), 'palmtree', 'info'),
      TbbKpi('Effectif paramédical', nombre(param.length), 'users-round', 'neutral'),
    ],
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Assistant de Direction — activités 7 et 8 : recouvrer les créances, « SURTOUT les assureurs ».
// ---------------------------------------------------------------------------------------------------------------------------------------------

TbbReleve tbbAssistantDirection(
    {required Iterable<TbbFiche> factures,
    required Iterable<TbbFiche> echeances,
    required Iterable<TbbFiche> ecritures,
    required Iterable<TbbFiche> produits,
    required DateTime auj}) {
  final fac = tbbActives(factures);
  final creances = [
    for (final f in fac)
      if (nombreOuZero(f['partAssurance']) > 0 && nombreOuZero(f['reliquat']) > 0) f
  ];
  final montant = creances.fold<num>(0, (n, f) => n + nombreOuZero(f['partAssurance']));
  final ech = [
    for (final e in tbbActives(echeances))
      if (!tbbVrai(e['paye']) && _t(e['echeance']).compareTo(iso(auj)) < 0) e
  ];
  final jour = [
    for (final f in fac)
      if (_jour(f['date']) == iso(auj)) f
  ];
  final brouillons = [
    for (final e in tbbActives(ecritures))
      if (e['statut'] == 'brouillon') e
  ];
  final reactifs = [
    for (final x in tbbActives(produits))
      if (RegExp(r'reactif|réactif', caseSensitive: false).hasMatch(_t(x['famille'])) &&
          x['seuilAlerte'] != null &&
          nombreOuZero(x['stock']) <= nombreOuZero(x['seuilAlerte']))
        x
  ];
  return TbbReleve(
    TbbRegard(
      valeur: montant,
      unite: 'FCFA de créances assureur',
      question: 'restent à recouvrer',
      vide: 'Aucune créance assureur en cours.',
      ton: 'warning',
      icone: 'hourglass',
      ecran: 'm9-creances',
      lienLabel: 'Créances',
      note: 'Activité 8 de votre description de poste : « suivre le règlement des créances par nos débiteurs et SURTOUT les assureurs ». Le mot est '
          'dans le document.',
    ),
    [
      TbbKpi('Échéances fiscales dépassées', nombre(ech.length), 'siren', ech.isNotEmpty ? 'danger' : 'success'),
      TbbKpi('Encaissé aujourd’hui', money(tbbSomme(jour, 'montantPaye')), 'banknote', 'success'),
      TbbKpi('Écritures en brouillon', nombre(brouillons.length), 'file-check-2', brouillons.isNotEmpty ? 'warning' : 'neutral'),
      TbbKpi('Réactifs sous seuil', nombre(reactifs.length), 'flask-conical', 'info', indice: 'inventaire — activité 23'),
    ],
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Bloc : chirurgien et anesthésiste
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Une check-liste est INCOMPLÈTE quand ses cases cochées n'atteignent pas son total — signalée, jamais refusée.
bool tbbChecklistIncomplete(TbbFiche c) => nombreOuZero(c['coches']) < nombreOuZero(c['total']);

TbbReleve tbbChirurgien(
    {required Iterable<TbbFiche> checklists,
    required Iterable<TbbFiche> comptesRendus,
    required Iterable<TbbFiche> admissions,
    required DateTime auj}) {
  final incompletes = [
    for (final c in tbbActives(checklists))
      if (tbbChecklistIncomplete(c)) c
  ];
  final cro = tbbActives(comptesRendus);
  final mois = tbbDuMois(cro, 'dateOperation', auj);
  final sansAide = [
    for (final r in mois)
      if (!tbbVrai(r['aideOperateur'])) r
  ];
  return TbbReleve(
    TbbRegard(
      valeur: incompletes.length,
      unite: 'check-liste(s)',
      question: 'restent incomplètes au bloc',
      vide: 'Toutes les check-listes du bloc sont complètes.',
      ton: 'warning',
      icone: 'clipboard-check',
      ecran: 'm3-bloc-checklist',
      lienLabel: 'Check-listes du bloc',
      note: 'Une check-liste incomplète est signalée, jamais refusée — la compléter après coup vaut mieux que cocher pour avancer.',
    ),
    [
      TbbKpi('Interventions du mois', nombre(mois.length), 'slice', 'danger'),
      TbbKpi('Comptes rendus opératoires', nombre(cro.length), 'file-text', 'navy', indice: 'chacun porte ses trois intervenants nommés'),
      TbbKpi('Sans aide-opérateur', nombre(sansAide.length), 'user-minus', 'warning'),
      TbbKpi('Patients hospitalisés', nombre(tbbLitsOccupes(admissions).length), 'bed-double', 'info'),
    ],
  );
}

TbbReleve tbbAnesthesiste(
    {required Iterable<TbbFiche> checklists,
    required Iterable<TbbFiche> comptesRendus,
    required Iterable<TbbFiche> admissions,
    required DateTime auj}) {
  final entrees = [
    for (final c in tbbActives(checklists))
      if (c['moment'] == 'entree' && tbbChecklistIncomplete(c)) c
  ];
  final mois = tbbDuMois(tbbActives(comptesRendus), 'dateOperation', auj);
  int type(String t) => mois.where((r) => r['anesthesie'] == t).length;
  return TbbReleve(
    TbbRegard(
      valeur: entrees.length,
      unite: 'check-liste(s) d’entrée',
      question: 'sont incomplètes avant induction',
      vide: 'Toutes les check-listes d’entrée sont complètes.',
      ton: 'danger',
      icone: 'syringe',
      ecran: 'm3-bloc-checklist',
      lienLabel: 'Check-listes du bloc',
      note: 'La consultation pré-anesthésique (CPA) et la feuille d’anesthésie arrivent en phase 6 du plan — d’ici là, la sécurité d’entrée se '
          'tient ici.',
    ),
    [
      TbbKpi('Interventions du mois', nombre(mois.length), 'slice', 'danger'),
      TbbKpi('Anesthésies générales', nombre(type('Anesthésie générale')), 'syringe', 'warning'),
      TbbKpi('Rachianesthésies', nombre(type('Rachianesthésie')), 'syringe', 'info'),
      TbbKpi('Patients hospitalisés', nombre(tbbLitsOccupes(admissions).length), 'bed-double', 'navy'),
    ],
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Assistant Comptable — il SAISIT, le Comptable principal VALIDE.
// ---------------------------------------------------------------------------------------------------------------------------------------------

TbbReleve tbbAssistantComptable(
    {required Iterable<TbbFiche> ecritures, required Iterable<TbbFiche> factures, required DateTime auj}) {
  final ecr = tbbActives(ecritures);
  final mois = tbbDuMois(ecr, 'date', auj);
  final brouillons = [
    for (final e in ecr)
      if (e['statut'] == 'brouillon' || e['etat'] == 'brouillon') e
  ];
  final fac = tbbActives(factures);
  final jour = tbbDuJour(fac, 'date', auj);
  final creances = [
    for (final f in fac)
      if (nombreOuZero(f['partAssurance']) > 0 && f['statutPaiement'] != 'soldee') f
  ];
  return TbbReleve(
    TbbRegard(
      valeur: brouillons.length,
      unite: 'écriture(s) en brouillon',
      question: 'attendent la validation du Comptable',
      vide: 'Aucune écriture en brouillon.',
      ton: 'warning',
      icone: 'file-clock',
      ecran: 'm12-ecritures',
      lienLabel: 'Écritures',
      note: 'Vous saisissez, le Comptable principal valide — la validation comptable reste un geste humain, et l’annulation ne vous est pas '
          'ouverte (D interdit, matrice cible).',
    ),
    [
      TbbKpi('Écritures du mois', nombre(mois.length), 'book-open', 'navy'),
      TbbKpi('Brouillons en attente', nombre(brouillons.length), 'file-clock', 'warning'),
      TbbKpi('Pièces de caisse du jour', nombre(jour.length), 'receipt', 'info', indice: 'le point journalier de la caisse est dans vos activités'),
      TbbKpi('Créances assurance ouvertes', nombre(creances.length), 'shield-alert', 'danger'),
    ],
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Maternité — le poste, pas la spécialité : qui est en travail, quels termes tombent, quelles grossesses sont à risque.
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Un partogramme non clos est une femme en salle de travail — la seule chose qui n'attend pas.
List<TbbFiche> tbbTravauxEnCours(Iterable<TbbFiche> partogrammes) => [
      for (final p in tbbActives(partogrammes))
        if (!tbbVrai(p['clos'])) p
    ];

/// Les termes qui tombent dans la fenêtre demandée, dépassés compris, du plus ancien au plus proche (tri STABLE, comme `Array.sort`).
List<TbbFiche> tbbTermesProches(Iterable<TbbFiche> dossiers, int jours, DateTime auj) {
  final l = <(int, int, TbbFiche)>[];
  var i = 0;
  for (final d in tbbActives(dossiers)) {
    if (!tbbVrai(d['dpa']) || d['statutDossier'] != 'suivi') continue;
    final dpa = tbbDate(d['dpa']);
    if (dpa == null) continue;
    final r = tbbJoursEntre(auj, dpa);
    if (r <= jours) l.add((r, i++, d));
  }
  l.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return [for (final x in l) x.$3];
}

/// Échéance d'un terme : « dépassé de N j » ou « dans N j » (orange à 7 jours ou moins).
({String texte, String ton}) tbbEcheanceTerme(TbbFiche d, DateTime auj) {
  final r = tbbJoursEntre(auj, tbbDate(d['dpa'])!);
  return r < 0 ? (texte: 'dépassé de ${-r} j', ton: 'danger') : (texte: 'dans $r j', ton: r <= 7 ? 'warning' : 'info');
}

/// Les grossesses à risque SUIVIES : au moins un facteur de surveillance coché (le risque est le CUMUL, jamais un champ).
List<TbbFiche> tbbGrossessesARisque(Iterable<TbbFiche> dossiers) => [
      for (final d in tbbActives(dossiers))
        if (d['statutDossier'] == 'suivi' && matFacteursCoches(d).isNotEmpty) d
    ];

/// Les facteurs relevés les plus fréquents sur TOUS les dossiers (ouverts ou non), par ordre décroissant, huit au plus (tri STABLE).
List<(String, int)> tbbFacteursFrequents(Iterable<TbbFiche> dossiers) {
  final compte = <String, int>{};
  for (final d in tbbActives(dossiers)) {
    for (final f in matFacteursCoches(d)) {
      final k = '${f['libelle']}';
      compte[k] = (compte[k] ?? 0) + 1;
    }
  }
  final l = <(int, String, int)>[];
  var i = 0;
  for (final e in compte.entries) {
    l.add((i++, e.key, e.value));
  }
  l.sort((a, b) => a.$3 != b.$3 ? b.$3.compareTo(a.$3) : a.$1.compareTo(b.$1));
  return [for (final e in l.take(8)) (e.$2, e.$3)];
}

/// Accouchements du mois par type (clé : `type`, dans l'ordre d'apparition).
List<(String, int)> tbbAccouchementsParType(Iterable<TbbFiche> accouchements, DateTime auj) {
  final g = <String, int>{};
  for (final a in tbbDuMois(tbbActives(accouchements), 'dateHeure', auj)) {
    final t = a['type'];
    final k = _t(tbbVrai(t) ? t : a['voie']);
    g[k] = (g[k] ?? 0) + 1;
  }
  return [for (final e in g.entries) (e.key, e.value)];
}

TbbReleve tbbMaternite(
    {required Iterable<TbbFiche> dossiers,
    required Iterable<TbbFiche> partogrammes,
    required Iterable<TbbFiche> accouchements,
    required Iterable<TbbFiche> naissances,
    required DateTime auj}) {
  final dos = tbbActives(dossiers);
  final gar = [
    for (final d in dos)
      if (matFacteursCoches(d).isNotEmpty) d
  ];
  final accMois = tbbDuMois(tbbActives(accouchements), 'dateHeure', auj);
  final naisMois = tbbDuMois(tbbActives(naissances), 'dateHeure', auj);
  final vivants = naisMois.where((n) => tbbVrai(n['vivant'])).length;
  final travaux = tbbTravauxEnCours(partogrammes);
  return TbbReleve(
    TbbRegard(
      valeur: travaux.length,
      unite: 'partogramme(s)',
      question: 'ouverts — travail en cours',
      vide: 'Aucun travail en cours dans la salle d’accouchement.',
      ton: 'danger',
      icone: 'activity',
      ecran: 'm4-partogramme',
      lienLabel: 'Partogrammes',
      note: 'Un partogramme non clos est une femme en salle de travail. La ligne d’alerte part de 4 cm à 1 cm par heure ; la ligne d’action lui est '
          'parallèle, décalée de 4 heures.',
    ),
    [
      TbbKpi('Dossiers suivis', nombre(dos.where((d) => d['statutDossier'] == 'suivi').length), 'folder-open', 'navy',
          indice: 'Dossiers obstétricaux ouverts, non encore clos'),
      TbbKpi('Grossesses à risque (GAR)', nombre(gar.length), 'alert-triangle', gar.isNotEmpty ? 'danger' : 'success',
          indice: 'Au moins un facteur de surveillance coché'),
      TbbKpi('Accouchements du mois', nombre(accMois.length), 'baby', 'info'),
      TbbKpi('Nouveau-nés vivants du mois', nombre(vivants), 'heart-pulse', 'success',
          indice: naisMois.isNotEmpty
              ? '${nombre(naisMois.length - vivants)} mort-né(s) sur ${nombre(naisMois.length)}'
              : 'Aucune naissance ce mois'),
    ],
  );
}

/// La dernière mesure d'un partogramme (celle qui dit où en est le travail), ou une carte vide.
TbbFiche tbbDerniereMesure(TbbFiche p) {
  final m = (p['mesures'] as List?) ?? const [];
  return m.isEmpty ? <String, Object?>{} : (m.last as Map).cast<String, Object?>();
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Espace patient — remis au personnel d'accueil et de caisse pour informer le patient (CDCT §5 : il n'a aucun accès direct).
// ---------------------------------------------------------------------------------------------------------------------------------------------

List<TbbKpi> tbbKpisPatient(
    {required int consultations, required int hospitalisations, required num facture, required num reste}) {
  return [
    TbbKpi('Consultations', nombre(consultations), 'stethoscope', 'navy'),
    TbbKpi('Hospitalisations', nombre(hospitalisations), 'bed-double', 'info'),
    TbbKpi('Total facturé', money(facture), 'receipt', 'neutral'),
    TbbKpi('Reste à payer', money(reste), 'wallet', reste > 0 ? 'danger' : 'success'),
  ];
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Cellules des tableaux (le texte tel que la maquette l'affiche)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Une cellule `key` de `K.miniTable` : `null` s'affiche « — ».
String tbbCelluleCle(Object? v) => v == null ? '—' : '$v';

String _dateFr(Object? v) {
  final d = tbbDate(v);
  return d == null ? '' : dateFR(d);
}

String _gp(TbbFiche f) => 'G${tbbVrai(f['gestite']) ? nombre(f['gestite']) : 0} P${tbbVrai(f['parite']) ? nombre(f['parite']) : 0}';

/// Travail en cours : parturiente, dossier, G / P, début du travail, dilatation de la dernière mesure, descente cotée, accoucheur.
List<String> tbbCellulesTravail(TbbFiche p) {
  final m = tbbDerniereMesure(p);
  final d = tbbDate(p['debut']);
  final dil = tbbVrai(m['dilatation']) ? m['dilatation'] : 0;
  return [
    tbbCelluleCle(p['patient']),
    tbbCelluleCle(p['patientCode']),
    _gp(p),
    d == null ? '' : '${dateFR(d)} à ${heure(d)}',
    '${nombre(dil)} cm',
    tbbVrai(m['descenteCotee']) ? '${m['descenteCotee']}' : '—',
    tbbCelluleCle(p['accoucheur']),
  ];
}

/// Surveillance d'un dossier : « GAR — n » (n facteurs cochés) ou « Sans facteur ».
({String texte, String ton}) tbbSurveillanceDossier(TbbFiche d) {
  final n = matFacteursCoches(d).length;
  return n > 0 ? (texte: 'GAR — $n', ton: 'danger') : (texte: 'Sans facteur', ton: 'success');
}

/// Termes attendus : n° dossier, parturiente, terme prévu, échéance, surveillance, sage-femme, téléphone.
List<String> tbbCellulesTerme(TbbFiche d, DateTime auj) => [
      tbbCelluleCle(d['numeroDossier']),
      tbbCelluleCle(d['patient']),
      _dateFr(d['dpa']),
      tbbEcheanceTerme(d, auj).texte,
      tbbSurveillanceDossier(d).texte,
      tbbCelluleCle(d['sageFemme']),
      tbbCelluleCle(d['telephone']),
    ];

/// Grossesses à risque : n° dossier, parturiente, âge, G / P, facteurs relevés (séparés par « · »).
List<String> tbbCellulesRisque(TbbFiche d) => [
      tbbCelluleCle(d['numeroDossier']),
      tbbCelluleCle(d['patient']),
      '${tbbVrai(d['age']) ? '${d['age']}' : '—'} ans',
      _gp(d),
      matFacteursCoches(d).map((f) => '${f['libelle']}').join(' · '),
    ];

/// Domicile : date, patient, motif, praticien (le statut s'affiche en pastille).
List<String> tbbCellulesDomicile(TbbFiche c) =>
    [_dateFr(c['date']), tbbCelluleCle(c['patient']), tbbCelluleCle(c['motif']), tbbCelluleCle(c['medecin'])];
