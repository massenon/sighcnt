/// ÉMISSION DE FACTURE — port de `enregistrer()` et de `totaux()` de `m8-facturation` (prototype_html/assets/js/modules/m8-facturation.js).
///
/// L'écran de la maquette garde ces règles dans sa fermeture ; elles sont ici sans écran ni magasin : le poste, le mobile
/// de secours et la mère appellent la MÊME décision. Les vecteurs (`test/vecteurs/emission.json`) sont engendrés en
/// PILOTANT l'écran réel (`build/vecteurs-emission.js`), jamais écrits à la main.
///
/// Pourquoi DEUX pièces pour un assuré (`-A` couvert, `-B` non couvert) :
///   · les lignes couvertes se réclament à l'assureur (relevé, facture mensuelle — contestable ligne à ligne) ;
///   · les lignes qu'aucune compagnie ne couvre (certificats hors SOS, planification familiale, exclus de la convention)
///     ne regardent que le patient : les mêler à la pièce de l'assureur rendrait la créance indémontrable le jour du litige ;
///   · la base MECeF ne porte que la part réglée par le patient (exigence écrite du cahier de charge).
/// Un patient non assuré, ou dont toutes les lignes sont du même côté, reçoit UNE pièce sans suffixe.
///
/// Reste porté fidèlement et signalé (docs/architecture/ECARTS-MAQUETTE.md, E6) : le millésime du numéro est écrit en dur
/// (« FN-2026- ») et le rang compte toutes les factures, non celles de l'année.
library;

import '../format/js.dart';
import 'prise_en_charge.dart';

/// Refus NOMMÉ d'une saisie ou d'une émission : `motif` s'affiche tel quel (RG-03, lignes manquantes…).
class RefusEmission implements Exception {
  const RefusEmission(this.code, this.motif);
  final String code;
  final String motif;
  @override
  String toString() => motif;
}

bool _vrai(Object? v) => v != null && v != '' && v != 0 && v != false;
double _n(Object? v) => nombreOuZero(v);

/// `categorieDe(nature, designation, article)` : la catégorie de garantie décide du taux appliqué.
String categorieLigne(String nature, String? designation, {String? secteur}) {
  final d = designation ?? '';
  if (nature == 'analyse') return 'analyse';
  if (nature == 'hospitalisation') return 'hospitalisation';
  if (nature == 'medicament') {
    return RegExp('vitamin|fortifiant', caseSensitive: false).hasMatch(d)
        ? 'vitamine'
        : 'medicament';
  }
  if (nature == 'acte' && secteur != null && secteur.isNotEmpty) {
    bool a(String motif) =>
        RegExp(motif, caseSensitive: false).hasMatch(secteur);
    if (a('Imagerie')) return 'imagerie';
    if (a('Maternité')) return 'maternite';
    if (a('Chirurgie')) {
      return RegExp('[Cc]onsultation').hasMatch(d) ? 'consultation' : 'chirurgie';
    }
    if (a('Hospitalisation')) return 'hospitalisation';
    if (a('Médecine générale')) {
      return RegExp('[Cc]ertificat').hasMatch(d) ? 'certificat' : 'consultation';
    }
    if (a('Soins')) return 'soin';
  }
  if (RegExp('consultation', caseSensitive: false).hasMatch(d)) {
    return 'consultation';
  }
  if (RegExp('ambulance', caseSensitive: false).hasMatch(d)) return 'ambulance';
  return 'autre';
}

/// L'ajout d'une prestation à la facture (bouton « Ajouter »). Lève [RefusEmission] — la ligne n'est alors PAS ajoutée.
/// [dejaSurLaFacture] : quantité du même médicament déjà posée sur la pièce ; [stockDetail] : disponible en pharmacie.
Map<String, Object?> ligneSaisie({
  required String nature,
  required String designation,
  required num quantite,
  required num prixUnitaire,
  String? produitId,
  String? secteur,
  num remise = 0,
  String typeRemise = 'pct',
  String? motifRemise,
  num? stockDetail,
  num dejaSurLaFacture = 0,
}) {
  if (nature == 'libre' && designation.trim().isEmpty) {
    throw const RefusEmission('DESIGNATION_VIDE', 'Saisir une désignation.');
  }
  final q = _n(quantite), prix = _n(prixUnitaire);
  if (q <= 0) {
    throw const RefusEmission(
        'QUANTITE_NULLE', 'La quantité doit être positive.');
  }
  if (produitId != null && stockDetail != null && q + dejaSurLaFacture > stockDetail) {
    throw RefusEmission('RG03_STOCK',
        'RG-03 — stock insuffisant en pharmacie (${_texte(stockDetail)} disponibles).');
  }
  final rem = _n(remise);
  final pct = typeRemise == 'pct';
  final remiseMontant = pct
      ? arrondiJs(prix * (rem < 100 ? rem : 100) / 100)
      : (rem < prix ? rem : prix);
  return {
    'nature': nature,
    'designation': designation,
    'quantite': q,
    'prixUnitaire': prix,
    'produitId': produitId,
    'remisePct': pct ? (rem < 100 ? rem : 100) : null,
    'remiseUnitaire': remiseMontant,
    'motifRemise': _vrai(motifRemise) ? motifRemise : null,
    'prixNet': prix - remiseMontant,
    'categorie': categorieLigne(nature, designation, secteur: secteur),
  };
}

String _texte(num v) => v == v.truncate() ? '${v.truncate()}' : '$v';

num _montantNet(Map l) =>
    _n(l['quantite']) * (l['prixNet'] != null ? _n(l['prixNet']) : _n(l['prixUnitaire']));

/// Les totaux de la pièce à émettre (`totaux()` de l'écran) : la répartition passe ligne par ligne par le moteur RG-09.
class TotauxEmission {
  const TotauxEmission(
      {required this.brut,
      required this.remises,
      required this.total,
      required this.partAssureur,
      required this.partPatient,
      required this.repartition});
  final double brut;
  final double remises;
  final double total;
  final double partAssureur;
  final double partPatient;
  final Repartition repartition;
}

TotauxEmission totauxEmission({
  required Map<String, Object?>? patient,
  required List<Map<String, Object?>> lignes,
  required String date,
  List<Map<String, Object?>> couvertures = const [],
  List<Map<String, Object?>> souscripteurs = const [],
  List<Map<String, Object?>> garanties = const [],
}) {
  final r = repartir(
    patient: patient,
    lignes: [
      for (final l in lignes)
        {
          'libelle': l['designation'],
          'categorie': _vrai(l['categorie']) ? l['categorie'] : 'autre',
          'montant': _montantNet(l),
        }
    ],
    date: date,
    couvertures: couvertures,
    souscripteurs: souscripteurs,
    garanties: garanties,
  );
  return TotauxEmission(
    brut: lignes.fold(0.0, (a, l) => a + _n(l['quantite']) * _n(l['prixUnitaire'])),
    remises: lignes.fold(0.0, (a, l) => a + _n(l['quantite']) * _n(l['remiseUnitaire'])),
    total: r.total,
    partAssureur: r.partAssureur,
    partPatient: r.partPatient,
    repartition: r,
  );
}

/// Une sortie de stock née d'une facture réglée (CDCT §10.7) : RG-03, justificatif = numéro de la première pièce.
class SortieStock {
  const SortieStock(this.produitId, this.quantite, this.justificatif,
      {required this.avant, required this.apres});
  final String produitId;
  final double quantite;
  final String justificatif;
  final ({double stockDetail, double stock}) avant;
  final ({double stockDetail, double stock}) apres;
}

class ResultatEmission {
  const ResultatEmission({required this.pieces, required this.sorties});

  /// Les pièces dans l'ordre d'émission : `-A` (couvert) puis `-B` (non couvert), ou une seule.
  /// `mecef` dit si la pièce part à la normalisation (le numéro est tiré par l'appelant : un hasard n'est pas une règle).
  final List<Map<String, Object?>> pieces;
  final List<SortieStock> sorties;
}

/// `enregistrer(proforma)` : une pièce pour un patient non assuré, DEUX pour un assuré dont les lignes se partagent.
///
/// [lignes] : lignes de [ligneSaisie] ; [reglement] : montant saisi (`null` = la part patient proposée par l'écran) ;
/// [rangDebut] : nombre de factures actives avant l'émission ; [produits] : `{id, stockDetail, stock}` des médicaments.
ResultatEmission emettreFacture({
  required Map<String, Object?> patient,
  required List<Map<String, Object?>> lignes,
  required String dateRepartition,
  required String dateFacture,
  required String type,
  required String mode,
  required int rangDebut,
  num? reglement,
  bool proforma = false,
  bool dissocier = false,
  List<Map<String, Object?>> couvertures = const [],
  List<Map<String, Object?>> souscripteurs = const [],
  List<Map<String, Object?>> garanties = const [],
  List<Map<String, Object?>> produits = const [],
}) {
  if (lignes.isEmpty) {
    throw const RefusEmission(
        'SANS_PRESTATION', 'Ajouter au moins une prestation.');
  }
  final t = totauxEmission(
      patient: patient,
      lignes: lignes,
      date: dateRepartition,
      couvertures: couvertures,
      souscripteurs: souscripteurs,
      garanties: garanties);
  final couvre = t.partAssureur > 0;

  final enrichies = <Map<String, Object?>>[
    for (var i = 0; i < lignes.length; i++)
      () {
        final l = lignes[i];
        final d = i < t.repartition.lignes.length
            ? t.repartition.lignes[i]
            : const <String, Object?>{};
        final net = l['prixNet'] != null ? _n(l['prixNet']) : _n(l['prixUnitaire']);
        final montant = _n(l['quantite']) * net;
        return {
          ...l,
          'prixNet': net,
          'montant': montant,
          'partAssureur': _n(d['partAssureur']),
          'partPatient': d['partPatient'] != null ? _n(d['partPatient']) : montant,
          'motifCouverture': _vrai(d['motif']) ? d['motif'] : null,
          'taux': _vrai(d['taux']) ? d['taux'] : 0,
        };
      }()
  ];
  final couvertes = enrichies.where((l) => _n(l['partAssureur']) > 0).toList();
  final nonCouvertes =
      enrichies.where((l) => _n(l['partAssureur']) == 0).toList();

  final volets = (!couvre || couvertes.isEmpty || nonCouvertes.isEmpty)
      ? [(enrichies, null as String?)]
      : [(couvertes, 'couvert'), (nonCouvertes, 'non_couvert')];

  double somme(List<Map<String, Object?>> ls, double Function(Map) f) =>
      ls.fold(0.0, (a, l) => a + f(l));

  final sous = t.repartition.souscripteurId == null
      ? null
      : souscripteurs
          .where((s) => '${s['id']}' == t.repartition.souscripteurId)
          .firstOrNull;
  final saisi = reglement == null ? t.partPatient : _n(reglement);
  final pieces = <Map<String, Object?>>[];
  var dejaRegle = 0.0;

  for (var rang = 0; rang < volets.length; rang++) {
    final (ls, volet) = volets[rang];
    final totalPiece = somme(ls, (l) => _n(l['montant']));
    final assPiece = somme(ls, (l) => _n(l['partAssureur']));
    final patPiece = somme(ls, (l) => _n(l['partPatient']));
    final remisePiece = somme(
        ls, (l) => _n(l['quantite']) * _n(l['remiseUnitaire']));
    // Le règlement saisi couvre d'abord la pièce à la charge du patient.
    final aRegler = proforma ? 0.0 : (saisi < t.partPatient ? saisi : t.partPatient);
    var reglePiece = proforma ? 0.0 : (aRegler < patPiece ? aRegler : patPiece);
    if (rang > 0) {
      final reste = aRegler - dejaRegle;
      final borne = reste < patPiece ? reste : patPiece;
      reglePiece = borne > 0 ? borne : 0.0;
    }
    dejaRegle += reglePiece;

    final suffixe = volet == 'couvert' ? '-A' : (volet == 'non_couvert' ? '-B' : '');
    final normalisee = !(proforma || patPiece == 0);
    pieces.add({
      'numero':
          '${proforma ? 'PRO-2026-' : 'FN-2026-'}${(rangDebut + 1 + rang).toString().padLeft(5, '0')}$suffixe',
      'mecef': normalisee,
      'baseMecef': proforma ? 0.0 : reglePiece,
      'patientId': patient['id'],
      'patient': '${patient['nom']} ${patient['prenom']}',
      'patientCode': dissocier ? null : patient['code'],
      'operationDissociee': dissocier,
      'date': dateFacture,
      'type': type,
      'volet': volet,
      'libelleVolet': volet == 'couvert'
          ? 'Prestations couvertes par l’assurance'
          : (volet == 'non_couvert'
              ? 'Prestations non couvertes — à la charge du patient'
              : null),
      'lignes': ls,
      'montantHT': totalPiece,
      'montantTTC': totalPiece,
      'montantRemises': remisePiece,
      'assureur': assPiece > 0 ? patient['assureur'] : null,
      'souscripteur': sous?['nom'],
      'numeroPolice': sous?['police'],
      'tauxPriseEnCharge': totalPiece != 0 ? arrondiJs(assPiece * 100 / totalPiece) : 0,
      'partAssurance': assPiece,
      'partPatient': patPiece,
      'montantPaye': reglePiece,
      'reliquat': patPiece - reglePiece,
      'modePaiement': mode,
      'statutPaiement': proforma
          ? 'impayee'
          : (reglePiece >= patPiece ? 'soldee' : (reglePiece > 0 ? 'partielle' : 'impayee')),
      'statutMecef': normalisee ? 'valide' : 'en_attente',
      'proforma': proforma,
    });
  }

  // Sortie automatique du stock pour les médicaments facturés (CDCT §10.7) — jamais sur une pro-forma.
  final sorties = <SortieStock>[];
  if (!proforma) {
    final stocks = {
      for (final p in produits)
        '${p['id']}': (stockDetail: _n(p['stockDetail']), stock: _n(p['stock']))
    };
    for (final l in lignes.where((l) => l['produitId'] != null)) {
      final id = '${l['produitId']}';
      final avant = stocks[id];
      if (avant == null) continue;
      final q = _n(l['quantite']);
      final apres = (
        stockDetail: avant.stockDetail - q > 0 ? avant.stockDetail - q : 0.0,
        stock: avant.stock - q > 0 ? avant.stock - q : 0.0,
      );
      stocks[id] = apres;
      sorties.add(SortieStock(id, q, 'Facture ${pieces.first['numero']}',
          avant: avant, apres: apres));
    }
  }
  return ResultatEmission(pieces: pieces, sorties: sorties);
}
