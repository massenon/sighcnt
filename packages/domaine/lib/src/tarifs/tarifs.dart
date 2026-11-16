// LE RÉFÉRENTIEL DE PRIX UNIQUE (PRD-TARIFS, lot T6) : le même modèle que la maquette, porté en Dart pur.
//
// Deux collections au magasin (famille R de la synchronisation : la mère seule écrit, un fileul la reçoit) :
//   - `tarifs` : l'identité d'une prestation tarifée (code canonique, codes d'acte, de grille et d'analyse, alias, libellé de facturation, famille, secteur) ;
//   - `versionsTarif` : une ligne par version de prix, IMMUABLE pour ce qui est du prix (une correction ajoute une version). L'état « en vigueur » n'est JAMAIS
//     stocké : c'est la version `valide` de plus grande (date d'effet, version) dont la date d'effet est antérieure ou égale au JOUR de la pièce.
//
// Règles portées de `prototype_html/assets/js/data-tarifs.js` (moteur pur : `D.TARIFS`) et de `parcours.js` (`PR.tarifALaDate`, `PR.proposerTarif`, `PR.deciderTarif`,
// `PR.retirerProposition`, `PR.deciderTousTarifs`, `PR.usagesTarif`, `PR.ecartProforma`) ; les vecteurs de `test/vecteurs/tarifs.json` sont tirés de l'écran réel de la maquette
// piloté dans Chrome (`build/vecteurs-tarifs.js`), et rejoués par `test/tarifs_test.dart`. Aucune règle n'est recopiée à la main ailleurs.
//
// Doctrine : fonctions PURES. Aucune date « du jour » n'est lue sur l'horloge (la date d'une pièce ou le jour du geste est toujours fournie) ; l'appelant écrit, journalise
// (RG-12) et notifie. Un refus se NOMME (code, motif, geste). « Absent » n'est pas zéro : une prestation sans version valide à la date ne se facture pas.

import '../droits/droit_geste.dart' show gesDroit, gesRoles;
import '../referentiels/regles.dart' show joursEntre;

part 'tarifs_produits.dart';

typedef FicheTarif = Map<String, Object?>;

/// Les collections du référentiel (famille R : la mère seule écrit) et celle des demandes d'un fileul (famille B : ajout seul, la mère applique).
const String tarCollectionTarifs = 'tarifs';
const String tarCollectionVersions = 'versionsTarif';
const String tarCollectionDemandes = 'propositionsTarif';
const List<String> tarCollectionsReferentiel = [tarCollectionTarifs, tarCollectionVersions];

/// Qui DÉCIDE un changement de prix (jamais le droit d'éditer l'écran) : le geste réservé [tarGesteDecider] de la fiche RBAC (lot TARIF-FIX-2, Direction du 16/11/2026 : « pas de
/// rôle ni validation en dur dans le code »). [tarRolesValidation] n'est que le DÉFAUT D'ORIGINE du manifeste (`N.GESTES`, `rolesDefaut`), vérifié égal à `rbac.json` par un test du
/// poste ; il ne vaut que tant qu'aucune matrice n'est installée ([tarInstallerDroitDecider]). Qui peut dater dans le passé (T6, 11/11/2026) reste une liste (lot CLO-3).
const String tarGesteDecider = 'decider_prix';
const List<String> tarRolesValidation = ['admin', 'da', 'direction'];
const List<String> tarRolesDatePassee = ['da', 'direction'];

/// LOT VAL : la date d'effet antérieure est le geste réservé `tarifer_date_passee` de la fiche RBAC ; [tarRolesDatePassee] n'est que le DÉFAUT d'origine du manifeste.
const String tarGesteDatePassee = 'tarifer_date_passee';
bool tarPeutDatePassee(String role) => gesDroit(role, tarGesteDatePassee, tarRolesDatePassee);

/// La durée de validité d'une pro-forma : défaut proposé et bornes (T5, 11/11/2026 : « à valider », réglable en base).
const int tarValiditeProformaDefaut = 30;
const int tarValiditeProformaMin = 0;
const int tarValiditeProformaMax = 365;
const String tarCleValiditeProforma = 'tarifsValiditeProformaJours';

/// Le seuil de variation que la Direction décide de SIGNALER : aucune valeur n'est documentée, vide par défaut (jamais une constante du code).
const String tarCleSeuilVariation = 'tarifsVariationAlertePct';

const String tarMotifNonCouvert = 'Acte NON COUVERT par les assurances — facturé au patient au tarif non assuré.';
const String tarMotifSos = 'Les certificats ne sont couverts que par SOS — vérifier la compagnie.';
const String tarDateSemence = '2026-11-11';
const String tarMotifGrilleAnalyses = 'Prix de la grille imprimée « Tarifs des analyses de laboratoire » : proposé à la Direction (décision T2 du 11/11/2026), '
    'Oui ou Non analyse par analyse. Il ne change rien tant qu’il n’est pas validé.';

/// Un refus NOMMÉ : le code (stable, testable), le motif (lisible au guichet) et le geste qui corrige. Un refus d'usage porte aussi les pièces en cause.
class RefusTarif {
  const RefusTarif(this.code, this.motif, this.geste, {this.usages = const [], this.nbPieces});
  final String code;
  final String motif;
  final String geste;
  final List<Map<String, Object?>> usages;
  final int? nbPieces;
  Map<String, Object?> toJson() => {'ok': false, 'code': code, 'motif': motif, 'geste': geste};
  @override
  String toString() => '$code : $motif';
}

/// Un résultat : soit [valeur], soit [refus] (jamais les deux).
class ResultatTarif<T> {
  const ResultatTarif.ok(T this.valeur) : refus = null;
  const ResultatTarif.refuse(RefusTarif this.refus) : valeur = null;
  final T? valeur;
  final RefusTarif? refus;
  bool get ok => refus == null;
}

/// La date d'un jour, `AAAA-MM-JJ` (la date d'une pièce ou d'un effet, jamais une heure).
String tarIso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final RegExp _jourIso = RegExp(r'^\d{4}-\d{2}-\d{2}$');
bool tarJourValide(Object? s) => s is String && _jourIso.hasMatch(s);

/// Le JOUR d'une date de pièce : une date vide vaut [aujourdhui] (fourni par l'appelant, jamais lu sur l'horloge ici), un `AAAA-MM-JJ` reste tel quel, un instant
/// est ramené au jour LOCAL (écart E4 : une date se compare au jour).
String tarJourDe(Object? d, String aujourdhui) {
  if (d == null || d == '') return aujourdhui;
  if (d is DateTime) return tarIso(d.toLocal());
  final s = '$d';
  if (_jourIso.hasMatch(s)) return s;
  final t = DateTime.tryParse(s);
  return t == null ? aujourdhui : tarIso(t.toLocal());
}

bool _egal(Object? a, Object? b) => (a == null && b == null) || a == b;

double _nombre(Object? x) {
  if (x is num) return x.toDouble();
  if (x is String) return double.tryParse(x.trim()) ?? double.nan;
  return double.nan;
}

bool _entierPositif(double x) => x.isFinite && x > 0 && x.floorToDouble() == x;

String _dateFr(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
}

String _libelleRole(String role, Map<String, String> libelles) {
  final l = libelles[role];
  return (l == null || l.isEmpty) ? role : l;
}

/// Ce que les deux colonnes disent en vigueur à un jour : ce que lisent l'écran et la projection de lecture.
class InstantaneTarif {
  const InstantaneTarif({required this.na, required this.pa, required this.etatNonAssure, required this.etatAssure, required this.nc, required this.version, required this.dateEffet, required this.provisoire, required this.vrs});
  final num? na;
  final num? pa;
  final String etatNonAssure;
  final String etatAssure;
  final bool nc;
  final int version;
  final String? dateEffet;
  final bool provisoire;
  final FicheTarif vrs;
}

/// Le prix d'une prestation à une date, selon que la carte est valide ou non (RG-09).
class ResolutionTarif {
  const ResolutionTarif({
    required this.code,
    this.montant,
    this.tarif,
    this.motif,
    this.version,
    this.dateEffet,
    this.provisoire = false,
    this.absent = false,
    this.reserveSos = false,
    this.libelle,
    this.famille,
    this.espaces = const {},
  });
  final String code;
  final num? montant;

  /// `non assuré` ou `assuré` : la colonne retenue.
  final String? tarif;
  final String? motif;
  final int? version;
  final String? dateEffet;
  final bool provisoire;
  final bool absent;
  final bool reserveSos;
  final String? libelle;
  final String? famille;

  /// Les trois espaces de codes de la prestation (`acte`, `grille`, `analyse`).
  final Map<String, String?> espaces;

  /// Une ligne se facture : un montant existe et la prestation n'est pas absente.
  bool get facturable => !absent && montant != null;

  ResolutionTarif _avec({String? libelle, String? famille, Map<String, String?>? espaces}) => ResolutionTarif(
      code: code, montant: montant, tarif: tarif, motif: motif, version: version, dateEffet: dateEffet, provisoire: provisoire, absent: absent, reserveSos: reserveSos,
      libelle: libelle, famille: famille, espaces: espaces ?? const {});

  Map<String, Object?> toJson() => {'montant': montant, 'tarif': tarif, 'motif': motif, 'version': version, 'absent': absent, 'reserveSos': reserveSos};
}

/// LOT TARIF-FIX : le geste commun d'une ligne « prix à définir » (mot pour mot celui de la maquette).
const String tarGesteProposer =
    'Proposer le prix dans « Tarifs et prix » (Proposer un changement de prix), puis le faire décider (Oui) par la Direction, la Directrice Administrative ou l’administrateur ; ou retirer la ligne de la prescription.';

/// LOT TARIF-FIX : le prix d'une ligne de prescription, ou « prix à définir » (code `PRIX_A_DEFINIR`) avec sa cause, son motif et son geste. Jamais un zéro.
class LignePrix {
  const LignePrix._ok({required num this.montant, required String this.tarif, this.motif, required this.prestation, required this.libelle, this.famille, this.version, this.dateEffet})
      : ok = true,
        cause = null,
        geste = null,
        effectifLe = null,
        colonne = null;
  const LignePrix._aDefinir(
      {required String this.cause, required this.prestation, required this.libelle, required String this.motif, required String this.geste, this.effectifLe, this.version, this.colonne})
      : ok = false,
        montant = null,
        tarif = null,
        famille = null,
        dateEffet = null;
  final bool ok;
  final num? montant;
  final String? tarif;
  final String? motif;
  final String prestation;
  final String libelle;
  final String? famille;
  final int? version;
  final String? dateEffet;
  final String? cause;
  final String? geste;
  final String? effectifLe;
  final String? colonne;
  bool get aDefinir => !ok;
  String get code => ok ? 'OK' : 'PRIX_A_DEFINIR';

  /// Ce que la vue dit d'une ligne : le montant, ou « prix à définir » (avec la date d'effet quand un prix décidé arrive).
  String get libelleCourt => ok ? '$montant' : (effectifLe != null ? 'prix à définir, effectif le ${_dateFr(effectifLe!)}' : 'prix à définir');
  Map<String, Object?> toJson() => ok
      ? {'ok': true, 'montant': montant, 'tarif': tarif, 'motif': motif, 'prestation': prestation, 'version': version}
      : {'ok': false, 'code': 'PRIX_A_DEFINIR', 'cause': cause, 'prestation': prestation, 'motif': motif, 'geste': geste, if (effectifLe != null) 'effectifLe': effectifLe};
}

/// LOT TARIF-FIX : un code ne se réutilise pas. Comparaison sur le code NORMALISÉ (espaces aux bords, majuscules), dans les trois espaces, les alias et les prestations
/// archivées. Rend la prestation qui le porte déjà, ou `null`. Port de `D.TARIFS.codePris`.
String tarCodeNormalise(Object? code) => '${code ?? ''}'.trim().toUpperCase();
FicheTarif? tarCodePris(Iterable<FicheTarif> tarifs, Object? code) {
  final n = tarCodeNormalise(code);
  if (n.isEmpty) return null;
  for (final p in tarifs) {
    final codes = [p['code'], p['codeActe'], p['codeGrille'], p['codeAnalyse'], ...(p['codesAlias'] as List? ?? const [])];
    if (codes.any((x) => x != null && tarCodeNormalise(x) == n)) return p;
  }
  return null;
}

/// L'index du référentiel : trois espaces de codes pour UNE prestation. Chaque lecteur historique garde son espace (`parActe`, `parGrille`, `parAnalyse`) ; l'accesseur
/// nouveau ([aLaDate]) résout les trois, plus les alias.
class ReferentielTarifs {
  ReferentielTarifs(Iterable<FicheTarif> tarifs, Iterable<FicheTarif> versions)
      : tarifs = List.unmodifiable(tarifs),
        versions = List.unmodifiable(versions) {
    for (final p in this.tarifs) {
      if (p['statut'] == 'archive') continue;
      final code = '${p['code']}';
      parCode[code] = p;
      if (p['codeActe'] != null) parActe['${p['codeActe']}'] = p;
      if (p['codeGrille'] != null) parGrille['${p['codeGrille']}'] = p;
      if (p['codeAnalyse'] != null) parAnalyse['${p['codeAnalyse']}'] = p;
    }
    for (final p in this.tarifs) {
      if (p['statut'] == 'archive') continue;
      for (final c in (p['codesAlias'] as List? ?? const [])) {
        parCode.putIfAbsent('$c', () => p);
      }
    }
    for (final v in this.versions) {
      (vers['${v['code']}'] ??= []).add(v);
    }
  }

  final List<FicheTarif> tarifs;
  final List<FicheTarif> versions;
  final Map<String, FicheTarif> parCode = {};
  final Map<String, FicheTarif> parActe = {};
  final Map<String, FicheTarif> parGrille = {};
  final Map<String, FicheTarif> parAnalyse = {};
  final Map<String, List<FicheTarif>> vers = {};

  bool get vide => tarifs.isEmpty;

  static bool _plusRecente(FicheTarif a, FicheTarif b) {
    final da = '${a['dateEffet'] ?? ''}', db = '${b['dateEffet'] ?? ''}';
    if (da != db) return da.compareTo(db) > 0;
    return ((a['version'] as num?) ?? 0) > ((b['version'] as num?) ?? 0);
  }

  /// Les versions de ce code, de la première à la dernière.
  List<FicheTarif> versionsDe(String code) => [...(vers[code] ?? const <FicheTarif>[])]..sort((a, b) => ((a['version'] as num?) ?? 0).compareTo((b['version'] as num?) ?? 0));

  /// La version en vigueur de ce code à ce jour (`AAAA-MM-JJ`), ou `null`. Une version `propose`, `refuse` ou `retire` n'est JAMAIS lue.
  FicheTarif? enVigueur(String code, String jour) {
    FicheTarif? meilleure;
    for (final v in vers[code] ?? const <FicheTarif>[]) {
      if (v['statut'] != 'valide') continue;
      final de = v['dateEffet'];
      if (de != null && '$de'.compareTo(jour) > 0) continue;
      if (meilleure == null || _plusRecente(v, meilleure)) meilleure = v;
    }
    return meilleure;
  }

  /// La résolution d'une prestation DÉJÀ retrouvée, à un jour, colonne choisie par la validité de la carte (RG-09).
  ResolutionTarif resoudre(FicheTarif p, String jour, bool assure) {
    final code = '${p['code']}';
    final v = enVigueur(code, jour);
    if (v == null) {
      return ResolutionTarif(code: code, absent: true, motif: 'Aucune version de prix valide à la date du $jour pour « ${p['libelle'] ?? code} ».');
    }
    final na = v['etatNonAssure'] == 'manquant' ? null : v['prixNonAssure'] as num?;
    final version = ((v['version'] as num?) ?? 0).toInt();
    final de = v['dateEffet'] as String?;
    final prov = v['provisoire'] == true;
    ResolutionTarif r({num? montant, required String tarif, String? motif, bool sos = false}) =>
        ResolutionTarif(code: code, montant: montant, tarif: tarif, motif: motif, version: version, dateEffet: de, provisoire: prov, reserveSos: sos);
    if (!assure) return r(montant: na, tarif: 'non assuré');
    if (v['etatAssure'] == 'nc' || p['assurable'] == false) return r(montant: na, tarif: 'non assuré', motif: tarMotifNonCouvert);
    if (p['assurable'] == 'sos') return r(montant: na, tarif: 'non assuré', motif: tarMotifSos, sos: true);
    if (v['etatAssure'] == 'unique') return r(montant: na, tarif: 'assuré');
    return r(montant: v['etatAssure'] == 'montant' ? v['prixAssure'] as num? : null, tarif: 'assuré');
  }

  /// `PR.tarifALaDate(code, date, assure)` : les trois espaces de codes et les alias. [aujourdhui] sert quand [date] est vide.
  ResolutionTarif aLaDate(Object? code, Object? date, bool assure, {required String aujourdhui}) {
    final c = '$code';
    final p = parCode[c];
    if (p == null) return ResolutionTarif(code: c, absent: true, motif: 'Prestation absente du référentiel de prix : « $c ».');
    final r = resoudre(p, tarJourDe(date, aujourdhui), assure);
    return r._avec(libelle: p['libelle'] as String?, famille: p['famille'] as String?, espaces: {
      'acte': p['codeActe'] as String?,
      'grille': p['codeGrille'] as String?,
      'analyse': p['codeAnalyse'] as String?,
    });
  }

  /// Les deux colonnes et leurs états, en vigueur à ce jour.
  InstantaneTarif? instantane(FicheTarif p, String jour) {
    final v = enVigueur('${p['code']}', jour);
    if (v == null) return null;
    final na = v['etatNonAssure'] == 'manquant' ? null : v['prixNonAssure'] as num?;
    final etatA = '${v['etatAssure']}';
    final num? pa = etatA == 'montant' ? v['prixAssure'] as num? : (etatA == 'unique' ? na : null);
    return InstantaneTarif(
        na: na,
        pa: pa,
        etatNonAssure: '${v['etatNonAssure'] ?? 'montant'}',
        etatAssure: etatA,
        nc: etatA == 'nc',
        version: ((v['version'] as num?) ?? 0).toInt(),
        dateEffet: v['dateEffet'] as String?,
        provisoire: v['provisoire'] == true,
        vrs: v);
  }

  /// Le prix d'un ACTE (espace des codes d'acte) selon la règle historique de la prescription : la colonne assurée ne s'applique que si l'acte est assurable ET porte un
  /// montant assuré ; sinon le prix non assuré. `connu` faux : l'acte n'est pas au référentiel.
  ({bool connu, num? montant}) prixActe(Object? code, Object? date, bool assure, {required String aujourdhui}) {
    final p = parActe['$code'];
    if (p == null) return (connu: false, montant: null);
    final s = instantane(p, tarJourDe(date, aujourdhui));
    if (s == null) return (connu: true, montant: null);
    return (connu: true, montant: (assure && p['assurable'] == true && s.etatAssure == 'montant') ? s.pa : s.na);
  }

  /// Le prix d'une ANALYSE (espace des codes d'analyse) : la colonne assurée vaut le prix unique tant qu'aucune version ne porte un montant assuré.
  ({bool connu, num? montant}) prixAnalyse(Object? code, Object? date, bool assure, {required String aujourdhui}) {
    final p = parAnalyse['$code'];
    if (p == null) return (connu: false, montant: null);
    final s = instantane(p, tarJourDe(date, aujourdhui));
    if (s == null) return (connu: true, montant: null);
    return (connu: true, montant: (assure && s.etatAssure == 'montant') ? s.pa : s.na);
  }

  /// LOT TARIF-FIX : le prix d'une ligne de PRESCRIPTION (`voie` `acte` ou `analyse`) à la date du JOUR de la pièce, lu à chaque appel. Port de
  /// `D.TARIFS.prixDeLigne` (maquette, `data-tarifs.js`), vecteurs `tarifs_ligne.json`. Rend un montant strictement positif, ou « prix à définir » avec sa cause,
  /// son motif et son geste : JAMAIS un zéro. L'espace de la voie d'abord, puis le code ou l'alias de toute prestation (un certificat ou une consultation n'est plus
  /// à 0 parce qu'il n'est pas dans l'espace des actes). Une colonne vide n'est jamais remplacée par l'autre.
  LignePrix prixDeLigne(Object? code, Object? date, bool assure, {String voie = 'acte', required String aujourdhui}) {
    final c = '${code ?? ''}';
    final analyse = voie == 'analyse';
    final p = (analyse ? parAnalyse[c] : parActe[c]) ?? parCode[c];
    final lib = p == null ? c : '${p['libelle'] ?? c}';
    LignePrix aDefinir(String cause, String motif, String geste, {String? effectifLe, int? version, String? colonne}) =>
        LignePrix._aDefinir(cause: cause, prestation: c, libelle: lib, motif: '« $c » $lib : $motif', geste: geste, effectifLe: effectifLe, version: version, colonne: colonne);
    if (vide) return aDefinir('referentiel-absent', 'prix à définir (le référentiel de prix n’est pas chargé)', 'Recharger la page.');
    if (p == null) {
      return aDefinir(
          'absent-du-referentiel',
          'prix à définir (aucune prestation de prix ne porte ce code)',
          analyse
              ? 'Créer la prestation dans « Tarifs et prix » : Nouvelle prestation, famille Analyses de laboratoire, MÊME code que le catalogue du laboratoire, puis la faire décider (Oui).'
              : 'Créer la prestation dans « Tarifs et prix » (Nouvelle prestation, même code), puis la faire décider (Oui) ; ou retirer la ligne de la prescription.');
    }
    final j = tarJourDe(date, aujourdhui);
    final pc = '${p['code']}';
    final v = enVigueur(pc, j);
    if (v == null) {
      final futures = [
        for (final x in vers[pc] ?? const <FicheTarif>[])
          if (x['statut'] == 'valide' && x['dateEffet'] != null && '${x['dateEffet']}'.compareTo(j) > 0) x
      ]..sort((a, b) => '${a['dateEffet']}'.compareTo('${b['dateEffet']}'));
      if (futures.isNotEmpty) {
        final de = '${futures.first['dateEffet']}';
        return aDefinir('version-future', 'prix à définir, effectif le ${_dateFr(de)}',
            'Le prix décidé prend effet le ${_dateFr(de)} : la ligne le lira ce jour-là. Pour l’appliquer plus tôt, proposer dans « Tarifs et prix » une version datée d’aujourd’hui et la faire décider (Oui).',
            effectifLe: de);
      }
      final attente = (vers[pc] ?? const <FicheTarif>[]).any((x) => x['statut'] == 'propose');
      if (attente) {
        return aDefinir('proposition-en-attente', 'prix à définir (une proposition attend la décision)', 'Décider la proposition (Oui, avec une date d’effet) dans « Tarifs et prix », onglet Alertes.');
      }
      return aDefinir('sans-version', 'prix à définir (aucune version de prix décidée)', tarGesteProposer);
    }
    final num? na = v['etatNonAssure'] == 'manquant' ? null : v['prixNonAssure'] as num?;
    final etatA = '${v['etatAssure']}';
    final version = ((v['version'] as num?) ?? 0).toInt();
    num? montant;
    var tarif = 'non assuré';
    String? motif;
    var colonneAssuree = false;
    if (!assure) {
      montant = na;
    } else if (!analyse && identical(parActe[c], p)) {
      // La règle historique de l'acte : la colonne assurée ne vaut que pour un acte assurable ; NON COUVERT et prix unique se facturent au non assuré.
      if (p['assurable'] == true && etatA == 'montant') {
        montant = v['prixAssure'] as num?;
        tarif = 'assuré';
        colonneAssuree = true;
      } else if (p['assurable'] == true && etatA == 'manquant') {
        montant = null;
        tarif = 'assuré';
        colonneAssuree = true;
      } else {
        montant = na;
      }
    } else if (analyse && identical(parAnalyse[c], p)) {
      if (etatA == 'montant') {
        montant = v['prixAssure'] as num?;
        tarif = 'assuré';
        colonneAssuree = true;
      } else if (etatA == 'manquant' && na != null) {
        montant = null;
        tarif = 'assuré';
        colonneAssuree = true;
      } else {
        montant = na;
      }
    } else {
      final r = resoudre(p, j, true);
      montant = r.montant;
      tarif = r.tarif ?? 'non assuré';
      motif = r.motif;
      colonneAssuree = r.tarif == 'assuré';
    }
    if (montant == null || !(montant > 0)) {
      if (colonneAssuree && na != null) {
        return aDefinir('prix-assure-vide',
            'prix assuré à définir (la colonne assurée de la version en vigueur n’est pas renseignée ; le prix non assuré ne la remplace pas)',
            'Proposer dans « Tarifs et prix » une version qui porte le prix assuré (ou qui déclare la prestation NON COUVERTE), puis la faire décider (Oui).',
            version: version, colonne: 'assuré');
      }
      return aDefinir('prix-non-assure-vide', 'prix à définir (la version en vigueur ne porte pas de prix non assuré ; le prix assuré ne le remplace pas)', tarGesteProposer,
          version: version, colonne: 'non assuré');
    }
    return LignePrix._ok(
        montant: montant, tarif: tarif, motif: motif, prestation: pc, libelle: lib, famille: p['famille'] as String?, version: version, dateEffet: v['dateEffet'] as String?);
  }

  /// Le prix d'une ligne de GRILLE (espace des codes de grille : imagerie, soins AMI, certificats) : la forme de l'ancien `D.tarifPrix(code, assure, date)`.
  ResolutionTarif prixGrille(Object? code, Object? date, bool assure, {required String aujourdhui}) {
    final c = '$code';
    final p = parGrille[c];
    if (p == null) return ResolutionTarif(code: c, absent: true, motif: 'Acte absent du catalogue tarifaire.');
    return resoudre(p, tarJourDe(date, aujourdhui), assure);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La projection de compatibilité : `actes`, `analyses` et `catalogueTarifs` portent le prix EN VIGUEUR AUJOURD'HUI (un pont, pas une cible)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Ce que la fiche d'ACTE doit porter aujourd'hui : le correctif des seuls champs de PRIX qui diffèrent (`null` si aucun).
Map<String, Object?>? tarCorrectifActe(FicheTarif doc, FicheTarif p, InstantaneTarif s) {
  final c = <String, Object?>{};
  void poser(String k, Object? v) {
    if (!_egal(doc[k], v)) c[k] = v;
  }

  poser('prix', s.na);
  if (doc.containsKey('prixNonAssure')) poser('prixNonAssure', s.na);
  if (doc.containsKey('prixAssure') || s.etatAssure == 'montant') poser('prixAssure', s.etatAssure == 'montant' ? s.pa : null);
  if (doc.containsKey('nonCouvert') || s.nc) poser('nonCouvert', s.nc);
  if (p.containsKey('assurable') && s.etatAssure == 'montant') poser('assurable', p['assurable']);
  return c.isEmpty ? null : c;
}

Map<String, Object?>? tarCorrectifAnalyse(FicheTarif doc, FicheTarif p, InstantaneTarif s) => _egal(doc['prix'], s.na) ? null : {'prix': s.na};

Map<String, Object?>? tarCorrectifGrille(FicheTarif doc, FicheTarif p, InstantaneTarif s) {
  final c = <String, Object?>{};
  void poser(String k, Object? v) {
    if (!_egal(doc[k], v)) c[k] = v;
  }

  poser('prixNonAssure', s.na);
  poser('nonCouvert', s.nc);
  poser('prixAssure', s.nc ? null : s.pa);
  poser('prixAValider', s.na == null || (s.pa == null && !s.nc && p['assurable'] != false));
  return c.isEmpty ? null : c;
}

/// Un correctif de la projection : la fiche de lecture [id] de [collection] doit recevoir [patch] (prix seulement, sans ligne de journal) ; ou, quand [creation] est posée,
/// la prestation n'a pas encore de fiche dans cette collection et celle-ci doit être AJOUTÉE (sans journal : ce n'est pas le geste d'un agent).
class CorrectifProjection {
  const CorrectifProjection(this.collection, this.id, this.patch, {this.creation});
  final String collection;
  final Object? id;
  final Map<String, Object?> patch;
  final Map<String, Object?>? creation;
}

/// La projection de lecture : `actes`, `analyses` et `catalogueTarifs` portent, pour chaque prestation, le prix EN VIGUEUR à [jour]. Ce n'est pas un geste : c'est l'état
/// dérivé du référentiel. Seuls les champs de PRIX sont touchés ; un marquage « tarif d'attente », un libellé ou un secteur restent ce qu'ils sont. Rend les correctifs ;
/// l'appelant les applique (sans journal) et `parites` (liste sans les créations) sert la garde de parité.
List<CorrectifProjection> tarProjection(
  ReferentielTarifs h,
  String jour, {
  required Iterable<FicheTarif> actes,
  required Iterable<FicheTarif> analyses,
  required Iterable<FicheTarif> catalogue,
  bool avecCreations = false,
}) {
  final out = <CorrectifProjection>[];
  void passe(String nom, List<FicheTarif> docs, Map<String, FicheTarif> index, Map<String, Object?>? Function(FicheTarif, FicheTarif, InstantaneTarif) correctif,
      FicheTarif Function(FicheTarif, InstantaneTarif, int) creer) {
    final vus = <String>{};
    for (final doc in docs) {
      vus.add('${doc['code']}');
      final p = index['${doc['code']}'];
      if (p == null) continue;
      final s = h.instantane(p, jour);
      if (s == null) continue;
      final c = correctif(doc, p, s);
      if (c != null) out.add(CorrectifProjection(nom, doc['id'], c));
    }
    if (!avecCreations) return;
    var n = docs.length;
    for (final e in index.entries) {
      if (vus.contains(e.key)) continue;
      final s = h.instantane(e.value, jour);
      if (s == null) continue;
      final fiche = creer(e.value, s, ++n);
      out.add(CorrectifProjection(nom, fiche['id'], const {}, creation: fiche));
    }
  }

  passe('actes', [...actes], h.parActe, tarCorrectifActe, (p, s, n) {
    final d = <String, Object?>{'id': 'ACT-${p['code']}', 'statut': 'actif', 'code': p['code'], 'libelle': p['libelle'], 'secteur': p['secteur'] ?? '', 'prix': s.na};
    if (p['source'] != null) d['source'] = p['source'];
    if (p['codeGrille'] != null) {
      d['codeTarif'] = p['codeGrille'];
      d['prixNonAssure'] = s.na;
      d['prixAssure'] = s.nc ? null : s.pa;
      d['nonCouvert'] = s.nc;
      if (p.containsKey('assurable')) d['assurable'] = p['assurable'];
    }
    return d;
  });
  passe('analyses', [...analyses], h.parAnalyse, tarCorrectifAnalyse, (p, s, n) => {
        'id': 'ANA-${p['code']}',
        'n': n,
        'code': p['code'],
        'designation': p['libelle'],
        'categorie': '',
        'prix': s.na,
        'echantillon': '',
        'delai': '',
        'statut': 'Actif',
      });
  passe('catalogueTarifs', [...catalogue], h.parGrille, tarCorrectifGrille, (p, s, n) {
    final d = <String, Object?>{
      'id': 'TAR-${p['codeGrille']}',
      'statut': 'actif',
      'code': p['codeGrille'],
      'libelle': p['libelleGrille'] ?? p['libelle'],
      'famille': p['famille'],
      'prixNonAssure': s.na,
      'prixAssure': s.nc ? null : s.pa,
      'nonCouvert': s.nc,
      'prixAValider': s.na == null,
    };
    if (p.containsKey('assurable')) d['assurable'] = p['assurable'];
    if (p['source'] != null) d['source'] = p['source'];
    return d;
  });
  return out;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La migration : les trois listes d'avant deviennent UN référentiel, sans changer un prix facturé aujourd'hui
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le libellé normalisé qui sert au SEUL rapprochement des analyses avec la grille (aucun rapprochement approximatif).
String tarNormaliserLibelle(Object? x) {
  var s = '${x ?? ''}'.toLowerCase();
  const accents = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a', 'ç': 'c', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'œ': 'oe',
  };
  s = s.split('').map((c) => accents[c] ?? c).join();
  s = s.replaceAll('’', "'").replaceAll(RegExp(r'\([^)]*\)'), ' ').replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  return s;
}

typedef _Etats = ({num? na, String etatNA, num? pa, String etatA});

_Etats _etatsActe(FicheTarif a) {
  final num? na = a['prixNonAssure'] != null ? a['prixNonAssure'] as num : (a['prix'] != null ? a['prix'] as num : null);
  num? pa = a['prixAssure'] as num?;
  String etatA;
  if (a['nonCouvert'] == true) {
    etatA = 'nc';
    pa = null;
  } else if (pa != null) {
    etatA = 'montant';
  } else if ((a['codeTarif'] != null && a['codeTarif'] != '') || a['assurable'] == true) {
    etatA = 'manquant';
  } else {
    etatA = 'unique';
  }
  return (na: na, etatNA: na == null ? 'manquant' : 'montant', pa: pa, etatA: etatA);
}

_Etats _etatsGrille(FicheTarif g) {
  final String etatA = g['nonCouvert'] == true ? 'nc' : (g['prixAssure'] != null ? 'montant' : 'manquant');
  final num? na = g['prixNonAssure'] as num?;
  return (na: na, etatNA: na == null ? 'manquant' : 'montant', pa: g['nonCouvert'] == true ? null : g['prixAssure'] as num?, etatA: etatA);
}

FicheTarif _creerVersion(String code, int n, _Etats e,
    {required String origine, String statut = 'valide', String? dateEffet, bool aDater = false, String? motif, bool provisoire = false, String? arreteLe, String? proposePar}) {
  final v = <String, Object?>{
    'id': '$code@${dateEffet ?? (aDater ? 'a-dater' : 'origine')}@$n',
    'code': code,
    'version': n,
    // Les champs nuls ne s'écrivent pas (quota du magasin, comme `sansNuls` de la maquette) : un prix absent est une CLÉ absente, jamais un zéro.
    if (e.na != null) 'prixNonAssure': e.na,
    if (e.pa != null) 'prixAssure': e.pa,
    'etatAssure': e.etatA,
    'origine': origine,
    'statut': statut,
  };
  // « montant » est l'état usuel de la colonne non assuré : il ne s'écrit que s'il est autre (quota du magasin).
  if (e.etatNA != 'montant') v['etatNonAssure'] = e.etatNA;
  if (dateEffet != null) v['dateEffet'] = dateEffet;
  if (aDater) v['aDater'] = true;
  if (motif != null && motif.isNotEmpty) v['motif'] = motif;
  if (provisoire) v['provisoire'] = true;
  if (arreteLe != null && arreteLe.isNotEmpty) v['arreteLe'] = arreteLe;
  if (proposePar != null) {
    v['proposePar'] = proposePar;
    v['proposeLe'] = tarDateSemence;
  }
  return v;
}

/// Le résultat d'une migration : les prestations, les versions, et la LISTE de ce qui diverge entre les sources (aucun prix n'est corrigé en silence).
class MigrationTarifs {
  const MigrationTarifs(this.tarifs, this.versions, this.ecarts);
  final List<FicheTarif> tarifs;
  final List<FicheTarif> versions;
  final List<Map<String, Object?>> ecarts;
}

/// `D.TARIFS.migrer(src)`. [actes] : les fiches de la collection `actes` ; [grille] : les lignes de la grille imprimée ; [analyses] : les analyses (`code`, `designation`,
/// `prix`, `tarifProvisoire`) ; [catalogue] : les fiches éditées de `catalogueTarifs` (facultatif : seuls ses écarts avec la grille sont listés).
MigrationTarifs tarMigrer({
  required Iterable<FicheTarif> actes,
  required Iterable<FicheTarif> grille,
  required Iterable<FicheTarif> analyses,
  Iterable<FicheTarif> catalogue = const [],
}) {
  final tarifs = <FicheTarif>[];
  final versions = <FicheTarif>[];
  final ecarts = <Map<String, Object?>>[];
  final gParCode = <String, FicheTarif>{};
  final gLabo = <String, FicheTarif>{};
  final grilleUtilisee = <String>{};
  for (final g in grille) {
    gParCode['${g['code']}'] = g;
    if (g['famille'] == 'LABO') gLabo[tarNormaliserLibelle(g['libelle'])] = g;
  }

  // 1. Les actes : le code d'acte est canonique, la ligne de grille rapprochée devient un alias.
  for (final a in actes) {
    final code = '${a['code']}';
    final g = (a['codeTarif'] != null && a['codeTarif'] != '') ? gParCode['${a['codeTarif']}'] : null;
    final e = _etatsActe(a);
    final p = <String, Object?>{
      'id': code,
      'code': code,
      'codeActe': code,
      'libelle': a['libelle'],
      'famille': g != null ? g['famille'] : (RegExp(r'^HO\d').hasMatch(code) ? 'HOSPITALISATION' : 'ACTE'),
      'statut': 'actif',
    };
    if (a['secteur'] != null && a['secteur'] != '') p['secteur'] = a['secteur'];
    if (g != null) {
      p['codeGrille'] = g['code'];
      p['codesAlias'] = [g['code']];
      if (g['libelle'] != a['libelle']) p['libelleGrille'] = g['libelle'];
      grilleUtilisee.add('${g['code']}');
    }
    if (a.containsKey('assurable')) p['assurable'] = a['assurable'];
    final vg = a['variantesGrille'] as List?;
    if (vg != null && vg.isNotEmpty) p['variantesGrille'] = [for (final x in vg) x is Map ? x['code'] : x];
    tarifs.add(p);
    versions.add(_creerVersion(code, 1, e,
        origine: 'migration', provisoire: a['tarifProvisoire'] == true, arreteLe: a['tarifArreteLe'] as String?, motif: a['motifPrix'] as String?));
    if (g != null) {
      final eg = _etatsGrille(g);
      if (eg.na != e.na || eg.pa != e.pa || eg.etatA != e.etatA) {
        ecarts.add({
          'type': 'acte-grille',
          'code': code,
          'grille': g['code'],
          'acte': {'na': e.na, 'pa': e.pa, 'etat': e.etatA},
          'ligneDeGrille': {'na': eg.na, 'pa': eg.pa, 'etat': eg.etatA},
          'detail': 'Le prix de l’acte diffère de la ligne de grille : le prix de l’acte (celui de la caisse) est retenu.',
        });
      }
    }
  }

  // 2. Les analyses : le code d'analyse est canonique ; la ligne LABO de même libellé NORMALISÉ devient un alias, et son prix arrive en version 2 PROPOSÉE quand il
  // diffère de ce que la caisse facture.
  for (final a in analyses) {
    final code = '${a['code']}';
    var g = gLabo[tarNormaliserLibelle(a['designation'])];
    if (g != null && grilleUtilisee.contains('${g['code']}')) g = null;
    final num? prix = (a['prix'] is num && (a['prix'] as num) > 0) ? a['prix'] as num : null;
    final e = (na: prix, etatNA: prix == null ? 'manquant' : 'montant', pa: prix, etatA: prix == null ? 'manquant' : 'unique');
    final p = <String, Object?>{'id': code, 'code': code, 'codeAnalyse': code, 'libelle': a['designation'], 'famille': 'LABO', 'statut': 'actif'};
    if (g != null) {
      p['codeGrille'] = g['code'];
      p['codesAlias'] = [g['code']];
      p['libelleGrille'] = g['libelle'];
      p['assurable'] = g['assurable'];
      grilleUtilisee.add('${g['code']}');
    }
    tarifs.add(p);
    versions.add(_creerVersion(code, 1, e, origine: 'migration', provisoire: a['tarifProvisoire'] == true));
    if (g != null) {
      final eg = _etatsGrille(g);
      if (eg.na != e.na || eg.pa != e.pa || eg.etatA != e.etatA) {
        versions.add(_creerVersion(code, 2, eg, origine: 'semence-grille', statut: 'propose', aDater: true, proposePar: 'Semence du socle', motif: tarMotifGrilleAnalyses));
        ecarts.add({
          'type': 'analyse-grille',
          'code': code,
          'grille': g['code'],
          'facture': {'na': e.na},
          'ligneDeGrille': {'na': eg.na, 'pa': eg.pa, 'etat': eg.etatA},
          'detail': 'Version 2 proposée (le prix facturé aujourd’hui reste la version 1).',
        });
      }
    } else {
      ecarts.add({'type': 'analyse-sans-grille', 'code': code, 'detail': 'Aucune ligne de la grille imprimée ne porte ce libellé : un seul prix, celui de la caisse.'});
    }
  }

  // 3. Les lignes de grille restantes : une prestation chacune, au prix que la grille donne (celui que lisaient les soins, l'imagerie, les certificats).
  for (final g in grille) {
    final code = '${g['code']}';
    if (grilleUtilisee.contains(code)) continue;
    final e = _etatsGrille(g);
    final p = <String, Object?>{'id': code, 'code': code, 'codeGrille': code, 'libelle': g['libelle'], 'famille': g['famille'], 'statut': 'actif'};
    if (g.containsKey('assurable')) p['assurable'] = g['assurable'];
    tarifs.add(p);
    versions.add(_creerVersion(code, 1, e, origine: 'migration', provisoire: g['tarifProvisoire'] == true, motif: g['motifPrix'] as String?));
    if (g['famille'] == 'LABO') {
      ecarts.add({'type': 'grille-sans-analyse', 'code': code, 'detail': 'Ligne LABO de la grille sans analyse de même libellé : prestation propre, au prix de la grille.'});
    }
  }

  // 4. Les éditions faites au catalogue tarifaire (collection que personne ne lisait) : listées, jamais appliquées.
  for (final c in catalogue) {
    final g = gParCode['${c['code']}'];
    if (g == null) {
      ecarts.add({'type': 'catalogue-inconnu', 'code': c['code'], 'detail': 'Fiche du catalogue tarifaire sans ligne de grille : non reprise.'});
      continue;
    }
    for (final k in const ['prixNonAssure', 'prixAssure', 'nonCouvert', 'assurable']) {
      final nulFaux = k == 'nonCouvert' && c[k] != true && g[k] != true;
      if (!_egal(c[k], g[k]) && !nulFaux) {
        ecarts.add({'type': 'catalogue-grille', 'code': c['code'], 'champ': k, 'catalogue': c[k], 'grille': g[k], 'detail': 'Édité au catalogue tarifaire sans effet sur la facturation : non repris.'});
      }
    }
  }
  return MigrationTarifs(tarifs, versions, ecarts);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le contexte d'un geste : qui agit, quel jour, sur quel référentiel, et quelles pièces ont déjà utilisé un prix
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les pièces que le contrôle d'usage lit SUR LES LIGNES : factures, demandes d'analyses, demandes d'imagerie (sans collection d'usages dédiée).
class PiecesTarif {
  const PiecesTarif({this.factures = const [], this.demandesAnalyses = const [], this.demandesImagerie = const []});
  final Iterable<FicheTarif> factures;
  final Iterable<FicheTarif> demandesAnalyses;
  final Iterable<FicheTarif> demandesImagerie;
}

class ContexteTarif {
  const ContexteTarif({
    required this.referentiel,
    required this.aujourdhui,
    required this.role,
    required this.auteur,
    this.peutEditerEcran = false,
    this.peutProposerProduit = false,
    this.fileul = false,
    this.libelles = const {},
    this.pieces = const PiecesTarif(),
  });
  final ReferentielTarifs referentiel;

  /// Le JOUR du geste (`AAAA-MM-JJ`), fourni par l'appelant : le domaine ne lit jamais l'horloge.
  final String aujourdhui;
  final String role;

  /// Qui agit (RG-12 : aucune action anonyme).
  final String auteur;

  /// Le droit d'ÉDITER l'écran « Tarifs et prix » (fiches RBAC) : proposer un prix. Décider est un autre droit, porté par [tarRolesValidation].
  final bool peutEditerEcran;

  /// Le droit de PROPOSER le prix d'achat d'un produit (lot TFIN) : modifier « Référentiel produits », importer le jeu `tarifs-produits` ou modifier les réceptions d'achats ; jamais le droit d'éditer « Tarifs et prix ».
  final bool peutProposerProduit;

  /// Le poste est un fileul : il ne peut pas ÉCRIRE une version ni la décider (famille R, la mère seule écrit).
  final bool fileul;

  /// Les libellés de rôle du manifeste (rôles renommés compris), pour les motifs de refus.
  final Map<String, String> libelles;
  final PiecesTarif pieces;

  bool get peutDecider => tarPeutDecider(role);
  bool get peutDatePassee => tarPeutDatePassee(role);
}

bool Function(String role)? _droitDecider;

/// Le poste installe la lecture de la fiche RBAC À CHAUD (`matrice.droitGeste(role, tarGesteDecider)`) ; `null` revient au défaut d'origine.
void tarInstallerDroitDecider(bool Function(String role)? lecture) => _droitDecider = lecture;

/// Le rôle détient-il le geste réservé « Décider un changement de prix » ? Lu dans la fiche RBAC installée, sinon le défaut d'origine du manifeste.
bool tarPeutDecider(String role) => _droitDecider != null ? _droitDecider!(role) : tarRolesValidation.contains(role);

String tarProfilsDatePassee(Map<String, String> libelles) => gesRoles(tarGesteDatePassee, tarRolesDatePassee).map((r) => _libelleRole(r, libelles)).join(' et ');

/// Le refus d'un fileul : même code que `ApplicateurConfiguration` et le centre des validations (famille R, la mère seule écrit).
RefusTarif tarRefusFileul() => const RefusTarif('CONFIGURATION_DE_LA_MERE', 'Réglé sur la mère : cette configuration se modifie sur le poste principal, puis elle est reprise ici.',
    'Valider depuis le poste principal : la validation est reprise ici ensuite.');

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le contrôle d'usage `tarif_deja_utilise`
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les pièces de VENTE non archivées qui portent déjà une ligne de cette prestation à la date d'effet ou après : un prix qui prendrait effet à cette date changerait après
/// coup la réponse à « quel prix s'appliquait », alors que la ligne dit autre chose. Le contrôle se lit SUR LES LIGNES ; une pro-forma n'est pas une pièce émise.
List<Map<String, Object?>> tarUsages(FicheTarif p, String dateEffet, PiecesTarif pieces, {required String aujourdhui, Set<String> produitsIds = const {}}) {
  final codes = <String>{
    for (final c in [p['code'], p['codeActe'], p['codeGrille'], p['codeAnalyse'], ...(p['codesAlias'] as List? ?? const [])])
      if (c != null) '$c'
  };
  final analyses = <String, String>{
    for (final d in pieces.demandesAnalyses)
      if (d['analyseCode'] != null && d['id'] != null) '${d['id']}': '${d['analyseCode']}'
  };
  final imageries = <String, String>{
    for (final d in pieces.demandesImagerie)
      if (d['examenCode'] != null && d['id'] != null) '${d['id']}': '${d['examenCode']}'
  };
  final out = <Map<String, Object?>>[];
  for (final f in pieces.factures) {
    if (f['statut'] == 'archive' || (f['proforma'] != null && f['proforma'] != false)) continue;
    final jour = (f['date'] != null && f['date'] != '') ? tarJourDe(f['date'], aujourdhui) : null;
    if (jour == null || jour.compareTo(dateEffet) < 0) continue;
    final porte = ((f['lignes'] as List?) ?? const []).any((l) {
      final x = (l as Map).cast<String, Object?>();
      // LOT TARIF-FIX-2 : une ligne SANS PRIX ne dit aucun prix ; poser son prix ne change rien de ce que la pièce dit (elle attend ce prix pour s'encaisser).
      if (x['prixManquant'] != null) return false;
      return (x['acteCode'] != null && codes.contains('${x['acteCode']}')) ||
          (x['demandeId'] != null && codes.contains(analyses['${x['demandeId']}'])) ||
          (x['demandeImagerieId'] != null && codes.contains(imageries['${x['demandeImagerieId']}'])) ||
          // Une ligne de PRODUIT porte `produitId` (lot TFIN) : le contrôle d'usage d'un prix d'achat lit les mêmes lignes.
          (x['produitId'] != null && produitsIds.contains('${x['produitId']}'));
    });
    if (porte) out.add({'id': f['id'], 'numero': f['numero'], 'date': jour});
  }
  out.sort((a, b) {
    final c = '${a['date']}'.compareTo('${b['date']}');
    return c != 0 ? c : '${a['numero']}'.compareTo('${b['numero']}');
  });
  return out;
}

RefusTarif _refusUsage(String code, String dateEffet, List<Map<String, Object?>> usages, {required bool decision}) {
  final u = usages.first;
  return RefusTarif(
    'TARIF_DEJA_UTILISE',
    'La facture ${u['numero']} du ${_dateFr('${u['date']}')} porte déjà « $code »${usages.length > 1 ? ' (et ${usages.length - 1} autre(s) pièce(s) depuis cette date)' : ''}'
        ' : un prix qui prendrait effet le ${_dateFr(dateEffet)} changerait après coup ce que la pièce dit.',
    decision
        ? 'Refuser cette proposition (Non), puis la reproposer avec une date d’effet postérieure à la dernière pièce, ou émettre un avoir pour corriger la pièce.'
        : 'Choisir une date d’effet postérieure à la dernière pièce, ou émettre un avoir pour corriger la pièce.',
    usages: usages.take(5).toList(),
    nbPieces: usages.length,
  );
}

/// Les pièces de vente portant la prestation sur les [jours] derniers jours : l'information utile de l'alerte (ce que le changement touchera).
int tarPiecesRecentes(FicheTarif p, int jours, PiecesTarif pieces, {required String aujourdhui}) {
  final fin = DateTime.parse('${aujourdhui}T12:00:00');
  final debut = tarIso(fin.subtract(Duration(days: jours)));
  return tarUsages(p, debut, pieces, aujourdhui: aujourdhui).where((u) => '${u['date']}'.compareTo(aujourdhui) <= 0).length;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Proposer un prix
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// La demande d'une proposition : ce que l'écran ou l'import saisit.
class DemandeProposition {
  const DemandeProposition({
    required this.code,
    this.prixNonAssure,
    this.prixAssure,
    this.etatAssure,
    this.dateEffet,
    this.motif,
    this.datePassee = false,
    this.valider = false,
    this.creation,
    this.assurable,
    this.source,
    this.importJeu,
    this.importLot,
  });
  final String code;
  final Object? prixNonAssure;
  final Object? prixAssure;

  /// `montant`, `nc`, `manquant` ou `unique` (défaut : `montant`).
  final String? etatAssure;
  final String? dateEffet;
  final String? motif;

  /// La case « Date antérieure à aujourd'hui » : jamais silencieuse.
  final bool datePassee;

  /// « Valider » à la modale : la version naît `valide` en un geste, tracée avec le rôle de l'auteur (Q3, famille de décision seulement).
  final bool valider;

  /// Création d'une prestation : `{libelle, famille, secteur?, source?}`.
  final Map<String, Object?>? creation;
  final Object? assurable;

  /// La source du prix (grille, avenant) : posée sur la version quand elle est renseignée.
  final String? source;

  /// LOT 8B : la proposition naît d'un fichier d'import. Le jeu `tarifs` seul compte comme import de prix de prestation : la version porte l'origine `import`, la référence du lot,
  /// et son journal et son motif de décision le disent (« validation à l'import », « Validée à l'import IMP-… »).
  final String? importJeu;
  final String? importLot;
  bool get viaImport => importJeu == 'tarifs';
}

/// Ce qu'une proposition recevable donne à ÉCRIRE : la version, et l'identité de la prestation quand c'est une création.
class PropositionTarif {
  const PropositionTarif({required this.version, this.identite, required this.valideeEnUnGeste, required this.journalAction, required this.journalExtra});
  final FicheTarif version;
  final FicheTarif? identite;
  final bool valideeEnUnGeste;

  /// La ligne de journal de la transition (RG-12) : « Changement de prix : <action> ».
  final String journalAction;
  final Map<String, Object?> journalExtra;
  bool get creation => identite != null;
}

RefusTarif? _controleProposition(DemandeProposition o) {
  final etatA = o.etatAssure ?? 'montant';
  if (o.prixNonAssure == null || o.prixNonAssure == '') {
    return const RefusTarif('PRIX_ABSENT', 'Le prix non assuré est absent : un prix vide n’est pas un tarif, la ligne ne se facturerait pas.', 'Saisir le prix non assuré.');
  }
  final na = _nombre(o.prixNonAssure);
  if (na == 0) {
    return const RefusTarif('PRIX_ZERO', 'Un zéro n’est pas un tarif (arbitrage « plus aucun montant nul »).',
        'Saisir un prix strictement positif ; la gratuité passe par la remise motivée ou la prise en charge du personnel.');
  }
  if (!_entierPositif(na)) {
    return const RefusTarif('PRIX_INVALIDE', 'Le prix non assuré doit être un nombre entier de francs, strictement positif (le boîtier fiscal n’accepte que des montants entiers).',
        'Corriger le prix non assuré.');
  }
  if (!const ['montant', 'nc', 'manquant', 'unique'].contains(etatA)) {
    return const RefusTarif('ETAT_ASSURE_INCONNU', 'La colonne assurée est un montant, NON COUVERT, non renseignée ou sans objet.', 'Choisir l’un de ces états.');
  }
  if (etatA == 'montant') {
    if (o.prixAssure == null || o.prixAssure == '') {
      return const RefusTarif('PRIX_ABSENT', 'La colonne assurée annonce un montant, mais il est absent.', 'Saisir le prix assuré, ou choisir un autre état.');
    }
    final pa = _nombre(o.prixAssure);
    if (pa == 0) return const RefusTarif('PRIX_ZERO', 'Un zéro n’est pas un tarif (arbitrage « plus aucun montant nul »).', 'Saisir un prix strictement positif.');
    if (!_entierPositif(pa)) return const RefusTarif('PRIX_INVALIDE', 'Le prix assuré doit être un nombre entier de francs, strictement positif.', 'Corriger le prix assuré.');
  }
  if ((o.motif ?? '').trim().isEmpty) {
    return const RefusTarif('MOTIF_REQUIS', 'Un changement de prix se motive : sans motif, la Direction ne peut pas décider.', 'Saisir le motif du changement.');
  }
  return null;
}

/// LE CONTRÔLE DE LA DATE D'EFFET, UN SEUL EXEMPLAIRE (prestations et produits) : une date valide ; une date passée n'est permise qu'à la DAF et à la Direction, avec la case explicite
/// (jamais silencieuse) et le motif déjà exigé (`controleDateEffetTarif` de la maquette).
({RefusTarif? refus, bool passee}) _controleDateEffet(ContexteTarif cx, String? dateEffet, bool datePassee) {
  if (!tarJourValide(dateEffet)) {
    return (refus: const RefusTarif('DATE_EFFET_REQUISE', 'Un changement de prix prend effet à une date : sans date d’effet, on ne sait pas à partir de quand il s’applique.', 'Saisir la date d’effet.'), passee: false);
  }
  final passee = dateEffet!.compareTo(cx.aujourdhui) < 0;
  if (passee) {
    if (!datePassee) {
      return (
        refus: RefusTarif(
            'DATE_PASSEE',
            'La date d’effet ($dateEffet) est antérieure à aujourd’hui (${cx.aujourdhui}) : un prix ne se change pas dans le passé sans une décision expresse.',
            cx.peutDatePassee
                ? 'Cocher « Date antérieure à aujourd’hui » et motiver, ou choisir aujourd’hui ou une date future.'
                : 'Choisir aujourd’hui ou une date future : une date antérieure est une autorité de ${tarProfilsDatePassee(cx.libelles)}.'),
        passee: true
      );
    }
    if (!cx.peutDatePassee) {
      return (
        refus: RefusTarif('DATE_PASSEE_RESERVEE', 'Une date d’effet antérieure à aujourd’hui est une autorité de ${tarProfilsDatePassee(cx.libelles)}.',
            'Choisir aujourd’hui ou une date future, ou demander cette date à l’un de ces profils.'),
        passee: true
      );
    }
  }
  return (refus: null, passee: passee);
}


/// Propose une version de prix pour une prestation existante (ou, avec `creation`, crée la prestation et sa première version). Ne CHANGE RIEN au prix en vigueur : la
/// proposition ne prend effet qu'au Oui, à sa date d'effet. Rend ce qu'il faut écrire, ou un refus nommé.
ResultatTarif<PropositionTarif> tarProposer(ContexteTarif cx, DemandeProposition o) {
  ResultatTarif<PropositionTarif> non(RefusTarif r) => ResultatTarif.refuse(r);
  if (!cx.peutEditerEcran) {
    // Par un fichier, le droit est celui d'IMPORTER le jeu (le gestionnaire de stock importe des prix sans pouvoir éditer l'écran) : la phrase le dit.
    if (o.viaImport) {
      return non(const RefusTarif('PROPOSITION_RESERVEE', 'Proposer un prix par un fichier revient aux profils qui détiennent le droit d’importer le jeu « Importation des tarifs et prix ».',
          'Demander ce droit à l’administrateur (« Rôles & permissions », section Importation).'));
    }
    return non(const RefusTarif('PROPOSITION_RESERVEE', 'Proposer un prix se fait depuis « Tarifs et prix », par un profil qui peut modifier cet écran.',
        'Demander la modification à la Directrice Administrative ou à la Direction.'));
  }
  // VALIDER EN UN GESTE (PRD 5.4, Q3) : la liste de rôles de la famille décide, jamais le simple droit d'éditer ; le moteur refuse en nommant.
  if (o.valider && !cx.peutDecider) {
    return non(const RefusTarif('VALIDATION_RESERVEE', 'Valider un changement de prix est réservé aux rôles qui détiennent le droit « Décider un changement de prix » (fiche RBAC) : valider n’est pas modifier la fiche.',
        'Enregistrer le changement comme proposition : la décision revient à un rôle qui détient ce droit.'));
  }
  if (o.valider && cx.fileul) return non(tarRefusFileul());
  final h = cx.referentiel;
  if (h.vide) return non(const RefusTarif('REFERENTIEL_ABSENT', 'Le référentiel de prix n’est pas chargé.', 'Recharger la page.'));
  final p = h.parCode[o.code];
  if (o.creation != null) {
    if (p != null) {
      return non(RefusTarif('CODE_EXISTANT', 'Le code « ${o.code} » existe déjà au référentiel (code ou alias) : un code ne se réutilise pas.',
          'Choisir un autre code, ou proposer un changement de prix à la prestation existante.'));
    }
    // LOT TARIF-FIX : le code se compare NORMALISÉ (casse, espaces), dans les trois espaces, les alias et les prestations archivées.
    final pris = tarCodePris(h.tarifs, o.code);
    if (pris != null) {
      return non(RefusTarif(
          'CODE_EXISTANT',
          'Le code « ${o.code.trim()} » est déjà pris au référentiel par « ${pris['code']} » (${pris['libelle'] ?? pris['code']}${pris['statut'] == 'archive' ? ', archivée' : ''}) : un code ne se réutilise pas, même écrit autrement (casse, espaces).',
          'Choisir un autre code (pour un certificat : CERT- suivi du sigle de la pièce), ou proposer un changement de prix à la prestation existante.'));
    }
    if (o.code.trim().isEmpty || '${o.creation!['libelle'] ?? ''}'.trim().isEmpty) {
      return non(const RefusTarif('IDENTITE_INCOMPLETE', 'Une prestation porte un code et un libellé.', 'Renseigner le code et le libellé.'));
    }
  } else if (p == null) {
    return non(RefusTarif('PRESTATION_INTROUVABLE', 'Aucune prestation ne porte le code « ${o.code} ».', 'Choisir une prestation de la liste.'));
  }
  final refus = _controleProposition(o);
  if (refus != null) return non(refus);
  final cd = _controleDateEffet(cx, o.dateEffet, o.datePassee);
  if (cd.refus != null) return non(cd.refus!);
  final dateEffet = o.dateEffet!;
  final passee = cd.passee;
  final code = o.creation != null ? o.code.trim() : '${p!['code']}';
  final existantes = h.versionsDe(code);
  final enAttente = existantes.where((v) => v['statut'] == 'propose').firstOrNull;
  if (enAttente != null) {
    return non(RefusTarif('CHANGEMENT_EN_ATTENTE', 'Une proposition est déjà en attente de décision pour « $code » (version ${enAttente['version']}).',
        'La décider (Oui ou Non) ou la retirer avant d’en proposer une autre.'));
  }
  final etatA = o.etatAssure ?? 'montant';
  final na = _nombre(o.prixNonAssure).toInt();
  if (p != null) {
    final s = h.instantane(p, dateEffet);
    if (s != null && s.na == na && s.etatAssure == etatA && (etatA != 'montant' || s.pa == _nombre(o.prixAssure))) {
      return non(const RefusTarif('PRIX_INCHANGE', 'Ce prix est déjà celui en vigueur à cette date : rien à proposer.', 'Modifier au moins un des prix, ou ne rien changer.'));
    }
    final us = tarUsages(p, dateEffet, cx.pieces, aujourdhui: cx.aujourdhui);
    if (us.isNotEmpty) return non(_refusUsage(code, dateEffet, us, decision: false));
  }
  final rang = existantes.fold<int>(0, (m, v) => ((v['version'] as num?) ?? 0).toInt() > m ? ((v['version'] as num).toInt()) : m) + 1;
  FicheTarif? identite;
  if (o.creation != null) {
    final c = o.creation!;
    final famille = '${c['famille']}';
    identite = {'id': code, 'code': code, 'libelle': '${c['libelle']}'.trim(), 'famille': famille, 'statut': 'actif'};
    if (c['secteur'] != null && c['secteur'] != '') identite['secteur'] = c['secteur'];
    if (c['source'] != null && c['source'] != '') identite['source'] = c['source'];
    if (famille == 'ACTE' || famille == 'HOSPITALISATION') {
      identite['codeActe'] = code;
    } else if (famille == 'LABO') {
      identite['codeAnalyse'] = code;
    } else {
      identite['codeGrille'] = code;
    }
    if (o.assurable != null) identite['assurable'] = o.assurable;
  }
  final v = <String, Object?>{
    'id': '$code@$dateEffet@$rang',
    'code': code,
    'version': rang,
    'dateEffet': dateEffet,
    'prixNonAssure': na,
    if (etatA == 'montant') 'prixAssure': _nombre(o.prixAssure).toInt(),
    'etatAssure': etatA,
    'motif': o.motif!.trim(),
    'origine': o.viaImport ? 'import' : 'ecran',
    'statut': 'propose',
    'proposePar': cx.auteur,
    'proposeLe': cx.aujourdhui,
    'proposeRole': cx.role,
  };
  if (o.viaImport && (o.importLot ?? '').isNotEmpty) v['lot'] = o.importLot;
  if ((o.source ?? '').trim().isNotEmpty) v['source'] = o.source!.trim();
  if (passee) v['datePassee'] = true;
  if (o.valider) {
    // Née VALIDE en un geste, avec le rôle de l'auteur tracé : la correction de la DAF n'attend pas la Direction.
    v['statut'] = 'valide';
    v['decidePar'] = v['proposePar'];
    v['decideLe'] = v['proposeLe'];
    v['roleDecision'] = v['proposeRole'];
    v['motifDecision'] = o.viaImport ? 'Validée à l’import ${o.importLot ?? ''}' : 'Validée en un geste à la saisie';
  }
  return ResultatTarif.ok(PropositionTarif(
    version: v,
    identite: identite,
    valideeEnUnGeste: o.valider,
    journalAction: o.viaImport ? (o.valider ? 'validation à l’import' : 'proposition à l’import') : (o.valider ? 'validation en un geste' : 'proposition'),
    journalExtra: _extraJournal(v, {'motif': v['motif'], 'role': v['proposeRole']}),
  ));
}

/// L'extrait de journal d'une transition (le journal est plafonné : le MOTIF d'abord, tronqué à 36 caractères ; l'historique d'un prix vit dans `versionsTarif`).
Map<String, Object?> _extraJournal(FicheTarif v, Map<String, Object?> extra) {
  final e = {...extra};
  if (e['motif'] != null) e['motif'] = '${e['motif']}'.length > 36 ? '${e['motif']}'.substring(0, 36) : '${e['motif']}';
  return {...e, 'v': v['version'], 'na': v['prixNonAssure'], 'pa': v['prixAssure'], 'du': v['dateEffet']};
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Décider une proposition (Oui ou Non) et la retirer
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Ce qu'une décision recevable donne à ÉCRIRE : le correctif de la version (statut, décideur, date), la version telle qu'elle devient, le retour à l'auteur.
class DecisionTarif {
  const DecisionTarif({required this.versionId, required this.decision, required this.patch, required this.version, required this.journalAction, required this.journalExtra, this.notification, this.leverMarquage = false});
  final String versionId;

  /// `oui` ou `non`.
  final String decision;
  final Map<String, Object?> patch;
  final FicheTarif version;
  final String journalAction;
  final Map<String, Object?> journalExtra;

  /// Le retour à l'auteur (« votre changement de prix a été accepté ou refusé ») : `null` quand l'auteur décide lui-même.
  final Map<String, Object?>? notification;

  /// Le Oui LÈVE le marquage « tarif d'attente » (fiche de lecture de l'acte ou de l'analyse, versions marquées provisoires de la prestation).
  final bool leverMarquage;
}

/// Décide une proposition : Oui (elle devient la version en vigueur à sa date d'effet) ou Non (refusée, motif obligatoire).
ResultatTarif<DecisionTarif> tarDecider(ContexteTarif cx, String versionId, String decision, {String? motif, String? dateEffet}) {
  ResultatTarif<DecisionTarif> non(RefusTarif r) => ResultatTarif.refuse(r);
  if (!cx.peutDecider) {
    return non(const RefusTarif('VALIDATION_RESERVEE', 'Décider d’un changement de prix est réservé aux rôles qui détiennent le droit « Décider un changement de prix » (fiche RBAC) : valider n’est pas modifier la fiche.',
        'Demander la décision à un rôle qui détient ce droit.'));
  }
  // DAF = la mère (T11, 11/11/2026) : la décision est une écriture de configuration, tenue par la mère.
  if (cx.fileul) return non(tarRefusFileul());
  if (decision != 'oui' && decision != 'non') return non(const RefusTarif('DECISION_INCONNUE', 'La décision est Oui ou Non.', 'Choisir Oui ou Non.'));
  final v = cx.referentiel.versions.where((x) => x['id'] == versionId).firstOrNull;
  if (v == null) return non(RefusTarif('VERSION_INTROUVABLE', 'Aucune version ne porte l’identifiant « $versionId ».', 'Actualiser la liste des alertes.'));
  if (v['statut'] != 'propose') {
    return non(RefusTarif('DEJA_DECIDEE', 'Cette version est déjà « ${v['statut']} » : une décision ne se rejoue pas.', 'Proposer une nouvelle version si le prix doit encore changer.'));
  }
  final m = (motif ?? '').trim();
  final patch = <String, Object?>{'decidePar': cx.auteur, 'decideLe': cx.aujourdhui, 'roleDecision': cx.role};
  if (m.isNotEmpty) patch['motifDecision'] = m;
  if (decision == 'non') {
    if (m.isEmpty) {
      return non(const RefusTarif('MOTIF_REQUIS', 'Un refus se motive : le service doit pouvoir lire pourquoi le changement n’est pas appliqué.', 'Saisir le motif du refus.'));
    }
    patch['statut'] = 'refuse';
  } else {
    if (v['prixNonAssure'] == null || v['etatNonAssure'] == 'manquant') {
      return non(const RefusTarif('TARIF_ABSENT', 'Cette version ne porte pas de prix non assuré : elle ne se valide pas.', 'La refuser, puis proposer une version chiffrée.'));
    }
    final date = (v['dateEffet'] as String?) ?? dateEffet;
    if (!tarJourValide(date)) {
      return non(const RefusTarif('DATE_EFFET_REQUISE', 'Cette proposition n’a pas de date d’effet : la décision la fixe.', 'Saisir la date d’effet avec le Oui.'));
    }
    if (date!.compareTo(cx.aujourdhui) < 0) {
      // La date a été dépassée PENDANT l'attente, ou la proposition était datée du passé : aucun décalage automatique (PRD 5.6). Une date passée proposée
      // expressément par la DAF ou la Direction se décide par elles seules.
      if (v['datePassee'] != true) {
        return non(RefusTarif('DATE_PASSEE', 'La date d’effet ($date) est antérieure à aujourd’hui : la proposition a attendu au-delà de sa date, et un prix ne se change pas dans le passé.',
            'Refuser cette proposition (Non), puis la reproposer avec une date d’effet d’aujourd’hui.'));
      }
      if (!cx.peutDatePassee) {
        return non(RefusTarif('DATE_PASSEE_RESERVEE', 'Une date d’effet antérieure à aujourd’hui se décide par ${tarProfilsDatePassee(cx.libelles)}.', 'Demander la décision à l’un de ces profils.'));
      }
    }
    // Le contrôle d'usage est REJOUÉ au Oui : une pièce a pu être émise pendant l'attente.
    final pp = cx.referentiel.parCode['${v['code']}'];
    if (pp != null) {
      final us = tarUsages(pp, date, cx.pieces, aujourdhui: cx.aujourdhui);
      if (us.isNotEmpty) return non(_refusUsage('${v['code']}', date, us, decision: true));
    }
    patch['statut'] = 'valide';
    if (v['dateEffet'] == null) patch['dateEffet'] = date;
  }
  final apres = {...v, ...patch};
  Map<String, Object?>? notif;
  if (v['proposeRole'] != null && v['proposePar'] != null && v['proposePar'] != cx.auteur) {
    // LE RETOUR À L'AUTEUR : « votre changement de prix a été accepté ou refusé, motif ». Une alerte dérivée ne peut pas porter un retour.
    notif = {
      'type': 'prix_decide',
      'poste': v['proposeRole'],
      'destinataire': v['proposePar'],
      'reference': v['code'],
      'ecran': 'cfg-tarifs',
      'priorite': decision == 'non' ? 'haute' : 'normale',
      'libelle': 'Votre changement de prix ${v['code']} a été ${decision == 'oui' ? 'accepté' : 'refusé'}',
      'detail': '${decision == 'oui' ? 'Il prend effet le ${_dateFr('${patch['dateEffet'] ?? v['dateEffet']}')}.' : 'Motif : $m.'} Décidé par ${cx.auteur}.',
    };
  }
  return ResultatTarif.ok(DecisionTarif(
    versionId: versionId,
    decision: decision,
    patch: patch,
    version: apres,
    journalAction: decision == 'oui' ? 'validation' : 'refus',
    journalExtra: _extraJournal(v, {'motif': m.isEmpty ? null : m, 'role': cx.role}),
    notification: notif,
    leverMarquage: decision == 'oui',
  ));
}

/// Retire une proposition en attente (son auteur, ou un profil qui décide) : elle reste lisible à l'historique (RG-14).
ResultatTarif<DecisionTarif> tarRetirer(ContexteTarif cx, String versionId, String? motif) {
  ResultatTarif<DecisionTarif> non(RefusTarif r) => ResultatTarif.refuse(r);
  final v = cx.referentiel.versions.where((x) => x['id'] == versionId).firstOrNull;
  if (v == null) return non(RefusTarif('VERSION_INTROUVABLE', 'Aucune version ne porte l’identifiant « $versionId ».', 'Actualiser la liste.'));
  if (v['statut'] != 'propose') return non(const RefusTarif('DEJA_DECIDEE', 'Seule une proposition en attente se retire.', 'Une version décidée se remplace par une nouvelle version.'));
  if (v['proposePar'] != cx.auteur && !cx.peutDecider) {
    return non(const RefusTarif('RETRAIT_RESERVE', 'Une proposition se retire par son auteur, ou par un profil qui décide.', 'Demander le retrait à son auteur.'));
  }
  final patch = <String, Object?>{
    'statut': 'retire',
    'decidePar': cx.auteur,
    'decideLe': cx.aujourdhui,
    'roleDecision': cx.role,
    'motifDecision': (motif == null || motif.isEmpty) ? 'Retirée par son auteur' : motif,
  };
  return ResultatTarif.ok(DecisionTarif(
    versionId: versionId,
    decision: 'retrait',
    patch: patch,
    version: {...v, ...patch},
    journalAction: 'retrait',
    journalExtra: _extraJournal(v, {'motif': (motif == null || motif.isEmpty) ? null : motif, 'role': cx.role}),
  ));
}

/// Le seuil de variation signalée lu de la base (`null` : aucune valeur arrêtée, aucun seuil).
double? tarSeuilVariation(Object? valeur) {
  final x = valeur is num ? valeur.toDouble() : (valeur is String ? double.tryParse(valeur) : null);
  return (x != null && x.isFinite && x > 0) ? x : null;
}

/// La variation en pourcentage d'une proposition par rapport à ce qui est en vigueur à sa date d'effet (à un chiffre après la virgule), ou `null`.
double? tarVariationPct(ReferentielTarifs h, FicheTarif v, String aujourdhui) {
  final p = h.parCode['${v['code']}'];
  final s = p == null ? null : h.instantane(p, (v['dateEffet'] as String?) ?? aujourdhui);
  if (s == null || s.na == null || s.na == 0 || v['prixNonAssure'] == null || v['etatNonAssure'] == 'manquant') return null;
  final x = ((v['prixNonAssure'] as num) - s.na!) / s.na! * 1000;
  return (x + 0.5).floorToDouble() / 10; // `Math.round` : la moitié s'arrondit vers le haut, négatifs compris
}

/// Le résultat d'un « Oui à tout ».
class DecisionEnBloc {
  const DecisionEnBloc({required this.acceptees, required this.refusees, required this.exclues});
  final List<Map<String, Object?>> acceptees;
  final List<Map<String, Object?>> refusees;
  final List<Map<String, Object?>> exclues;
}

/// « Oui à tout », ENCADRÉ (PRD 5.3, Q8) : décide Oui chaque proposition de la liste, JAMAIS sans que la comparaison ligne à ligne ait été affichée. Chaque ligne passe par
/// la décision ordinaire ([tarDecider] : contrôle d'usage, date, droit) ; celles qui ne passent pas sont NOMMÉES avec leur refus. Comme chaque décision change le
/// référentiel, [contexte] est relu avant chaque ligne et [appliquer] écrit la décision.
ResultatTarif<DecisionEnBloc> tarDeciderTous(
  ContexteTarif Function() contexte, {
  required bool comparaisonAffichee,
  required void Function(DecisionTarif) appliquer,
  List<String>? ids,
  String? dateEffet,
  double? seuil,
}) {
  final cx0 = contexte();
  if (!cx0.peutDecider) {
    return const ResultatTarif.refuse(RefusTarif('VALIDATION_RESERVEE', 'Décider d’un changement de prix est réservé aux rôles qui détiennent le droit « Décider un changement de prix » (fiche RBAC) : valider n’est pas modifier la fiche.',
        'Demander la décision à un rôle qui détient ce droit.'));
  }
  if (cx0.fileul) return ResultatTarif.refuse(tarRefusFileul());
  if (!comparaisonAffichee) {
    return const ResultatTarif.refuse(RefusTarif('COMPARAISON_REQUISE', 'Un « Oui à tout » ne se donne qu’après l’affichage de la comparaison ligne à ligne (ancien prix, nouveau prix, variation).',
        'Ouvrir la comparaison, la lire, puis confirmer.'));
  }
  final liste = ids ?? [for (final v in cx0.referentiel.versions) if (v['statut'] == 'propose') '${v['id']}'];
  final acceptees = <Map<String, Object?>>[];
  final refusees = <Map<String, Object?>>[];
  final exclues = <Map<String, Object?>>[];
  for (final id in liste) {
    final cx = contexte();
    final v = cx.referentiel.versions.where((x) => x['id'] == id).firstOrNull;
    if (v == null || v['statut'] != 'propose') {
      refusees.add({'id': id, 'code': v?['code'], 'refus': 'DEJA_DECIDEE', 'motif': 'Cette version n’est plus en attente.'});
      continue;
    }
    final pct = tarVariationPct(cx.referentiel, v, cx.aujourdhui);
    if (seuil != null && pct != null && pct.abs() > seuil) {
      exclues.add({'id': id, 'code': v['code'], 'variation': pct, 'motif': 'Variation de $pct % au-delà du seuil signalé ($seuil %) : à décider seule.'});
      continue;
    }
    final r = tarDecider(cx, id, 'oui', dateEffet: dateEffet);
    if (r.ok) {
      appliquer(r.valeur!);
      acceptees.add({'id': id, 'code': v['code']});
    } else {
      refusees.add({'id': id, 'code': v['code'], 'refus': r.refus!.code, 'motif': r.refus!.motif, 'geste': r.refus!.geste});
    }
  }
  return ResultatTarif.ok(DecisionEnBloc(acceptees: acceptees, refusees: refusees, exclues: exclues));
}

/// Les versions de la prestation marquées « provisoires » et valides, que le Oui d'une version arrête : [(id, correctif)] (`provisoire` levé, date et auteur).
List<(String, Map<String, Object?>)> tarLeverProvisoire(ReferentielTarifs h, String code, {required String qui, required String jour}) => [
      for (final x in h.versionsDe(code))
        if (x['provisoire'] == true && x['statut'] == 'valide') ('${x['id']}', {'provisoire': false, 'arreteLe': jour, 'arretePar': qui})
    ];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La pro-forma à la conversion (T5, Direction, 11/11/2026)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// La durée de validité d'une pro-forma lue de la base : un entier de 0 à 365, sinon le défaut (30 jours proposés, « à valider »).
int tarValiditeProformaJours(Object? reglage) {
  final x = reglage is num ? reglage.toDouble() : (reglage is String ? double.tryParse(reglage) : null);
  return (x != null && x.isFinite && x == x.floorToDouble() && x >= tarValiditeProformaMin && x <= tarValiditeProformaMax) ? x.toInt() : tarValiditeProformaDefaut;
}

/// Le réglage de la durée de validité : réservé aux profils de la famille de décision ; refuse en nommant une durée illisible. Rend (jours, avant).
ResultatTarif<({int jours, int avant})> tarDefinirValiditeProforma(ContexteTarif cx, Object? jours, {required Object? reglageActuel}) {
  if (!cx.peutDecider) {
    return const ResultatTarif.refuse(RefusTarif('REGLAGE_RESERVE', 'La durée de validité d’une pro-forma se règle par un rôle qui détient le droit « Décider un changement de prix » (fiche RBAC).',
        'Demander le réglage à un rôle qui détient ce droit.'));
  }
  final j = jours is num ? jours.toDouble() : (jours is String && jours.trim().isNotEmpty ? double.tryParse(jours.trim()) : null);
  if (j == null || !j.isFinite || j != j.floorToDouble() || j < tarValiditeProformaMin || j > tarValiditeProformaMax) {
    return const ResultatTarif.refuse(RefusTarif('DUREE_INVALIDE', 'La durée de validité est un nombre entier de jours, de $tarValiditeProformaMin à $tarValiditeProformaMax.', 'Saisir un nombre entier de jours.'));
  }
  return ResultatTarif.ok((jours: j.toInt(), avant: tarValiditeProformaJours(reglageActuel)));
}

/// L'écart d'une pro-forma à la conversion, ligne par ligne : le prix de la pro-forma, le prix du jour, l'écart et le prix retenu (dans la durée de validité, le prix de la
/// pro-forma est tenu ; au-delà, le prix du jour). N'écrit aucune pièce. [assureA] dit si la carte du patient est valide au jour de la conversion (RG-09).
ResultatTarif<Map<String, Object?>> tarEcartProforma(
  FicheTarif? f, {
  required ReferentielTarifs referentiel,
  required PiecesTarif pieces,
  required String aujourdhui,
  required int validiteJours,
  required bool Function(String jourConversion) assureA,
  String? dateConversion,
}) {
  if (f == null) return const ResultatTarif.refuse(RefusTarif('FACTURE_INTROUVABLE', 'Aucune facture ne porte cet identifiant.', 'Choisir une pro-forma de la liste.'));
  if (f['proforma'] == null || f['proforma'] == false) {
    return ResultatTarif.refuse(RefusTarif('PAS_UNE_PROFORMA', 'La pièce ${f['numero']} est une vente : elle garde son prix (une pièce émise ne se réécrit pas).', 'Choisir une pro-forma.'));
  }
  final conv = (dateConversion != null && dateConversion.isNotEmpty) ? tarJourDe(dateConversion, aujourdhui) : aujourdhui;
  final jourPro = tarJourDe(f['date'], aujourdhui);
  final age = joursEntre(DateTime.utc(int.parse(jourPro.substring(0, 4)), int.parse(jourPro.substring(5, 7)), int.parse(jourPro.substring(8, 10))),
      DateTime.utc(int.parse(conv.substring(0, 4)), int.parse(conv.substring(5, 7)), int.parse(conv.substring(8, 10))));
  final regle = age <= validiteJours ? 'prix_de_la_proforma' : 'prix_du_jour';
  final assure = assureA(conv);
  final analyses = {
    for (final d in pieces.demandesAnalyses)
      if (d['analyseCode'] != null) '${d['id']}': '${d['analyseCode']}'
  };
  final imageries = {
    for (final d in pieces.demandesImagerie)
      if (d['examenCode'] != null) '${d['id']}': '${d['examenCode']}'
  };
  num ecartTotal = 0;
  final lignes = <Map<String, Object?>>[];
  for (final l0 in (f['lignes'] as List? ?? const [])) {
    final l = (l0 as Map).cast<String, Object?>();
    final String? code = l['acteCode'] != null && l['acteCode'] != ''
        ? '${l['acteCode']}'
        : (l['demandeId'] != null ? analyses['${l['demandeId']}'] : null) ?? (l['demandeImagerieId'] != null ? imageries['${l['demandeImagerieId']}'] : null);
    final ancien = l['prixUnitaire'] as num?;
    final q = (l['quantite'] as num?) ?? 1;
    final t = code != null ? referentiel.aLaDate(code, conv, assure, aujourdhui: aujourdhui) : null;
    final num? nouveau = (t != null && !t.absent && t.montant != null) ? t.montant : null;
    final retenu = (regle == 'prix_du_jour' && nouveau != null) ? nouveau : ancien;
    final ecart = (nouveau != null && ancien != null) ? (nouveau - ancien) * q : 0;
    ecartTotal += ecart;
    lignes.add({
      'id': l['id'],
      'designation': l['designation'],
      'code': code,
      'quantite': q,
      'ancien': ancien,
      'nouveau': nouveau,
      'retenu': retenu,
      'ecart': ecart,
      'sansTarif': nouveau == null ? (code != null ? 'prix du jour absent du référentiel' : 'ligne sans prestation tarifée (médicament au prix d’achat, RG-02)') : null,
    });
  }
  return ResultatTarif.ok({
    'ok': true,
    'factureId': f['id'],
    'numero': f['numero'],
    'jourProforma': jourPro,
    'jourConversion': conv,
    'ageJours': age,
    'validiteJours': validiteJours,
    'regle': regle,
    'assure': assure,
    'lignes': lignes,
    'ecartTotal': ecartTotal,
  });
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les gardes du magasin : une version est IMMUABLE, les listes de lecture ne s'éditent plus pour un prix
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les champs qu'une version ne change jamais (une correction AJOUTE une version).
const List<String> tarChampsImmuables = ['code', 'version', 'prixNonAssure', 'etatNonAssure', 'prixAssure', 'etatAssure', 'origine', 'proposePar', 'proposeLe', 'lot'];

/// Les champs de PRIX des trois collections de lecture (`actes`, `analyses`, `catalogueTarifs`), projections du référentiel : le moteur les reconstruit, l'agent ne les écrit pas.
const Map<String, List<String>> tarChampsPrixLecture = {
  'actes': ['prix', 'prixNonAssure', 'prixAssure', 'nonCouvert'],
  'analyses': ['prix'],
  'catalogueTarifs': ['prixNonAssure', 'prixAssure', 'nonCouvert', 'prixAValider'],
};

bool _memeValeur(Object? a, Object? b) => (a == null && b == null) || a == b;

/// Le motif du refus d'une écriture sur `versionsTarif` (RG-14 : le prix d'une pièce émise doit pouvoir se relire), ou `null`. [apres] est la fiche telle qu'elle serait
/// après l'écriture, [avant] celle qui existe (ou `null`). Seules passent : l'insertion d'une version neuve, la décision d'une proposition (statut, décideur, motif, date
/// d'effet d'une proposition « à dater »), et l'arrêt du marquage « tarif d'attente » d'une version.
String? tarGardeVersion(String operation, FicheTarif apres, FicheTarif? avant) {
  if (operation == 'archiver') {
    return 'Une version de prix ne s’archive pas : elle se REFUSE ou se RETIRE, et reste lisible (RG-14 : le prix d’une pièce émise doit pouvoir se relire).';
  }
  if (operation == 'inserer') {
    return avant != null ? 'La version « ${apres['id']} » existe déjà : une version ne se réécrit pas.' : null;
  }
  if (operation != 'modifier' || avant == null) return null;
  for (final k in tarChampsImmuables) {
    if (!_memeValeur(avant[k], apres[k])) return 'Une version de prix est IMMUABLE (champ « $k ») : une correction AJOUTE une version, elle ne réécrit pas l’ancienne.';
  }
  if (avant['statut'] != apres['statut'] && !(avant['statut'] == 'propose' && const ['valide', 'refuse', 'retire'].contains(apres['statut']))) {
    return 'Une version « ${avant['statut']} » ne devient pas « ${apres['statut']} » : seule une proposition se décide ; une version validée se remplace par une nouvelle version.';
  }
  if (!_memeValeur(avant['dateEffet'], apres['dateEffet']) && !(avant['aDater'] == true && apres['statut'] == 'valide')) {
    return 'La date d’effet d’une version est immuable (seule la décision d’une proposition « à dater » la fixe).';
  }
  return null;
}

/// Le motif du refus d'un PRIX écrit dans une liste de lecture (`actes`, `analyses`, `catalogueTarifs`), ou `null`. Le libellé, l'échantillon, le délai et les marquages
/// restent libres. Sans référentiel chargé, aucune garde (la liste reste la seule source).
String? tarGardeLecture(String collection, String operation, FicheTarif apres, FicheTarif? avant, {required bool referentielPresent}) {
  if (operation != 'modifier' || !referentielPresent || avant == null) return null;
  for (final k in tarChampsPrixLecture[collection] ?? const <String>[]) {
    if (!_memeValeur(avant[k], apres[k])) {
      return 'Le prix (« $k ») ne se modifie plus dans cette liste : elle reflète le référentiel de prix. Le proposer à l’écran « Tarifs et prix » (Oui ou Non, date d’effet).';
    }
  }
  return null;
}
