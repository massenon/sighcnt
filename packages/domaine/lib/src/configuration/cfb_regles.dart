import '../format/format_fr.dart';
import '../format/js.dart';
import '../format/recherche.dart' show trierPar;
import '../paie/pai_moteur.dart' show paiRedevances, paiSeuilTele, paiCnssOuvriere, paiCnssPatronale, paiVpsTaux;
import 'cfa_regles.dart' show CfaKpi, CfaFiche, cfaVrai, cfaTexte;
import 'cfb_donnees.dart';

/// RÈGLES DE CFG (B) — centres de coûts, règles métier versionnées, paramètres fiscaux, paramètres comptables, notifications, mon compte, activité des
/// modules, paramètres système. Portées de `prototype_html/assets/js/modules/configuration.js` et rejouées sur les vecteurs de la maquette
/// (`test/vecteurs/cfb.json`, engendré par `prototype_html/build/vecteurs-cfg-b.js`). Les référentiels statiques (`D.*`) sont dans `cfb_donnees.dart`
/// (ENGENDRÉ). Symboles préfixés `cfb` / `Cfb`.

double _n(Object? v) => nombreOuZero(v);
String _p2(int n) => n.toString().padLeft(2, '0');

// =============================================================================================================================================
// cfg-centres-couts
// =============================================================================================================================================

/// Les quatre indicateurs de l'écran, sur les centres ACTIFS.
List<CfaKpi> cfbKpisCentres(Iterable<CfaFiche> rows) {
  final l = rows.toList();
  int type(String t) => l.where((c) => c['type'] == t).length;
  return [
    CfaKpi('Centres de coûts', nombre(l.length), 'target', 'navy'),
    CfaKpi('Centres d’exploitation', nombre(type('exploitation')), 'activity', 'success'),
    CfaKpi('Centres de support', nombre(type('support')), 'life-buoy', 'info'),
    CfaKpi('Sans responsable', nombre(l.where((c) => !cfaVrai(c['responsable'])).length), 'user-x', 'warning'),
  ];
}

/// La fiche née d'une saisie : sans code, `CC` + le rang (TOUTES les fiches, archivées comprises, +1) sur deux chiffres.
CfaFiche cfbFicheCentre(Map<String, Object?> saisie, int nbToutes) {
  final v = {...saisie};
  if (!cfaVrai(v['code'])) v['code'] = 'CC${_p2(nbToutes + 1)}';
  return v;
}

// =============================================================================================================================================
// cfg-regles
// =============================================================================================================================================

/// L'effet MESURÉ de la méthode de valorisation sur le stock détenu : écart cumulé entre prix de vente et CUMP, et nombre d'articles qui divergent.
({double ecart, int divergents}) cfbEffetValorisation(Iterable<CfaFiche> produits) {
  var ecart = 0.0;
  var divergents = 0;
  for (final p in produits) {
    final pv = _n(p['prixVente'] != null ? p['prixVente'] : p['prixAchat']);
    final cump = p['cump'] != null ? _n(p['cump']) : pv;
    final q = _n(p['stock']);
    if ((pv - cump).abs() > 0.0001) divergents++;
    ecart += (pv - cump) * q;
  }
  return (ecart: ecart, divergents: divergents);
}

/// Les deux phrases de la carte « Effet mesuré sur le stock détenu ».
(String, String) cfbTextesEffet(({double ecart, int divergents}) e, int nbProduits) {
  final a = arrondiJs(e.ecart).abs();
  final premiere = e.ecart.abs() < 5000
      ? 'Écart entre les deux méthodes : ${money(a)} sur l’ensemble du stock — un effet d’arrondi, non une différence de méthode.'
      : 'Écart entre les deux méthodes : ${money(a)} sur l’ensemble du stock.';
  final seconde = '${e.divergents} article(s) sur $nbProduits présentent un prix de vente différent du CUMP. '
      'Tant que RG-02 s’applique — médicaments au prix d’achat, sans marge — les deux valorisations coïncident. '
      'Elles divergeront le jour où une marge sera appliquée à un article hors médicament.';
  return (premiere, seconde);
}

/// La ligne d'un groupe/famille : libellés, nombre d'articles, quantité, valeur au prix d'achat.
class CfbLigneFamille {
  const CfbLigneFamille(this.famille, this.groupe, this.articles, this.quantite, this.valeur);
  final String famille, groupe;
  final int articles;
  final num quantite, valeur;
}

/// « Groupes et familles d'articles » : une ligne par famille du document, rangée par groupe (tri français, stable).
List<CfbLigneFamille> cfbParFamille(Iterable<CfaFiche> produits) {
  final lignes = <CfbLigneFamille>[];
  for (final f in cfbFamillesArticles) {
    final lot = [for (final p in produits) if (p['categorie'] == f.$1) p];
    final g = cfbGroupesArticles.where((x) => x.$1 == f.$3).firstOrNull;
    var q = 0.0, v = 0.0;
    for (final p in lot) {
      q += _n(p['stock']);
      v += _n(p['prixAchat']) * _n(p['stock']);
    }
    lignes.add(CfbLigneFamille(f.$2, g?.$2 ?? '—', lot.length, q, v));
  }
  return trierPar(lignes, (l) => l.groupe);
}

/// Les quatre indicateurs de la matrice « document collecté → rôle dans le logiciel » et des règles de gestion.
List<CfaKpi> cfbKpisRegles() => [
      CfaKpi('Documents sources', nombre(cfbSourcesVerite.length), 'file-check-2', 'navy'),
      CfaKpi('Intégrés au système', nombre(cfbSourcesVerite.where((s) => s.statut.startsWith('Intégré')).length), 'check-circle-2', 'success'),
      CfaKpi('À importer', nombre(cfbSourcesVerite.where((s) => s.statut.startsWith('À')).length), 'upload', 'warning'),
      const CfaKpi('Règles de gestion', '14', 'scale', 'info', 'RG-01 à RG-14'),
    ];

/// Le ton du badge de statut d'un document source : « Intégré » vert, sauf partiel / à confirmer (orange) ; tout le reste orange.
String cfbTonStatutSource(String statut) {
  if (statut.startsWith('Intégré')) {
    final i = statut.indexOf('partiel');
    final j = statut.indexOf('confirmer');
    return (i > 0 || j > 0) ? 'warning' : 'success';
  }
  return 'warning';
}

/// Le titre et le message de la confirmation d'un changement de méthode de valorisation.
(String, String) cfbConfirmationValorisation((String, String, String) option) => (
      'Valoriser les sorties au ${option.$2.toLowerCase()} ?',
      '${option.$3} Le changement s’applique aux sorties à venir ; les mouvements déjà enregistrés conservent la valeur retenue au moment de leur saisie, '
          'ainsi que les deux valorisations, de sorte que l’historique reste comparable.'
    );

/// « Moteur piloté » de la carte des versions : la NS 131 pilote l'évaluation, la NS 132 les primes.
String cfbMoteurPilote(CfbNoteService n) => identical(n, cfbNs131) ? 'Évaluation et sanctions' : 'Primes diverses';

// =============================================================================================================================================
// cfg-fiscalite
// =============================================================================================================================================

/// `jourOuvrable(d)` : tant que la date tombe un samedi ou un dimanche, on avance d'un jour (jamais en arrière).
DateTime cfbJourOuvrable(DateTime d) {
  var x = d;
  while (x.weekday == DateTime.saturday || x.weekday == DateTime.sunday) {
    x = DateTime(x.year, x.month, x.day + 1);
  }
  return x;
}

String cfbIso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_p2(d.month)}-${_p2(d.day)}';

/// Une obligation avec sa PROCHAINE échéance calculée à une date.
class CfbEcheance {
  const CfbEcheance(this.obligation, this.echeance, this.jours, this.reporte);
  final CfbObligation obligation;
  final DateTime echeance;

  /// `C.daysBetween(AUJ, échéance)` : arrondi à l'entier le plus proche.
  final int jours;
  final bool reporte;
  String get code => obligation.code;
}

/// `prochaineEcheance(e)` : le mois courant (puis le suivant) pour une obligation mensuelle, l'année courante (puis la suivante) pour une annuelle ;
/// reportée au jour ouvrable suivant. La comparaison à AUJ se fait à l'HEURE près : le jour même, l'échéance du matin est passée.
CfbEcheance cfbProchaineEcheance(CfbObligation e, DateTime auj) {
  final an = auj.year;
  final mensuelle = e.periodicite == 'mensuelle';
  DateTime d;
  if (mensuelle) {
    final m = auj.month - 1;
    d = DateTime(an, m + 1, e.jour);
    if (d.isBefore(auj)) d = DateTime(an, m + 2, e.jour);
  } else {
    d = DateTime(an, e.mois! + 1, e.jour);
    if (d.isBefore(auj)) d = DateTime(an + 1, e.mois! + 1, e.jour);
  }
  final ouvrable = cfbJourOuvrable(d);
  final nominal = DateTime(ouvrable.year, mensuelle ? ouvrable.month : e.mois! + 1, e.jour);
  final reporte = cfbIso(ouvrable) != cfbIso(nominal);
  return CfbEcheance(e, ouvrable, arrondiJs(ouvrable.difference(auj).inMilliseconds / 86400000).toInt(), reporte);
}

/// Les échéances du calendrier à une date, dans l'ordre du calendrier (le tableau les trie par délai).
List<CfbEcheance> cfbEcheances(DateTime auj) => [for (final e in cfbCalendrierFiscal) cfbProchaineEcheance(e, auj)];

/// Celles qui tombent dans les trente jours.
List<CfbEcheance> cfbEcheancesProches(List<CfbEcheance> l) => [for (final e in l) if (e.jours >= 0 && e.jours <= 30) e];

List<CfaKpi> cfbKpisFiscalite(List<CfbEcheance> l) {
  final proches = cfbEcheancesProches(l);
  return [
    CfaKpi('Échéances suivies', nombre(l.length), 'landmark', 'navy'),
    CfaKpi('Mensuelles', nombre(l.where((e) => e.obligation.periodicite == 'mensuelle').length), 'calendar-days', 'info', 'ITS, AIB, VPS, CNSS'),
    CfaKpi('Dans les 30 jours', nombre(proches.length), 'alarm-clock', proches.isNotEmpty ? 'warning' : 'success'),
    CfaKpi('CCIB annuelle', money(cfbCcibTotal), 'coins', 'neutral', 'Deux tranches de 150 000 F'),
  ];
}

/// La note orange « N échéance(s) dans les trente jours : … » ; `null` s'il n'y en a aucune.
String? cfbNoteProches(List<CfbEcheance> l, String Function(DateTime) dateFr) {
  final proches = cfbEcheancesProches(l);
  if (proches.isEmpty) return null;
  return '${proches.length} échéance(s) dans les trente jours : ${proches.take(4).map((e) => '${e.code} le ${dateFr(e.echeance)}').join(' · ')}'
      '${proches.length > 4 ? ' …' : ''}. Une déclaration précède généralement le paiement.';
}

/// Le texte de la colonne « Dans » : « passée » ou « N j ».
String cfbLibelleDelai(int jours) => jours < 0 ? 'passée' : '$jours j';

// =============================================================================================================================================
// cfg-comptabilite
// =============================================================================================================================================

List<CfaKpi> cfbKpisComptabilite() => [
      CfaKpi('Obligations suivies', nombre(cfbCalendrierFiscal.length), 'book-open-check', 'navy'),
      CfaKpi('Mensuelles', nombre(cfbCalendrierFiscal.where((e) => e.periodicite == 'mensuelle').length), 'calendar-days', 'info', 'ITS, AIB, VPS, CNSS'),
      CfaKpi('Annuelles', nombre(cfbCalendrierFiscal.where((e) => e.periodicite == 'annuelle').length), 'calendar-range', 'neutral', 'IS, patente, CCIB, TVM, ORTB'),
      CfaKpi('Réglées en tranches', nombre(cfbCalendrierFiscal.where((e) => e.part != null && e.part! < 100).length), 'divide', 'warning'),
    ];

/// « CNSS — part patronale 16.4 %, part ouvrière 3.6 %. VPS — 4 % … » : les taux s'écrivent comme JavaScript les écrit (16.4, 4).
String cfbTexteAssiettes() => 'CNSS — part patronale ${cfaTexte(paiCnssPatronale)} %, part ouvrière ${cfaTexte(paiCnssOuvriere)} %. '
    'VPS — ${cfaTexte(paiVpsTaux)} % du salaire brut. ITS — barème progressif par tranches. AIB — acompte assis sur les bénéfices.';

/// Les acomptes de l'impôt sur les sociétés (IS-1 … IS-4) du calendrier.
List<CfbObligation> cfbAcomptesIs() => [for (final e in cfbCalendrierFiscal) if (RegExp(r'^IS-\d$').hasMatch(e.code)) e];

const _moisCap = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

/// « le 10 mars » (la maquette écrit le mois en minuscules).
String cfbEcheanceAcompte(CfbObligation e) => 'le ${e.jour} ${_moisCap[e.mois!]}';

/// Le cumul maximal ORTB d'un agent au-dessus du seuil : radio + télé.
num cfbCumulOrtbMaximum() => paiRedevances.fold<num>(0, (a, r) => a + r.montant);

/// La note orange de la carte ORTB et la phrase « Ce que supporte un agent ».
(String, String) cfbTextesOrtb() {
  final seuil = money(paiSeuilTele, avecDevise: false);
  final cumul = money(cfbCumulOrtbMaximum(), avecDevise: false);
  final radio = money(1000, avecDevise: false);
  final tele = money(3000, avecDevise: false);
  return (
    'Deux redevances distinctes, qui se cumulent — et non deux tranches exclusives d’un même barème. La radio est due par tous les salariés sans exception ; '
        'la télé s’y ajoute au-delà de $seuil de salaire brut. Un agent au-dessus du seuil acquitte donc $cumul sur l’exercice, et non $tele seulement.',
    'Salaire brut jusqu’à $seuil — $radio au titre de la radio, en mars. Salaire brut supérieur à $seuil — $radio en mars pour la radio, puis $tele en juin pour la télé, '
        'soit $cumul sur l’année.'
  );
}

// =============================================================================================================================================
// cfg-notifications
// =============================================================================================================================================

/// Les paramètres du canal sonore : les défauts, surchargés par ce que le poste a enregistré.
Map<String, Object?> cfbParamsNotif(Map<String, Object?>? brut) => {...cfbParamsNotifDefaut, ...?brut};

/// `NT.profilAudio()` : le profil choisi, ou « Standard » s'il est inconnu.
(String, String, double, int, String) cfbProfilAudio(Object? id) =>
    cfbProfilsAudio.where((p) => p.$1 == id).firstOrNull ?? cfbProfilsAudio.firstWhere((p) => p.$1 == 'standard');

/// Les temporisations proposées (minutes, libellé).
const cfbTemporisations = <(int, String)>[(5, '5 minutes'), (15, '15 minutes'), (30, '30 minutes'), (60, '1 heure'), (240, '4 heures')];

/// Les canaux d'un événement tels qu'ils sont enregistrés (`{app, sms, mail}`) ou, à défaut, ceux par défaut.
Map<String, bool> cfbCanaux(CfbNotification n, Map<String, Object?>? enregistres) {
  final e = enregistres?[n.id];
  if (e is Map) return {'app': e['app'] == true, 'sms': e['sms'] == true, 'mail': e['mail'] == true};
  return {'app': n.app, 'sms': n.sms, 'mail': n.mail};
}

List<CfaKpi> cfbKpisNotifications(Iterable<Map<String, bool>> canaux) {
  final l = canaux.toList();
  int nb(String c) => l.where((x) => x[c] == true).length;
  return [
    CfaKpi('Événements paramétrés', nombre(l.length), 'bell', 'navy'),
    CfaKpi('Notifications dans l’application', nombre(nb('app')), 'monitor', 'success'),
    CfaKpi('Notifications par SMS', nombre(nb('sms')), 'smartphone', 'info'),
    CfaKpi('Notifications par courriel', nombre(nb('mail')), 'mail', 'warning'),
  ];
}

/// Le nombre de canaux cochés dans la matrice (ce que le journal retient).
int cfbCanauxActifs(Iterable<Map<String, bool>> canaux) => canaux.fold(0, (a, c) => a + c.values.where((v) => v).length);

String cfbNoteAttente(int n) =>
    '$n alerte(s) en attente pour votre poste. Le moteur route chaque alerte selon les rôles et les droits déjà définis : une alerte qui renverrait vers un écran interdit à votre profil ne vous est pas présentée.';

// =============================================================================================================================================
// cfg-compte
// =============================================================================================================================================

/// L'authentification à deux facteurs est cochée d'office pour ces rôles.
bool cfbMfaParDefaut(String role) => const ['admin', 'direction', 'dm', 'da'].contains(role);

/// Le refus nommé du changement de mot de passe, `null` s'il passe : la confirmation d'abord, puis les douze caractères. Le reste de la politique affichée
/// (majuscules, minuscules, chiffre, caractère spécial) n'est PAS contrôlé par la maquette — voir E883.
String? cfbRefusMotDePasse(String nouveau, String confirmation) {
  if (nouveau != confirmation) return 'Les deux mots de passe ne correspondent pas.';
  if (nouveau.length < 12) return 'Le mot de passe doit comporter au moins 12 caractères.';
  return null;
}

// =============================================================================================================================================
// cfg-modules
// =============================================================================================================================================

/// Un écran du manifeste avec son module (`tousEcrans()` : les rangées d'ALIAS n'engendrent aucun écran).
class CfbEcranModule {
  const CfbEcranModule(this.id, this.label, this.module, this.moduleLabel, this.domaine);
  final String id, label, module, moduleLabel, domaine;
}

List<CfbEcranModule> cfbTousEcrans(Iterable<CfaFiche> rangees) => [
      for (final r in rangees)
        if (r['alias'] != true)
          for (final e in (r['ecrans'] as List? ?? const []))
            CfbEcranModule('${(e as List)[0]}', '${e[1]}', '${r['code']}', '${r['label']}', '${r['domaine']}')
    ];

/// Un module du ruban (`listeModules()` : la PREMIÈRE rangée non alias de chaque code).
class CfbModuleRuban {
  const CfbModuleRuban(this.code, this.label, this.icone, this.domaine, this.nbEcrans);
  final String code, label, icone, domaine;
  final int nbEcrans;
}

List<CfbModuleRuban> cfbListeModules(Iterable<CfaFiche> rangees) {
  final vus = <String>{};
  final out = <CfbModuleRuban>[];
  for (final r in rangees) {
    if (r['alias'] == true || vus.contains('${r['code']}')) continue;
    vus.add('${r['code']}');
    out.add(CfbModuleRuban('${r['code']}', '${r['label']}', '${r['icone'] ?? 'box'}', '${r['domaine']}', (r['ecrans'] as List? ?? const []).length));
  }
  return out;
}

/// Les fermetures en vigueur : écrans fermés nommément et modules fermés en entier. UNE FICHE ARCHIVÉE NE FERME PLUS RIEN (RG-14) — une fermeture que
/// l'écran de pilotage ne montre plus serait indébrayable.
class CfbFermetures {
  const CfbFermetures(this.ecrans, this.modules);
  final Map<String, CfaFiche> ecrans, modules;

  factory CfbFermetures.depuis(Iterable<CfaFiche> fiches) {
    final e = <String, CfaFiche>{}, m = <String, CfaFiche>{};
    for (final f in fiches) {
      if (f['statut'] == 'archive' || f['actif'] != false) continue;
      final ids = f['ecrans'];
      if (ids is List && ids.isNotEmpty) {
        for (final id in ids) {
          e['$id'] = f;
        }
      } else if (cfaVrai(f['module'])) {
        m['${f['module']}'] = f;
      }
    }
    return CfbFermetures(e, m);
  }

  /// `ecranActif(id, code)` : un écran d'un module fermé l'est aussi.
  bool ecranActif(String id, String code) => !ecrans.containsKey(id) && !modules.containsKey(code);

  /// `fermeturePour(id, code)` : la fiche qui ferme l'écran, pour pouvoir le DIRE.
  CfaFiche? fermeturePour(String id, String code) => ecrans[id] ?? modules[code];
}

/// La fiche MODULE-niveau (sans liste d'écrans) d'un code.
CfaFiche? cfbFicheModule(Iterable<CfaFiche> actives, String code) {
  for (final x in actives) {
    if (x['module'] == code && !((x['ecrans'] is List) && (x['ecrans'] as List).isNotEmpty)) return x;
  }
  return null;
}

/// `v.code = module + '-' + libellé en majuscules, hors A-Z0-9, tronqué à 8` : l'identifiant d'une activité déclarée.
String cfbCodeActivite(String module, String libelle) {
  final s = libelle.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '');
  return '$module-${s.length > 8 ? s.substring(0, 8) : s}';
}

String cfbPortee(CfaFiche f) {
  final nb = (f['ecrans'] is List) ? (f['ecrans'] as List).length : 0;
  return nb > 0 ? '${nombre(nb)} écran(s)' : 'Module ${f['module']} entier';
}

List<CfaKpi> cfbKpisModules({required int ecrans, required int fermees, required int retires}) => [
      CfaKpi('Écrans au périmètre', nombre(ecrans), 'layout-grid', 'navy'),
      CfaKpi('Activités fermées', nombre(fermees), 'toggle-left', fermees > 0 ? 'warning' : 'success'),
      CfaKpi('Écrans retirés du menu', nombre(retires), 'eye-off', retires > 0 ? 'warning' : 'neutral'),
      CfaKpi('Écrans ouverts', nombre(ecrans - retires), 'eye', 'success'),
    ];

/// Le refus nommé de la fermeture d'un module du NOYAU (titre, détail), `null` si la fermeture peut avoir lieu.
(String, String)? cfbRefusNoyau(CfaFiche f, {required bool fermer}) {
  final nb = (f['ecrans'] is List) ? (f['ecrans'] as List).length : 0;
  final raison = cfbNoyau['${f['module']}'];
  if (fermer && nb == 0 && raison != null) return ('Le module ${f['module']} ne se ferme pas.', 'Il $raison.');
  return null;
}

/// La confirmation d'une bascule : (titre, message, libellé du bouton). Les balises de mise en forme de la maquette sont retirées.
(String, String, String) cfbConfirmationBascule(CfaFiche f, {required bool fermer}) {
  final nb = (f['ecrans'] is List) ? (f['ecrans'] as List).length : 0;
  final titre = fermer ? 'Fermer « ${f['libelle']} » ?' : 'Rouvrir « ${f['libelle']} » ?';
  final message = fermer
      ? '${nb > 0 ? '${nombre(nb)} écran(s) disparaîtront du méga-menu, de la recherche globale et de leurs propres adresses' : 'Le module ${f['module']} entier disparaîtra du méga-menu, de la recherche globale et de ses adresses'}'
          ', pour tous les rôles, administrateur compris.\n\nAucune donnée n’est supprimée : la réouverture rend les écrans en l’état.'
      : '${nb > 0 ? '${nombre(nb)} écran(s) réapparaîtront' : 'Le module ${f['module']} réapparaîtra'} au méga-menu, avec leurs données inchangées.';
  return (titre, message, fermer ? 'Fermer l’activité' : 'Rouvrir l’activité');
}

// =============================================================================================================================================
// cfg-systeme
// =============================================================================================================================================

/// `S.libelleCollection(nom)` : (module, entité), « — » et le nom technique pour une collection que la table ne connaît pas.
(String, String) cfbLibelleCollection(String nom) => cfbLibellesCollections[nom] ?? ('—', nom);

/// Une collection du « Contenu du jeu de données ».
class CfbStatCollection {
  const CfbStatCollection(this.nom, this.total, this.actifs, this.archives);
  final String nom;
  final int total, actifs, archives;
}

CfbStatCollection cfbStatCollection(String nom, Iterable<CfaFiche> fiches) {
  final l = fiches.toList();
  final arch = l.where((r) => r['statut'] == 'archive').length;
  return CfbStatCollection(nom, l.length, l.length - arch, arch);
}

/// Le libellé d'une fiche archivée à la corbeille : nom + prénom, sinon le premier champ nommé que la fiche porte, sinon son identifiant.
String cfbLibelleElement(CfaFiche r) {
  if (cfaVrai(r['nom'])) return '${r['nom']} ${r['prenom'] ?? ''}'.trim();
  for (final k in const ['libelle', 'designation', 'reference', 'numero', 'intitule', 'code']) {
    if (cfaVrai(r[k])) return '${r[k]}';
  }
  return '${r['id']}';
}

/// Une ligne de la corbeille (RG-14).
class CfbLigneCorbeille {
  const CfbLigneCorbeille(
      {required this.collection, required this.module, required this.entite, required this.libelle, required this.refId, this.archiveLe, this.archivePar = '—', this.motif});
  final String collection, module, entite, libelle, refId, archivePar;
  final String? archiveLe, motif;
  String get id => '$collection:$refId';
}

/// La corbeille triée par date d'archivage DÉCROISSANTE (comparaison de chaînes ISO ; une fiche sans date passe en dernier).
List<CfbLigneCorbeille> cfbTrierCorbeille(List<CfbLigneCorbeille> l) {
  final c = [...l];
  c.sort((a, b) => (b.archiveLe ?? '').compareTo(a.archiveLe ?? ''));
  return c;
}

/// Le bilan d'un vidage des jeux de test : les collections d'ACTIVITÉ (ni essentielles, ni techniques) et leur nombre de fiches.
class CfbPlanVidage {
  const CfbPlanVidage(this.collections, this.enregistrements);
  final List<String> collections;
  final int enregistrements;
  int get tables => collections.length;
}

/// [tailles] : nombre de fiches (archivées comprises) par collection ; [conservees] : les collections qui survivent TOUJOURS (essentielles + techniques).
CfbPlanVidage cfbPlanVidage(Map<String, int> tailles, Set<String> conservees) {
  final c = <String>[];
  var n = 0;
  tailles.forEach((k, v) {
    if (!conservees.contains(k)) {
      c.add(k);
      n += v;
    }
  });
  return CfbPlanVidage(c, n);
}

/// « 103 table(s) vidée(s) — 9 549 enregistrements retirés. »
String cfbToastVidage(CfbPlanVidage p) => '${p.tables} table(s) vidée(s) — ${nombre(p.enregistrements)} enregistrements retirés.';
