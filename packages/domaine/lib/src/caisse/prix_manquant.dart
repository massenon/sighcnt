/// LOT TARIF-FIX-2 (décision de la Direction du 16/11/2026, section AL point 2) : PRESCRIRE TOUJOURS, BLOQUER SEULEMENT L'ENCAISSEMENT.
///
/// Port de `prototype_html/assets/js/parcours.js` (bloc « LOT TARIF-FIX-2 » : `manqueDePrix`, `partsLigne`, `totauxPiece`, `refusEncaissementPrix`,
/// `encaissementPartielALaDate`, `valoriserFacture`). Vecteurs : `test/vecteurs/prix_manquant.json` (`prototype_html/build/vecteurs-prix-manquant.js`, tirés
/// de la maquette ouverte dans Chrome).
///
/// Une ligne sans prix porte `prixManquant` (nature, code, libellé, cause, motif, geste) : « prix à valoriser » pour un médicament sans prix d'achat,
/// « prix à définir » pour un acte, une analyse, un examen d'imagerie ou un soin. Jamais 0 : prix, montant et parts NULS, total de la pièce NUL (non
/// calculable). Seul l'encaissement d'une ligne sans prix est refusé (`ENCAISSEMENT_PRIX_MANQUANT`) ; par défaut la pièce entière attend (réglage de
/// clinique en base, versionné par date, défaut semé « non », proposition à valider). Dès qu'un prix est en vigueur à la DATE DE LA PIÈCE, la ligne se
/// valorise (colonne et taux décidés à la prescription).
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import '../tarifs/tarifs.dart';

const codeRefusEncaissementPrix = 'ENCAISSEMENT_PRIX_MANQUANT';

/// La clé du réglage de clinique au poste (collection `parametres`, versionnée par date, défaut semé « non »). La maquette le porte dans `_reglages`
/// (`caisseEncaissementPartielSansPrix`).
const cleEncaissementPartielSansPrix = 'caisse.encaissementPartielSansPrix';
const natureManquePrixAchat = 'prix_achat';
const natureManqueTarif = 'tarif';

const gestePrixAchat =
    'Changer le prix d’achat au « Référentiel produits » (ou proposer le premier prix dans « Tarifs et prix », liste « Produits à valoriser »), puis le faire décider (Oui).';
const gesteProposerPrix = 'Proposer le prix dans « Tarifs et prix », puis le faire décider (Oui).';

/// Le défaut SEMÉ du réglage « encaissement partiel d'une pièce en attente de prix » (proposition à valider, section AM) : la pièce entière attend.
const List<Map<String, Object?>> encaissementPartielSeme = [
  {'valeur': 'non', 'dateEffet': '2026-01-01', 'source': 'Défaut semé : la pièce entière attend le prix (proposition à valider, section AM)', 'par': 'semence'},
];

/// `manqueDePrix(nature, code, libelle, r)` : ce qui manque à une ligne. Aucune donnée de santé : le code et le libellé seuls.
/// [cause], [motif], [geste], [effectifLe] : ceux de la lecture du prix (`prixDeLigne`, `prixProduitALaDate`) quand elle les porte.
Map<String, Object?> manqueDePrix(String nature, Object? code, Object? libelle,
    {String? cause, String? motif, String? geste, String? effectifLe, String? voie, String? tarifCode}) {
  final c = code == null ? '' : '$code';
  final lib = (libelle == null || libelle == '') ? (c.isEmpty ? '' : c) : '$libelle';
  final m = <String, Object?>{
    'nature': nature,
    'code': c,
    'libelle': lib,
    'cause': cause ?? (nature == natureManquePrixAchat ? 'prix-achat-absent' : 'sans-version'),
  };
  if (nature == natureManquePrixAchat) {
    final brut = (motif == null || motif.isEmpty) ? 'prix d’achat non renseigné' : motif;
    final net = brut.replaceFirst(RegExp(r'\s*:\s*l’article ne se facture jamais à zéro\.?$'), '').replaceFirst(RegExp(r'\.$'), '');
    m['motif'] = '« $c » $lib : prix à valoriser ($net)';
    m['geste'] = gestePrixAchat;
  } else {
    m['motif'] = (motif == null || motif.isEmpty) ? '« $c » $lib : prix à définir' : motif;
    m['geste'] = (geste == null || geste.isEmpty) ? gesteProposerPrix : geste;
  }
  if (effectifLe != null) m['effectifLe'] = effectifLe;
  if (voie != null) m['voie'] = voie;
  if (tarifCode != null) m['tarifCode'] = tarifCode;
  return m;
}

/// Le manque d'une ligne de prescription d'acte ou d'analyse, depuis la lecture du référentiel ([LignePrix] non `ok`).
Map<String, Object?> manqueDepuisLignePrix(LignePrix r, Object? code, Object? libelle, {required String voie, String? tarifCode}) =>
    manqueDePrix(natureManqueTarif, code, libelle, cause: r.cause, motif: r.motif, geste: r.geste, effectifLe: r.effectifLe, voie: voie, tarifCode: tarifCode);

bool ligneSansPrix(Map<String, Object?>? l) => l != null && l['prixManquant'] != null;

/// Les lignes sans prix encore dues d'une pièce.
List<Map<String, Object?>> lignesPrixManquant(Map<String, Object?> facture) => [
      for (final l in ((facture['lignes'] ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()))
        if (ligneSansPrix(l) && l['statutPaiement'] != 'paye') l
    ];

/// Les parts d'une ligne valorisée : même arithmétique que la construction des lignes (pas de remise).
({num partAssureur, num partPersonnel, num partPatient}) partsLigne(num montant, num taux, bool estAgent) {
  final pa = estAgent ? 0 : arrondiJs((montant * taux / 100).toDouble()).toInt();
  final pp = estAgent ? montant : 0;
  return (partAssureur: pa, partPersonnel: pp, partPatient: montant - pa - pp);
}

num _somme(Iterable<Map<String, Object?>> l, String k) => l.fold<num>(0, (a, x) => a + nombreOuZero(x[k]));

/// Les totaux d'une pièce : la somme des lignes, ou NULS (non calculable) tant qu'une ligne est sans prix. `enAttentePrix` n'est porté que s'il est vrai.
Map<String, Object?> totauxPiece(List<Map<String, Object?>> lignes) {
  if (lignes.any(ligneSansPrix)) {
    return {
      'montantHT': null,
      'montantTTC': null,
      'montantBrut': null,
      'partAssurance': null,
      'partPersonnel': null,
      'partPatient': null,
      'reliquat': null,
      'enAttentePrix': true,
    };
  }
  return {
    'montantHT': _somme(lignes, 'montant'),
    'montantTTC': _somme(lignes, 'montant'),
    'montantBrut': _somme(lignes, 'montantBrut'),
    'partAssurance': _somme(lignes, 'partAssureur'),
    'partPersonnel': _somme(lignes, 'partPersonnel'),
    'partPatient': _somme(lignes, 'partPatient'),
    'reliquat': _somme(lignes.where((l) => l['statutPaiement'] != 'paye'), 'partPatient'),
  };
}

/// Le réglage à la date : `valeur` (« oui » | « non »), `partiel`, `dateEffet`, `version`, `source`. [versions] : la liste stockée, vide ou nulle = défaut semé.
({String valeur, bool partiel, String dateEffet, int version, String? source}) encaissementPartielALaDate(List<Map<String, Object?>>? versions, String jour) {
  final toutes = [...((versions == null || versions.isEmpty) ? encaissementPartielSeme : versions)]
    ..sort((a, b) => '${a['dateEffet']}'.compareTo('${b['dateEffet']}'));
  final couvrantes = toutes.where((x) => '${x['dateEffet']}'.compareTo(jour) <= 0).toList();
  final v = couvrantes.isNotEmpty ? couvrantes.last : toutes.first;
  final oui = v['valeur'] == 'oui';
  return (valeur: oui ? 'oui' : 'non', partiel: oui, dateEffet: '${v['dateEffet']}', version: toutes.indexOf(v) + 1, source: v['source'] as String?);
}

String _dateFrJour(String jour) {
  final p = jour.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : jour;
}

/// Le refus NOMMÉ d'un encaissement qui toucherait une ligne sans prix (`refusEncaissementPrix`). [aujourdhui] : jour de repli si la pièce n'a pas de date.
({String code, String motif, String geste, List<Map<String, Object?>> lignes, bool partiel}) refusEncaissementPrix(
    Map<String, Object?> facture, List<Map<String, Object?>> manques, bool partiel,
    {required String aujourdhui}) {
  final fr = _dateFrJour(tarJourDe(facture['date'], aujourdhui));
  final ref = (facture['numero'] != null && facture['numero'] != '') ? facture['numero'] : facture['id'];
  final motif = 'La pièce $ref porte ${manques.length > 1 ? '${manques.length} lignes' : 'une ligne'} sans prix : '
      '${manques.map((m) => m['motif']).join(' ; ')}. '
      '${partiel ? 'Une ligne sans prix ne s’encaisse pas ; le reste de la pièce peut s’encaisser (réglage de la clinique).' : 'Elle ne s’encaisse pas tant que ce prix n’est pas posé : la pièce entière attend le prix (réglage de la clinique).'}';
  final geste = '${manques.first['geste']} La ligne se lit à la date de la pièce ($fr) : il faut un prix en vigueur ce jour-là (date d’effet du $fr au plus tard), puis rouvrir l’encaissement.';
  return (code: codeRefusEncaissementPrix, motif: motif, geste: geste, lignes: manques, partiel: partiel);
}

/// Le prix d'une ligne en attente, lu à la DATE DE LA PIÈCE par l'appelant : soit un prix (`ok`), soit le manque mis à jour.
typedef PrixEnAttente = ({bool ok, num? prixUnitaire, num? montant, int? version, Map<String, Object?>? manque});

/// VALORISE les lignes sans prix d'une pièce (`valoriserFacture`, cœur pur) : [lire] rend le prix de la ligne à la date de la pièce. Une ligne réglée n'est
/// jamais touchée. Rend la pièce mise à jour (lignes et totaux), les lignes valorisées et les manques restants. [maintenant] : ISO de la valorisation.
({Map<String, Object?> facture, List<Map<String, Object?>> valorisees, List<Map<String, Object?>> restantes, bool change}) valoriserLignes(
    Map<String, Object?> facture, PrixEnAttente Function(Map<String, Object?> ligne) lire,
    {required String maintenant, required String aujourdhui}) {
  final lignes0 = ((facture['lignes'] ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()).toList();
  if (!lignes0.any(ligneSansPrix)) return (facture: facture, valorisees: const [], restantes: const [], change: false);
  final estAgent = facture['personnelId'] != null && facture['personnelId'] != '';
  final taux = nombreOuZero(facture['tauxPriseEnCharge']);
  final valorisees = <Map<String, Object?>>[], restantes = <Map<String, Object?>>[];
  var change = false;
  final lignes = <Map<String, Object?>>[];
  for (final l in lignes0) {
    if (!ligneSansPrix(l) || l['statutPaiement'] == 'paye') {
      lignes.add(l);
      continue;
    }
    final r = lire(l);
    final m0 = (l['prixManquant'] as Map).cast<String, Object?>();
    if (!r.ok) {
      restantes.add(r.manque!);
      final nl = {...l, 'prixManquant': r.manque};
      if (!_egalProfond(m0, r.manque)) change = true;
      lignes.add(nl);
      continue;
    }
    final montant = arrondiJs(r.montant!.toDouble()).toInt();
    final p = partsLigne(montant, taux, estAgent);
    final nl = <String, Object?>{
      ...l,
      'prixUnitaire': r.prixUnitaire,
      'prixUnitaireNet': r.prixUnitaire,
      'montantBrut': montant,
      'remise': 0,
      'montant': montant,
      'partAssureur': p.partAssureur,
      'partPersonnel': p.partPersonnel,
      'partPatient': p.partPatient,
      'valoriseLe': maintenant,
      'valorisation': {'code': m0['code'], 'nature': m0['nature'], 'jour': tarJourDe(facture['date'], aujourdhui), 'version': r.version},
    }..remove('prixManquant');
    valorisees.add({'id': l['id'], 'code': m0['code'], 'nature': m0['nature'], 'prixUnitaire': r.prixUnitaire, 'montant': montant});
    change = true;
    lignes.add(nl);
  }
  if (valorisees.isEmpty) return (facture: change ? {...facture, 'lignes': lignes} : facture, valorisees: valorisees, restantes: restantes, change: change);
  final t = totauxPiece(lignes);
  final f = <String, Object?>{...facture, 'lignes': lignes, ...t};
  if (t['enAttentePrix'] != true) {
    f['enAttentePrix'] = false;
    final r = nombreOuZero(t['partPatient']) - nombreOuZero(facture['montantPaye']);
    f['reliquat'] = r > 0 ? r : 0;
  }
  return (facture: f, valorisees: valorisees, restantes: restantes, change: true);
}

bool _egalProfond(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_egalProfond(a[k], b[k])) return false;
    }
    return true;
  }
  return a == b;
}

/// Ce que l'écran de prescription DIT d'une pièce acceptée avec des lignes sans prix (`messageSansPrix`), ou null.
String? messageSansPrix(List<Map<String, Object?>> sansPrix) {
  if (sansPrix.isEmpty) return null;
  return '${nombre(sansPrix.length)} ligne(s) sans prix (${sansPrix.map((m) => '« ${m['code']} » ${m['nature'] == natureManquePrixAchat ? 'prix à valoriser' : 'prix à définir'}').join(', ')}) : total non calculable, la caisse attend le prix ; alerte transmise à qui le fixe.';
}
