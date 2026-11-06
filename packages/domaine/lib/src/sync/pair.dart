/// LA RÈGLE DE FUSION ENTRE PAIRS (ADR-0006), port Dart de `packages/sync/banc/pair.js`, qui reste l'exécutable de référence (vecteurs : `test/vecteurs/pair.json`).
///
/// Quand la mère est éteinte, les fileuls échangent leurs opérations par le relais. L'état est une FONCTION PURE de l'ensemble des opérations :
///
///     etatPair(ops) = plier(trier(sans doublon(ops)))      ordre total : (hlc, appareil, id)
///
/// Rien n'est appliqué « au fil de l'eau » : deux appareils qui ont reçu les mêmes opérations aboutissent au même état, quel que soit l'ordre d'arrivée.
/// Le relais ne contient aucune de ces règles. Les droits (RBAC) sont vérifiés à la RÉCEPTION comme à l'émission : [DroitsOperation] est injecté.
/// Ce qui est appliqué sans la mère est PROVISOIRE : une fiche touchée par une opération sans `seq` (attribué par la mère) l'est.
///
/// Familles : A fiche (fusion par champ) · B journal (ajout seul) · C pièce émise (immuable) · D stock (sorties dans la PART de l'appareil, RG-03)
///            · W flux de travail (validation par le rôle habilité).
library;

import 'dart:convert';

const Map<String, String> famillesPair = {
  'patients': 'A',
  'rendezvous': 'A',
  'constantes': 'B',
  'notes': 'B',
  'factures': 'C',
  'avoirs': 'C',
  'lots': 'D',
  'mouvements': 'B',
  'produits': 'A',
  'admissions': 'A',
  'ecritures': 'C',
  'prescriptions': 'C',
  'stock': 'D',
  'besoins': 'W',
  'consultations': 'A',
  'dossiersConsultation': 'A',
  'antecedents': 'A',
  'appels': 'A',
  'observations': 'A',
  'releves': 'B',
};

/// Une opération échangée entre pairs (déjà déchiffrée). `seq` n'est posé que par la mère.
class OperationPair {
  const OperationPair({
    required this.id,
    required this.appareil,
    required this.hlc,
    required this.collection,
    required this.fiche,
    required this.type,
    this.champs = const {},
    this.vu,
    this.role,
    this.seq,
  });

  final String id, appareil, collection, fiche, type;
  final int hlc;
  final Map<String, Object?> champs;
  final Map<String, Object?>? vu;
  final String? role;
  final int? seq;

  factory OperationPair.depuisJson(Map<String, Object?> j) => OperationPair(
        id: '${j['id']}',
        appareil: '${j['appareil']}',
        hlc: (j['hlc'] as num).toInt(),
        collection: '${j['collection']}',
        fiche: '${j['fiche']}',
        type: '${j['type']}',
        champs: ((j['champs'] ?? const <String, Object?>{}) as Map).cast<String, Object?>(),
        vu: j['vu'] == null ? null : (j['vu'] as Map).cast<String, Object?>(),
        role: j['role'] as String?,
        seq: (j['seq'] as num?)?.toInt(),
      );

  Map<String, Object?> versJson() => {
        'id': id,
        'appareil': appareil,
        'hlc': hlc,
        'collection': collection,
        'fiche': fiche,
        'type': type,
        'champs': champs,
        if (vu != null) 'vu': vu,
        if (role != null) 'role': role,
        if (seq != null) 'seq': seq,
      };
}

typedef DroitsOperation = bool Function(OperationPair op);

/// Ordre total identique sur tous les appareils.
int comparerOperationsPair(OperationPair a, OperationPair b) {
  if (a.hlc != b.hlc) return a.hlc < b.hlc ? -1 : 1;
  if (a.appareil != b.appareil) return a.appareil.compareTo(b.appareil) < 0 ? -1 : 1;
  return a.id.compareTo(b.id);
}

/// Horloge logique hybride : strictement croissante, supérieure à tout ce qu'on a vu ET à l'horloge murale ; la dérive est bornée et SIGNALÉE (EF-SYNC-20).
class HorlogePair {
  HorlogePair({int Function()? maintenantMs, this.deriveMaxMs = 2 * 60 * 1000}) : _maintenant = maintenantMs ?? (() => DateTime.now().millisecondsSinceEpoch);
  final int Function() _maintenant;
  final int deriveMaxMs;
  int dernier = 0;
  bool derive = false;

  int emettre() {
    final mur = _maintenant() * 1000;
    dernier = (dernier + 1) > mur ? dernier + 1 : mur;
    return dernier;
  }

  void recevoir(int hlc) {
    if (hlc / 1000 - _maintenant() > deriveMaxMs) derive = true;
    if (hlc > dernier) dernier = hlc;
  }
}

class RefusPair {
  const RefusPair(this.id, this.appareil, this.code, this.motif);
  final String id, appareil, code, motif;
}

/// L'état de tous les appareils qui ont reçu les mêmes opérations.
class EtatPair {
  final Map<String, Map<String, Object?>> fiches = {};
  final Map<String, Map<String, Object?>> stock = {};
  final Map<String, Map<String, Object?>> besoins = {};
  final List<Map<String, Object?>> conflits = [];
  final List<Map<String, Object?>> tranches = [];
  final List<RefusPair> refusees = [];
  final Set<String> provisoire = {};

  /// Forme JSON canonique (celle des vecteurs) : le motif des refus n'en fait pas partie, seul leur code est un contrat.
  Map<String, Object?> versJson() => {
        'fiches': fiches,
        'stock': stock,
        'besoins': besoins,
        'conflits': conflits,
        'tranches': tranches,
        'refusees': [for (final r in refusees) {'id': r.id, 'appareil': r.appareil, 'code': r.code}],
        'provisoire': provisoire.toList()..sort(),
      };
}

bool _vrai(Object? v) => !(v == null || v == false || v == '' || (v is num && v == 0));

num _nombre(Object? v) => v is num ? v : (v is String ? (num.tryParse(v) ?? 0) : 0);

/// A (admissions) : un lit ne porte qu'UNE admission active. Deux admissions `en_cours` sur le même lit, créées chacune hors ligne, sont MARQUÉES `litEnConflit` sur les deux :
/// aucune n'est refusée ni déplacée (un patient est réellement là), l'établissement transfère l'un d'eux. Calculé sur l'état final, indépendant de l'ordre d'arrivée.
void _marquerLits(EtatPair e) {
  final parLit = <String, List<Map<String, Object?>>>{};
  for (final en in e.fiches.entries) {
    final f = en.value;
    final data = f['data']! as Map<String, Object?>;
    if (!en.key.startsWith('admissions/') || f['archive'] == true || data['statut'] != 'en_cours' || !_vrai(data['lit'])) continue;
    parLit.putIfAbsent('${data['lit']}', () => []).add(f);
  }
  for (final l in parLit.values) {
    if (l.length > 1) {
      for (final f in l) {
        f['litEnConflit'] = true;
      }
    }
  }
}

/// C : l'ÉMISSION d'une pièce certifiante. Le numéro, une fois posé, ne se réécrit jamais ; un numéro porté par deux pièces émises est MARQUÉ (`doublon`) sur les
/// deux et n'est jamais renuméroté (RG-01, pièce émise intouchable). Une écriture ne s'émet que ÉQUILIBRÉE (RG-10).
void _emettre(EtatPair e, OperationPair op, Map<String, Object?> f, String k) {
  final numero = op.champs.containsKey('numero') ? op.champs['numero'] : null;
  if (f['archive'] == true) {
    e.refusees.add(RefusPair(op.id, op.appareil, 'fiche_archivee', 'Restaurer d’abord (RG-14).'));
    return;
  }
  if (f['emise'] == true) {
    if (numero != null && jsonEncode(numero) != jsonEncode(f['numero'])) {
      e.refusees.add(RefusPair(op.id, op.appareil, 'numero_immuable', 'Le numéro d’une pièce émise ne se réécrit jamais.'));
    }
    return;
  }
  if (op.collection == 'ecritures' && !_equilibree((f['data']! as Map<String, Object?>)['lignes'])) {
    e.refusees.add(RefusPair(op.id, op.appareil, 'ecriture_desequilibree', 'Débit et crédit doivent s’égaler (RG-10) avant l’émission.'));
    return;
  }
  f['emise'] = true;
  if (numero != null) {
    f['numero'] = numero;
    for (final en in e.fiches.entries) {
      final g = en.value;
      if (en.key != k && en.key.startsWith('${op.collection}/') && g['emise'] == true && jsonEncode(g['numero']) == jsonEncode(numero)) {
        f['doublon'] = true;
        g['doublon'] = true;
      }
    }
  }
}

bool _equilibree(Object? lignes) {
  if (lignes is! List || lignes.length < 2) return false;
  num d = 0, c = 0;
  for (final l in lignes) {
    final m = l as Map;
    d += _nombre(m['debit']);
    c += _nombre(m['credit']);
  }
  return d > 0 && (d * 100).round() == (c * 100).round();
}

bool _avoirValide(EtatPair e, OperationPair op) {
  final cibleK = 'factures/${op.champs['facture']}';
  final facture = e.fiches[cibleK];
  if (facture == null || facture['emise'] != true) {
    e.refusees.add(RefusPair(op.id, op.appareil, 'avoir_sans_facture_emise', 'Un avoir vise une facture émise : $cibleK'));
    return false;
  }
  final montant = _nombre(op.champs['montant']);
  final deja = _nombre(facture['avoirs']);
  final total = _nombre((facture['data']! as Map<String, Object?>)['total']);
  if (montant <= 0 || deja + montant > total) {
    e.refusees.add(RefusPair(op.id, op.appareil, 'avoir_depasse', 'Avoirs cumulés ${deja + montant} au-delà de la facture ($total).'));
    return false;
  }
  facture['avoirs'] = deja + montant;
  return true;
}

String _cle(OperationPair o) => '${o.collection}/${o.fiche}';

num _quantite(OperationPair o) {
  final v = o.champs['qte'];
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

List<OperationPair> _sansDoublon(Iterable<OperationPair> ops) {
  final vu = <String>{};
  return [for (final o in ops) if (vu.add(o.id)) o];
}

/// L'état issu de [ops] (n'importe quel ordre, doublons admis). [droits] : le RBAC, vérifié à la réception.
EtatPair etatPair(Iterable<OperationPair> ops, {DroitsOperation? droits}) {
  final e = EtatPair();
  final tri = _sansDoublon(ops)..sort(comparerOperationsPair);
  for (final op in tri) {
    final fam = famillesPair[op.collection];
    if (fam == null) {
      e.refusees.add(RefusPair(op.id, op.appareil, 'collection_inconnue', op.collection));
      continue;
    }
    if (op.type == 'supprimer') {
      e.refusees.add(RefusPair(op.id, op.appareil, 'suppression_interdite', 'Aucune suppression physique (RG-14).'));
      continue;
    }
    if (droits != null && !droits(op)) {
      e.refusees.add(RefusPair(op.id, op.appareil, 'droit_refuse', '${op.role ?? '?'} ne peut pas ${op.type} sur ${op.collection}'));
      continue;
    }
    if (op.seq == null) e.provisoire.add(_cle(op));

    if (fam == 'D') {
      _stock(e, op);
      continue;
    }
    if (fam == 'W') {
      _flux(e, op);
      continue;
    }
    final k = _cle(op);
    final f = e.fiches[k];

    if (fam == 'B') {
      if (op.type != 'creer') {
        e.refusees.add(RefusPair(op.id, op.appareil, 'journal_immuable', 'Un journal ne se modifie pas.'));
        continue;
      }
      if (f != null) {
        e.refusees.add(RefusPair(op.id, op.appareil, 'fiche_existe', 'Ligne déjà présente.'));
        continue;
      }
      // RG-03 : toute sortie de stock est rattachée à un justificatif
      if (op.collection == 'mouvements' && op.champs['sens'] == 'sortie' && !_vrai(op.champs['justificatif'])) {
        e.refusees.add(RefusPair(op.id, op.appareil, 'justificatif_manquant', 'Toute sortie de stock porte son justificatif (RG-03).'));
        continue;
      }
      e.fiches[k] = {
        'data': {...op.champs},
        'hlc': {for (final c in op.champs.keys) c: op.hlc},
        'archive': false,
      };
      continue;
    }
    // A et C
    if (op.type == 'creer') {
      if (f != null) {
        e.refusees.add(RefusPair(op.id, op.appareil, 'fiche_existe', 'Fiche déjà présente.'));
        continue;
      }
      // un AVOIR est le seul canal de correction d'une pièce émise : il vise une facture ÉMISE, et le cumul des avoirs ne dépasse jamais la facture
      if (op.collection == 'avoirs' && !_avoirValide(e, op)) continue;
      e.fiches[k] = {
        'data': {...op.champs},
        'hlc': {for (final c in op.champs.keys) c: op.hlc},
        'archive': false,
        'emise': false,
      };
      continue;
    }
    if (f == null) {
      e.refusees.add(RefusPair(op.id, op.appareil, 'fiche_inconnue', k));
      continue;
    }
    if (op.type == 'archiver' || op.type == 'restaurer') {
      f['archive'] = op.type == 'archiver';
      continue;
    }
    if (fam == 'C' && op.type == 'emettre') {
      _emettre(e, op, f, k);
      continue;
    }
    // TRANCHER (la personne habilitée, ou la mère à son retour) : la valeur choisie remplace celle de l'ordre total et le conflit marqué est levé.
    // Un conflit qui naît APRÈS cette décision dans l'ordre total reste marqué : on ne tranche que ce qui a été vu.
    if (op.type == 'trancher') {
      if (f['archive'] == true) {
        e.refusees.add(RefusPair(op.id, op.appareil, 'fiche_archivee', 'Restaurer d’abord (RG-14).'));
        continue;
      }
      if (fam == 'C' && f['emise'] == true) {
        e.refusees.add(RefusPair(op.id, op.appareil, 'piece_emise_immuable', 'Une pièce émise ne se réécrit jamais : établir un avoir.'));
        continue;
      }
      final data = f['data']! as Map<String, Object?>;
      final hlcs = f['hlc']! as Map<String, Object?>;
      for (final en in op.champs.entries) {
        data[en.key] = en.value;
        hlcs[en.key] = op.hlc;
        f['dernier'] = op.appareil;
        e.conflits.removeWhere((c) => c['fiche'] == k && c['champ'] == en.key);
        e.tranches.add({'fiche': k, 'champ': en.key, 'valeur': en.value, 'par': op.appareil, 'hlc': op.hlc});
      }
      continue;
    }
    if (op.type == 'modifier') {
      if (f['archive'] == true) {
        e.refusees.add(RefusPair(op.id, op.appareil, 'fiche_archivee', 'Restaurer d’abord (RG-14).'));
        continue;
      }
      if (fam == 'C' && f['emise'] == true) {
        e.refusees.add(RefusPair(op.id, op.appareil, 'piece_emise_immuable', 'Une pièce émise ne se réécrit jamais : établir un avoir.'));
        continue;
      }
      final data = f['data']! as Map<String, Object?>;
      final hlcs = f['hlc']! as Map<String, Object?>;
      for (final en in op.champs.entries) {
        final champ = en.key, val = en.value;
        final courant = (hlcs[champ] as int?) ?? 0;
        final vu = (op.vu == null ? null : op.vu![champ] as num?)?.toInt() ?? 0;
        // écriture CONCURRENTE : l'auteur n'avait pas vu la version courante et les valeurs diffèrent -> conflit marqué, la plus récente de l'ordre total l'emporte
        if (courant > vu && jsonEncode(data[champ]) != jsonEncode(val)) {
          e.conflits.add({
            'fiche': k,
            'champ': champ,
            'a': data.containsKey(champ) ? data[champ] : null,
            'b': val,
            'appareils': [f['dernier'], op.appareil],
          });
        }
        data[champ] = val;
        hlcs[champ] = op.hlc;
        f['dernier'] = op.appareil;
      }
    }
  }
  _marquerLits(e);
  // tri STABLE (Dart ne garantit pas la stabilité de List.sort) : l'ordre de pliage départage les conflits de même clé
  final indexes = {for (var i = 0; i < e.conflits.length; i++) e.conflits[i]: i};
  e.conflits.sort((x, y) {
    final c = ('${x['fiche']}${x['champ']}').compareTo('${y['fiche']}${y['champ']}');
    return c != 0 ? c : indexes[x]!.compareTo(indexes[y]!);
  });
  return e;
}

/// D : ouverture et entrées par un rôle habilité ; la PART d'un appareil est un bail accordé ; une sortie hors part n'est JAMAIS appliquée (RG-03).
void _stock(EtatPair e, OperationPair op) {
  final sk = op.collection == 'stock' ? op.fiche : '${op.collection}/${op.fiche}'; // le stock historique garde sa clé nue : les lots ne la partagent pas
  final s = e.stock.putIfAbsent(sk, () => {'qte': 0, 'ouvert': false, 'parts': <String, Object?>{}, 'sorties': <String, Object?>{}});
  final parts = s['parts']! as Map<String, Object?>;
  final sorties = s['sorties']! as Map<String, Object?>;
  final q = _quantite(op);
  num qte() => s['qte']! as num;
  if (op.type == 'creer') {
    if (s['ouvert'] == true) {
      e.refusees.add(RefusPair(op.id, op.appareil, 'fiche_existe', 'Stock déjà ouvert.'));
      return;
    }
    s['ouvert'] = true;
    s['qte'] = qte() + q;
    return;
  }
  if (s['ouvert'] != true) {
    e.refusees.add(RefusPair(op.id, op.appareil, 'fiche_inconnue', 'Stock non ouvert : ${op.fiche}'));
    return;
  }
  if (op.type == 'entree') {
    s['qte'] = qte() + q;
    return;
  }
  if (op.type == 'bail') {
    final a = '${op.champs['appareil']}';
    parts[a] = ((parts[a] as num?) ?? 0) + q;
    return;
  }
  if (op.type == 'sortie') {
    final reste = ((parts[op.appareil] as num?) ?? 0) - ((sorties[op.appareil] as num?) ?? 0);
    if (q > reste || q > qte()) {
      e.refusees.add(RefusPair(op.id, op.appareil, 'hors_part', 'Sortie de $q hors de la part de ${op.appareil} (reste $reste) : RG-03.'));
      return;
    }
    sorties[op.appareil] = ((sorties[op.appareil] as num?) ?? 0) + q;
    s['qte'] = qte() - q;
    return;
  }
  e.refusees.add(RefusPair(op.id, op.appareil, 'type_invalide', op.type));
}

/// W : soumettre (demandeur), valider ou rejeter (rôle habilité, déjà contrôlé par les droits) ; une décision sans demande préalable dans l'ordre total est écartée.
void _flux(EtatPair e, OperationPair op) {
  final b = e.besoins.putIfAbsent(op.fiche, () => {'etat': null, 'historique': <Object?>[]});
  final histo = b['historique']! as List<Object?>;
  if (op.type == 'soumettre') {
    if (b['etat'] != null) {
      e.refusees.add(RefusPair(op.id, op.appareil, 'deja_soumis', op.fiche));
      return;
    }
    b['etat'] = 'soumis';
    histo.add([op.hlc, 'soumis', op.appareil]);
    return;
  }
  if (b['etat'] == null) {
    e.refusees.add(RefusPair(op.id, op.appareil, 'demande_inconnue', op.fiche));
    return;
  }
  if (op.type == 'valider' || op.type == 'rejeter') {
    if (b['etat'] != 'soumis') {
      e.refusees.add(RefusPair(op.id, op.appareil, 'deja_decide', '${op.fiche} est ${b['etat']}'));
      return;
    }
    b['etat'] = op.type == 'valider' ? 'valide' : 'rejete';
    histo.add([op.hlc, b['etat'], op.appareil]);
    return;
  }
  e.refusees.add(RefusPair(op.id, op.appareil, 'type_invalide', op.type));
}

/// Les droits du BANC (la matrice réelle vit dans rbac.json) : rôles habilités par collection et par type d'opération (`*` = tous les types).
const Map<String, Map<String, List<String>>> droitsBancPair = {
  'stock': {
    'creer': ['stock', 'da'],
    'entree': ['stock', 'da'],
    'bail': ['stock', 'da'],
    'sortie': ['stock', 'da', 'infirmier', 'pharmacien'],
  },
  'besoins': {
    'soumettre': ['stock', 'infirmier', 'medecin', 'da', 'caissier'],
    'valider': ['da'],
    'rejeter': ['da'],
  },
  'patients': {'*': ['reception', 'infirmier', 'medecin', 'da', 'x'], 'trancher': ['da', 'mere']},
  'rendezvous': {'*': ['reception', 'infirmier', 'medecin', 'da', 'x'], 'trancher': ['da', 'mere']},
  'constantes': {'*': ['infirmier', 'medecin', 'x']},
  'notes': {'*': ['infirmier', 'medecin', 'x']},
  'factures': {'*': ['caissier', 'da', 'x'], 'trancher': ['da', 'mere']},
  'avoirs': {'*': ['comptable', 'da', 'x'], 'trancher': ['da', 'mere']},
  'lots': {'creer': ['stock', 'da'], 'entree': ['stock', 'da'], 'bail': ['stock', 'da'], 'sortie': ['stock', 'da', 'infirmier', 'pharmacien']},
  'mouvements': {'*': ['stock', 'da', 'infirmier', 'pharmacien', 'x']},
  'produits': {'*': ['stock', 'da', 'x'], 'trancher': ['da', 'mere']},
  'admissions': {'*': ['reception', 'infirmier', 'medecin', 'da', 'x'], 'trancher': ['da', 'mere']},
  'ecritures': {'*': ['comptable', 'da', 'x'], 'trancher': ['da', 'mere']},
  'prescriptions': {'*': ['medecin', 'x']},
  'consultations': {'*': ['medecin', 'da', 'x'], 'trancher': ['da', 'mere']},
  'dossiersConsultation': {'*': ['medecin', 'x'], 'trancher': ['da', 'mere']},
  'antecedents': {'*': ['medecin', 'infirmier', 'x'], 'trancher': ['da', 'mere']},
  'appels': {'*': ['reception', 'da', 'x'], 'trancher': ['da', 'mere']},
  'observations': {'*': ['infirmier', 'medecin', 'x'], 'trancher': ['da', 'mere']},
  'releves': {'*': ['infirmier', 'medecin', 'x']},
};

/// Construit un contrôle de droits depuis une table (celle du banc, ou celle déduite de la matrice RBAC quand le poste la branchera).
DroitsOperation droitsDepuisTable(Map<String, Map<String, List<String>>> table) => (op) {
      final c = table[op.collection];
      if (c == null) return false;
      final roles = c[op.type] ?? c['*'];
      return roles != null && op.role != null && roles.contains(op.role);
    };

/// Journal d'un appareil au relais : rang contigu, dépôt idempotent ; un trou est DÉTECTÉ, jamais comblé en silence.
class JournalPair {
  final Map<String, List<Object?>> _parAppareil = {};

  /// `ok` · `deja` (idempotent). Lève [StateError] sur un trou de rang.
  String deposer(String appareil, int n, Object? enveloppe) {
    final l = _parAppareil.putIfAbsent(appareil, () => []);
    if (n <= l.length) return 'deja';
    if (n != l.length + 1) throw StateError('trou de rang pour $appareil : attendu ${l.length + 1}, reçu $n');
    l.add(enveloppe);
    return 'ok';
  }

  List<({int n, Object? enveloppe})> releve(String appareil, int depuisN, {int limite = 100}) {
    final l = _parAppareil[appareil] ?? const [];
    final fin = (depuisN + limite) > l.length ? l.length : depuisN + limite;
    return [for (var i = depuisN; i < fin; i++) (n: i + 1, enveloppe: l[i])];
  }

  Iterable<String> get appareils => _parAppareil.keys;
}

/// L'écran du manifeste qui PORTE chaque collection de la règle de fusion : ses droits (voir, éditer, annuler) sont ceux que la matrice `rbac.json` donne au rôle
/// sur cet écran. Une collection ajoutée à [famillesPair] sans ligne ici est REFUSÉE à l'émission (refus nommé), jamais ouverte à tous.
const Map<String, String> ecranParCollectionPair = {
  'patients': 'm1-patients',
  'rendezvous': 'm2-rendezvous',
  'constantes': 'm1-constantes',
  'notes': 'm13-notes-service',
  'factures': 'm8-factures',
  'avoirs': 'm8-facture-avoir',
  'lots': 'm6-lots',
  'mouvements': 'm6-mouvements',
  'produits': 'm6-stock-detail',
  'admissions': 'm3-admissions',
  'ecritures': 'm12-ecritures',
  'prescriptions': 'm2-prescriptions',
  'stock': 'm6-stock-detail',
  'besoins': 'm7-besoins',
  'consultations': 'm2-consultations',
  'dossiersConsultation': 'm2-dossiers-consultation',
  'antecedents': 'm1-antecedents',
  'appels': 'm2-registre-appels',
  'observations': 'm3-observation',
  'releves': 'm3-feuille-temperature',
};

/// Les collections de famille A que le pont d'activité du POSTE ne doit PAS encore porter : le catalogue des produits est écrit par la mère seule (famille R du pont
/// existant) et les admissions ont leur propre marquage de lit dans `fusion_activite.dart`. Le poste retranche cet ensemble de ses familles A tant que ces deux
/// collections ne sont pas branchées volontairement.
const Set<String> collectionsPairSansPontPoste = {'produits', 'admissions'};

/// Ceux qui TRANCHENT un conflit ou VALIDENT un flux : une décision institutionnelle, pas une saisie. `mere` est l'appareil de la mère (ses décisions à son retour).
const List<String> rolesQuiTranchentPair = ['da', 'direction', 'admin', 'mere'];
const List<String> rolesQuiValidentPair = ['da', 'admin'];

/// Les droits de la règle de fusion, DÉDUITS de la matrice RBAC (source unique, engendrée par la maquette) au lieu de la table du banc : écrire = éditer l'écran
/// de la collection ; archiver ou restaurer = annuler ; trancher et valider = rôles institutionnels. Tout ce qui n'est pas listé est refusé.
/// [peutEditer] et [peutAnnuler] : `(role, ecran) -> bool`, c'est-à-dire `MatriceDroits.peutEditer`.
DroitsOperation droitsDepuisMatrice({
  required bool Function(String role, String ecran) peutEditer,
  required bool Function(String role, String ecran) peutAnnuler,
  Map<String, String> ecrans = ecranParCollectionPair,
}) =>
    (op) {
      final role = op.role;
      final ecran = ecrans[op.collection];
      if (role == null || ecran == null) return false;
      switch (op.type) {
        case 'trancher':
          return rolesQuiTranchentPair.contains(role);
        case 'valider':
        case 'rejeter':
          return rolesQuiValidentPair.contains(role);
        case 'archiver':
        case 'restaurer':
          return peutAnnuler(role, ecran);
        default:
          return peutEditer(role, ecran);
      }
    };
