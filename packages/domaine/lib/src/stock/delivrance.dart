/// DÉLIVRANCE (M6) — port de `PR.delivrer` / `PR.verifierStock` / `PR.alerterStock` (prototype_html/assets/js/parcours.js) et des deux pharmacies de
/// `m6-stock.js` (`voieDe`, `ecranPharmacie`).
///
/// RG-03 : toute sortie de stock porte son justificatif — le numéro d'ordonnance — et le stock ne devient JAMAIS négatif. Une ligne insuffisante bloque la
/// délivrance entière (rien n'est servi à moitié) et le refus NOMME l'article. RG-02 : la sortie est valorisée au prix de vente (= prix d'achat, sans marge)
/// ou au CUMP selon le paramètre de la Direction ; le mouvement porte LES DEUX valeurs. RG-05 (FEFO) ne se joue pas ici : le décompte est celui du stock de
/// détail, l'ordre des lots relève de l'écran des lots.
///
/// Comme `avoir.dart` : le moteur de la maquette lit le magasin, celui-ci reçoit les fiches EN ARGUMENT et RENVOIE ce qu'il faut écrire. Les vecteurs
/// (`test/vecteurs/delivrance.json`) sont engendrés par la maquette (`prototype_html/build/vecteurs-delivrance.js`).
///
/// Corrigés dans la maquette PUIS portés (docs/architecture/ECARTS-MAQUETTE.md) : E40 — les pharmacies comparaient l'état de l'ordonnance à « payee » /
/// « delivree » alors que le parcours écrit « soldee » / « servie » ; E41 — « inj », l'abréviation du catalogue, n'était pas reconnu comme injectable ;
/// E41b — la référence du mouvement venait d'un compteur de page ; E42 — le cumul des lignes d'un même produit n'était pas contrôlé (stock NÉGATIF) ;
/// E44 — la délivrance par ligne levait une exception APRÈS l'écriture (alerterStock appelé avec un identifiant nu).
/// Portés fidèlement et signalés : E43 (une tâche de réapprovisionnement « fait » est mise à jour, jamais recréée), E45 (la pharmacie compte et
/// décompte le stock TOTAL, `PR.delivrer` le stock de DÉTAIL), E46 (la délivrance par ligne marque l'ordonnance ENTIÈRE servie).
library;

import '../format/format_fr.dart';
import '../format/js.dart';

/// Refus NOMMÉ : un refus se lit, il ne se devine pas. Rien n'est écrit.
class RefusDelivrance implements Exception {
  const RefusDelivrance(this.motif, {this.manquants = const []});
  final String motif;

  /// Les lignes non couvertes (pour la modale de la file de dispensation).
  final List<LigneStock> manquants;
  @override
  String toString() => motif;
}

double _n(Object? v) => nombreOuZero(v);

/// `Number.isFinite` sur un champ de fiche : `null` si absent ou non numérique (un stock inconnu n'est pas un stock nul).
num? _num(Object? v) => v is num ? v : null;

/// Un nombre comme JavaScript l'écrit dans une chaîne (`3`, jamais `3.0`).
String _js(num v) => v == v.truncate() && v.abs() < 1e15 ? '${v.truncate()}' : '$v';

final RegExp _injectable =
    RegExp(r'inject|\binj\b|amp\.|ampoule|perfus|solut|iv\b|im\b|flacon');

/// `voieDe(ligne, produit)` : la voie d'administration décide de la pharmacie. Portée par la ligne d'ordonnance ; à défaut, la forme (ou la désignation)
/// du produit la révèle — un injectable ne se prend pas par la bouche. `parenterale` ou `orale`.
String voieDe(Map<String, Object?>? ligne, Map<String, Object?>? produit) {
  final v = ligne?['voie'];
  if (v != null && v != '' && v != false && v != 0) return '$v';
  final f = produit?['forme'];
  final d = produit?['designation'];
  final s = (f != null && f != '' ? f : (d != null && d != '' ? d : '')).toString().toLowerCase();
  return _injectable.hasMatch(s) ? 'parenterale' : 'orale';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les deux pharmacies — la vue « lignes d'ordonnance » d'une voie
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Une ligne d'ordonnance qui relève d'une pharmacie.
class LignePharmacie {
  const LignePharmacie({
    required this.id,
    required this.ordonnance,
    required this.index,
    required this.ligne,
    required this.produit,
    required this.numero,
    required this.date,
    required this.patient,
    required this.patientCode,
    required this.designation,
    required this.quantite,
    required this.posologie,
    required this.paye,
    required this.delivre,
    required this.stock,
    required this.couvert,
  });
  final String id;
  final Map<String, Object?> ordonnance;
  final int index;
  final Map<String, Object?> ligne;
  final Map<String, Object?>? produit;
  final Object? numero, date, patient, patientCode, designation, posologie;
  final Object? quantite;
  final bool paye, delivre, couvert;

  /// `null` : produit inconnu (la maquette écrit « produit inconnu »).
  final num? stock;

  /// « Non réglée », « Stock insuffisant » ou « Délivrable » : dans CET ordre de priorité.
  String get etat => !paye ? 'Non réglée' : (!couvert ? 'Stock insuffisant' : 'Délivrable');
}

/// `lignes()` de `ecranPharmacie` : les lignes d'ordonnance des ordonnances ACTIVES qui relèvent de [voie] (`parenterale` = pharmacie interne,
/// `orale` = pharmacie externe), dans l'ordre du magasin.
List<LignePharmacie> lignesPharmacie({
  required Iterable<Map<String, Object?>> ordonnances,
  required Iterable<Map<String, Object?>> produits,
  required String voie,
}) {
  final out = <LignePharmacie>[];
  final liste = produits.toList();
  for (final o in ordonnances) {
    final meds = (o['medicaments'] as List?) ?? const [];
    for (var i = 0; i < meds.length; i++) {
      final l = (meds[i] as Map).cast<String, Object?>();
      final pr = liste.where((x) => x['id'] == l['produitId']).firstOrNull;
      if (voieDe(l, pr) != voie) continue;
      final stock = pr == null ? null : _num(pr['stock']);
      final q = _num(l['quantite']);
      out.add(LignePharmacie(
        id: '${o['id']}:$i',
        ordonnance: o,
        index: i,
        ligne: l,
        produit: pr,
        numero: o['numero'],
        date: o['date'],
        patient: o['patient'],
        patientCode: o['patientCode'],
        designation: l['produit'],
        quantite: l['quantite'],
        posologie: l['posologie'],
        paye: o['statutPaiement'] == 'soldee',
        delivre: o['statutDispensation'] == 'servie',
        stock: stock,
        couvert: pr != null && stock != null && q != null && stock >= q,
      ));
    }
  }
  return out;
}

/// Les quatre indicateurs d'une pharmacie.
class StatsPharmacie {
  const StatsPharmacie(
      {required this.lignes,
      required this.aDelivrer,
      required this.bloquees,
      required this.decouvertes});
  final int lignes, aDelivrer, bloquees, decouvertes;
}

StatsPharmacie statsPharmacie(List<LignePharmacie> ls) {
  final a = ls.where((x) => !x.delivre).toList();
  return StatsPharmacie(
    lignes: ls.length,
    aDelivrer: a.length,
    bloquees: a.where((x) => !x.paye).length,
    decouvertes: a.where((x) => !x.couvert).length,
  );
}

/// Les lignes À DÉLIVRER, par date décroissante (`C.sortBy(aDelivrer, 'date').reverse()` : à date égale, la dernière rencontrée vient d'abord).
List<LignePharmacie> aDelivrerTriees(List<LignePharmacie> ls) {
  final a = ls.where((x) => !x.delivre).toList();
  final indexees = [for (var i = 0; i < a.length; i++) (i, a[i])];
  indexees.sort((x, y) {
    final dx = x.$2.date, dy = y.$2.date;
    if (dx == null) return 1;
    if (dy == null) return -1;
    final c = _comparerTexte('$dx', '$dy');
    return c != 0 ? c : x.$1.compareTo(y.$1); // tri croissant STABLE, puis inversé
  });
  return [for (final e in indexees.reversed) e.$2];
}

// Les dates ISO se comparent comme du texte (ordre lexicographique = chronologique).
int _comparerTexte(String a, String b) => a.compareTo(b);

/// Ce qu'écrit la délivrance PAR LIGNE de la pharmacie (le geste « Délivrer » d'une ligne du tableau).
class DelivranceLigne {
  const DelivranceLigne(
      {required this.avant,
      required this.produitPatch,
      required this.mouvement,
      required this.ordonnancePatch,
      required this.message,
      required this.detail,
      required this.alerteProduitIds});
  final num avant;

  /// `{stock: avant − quantité}` — le stock de DÉTAIL n'est pas touché (E45).
  final Map<String, Object?> produitPatch;
  final Map<String, Object?> mouvement;

  /// L'ordonnance ENTIÈRE passe « servie » (E46).
  final Map<String, Object?> ordonnancePatch;
  final String message, detail;
  final List<String> alerteProduitIds;
}

/// Le message de la modale de confirmation (sans balises) : la sortie, son justificatif et son destinataire.
String messageConfirmation(LignePharmacie l, String voie) =>
    '${nombre(l.quantite)} unité(s) sortiront du stock au titre de l’ordonnance ${l.numero}'
    '${voie == 'parenterale' ? ', à destination de la salle de soins qui les administrera.' : ', remises au patient au comptoir.'}';

/// Délivre UNE ligne. RG-03 : le refus NOMME l'article. [reference] : `MVT-NNNNN`, série lue sur les mouvements existants (E41b) ; [jour] : `YYYY-MM-DD`.
DelivranceLigne delivrerLigne(LignePharmacie l, String voie,
    {required String reference, required String jour}) {
  if (!l.couvert) {
    throw RefusDelivrance(
        'Délivrance refusée — stock insuffisant sur « ${l.designation} » : ${nombre(l.stock)} en rayon pour ${nombre(l.quantite)} demandé(s).');
  }
  final pr = l.produit!;
  final avant = l.stock!;
  final q = _n(l.quantite);
  return DelivranceLigne(
    avant: avant,
    produitPatch: {'stock': avant - q},
    mouvement: {
      'reference': reference,
      'date': jour,
      'type': voie == 'parenterale' ? 'delivrance_interne' : 'delivrance_externe',
      'produitId': pr['id'],
      'produit': l.designation,
      'quantite': l.quantite,
      'sens': 'sortie',
      'valeur': q * _n(pr['prixAchat']),
      // RG-03 : le justificatif est le numéro d'ordonnance.
      'justificatif': 'Ordonnance ${l.numero}',
      'destination': voie == 'parenterale' ? 'Salle de soins' : 'Patient',
    },
    ordonnancePatch: const {'statutDispensation': 'servie'},
    message: 'Délivré — stock ramené à ${nombre(avant - q)}.',
    detail: '${l.designation} — ${l.patient}',
    alerteProduitIds: ['${pr['id']}'],
  );
}

/// `C.referenceSuivante(prefixe, largeur, fiches)` : le plus grand rang déjà écrit pour ce préfixe, plus un (jamais un compteur de page — E8/E41b).
String referenceSuivante(String prefixe, int largeur, Iterable<Map<String, Object?>> fiches) {
  var max = 0;
  for (final f in fiches) {
    final r = '${f['reference'] ?? ''}';
    if (r.startsWith(prefixe)) {
      final k = int.tryParse(RegExp(r'^\s*[+-]?\d+').firstMatch(r.substring(prefixe.length))?.group(0)?.trim() ?? '') ?? 0;
      if (k > max) max = k;
    }
  }
  return '$prefixe${(max + 1).toString().padLeft(largeur, '0')}';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le moteur — PR.delivrer(ordonnanceId)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Une ligne d'ordonnance mise en regard du stock (`PR.verifierStock`).
class LigneStock {
  const LigneStock(
      {required this.ligne,
      required this.produit,
      required this.disponible,
      required this.suffisant});
  final Map<String, Object?> ligne;
  final Map<String, Object?>? produit;

  /// Ce qui reste APRÈS les lignes précédentes du même produit (E42).
  final num disponible;
  final bool suffisant;
}

num _dispo(Map<String, Object?> p) => (p['stockDetail'] != null ? _n(p['stockDetail']) : _n(p['stock']));

/// `verifierStock(ordonnance)` : le stock de DÉTAIL (à défaut le stock total) couvre-t-il chaque ligne ? RG-03 : le CUMUL des lignes d'un même produit
/// est contrôlé.
List<LigneStock> verifierStock(
    Map<String, Object?> ordonnance, Iterable<Map<String, Object?>> produits) {
  final liste = produits.toList();
  final prises = <Object?, num>{};
  return [
    for (final raw in (ordonnance['medicaments'] as List? ?? const []))
      () {
        final l = (raw as Map).cast<String, Object?>();
        final prod = liste.where((x) => x['id'] == l['produitId']).firstOrNull;
        final total = prod == null ? 0 : _dispo(prod);
        final dispo = total - (prises[l['produitId']] ?? 0);
        if (prod != null) prises[l['produitId']] = (prises[l['produitId']] ?? 0) + _n(l['quantite']);
        return LigneStock(
            ligne: l, produit: prod, disponible: dispo, suffisant: prod != null && dispo >= _n(l['quantite']));
      }(),
  ];
}

/// Valorisation d'une sortie : paramétrable (prix de vente ou CUMP), le mouvement porte LES DEUX valeurs — sans cela, changer de méthode rendrait
/// l'historique incomparable.
class Valorisation {
  const Valorisation(
      {required this.methode,
      required this.valeur,
      required this.valeurPrixVente,
      required this.valeurCump});
  final String methode;
  final int valeur, valeurPrixVente, valeurCump;
}

Valorisation valoriserSortie(
    Map<String, Object?> produit, num quantite, String methode) {
  final pvBrut = produit['prixVente'] != null ? produit['prixVente'] : produit['prixAchat'];
  final pv = _n(pvBrut);
  final cump = produit['cump'] != null ? _n(produit['cump']) : pv;
  final retenu = methode == 'cump' ? cump : pv;
  int r(double x) => arrondiJs(x).toInt();
  return Valorisation(
      methode: methode,
      valeur: r(retenu * quantite),
      valeurPrixVente: r(pv * quantite),
      valeurCump: r(cump * quantite));
}

/// L'alerte de stock d'une référence : `rupture`, `alerte` (sous le seuil) ou `sansSeuil` (le seuil n'est pas fixé — signalé, aucune tâche).
class AlerteStock {
  const AlerteStock(this.produitId, this.niveau, this.dispo, this.seuil);
  final Object? produitId;
  final String niveau;
  final num dispo;
  final Object? seuil;
}

/// Ce que la délivrance d'une ordonnance écrit.
class Delivrance {
  const Delivrance({
    required this.deja,
    this.ordonnancePatch = const {},
    this.produits = const [],
    this.mouvements = const [],
    this.tachesFermees = const [],
    this.tachesCreees = const [],
    this.tachesMisesAJour = const [],
    this.alertes = const [],
    this.journal = const {},
  });

  /// L'ordonnance était déjà servie : rien n'est refait.
  final bool deja;
  final Map<String, Object?> ordonnancePatch;

  /// Les mises à jour de produits, DANS L'ORDRE des lignes (un produit sur deux lignes est mis à jour deux fois).
  final List<({Object? id, Map<String, Object?> patch})> produits;
  final List<Map<String, Object?>> mouvements;
  final List<({Object? id, Map<String, Object?> patch})> tachesFermees;
  final List<Map<String, Object?>> tachesCreees;
  final List<({Object? id, Map<String, Object?> patch})> tachesMisesAJour;
  final List<AlerteStock> alertes;

  /// L'entrée de journal (RG-12) : `{action, module, entite, reference, avant, apres}`.
  final Map<String, Object?> journal;
}

/// `PR.delivrer(ordonnanceId)`. [mouvementsExistants] : pour la série `M000000` ; [taches] : les tâches ACTIVES (la fermeture de la tâche de dispensation et
/// l'alerte de réapprovisionnement les lisent) ; [methode] : `prixVente` ou `cump` ; [instant] : ISO 8601. Lève [RefusDelivrance].
Delivrance delivrerOrdonnance({
  required Map<String, Object?>? ordonnance,
  required Iterable<Map<String, Object?>> produits,
  required Iterable<Map<String, Object?>> taches,
  required Iterable<Map<String, Object?>> mouvementsExistants,
  required String methode,
  required String utilisateur,
  required String instant,
}) {
  if (ordonnance == null) throw const RefusDelivrance('Ordonnance introuvable.');
  if (ordonnance['statutPaiement'] != 'soldee') {
    throw const RefusDelivrance('Facture non réglée — la délivrance est bloquée.');
  }
  if (ordonnance['statutDispensation'] == 'servie') return const Delivrance(deja: true);

  final etat = verifierStock(ordonnance, produits);
  final manquants = etat.where((e) => !e.suffisant).toList();
  if (manquants.isNotEmpty) {
    // RG-03 — jamais de stock négatif : on refuse et on dit lequel.
    throw RefusDelivrance(
        'Stock insuffisant : ${manquants.map((m) => '${m.ligne['produit']} (${_js(m.disponible)} pour ${m.ligne['quantite']} demandés)').join(', ')}',
        manquants: manquants);
  }

  // Les produits sont mis à jour AU FIL des lignes : la maquette lit l'objet vivant du magasin, un produit sur deux lignes voit la première sortie.
  final vivants = <Object?, Map<String, Object?>>{
    for (final p in produits) p['id']: {...p}
  };
  final patchs = <({Object? id, Map<String, Object?> patch})>[];
  final mouvements = <Map<String, Object?>>[];
  final refs = [...mouvementsExistants];
  for (final x in etat) {
    final prod = vivants[x.produit!['id']]!;
    final q = _n(x.ligne['quantite']);
    final reste = _dispo(prod) - q;
    final patch = <String, Object?>{
      'stockDetail': prod['stockDetail'] != null ? reste : prod['stockDetail'],
      'stock': (_n(prod['stock']) - q) < 0 ? 0 : _n(prod['stock']) - q,
    };
    prod.addAll(patch);
    patchs.add((id: prod['id'], patch: patch));
    final val = valoriserSortie(prod, q, methode);
    final mv = <String, Object?>{
      'reference': referenceSuivante('M', 6, refs),
      'date': instant,
      'produitId': prod['id'],
      'produit': prod['designation'],
      'type': 'sortie',
      'typeLabel': 'Sortie',
      'quantite': x.ligne['quantite'],
      'stockType': 'detail',
      'justificatif': 'Ordonnance ${ordonnance['numero']}',
      'ordonnanceId': ordonnance['id'],
      // Valorisation : méthode retenue et les deux valeurs, pour comparaison.
      'valorisation': val.methode,
      'valeur': val.valeur,
      'valeurPrixVente': val.valeurPrixVente,
      'valeurCump': val.valeurCump,
      'utilisateur': utilisateur,
    };
    mouvements.add(mv);
    refs.add(mv);
  }

  final fermees = [
    for (final t in taches)
      if (t['ordonnanceId'] == ordonnance['id'] && t['type'] == 'dispensation')
        (id: t['id'], patch: <String, Object?>{'statut': 'fait', 'faitLe': instant, 'faitPar': utilisateur})
  ];

  // Le gestionnaire de stock est informé au moment où la sortie a lieu, et non le jour de l'inventaire.
  final alertes = alerterStock(
      [for (final x in etat) x.produit!['id']], vivants, taches, '${ordonnance['numero']}', instant);

  return Delivrance(
    deja: false,
    ordonnancePatch: {
      'statutDispensation': 'servie',
      'dispenseLe': instant,
      'dispensePar': utilisateur,
    },
    produits: patchs,
    mouvements: mouvements,
    tachesFermees: fermees,
    tachesCreees: alertes.creees,
    tachesMisesAJour: alertes.miseAJour,
    alertes: alertes.alertes,
    journal: {
      'action': 'Dispensation',
      'module': 'M6',
      'entite': 'ordonnance',
      'reference': ordonnance['numero'],
      'avant': {'statutDispensation': 'en_attente'},
      'apres': {'statutDispensation': 'servie', 'lignes': mouvements.length},
    },
  );
}

/// Le résultat de `alerterStock` : les alertes et les tâches qu'elles créent ou mettent à jour.
class ResultatAlertes {
  ResultatAlertes(this.alertes, this.creees, this.miseAJour);
  final List<AlerteStock> alertes;
  final List<Map<String, Object?>> creees;
  final List<({Object? id, Map<String, Object?> patch})> miseAJour;
}

/// `PR.alerterStock(produitIds, justificatif)` : une sortie qui fait passer un article sous son seuil ouvre une tâche de réapprovisionnement AU MOMENT où
/// elle a lieu. Une seule tâche par article — réalerter à chaque sortie noierait le gestionnaire sous les doublons. Le seuil est celui que la clinique a
/// fixé : sans seuil, aucune alerte n'est possible, et l'article est signalé comme tel. [produits] : les produits TELS QU'APRÈS la sortie.
///
/// E43, porté tel quel : une tâche déjà « fait » compte comme « ouverte » (la maquette teste `statut !== 'termine'`, un statut que rien n'écrit).
ResultatAlertes alerterStock(
  Iterable<Object?> produitIds,
  Map<Object?, Map<String, Object?>> produits,
  Iterable<Map<String, Object?>> taches,
  String? justificatif,
  String instant,
) {
  final alertes = <AlerteStock>[];
  final creees = <Map<String, Object?>>[];
  final majs = <({Object? id, Map<String, Object?> patch})>[];
  // La maquette relit les tâches à CHAQUE article : une tâche créée plus haut dans la boucle est vue.
  final courantes = [for (final t in taches) {...t}];
  for (final id in produitIds) {
    final prod = produits[id];
    if (prod == null) continue;
    final dispo = _dispo(prod);
    final seuil = prod['seuilAlerte'];
    String? niveau;
    if (dispo <= 0) {
      niveau = 'rupture';
    } else if (seuil != null && seuil != '' && dispo <= _n(seuil)) {
      niveau = 'alerte';
    } else if (seuil == null || seuil == '') {
      niveau = 'sansSeuil';
    }
    if (niveau == null) continue;
    if (niveau == 'sansSeuil') {
      alertes.add(AlerteStock(id, niveau, dispo, null));
      continue;
    }
    final libelle = '${niveau == 'rupture' ? 'RUPTURE — ' : 'Sous le seuil — '}${prod['designation']}';
    final deja = courantes
        .where((t) => t['type'] == 'reapprovisionnement' && t['produitId'] == id && t['statut'] != 'termine')
        .firstOrNull;
    if (deja != null) {
      final patch = {'stockRestant': dispo, 'libelle': libelle};
      deja.addAll(patch);
      final existant = majs.indexWhere((m) => m.id == deja['id']);
      if (existant >= 0) {
        majs[existant] = (id: deja['id'], patch: {...majs[existant].patch, ...patch});
      } else if (!creees.any((c) => identical(c, deja))) {
        majs.add((id: deja['id'], patch: patch));
      } else {
        creees[creees.indexWhere((c) => identical(c, deja))] = deja;
      }
    } else {
      final t = <String, Object?>{
        'type': 'reapprovisionnement',
        'poste': 'stock',
        'libelle': libelle,
        'produitId': id,
        'produitCode': prod['code'],
        'stockRestant': dispo,
        'seuil': seuil,
        'justificatif': justificatif,
        'statut': 'en_attente',
        'priorite': niveau == 'rupture' ? 'haute' : 'normale',
        'creeLe': instant,
      };
      creees.add(t);
      courantes.add(t);
    }
    alertes.add(AlerteStock(id, niveau, dispo, seuil));
  }
  return ResultatAlertes(alertes, creees, majs);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La dispensation — le registre des délivrances faites
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les quatre indicateurs de `m6-dispensation`. « Références en pharmacie » : stock de détail > 0 ; « Ruptures » : stock de détail EXACTEMENT 0 (une
/// référence sans stock de détail renseigné n'est ni l'un ni l'autre).
({int dispensations, num valeur, int references, int ruptures}) kpisDispensation(
    Iterable<Map<String, Object?>> dispensations, Iterable<Map<String, Object?>> produits) {
  final d = dispensations.toList();
  final p = produits.toList();
  return (
    dispensations: d.length,
    valeur: d.fold<num>(0, (t, x) => t + _n(x['montant'])),
    references: p.where((x) => _n(x['stockDetail']) > 0).length,
    ruptures: p.where((x) => x['stockDetail'] == 0).length,
  );
}
