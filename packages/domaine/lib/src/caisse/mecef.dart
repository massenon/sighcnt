/// MECeF (SIMULATION) — port de `prototype_html/assets/js/modules/mecef.js` : la facturation normalisée vue du poste.
///
/// Ce qui est porté, c'est le COMPORTEMENT DE LA MAQUETTE : décomposition fiscale d'un montant selon le régime de TVA, facture normalisée imprimée,
/// code de certification, synchronisation avec le dispositif, avoir MECeF. Les échanges avec le dispositif fiscal y sont un tirage pseudo-aléatoire
/// GRAINÉ — le boîtier physique (modèle, interface, protocole) n'est dans aucun document du dépôt : son intégration attend la Direction
/// (ADR-0003, dix questions posées au fournisseur et à la DGI). Aucune de ces fonctions ne prétend certifier quoi que ce soit.
///
/// Rejoué sur `test/vecteurs/mecef.json`, engendré en pilotant le module réel de la maquette pour chaque régime de TVA.
///
/// Portés fidèlement et signalés (docs/architecture/ECARTS-MAQUETTE.md) : E13 (l'enregistrement de la configuration fiscale n'est pas relu : les
/// taux restent ceux du référentiel) ; E14 (« IFU client » imprime l'IFU de la clinique pour tous les clients) ; E15 (l'avoir MECeF ne contrôle que
/// « montant ≤ facture », jamais le cumul des avoirs, et s'ajoute aux deux autres canaux d'avoir).
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import '../impression/etat.dart';
import '../impression/identite.dart';

/// Un régime de TVA du référentiel `PARAM_FISCAL.regimesTva`.
class RegimeTva {
  const RegimeTva(this.id, this.libelle, this.taux);
  final String id;
  final String libelle;
  final num taux;
}

/// `D.PARAM_FISCAL`, tel que la maquette le déclare (document : facture SoBAPS n° 26FNA00026 certifiée MECeF).
class ParamFiscal {
  const ParamFiscal({
    this.regimeTva = 'exonere',
    this.regimes = const [
      RegimeTva('exonere', 'Exonéré — produits et actes de santé', 0),
      RegimeTva('normal', 'Taux normal 18 %', 18),
    ],
    this.libelleTva = 'TVA 18 %',
    this.tauxAib = 1,
    this.libelleAib = 'AIB 1 %',
    this.codeAib = 'AIB2',
    this.mentionExoneration =
        'Opérations exonérées de TVA — produits et actes de santé.',
    this.mentionMontant = 'Arrêté la présente facture à la somme de',
  });
  final String regimeTva;
  final List<RegimeTva> regimes;
  final String libelleTva;
  final num tauxAib;
  final String libelleAib;
  final String codeAib;
  final String mentionExoneration;
  final String mentionMontant;

  RegimeTva get regime =>
      regimes.where((r) => r.id == regimeTva).firstOrNull ?? regimes.first;
  num get tauxTva => regime.taux;

  factory ParamFiscal.depuis(Map<String, Object?> j) {
    final aib = (j['aib'] as Map?)?.cast<String, Object?>() ?? const {};
    final tva = (j['tva'] as Map?)?.cast<String, Object?>() ?? const {};
    return ParamFiscal(
      regimeTva: '${j['regimeTva'] ?? 'exonere'}',
      regimes: [
        for (final r in (j['regimesTva'] as List? ?? const []))
          RegimeTva('${(r as Map)['id']}', '${r['label']}', r['taux'] as num)
      ],
      libelleTva: '${tva['libelle'] ?? 'TVA 18 %'}',
      tauxAib: (aib['taux'] as num?) ?? 1,
      libelleAib: '${aib['libelle'] ?? 'AIB 1 %'}',
      codeAib: '${aib['code'] ?? 'AIB2'}',
      mentionExoneration: '${j['mentionExoneration']}',
      mentionMontant: '${j['mentionMontant']}',
    );
  }
}

/// `decomposer(montantTTC)` : HT, TVA, AIB et net à payer selon le régime en vigueur.
class Decomposition {
  const Decomposition(this.ht, this.tva, this.aib, this.ttc, this.net);
  final double ht, tva, aib, ttc, net;
}

Decomposition decomposer(num ttc, ParamFiscal p) {
  final t = p.tauxTva;
  final ht = t != 0 ? arrondiJs(ttc * 100 / (100 + t)) : ttc.toDouble();
  final tva = ttc - ht;
  final aib = arrondiJs(ht * p.tauxAib / 100);
  return Decomposition(ht, tva, aib, ttc.toDouble(), ttc + aib);
}

/// La TVA d'un montant TTC telle que les REGISTRES la calculent (`colTVA`, KPI) : elle diffère parfois de 1 FCFA de `decomposer().tva`.
double tvaRegistre(num ttc, ParamFiscal p) =>
    arrondiJs(ttc * p.tauxTva / (100 + p.tauxTva));

/// Le HT des registres (`Math.round(ttc * 100 / (100 + taux))`, y compris à taux 0).
double htRegistre(num ttc, ParamFiscal p) =>
    arrondiJs(ttc * 100 / (100 + p.tauxTva));

// --- le tirage graine de la maquette (`C.seeded`, `C.between`, `C.pick`) ------------------------------------------------
/// `C.seeded(graine)` : `s = (s * 9301 + 49297) % 233280`, `s / 233280`. Une graine nulle vaut 42.
double Function() tirage(int graine) {
  var s = graine == 0 ? 42 : graine;
  return () {
    s = (s * 9301 + 49297) % 233280;
    return s / 233280;
  };
}

int _entre(double Function() rnd, int a, int b) =>
    (rnd() * (b - a + 1)).floor() + a;

/// L'identifiant MECeF simulé : `MECEF` + sept chiffres tirés d'une graine (l'appelant la tire de son horloge, comme la maquette de `Date.now()`).
String numeroMecefSimule(int graine) =>
    'MECEF${_entre(tirage(graine), 1000000, 9999999)}';

/// Code de certification MECeF/DGI : six groupes de quatre caractères.
String codeMecef(int graine) {
  const alphabet = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  final rnd = tirage(graine == 0 ? 1 : graine);
  return [
    for (var g = 0; g < 6; g++)
      [for (var i = 0; i < 4; i++) alphabet[(rnd() * alphabet.length).floor()]]
          .join()
  ].join('-');
}

/// La graine d'une pièce : les six derniers chiffres de son identifiant MECeF (à défaut, de son numéro) ; 1 si aucun.
int graineDe(Map<String, Object?> f) {
  final chiffres = '${f['numeroMecef'] ?? f['numero']}'.replaceAll(RegExp(r'\D'), '');
  final fin = chiffres.length > 6 ? chiffres.substring(chiffres.length - 6) : chiffres;
  final n = int.tryParse(fin) ?? 0;
  return n == 0 ? 1 : n;
}

/// Les compteurs imprimés (« MECeF Compteurs : 4386/04506 »).
String compteurs(int graine) {
  final a = graine % 9999;
  return '${a.toString().padLeft(4, '0')}/${(a + 120).toString().padLeft(5, '0')}';
}

// --- facture normalisée imprimée --------------------------------------------------------------------------------------
class FactureNormalisee {
  const FactureNormalisee(
      {required this.lignes,
      required this.taxes,
      required this.totaux,
      required this.netAPayer,
      required this.enLettres,
      required this.codeDgi,
      required this.nim,
      required this.compteurs,
      required this.mentionExoneration});
  final TableauEtat lignes;
  final TableauEtat taxes;
  final TableauEtat totaux;
  final double netAPayer;
  final String enLettres;
  final String codeDgi;
  final String nim;
  final String compteurs;

  /// Présente seulement au régime exonéré.
  final String? mentionExoneration;
}

/// La facture de vente normalisée, d'après la facture SoBAPS n° 26FNA00026 : colonnes HT/TTC, TVA, AIB, montant en toutes lettres, bloc de certification.
FactureNormalisee factureNormalisee(Map<String, Object?> f, ParamFiscal p) {
  final dec = decomposer(nombreOuZero(f['montantTTC']), p);
  final detail = (f['lignes'] as List?) ?? const [];
  final lignes = detail.isNotEmpty
      ? [for (final l in detail) (l as Map).cast<String, Object?>()]
      : [
          {
            'designation': 'Prestation — ${f['type']}',
            'quantite': 1,
            'prixUnitaire': f['montantTTC']
          }
        ];
  num q(Map l) => nombreOuZero(l['quantite']);
  num pu(Map l) => nombreOuZero(l['prixUnitaire']);
  String m(num v) => money(v, avecDevise: false);
  final graine = graineDe(f);
  return FactureNormalisee(
    lignes: TableauEtat(colonnes: [
      ColonneEtat(libelle: 'Désignation', valeur: (l) => l['designation']),
      ColonneEtat(libelle: 'Qté', valeur: (l) => l['quantite'], droite: true),
      ColonneEtat(
          libelle: 'P.U. HT',
          valeur: (l) => m(decomposer(pu(l), p).ht),
          droite: true),
      ColonneEtat(
          libelle: 'P.U. TTC', valeur: (l) => m(pu(l)), droite: true),
      ColonneEtat(
          libelle: 'Montant HT',
          valeur: (l) => m(decomposer(q(l) * pu(l), p).ht),
          droite: true,
          somme: (l) => decomposer(q(l) * pu(l), p).ht),
      ColonneEtat(
          libelle: 'Montant TTC',
          valeur: (l) => m(q(l) * pu(l)),
          droite: true,
          somme: (l) => q(l) * pu(l)),
    ], lignes: lignes),
    taxes: TableauEtat(colonnes: [
      ColonneEtat(libelle: 'Taxe', valeur: (r) => r['k']),
      ColonneEtat(libelle: 'Montant', valeur: (r) => r['v'], droite: true),
    ], lignes: [
      {'k': p.libelleTva, 'v': m(dec.tva)},
      {'k': '${p.libelleAib} (${p.codeAib})', 'v': m(dec.aib)},
    ]),
    totaux: TableauEtat(colonnes: [
      ColonneEtat(libelle: 'Rubrique', valeur: (r) => r['k']),
      ColonneEtat(libelle: 'Montant', valeur: (r) => r['v'], droite: true),
    ], lignes: [
      {'k': 'TOTAL HT', 'v': m(dec.ht)},
      {'k': 'TOTAL TTC', 'v': m(nombreOuZero(f['montantTTC']))},
      {'k': 'NET À PAYER', 'v': m(dec.net)},
    ]),
    netAPayer: dec.net,
    enLettres: montantEnLettres(dec.net),
    codeDgi: codeMecef(graine),
    nim: f['numeroMecef'] != null && '${f['numeroMecef']}'.isNotEmpty
        ? '${f['numeroMecef']}'
        : 'en attente d’attribution',
    compteurs: compteurs(graine),
    mentionExoneration: p.tauxTva == 0 ? p.mentionExoneration : null,
  );
}

/// `IFU client` imprimé : celui de la CLINIQUE, pour tous les clients (écart E14).
const ifuClientImprime = IdentiteClinique.ifu;

// --- synchronisation --------------------------------------------------------------------------------------------------
const codesRejet = [
  ('E-101', 'Identifiant fiscal du client absent ou invalide'),
  ('E-204', 'Montant de TVA incohérent avec le montant HT'),
  ('E-307', 'Numérotation non séquentielle'),
  ('E-412', 'Dépassement du délai de transmission'),
  ('E-500', 'Dispositif temporairement indisponible'),
];

/// La réponse du dispositif pour une facture : ce qu'il faut écrire dessus.
class ReponseDispositif {
  const ReponseDispositif(this.statutMecef, this.numeroMecef, this.codeRetour,
      this.dateTransmission);
  final String statutMecef;
  final String? numeroMecef;
  final String codeRetour;
  final String dateTransmission;
  Map<String, Object?> get patch => {
        'statutMecef': statutMecef,
        'numeroMecef': numeroMecef,
        'codeRetour': codeRetour,
        'dateTransmission': dateTransmission,
      };
}

/// « Synchroniser maintenant » : transmet UN LOT. Le tirage est graine par la taille du lot (`n * 7 + 13`) : 88 % acceptées, les autres rejetées
/// avec un code de retour. [jour] : `YYYY-MM-DD`.
List<ReponseDispositif> synchroniser(int enAttente, String jour) {
  final rnd = tirage(enAttente * 7 + 13);
  return [
    for (var i = 0; i < enAttente; i++)
      () {
        final accepte = rnd() > 0.12;
        final numero = accepte ? 'MECEF${_entre(rnd, 1000000, 9999999)}' : null;
        final code = accepte
            ? 'OK-200'
            : codesRejet[(rnd() * codesRejet.length).floor() % codesRejet.length].$1;
        return ReponseDispositif(
            accepte ? 'valide' : 'rejete', numero, code, jour);
      }()
  ];
}

/// « Transmettre » (une facture) et « Corriger et réémettre » : acceptation d'office, identifiant tiré de l'horloge (les graines `% 99999`
/// et `% 88888` de la maquette sont celles de l'appelant, qui connaît son horloge).
ReponseDispositif transmettreUne(int graine, String jour) => ReponseDispositif(
    'valide', numeroMecefSimule(graine), 'OK-200', jour);

// --- avoir MECeF -------------------------------------------------------------------------------------------------------
class RefusAvoirMecef implements Exception {
  const RefusAvoirMecef(this.motif);
  final String motif;
  @override
  String toString() => motif;
}

const motifsAvoirMecef = [
  'Erreur de facturation',
  'Prestation non réalisée',
  'Remise commerciale',
  'Annulation de commande',
  'Erreur de tarif',
];

/// La fiche `avoirs` d'un avoir MECeF : transmis et validé d'office (simulation). [graine] : tirée de l'horloge par l'appelant.
/// `mecef: true` dit qu'un identifiant est attribué (l'appelant le pose via [numeroMecefSimule]).
Map<String, Object?> avoirMecef({
  required Map<String, Object?>? facture,
  required Map<String, Object?> saisie,
  required List<Map<String, Object?>> avoirs,
}) {
  bool vide(String k) => '${saisie[k] ?? ''}'.trim().isEmpty;
  if (['factureId', 'date', 'montant', 'motif'].any(vide)) {
    throw const RefusAvoirMecef('Le formulaire comporte des erreurs.');
  }
  final montant = nombreOuZero(saisie['montant']);
  if (facture != null && montant > nombreOuZero(facture['montantTTC'])) {
    throw const RefusAvoirMecef(
        'Le montant de l’avoir ne peut excéder celui de la facture.');
  }
  final date = '${saisie['date']}';
  final prefixe = 'AV-${date.length >= 4 ? date.substring(0, 4) : date}-';
  var max = 0;
  for (final a in avoirs) {
    final r = '${a['reference'] ?? ''}';
    if (r.startsWith(prefixe)) {
      final k = int.tryParse(r.substring(prefixe.length)) ?? 0;
      if (k > max) max = k;
    }
  }
  return {
    ...saisie,
    'montant': montant,
    if (facture != null) ...{
      'factureNumero': facture['numero'],
      'patient': facture['patient'],
      'patientCode': facture['patientCode'],
    },
    'reference': '$prefixe${(max + 1).toString().padLeft(4, '0')}',
    'mecef': true,
    'statutMecef': 'valide',
  };
}
