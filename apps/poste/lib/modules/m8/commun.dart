import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/piece.dart';

num n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);
String m(Object? v) => money(v, avecDevise: false);
String dateDe(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : dateFR(d);
}

/// `D.MODES_PAIEMENT` : (identifiant, libellé, icône).
const modesPaiement = [
  ('especes', 'Espèces', 'banknote'),
  ('tpe', 'TPE (carte bancaire)', 'credit-card'),
  ('mtn', 'MTN Mobile Money', 'smartphone'),
  ('moov', 'Moov Money', 'smartphone'),
  ('assurance', 'Prise en charge assurance', 'shield-check'),
];

String modeLabel(Object? id) =>
    modesPaiement.where((x) => x.$1 == id).map((x) => x.$2).firstOrNull ??
    '${id ?? ''}';

num partNonAssuree(Iterable<Fiche> lignes) => lignes.fold<num>(0, (a, l) {
      if (n(l['partAssureur']) > 0) return a;
      final montant = l['montant'] != null
          ? n(l['montant'])
          : n(l['quantite']) *
              (l['prixNet'] != null ? n(l['prixNet']) : n(l['prixUnitaire']));
      return a + montant;
    });

List<Fiche> lignesDe(Fiche f) {
  final l = f['lignes'];
  if (l is List && l.isNotEmpty)
    return [for (final x in l) (x as Map).cast<String, Object?>()];
  return [
    {
      'designation': 'Prestation — ${f['type']}',
      'quantite': 1,
      'prixUnitaire': f['montantTTC']
    }
  ];
}

/// `etatFacture(f, {proforma})` : la facture normalisée (ou pro-forma, non fiscale) imprimable. Le total des colonnes est REFAIT depuis les lignes.
PieceA4 pieceFacture(Fiche f,
    {bool proforma = false,
    Fiche? jumelle,
    required String utilisateur,
    required DateTime edite,
    required String reference}) {
  final lignes = lignesDe(f);
  final avecAssurance =
      lignes.any((l) => n(l['partAssureur']) > 0) || f['assureur'] != null;
  num montantLigne(Fiche l) => l['montant'] != null
      ? n(l['montant'])
      : n(l['quantite']) * n(l['prixUnitaire']);
  num partPat(Fiche l) => l['partPatient'] != null
      ? n(l['partPatient'])
      : n(l['quantite']) *
          (l['prixNet'] != null ? n(l['prixNet']) : n(l['prixUnitaire']));
  final colonnes = [
    ColonneEtat(
        libelle: 'Référence',
        valeur: (l) => l['produitId'] ?? l['nature'] ?? '—'),
    ColonneEtat(libelle: 'Désignation', valeur: (l) => l['designation']),
    ColonneEtat(
        libelle: 'Qté',
        valeur: (l) => l['quantite'],
        droite: true,
        somme: (l) => n(l['quantite'])),
    ColonneEtat(
        libelle: 'P.U', valeur: (l) => m(l['prixUnitaire']), droite: true),
    if (avecAssurance)
      ColonneEtat(
          libelle: 'Part ass.',
          valeur: (l) => m(l['partAssureur'] ?? 0),
          droite: true,
          somme: (l) => n(l['partAssureur'])),
    if (avecAssurance)
      ColonneEtat(
          libelle: 'Part pat.',
          valeur: (l) => m(partPat(l)),
          droite: true,
          somme: partPat),
    ColonneEtat(
        libelle: 'Montant',
        valeur: (l) => m(montantLigne(l)),
        droite: true,
        somme: montantLigne),
  ];
  final remises = n(f['montantRemises']);
  final assure = f['assureur'] != null;
  final rep = TableauEtat(colonnes: [
    ColonneEtat(libelle: 'Rubrique', valeur: (r) => r['k']),
    ColonneEtat(libelle: 'Montant', valeur: (r) => r['v'], droite: true),
  ], lignes: [
    {'k': 'Montant brut', 'v': m(n(f['montantTTC']) + remises)},
    if (remises > 0) {'k': 'Remises accordées', 'v': '- ${m(remises)}'},
    {'k': 'Montant total de la facture', 'v': m(f['montantTTC'])},
    if (assure)
      {
        'k':
            'Part assureur ${f['assureur']}${f['souscripteur'] != null ? ' — ${f['souscripteur']}' : ''}',
        'v': m(f['partAssurance'])
      },
    {'k': 'Part à la charge du patient', 'v': m(f['partPatient'])},
    // La part NON ASSURÉE n'est pas le ticket modérateur : elle porte les lignes qu'AUCUNE compagnie ne couvre.
    {
      'k': 'dont part NON ASSURÉE (aucune couverture)',
      'v': m(partNonAssuree(lignes))
    },
    {'k': 'TOTAL DÛ', 'v': m(f['reliquat'] ?? f['partPatient'])},
    {'k': 'Montant réglé', 'v': m(f['montantPaye'])},
    {'k': 'Reste à payer', 'v': m(f['reliquat'])},
    {'k': 'Base normalisée MECeF', 'v': m(f['baseMecef'] ?? f['montantPaye'])},
  ]);
  return PieceA4(
    titre: proforma ? 'Facture pro-forma' : 'Facture normalisée',
    sousTitre:
        '${f['numero']}${f['numeroMecef'] != null && !proforma ? ' — ${f['numeroMecef']}' : ''}',
    filigrane: proforma ? 'Pro-forma' : null,
    reference: reference,
    utilisateur: utilisateur,
    edite: edite,
    cartouche: [
      ('Facture n°', '${f['numero']}'),
      ('Date', dateDe(f['date'])),
      ('Patient', '${f['patient'] ?? ''}'),
      (
        'Dossier',
        f['operationDissociee'] == true
            ? 'opération détachée du dossier'
            : '${f['patientCode'] ?? '—'}'
      ),
      ('Nature', '${f['type'] ?? ''}'),
      (
        'Assurance',
        assure
            ? '${f['assureur']}${f['souscripteur'] != null ? ' — ${f['souscripteur']}' : ''}'
            : 'Aucune'
      ),
      ('N° de police', '${f['numeroPolice'] ?? '—'}'),
      ('RCCM', IdentiteClinique.rccm),
    ],
    blocs: [
      if (f['libelleVolet'] != null)
        BlocTexte(
            '${f['libelleVolet']}${jumelle != null ? ' — pièce jumelle : ${jumelle['numero']}' : ''}',
            gras: true),
      BlocTableau(TableauEtat(colonnes: colonnes, lignes: lignes)),
      BlocTableau(rep),
      BlocTexte(
          '${IdentiteClinique.formuleArrete} : ${montantEnLettres(f['partPatient'])}.',
          gras: true),
      BlocTexte(
          proforma
              ? 'Facture pro-forma — document non fiscal, établi à titre d’estimation. Elle ne vaut pas facture normalisée et ne peut servir de justificatif comptable.'
              : 'Facture normalisée conforme au dispositif de facturation électronique en vigueur en République du Bénin. Mode de règlement : ${modeLabel(f['modePaiement'])}.',
          italique: true),
      if (!proforma && f['numeroMecef'] != null)
        BlocTexte(
            'Identifiant fiscal MECeF : ${f['numeroMecef']} — IFU : ${IdentiteClinique.ifu} — RCCM : ${IdentiteClinique.rccm} — Statut de transmission : ${f['statutMecef'] == 'valide' ? 'validée par l’administration fiscale' : f['statutMecef']}'),
      const BlocTexte(IdentiteClinique.formulePolitesse, gras: true),
    ],
    // Pas de signature patient sur une pièce de caisse : c'est la caisse qui atteste l'encaissement.
    signatures: const [
      Signature('Le Caissier', mention: 'Signature et cachet')
    ],
  );
}

/// Reçu de paiement : détaille les PRESTATIONS réglées ET celles qui restent dues (quel examen précis a été payé, lequel attend).
PieceA4 pieceRecu(Fiche f,
    {Fiche? versement,
    required String utilisateur,
    required DateTime edite,
    required String reference}) {
  final lignes = lignesDe(f).where((l) => l['designation'] != null).toList();
  final payees = lignes.where((l) => l['statutPaiement'] == 'paye').toList();
  final dues = lignes.where((l) => l['statutPaiement'] != 'paye').toList();
  const categories = {
    'analyse': 'Analyse',
    'medicament': 'Médicament',
    'acte': 'Acte',
    'consultation': 'Consultation',
    'hospitalisation': 'Hospitalisation'
  };
  TableauEtat tl(List<Fiche> rows) => TableauEtat(colonnes: [
        ColonneEtat(
            libelle: 'Nature',
            valeur: (l) =>
                categories['${l['categorie']}'] ?? l['categorie'] ?? '—'),
        ColonneEtat(libelle: 'Prestation', valeur: (l) => l['designation']),
        ColonneEtat(
            libelle: 'Qté',
            valeur: (l) => nombre(l['quantite'] ?? 1),
            droite: true,
            somme: (l) => n(l['quantite'] ?? 1)),
        ColonneEtat(
            libelle: 'P.U.', valeur: (l) => m(l['prixUnitaire']), droite: true),
        ColonneEtat(
            libelle: 'Part assureur',
            valeur: (l) =>
                n(l['partAssureur']) > 0 ? m(l['partAssureur']) : '—',
            droite: true,
            somme: (l) => n(l['partAssureur'])),
        ColonneEtat(
            libelle: 'À la charge du patient',
            valeur: (l) => m(l['partPatient']),
            droite: true,
            somme: (l) => n(l['partPatient'])),
      ], lignes: rows, libelleTotal: 'TOTAL');
  TableauEtat rub(List<Fiche> r) => TableauEtat(colonnes: [
        ColonneEtat(libelle: 'Rubrique', valeur: (x) => x['k']),
        ColonneEtat(libelle: 'Montant', valeur: (x) => x['v'], droite: true),
      ], lignes: r);
  final encaisse = versement != null
      ? n(versement['montant'])
      : n(f['dernierReglement'] is Map
          ? (f['dernierReglement'] as Map)['montant']
          : f['montantPaye']);
  final mode = versement?['modePaiement'] ?? f['modePaiement'];
  return PieceA4(
    titre: 'Reçu de paiement',
    sousTitre: '${f['numero']}',
    reference: reference,
    utilisateur: utilisateur,
    edite: edite,
    cartouche: [
      ('Facture', '${f['numero']}'),
      ('Patient', '${f['patient'] ?? ''}'),
      ('Dossier', '${f['patientCode'] ?? ''}'),
      ('Date', dateFR(edite)),
      ('Mode de règlement', modeLabel(mode)),
      ('Encaissé par', utilisateur),
      ('Référence transaction', '${versement?['reference'] ?? '—'}'),
      ('RCCM', IdentiteClinique.rccm),
    ],
    blocs: [
      if (payees.isNotEmpty)
        BlocTableau(tl(payees), titre: 'Prestations réglées'),
      if (f['lignes'] is! List || (f['lignes'] as List).isEmpty)
        BlocTableau(rub([
          {'k': 'Montant total de la facture', 'v': m(f['montantTTC'])},
          {'k': 'Part à la charge du patient', 'v': m(f['partPatient'])},
          {'k': 'Montant encaissé ce jour', 'v': m(encaisse)},
        ])),
      if (dues.isNotEmpty && (f['lignes'] is List)) ...[
        BlocTableau(tl(dues), titre: 'Reste à régler', alerte: true),
        const BlocTexte(
            'Ces prestations ne sont pas exécutées tant qu’elles ne sont pas réglées. Le patient peut revenir les acquitter : ce reçu en fait foi.',
            italique: true),
      ],
      BlocTableau(rub([
        {'k': 'Montant total de la facture', 'v': m(f['montantTTC'])},
        if (n(f['partAssurance']) > 0)
          {
            'k': 'Part assureur — ${f['assureur'] ?? ''}',
            'v': m(f['partAssurance'])
          },
        {'k': 'Part à la charge du patient', 'v': m(f['partPatient'])},
        {'k': 'ENCAISSÉ CE JOUR', 'v': m(encaisse)},
        {'k': 'Total réglé à ce jour', 'v': m(f['montantPaye'])},
        {'k': 'RESTE À PAYER', 'v': m(f['reliquat'])},
      ])),
      BlocTexte(
          '${IdentiteClinique.formuleArrete} : ${montantEnLettres(f['montantPaye'] ?? 0)}.'),
      const BlocTexte(
          'Reçu délivré par la caisse de la CLINIQUE NASSIERA TOO SARL. À conserver et à présenter au laboratoire et à la pharmacie.',
          italique: true),
    ],
    // La signature du patient n'a pas lieu d'être : un encaissement est attesté par celui qui encaisse, pas par celui qui paie.
    signatures: [
      Signature('Le Caissier', nom: utilisateur, mention: 'Signature et cachet')
    ],
  );
}

/// Engagement de paiement : reconnaissance de dette écrite, échéancier par tranches de 30 jours.
PieceA4 pieceEngagement(Fiche f,
    {required String utilisateur,
    required DateTime edite,
    required String reference}) {
  final e = (f['engagement'] as Map?)?.cast<String, Object?>() ?? const {};
  final montant = n(e['montant'] ?? f['reliquat']);
  final tr = (n(e['tranches']).toInt()).clamp(1, 12);
  final part = (montant / tr).round();
  final d0 = DateTime.tryParse('${e['date']}') ?? edite;
  final lignes = [
    for (var i = 0; i < tr; i++)
      {
        'tranche': 'Tranche ${i + 1} sur $tr',
        'echeance': dateFR(d0.add(Duration(days: 30 * i))),
        'montant': i == tr - 1 ? montant - part * (tr - 1) : part,
      }
  ];
  return PieceA4(
    titre: 'Engagement de paiement',
    sousTitre: '${f['numero']} — ${f['patient']}',
    reference: reference,
    utilisateur: utilisateur,
    edite: edite,
    cartouche: [
      ('Facture', '${f['numero']}'),
      ('Patient', '${f['patient'] ?? ''}'),
      ('Dossier', '${f['patientCode'] ?? '—'}'),
      ('Montant dû', money(montant)),
      (
        'Modalité',
        e['modalite'] == 'echeancier' ? 'Échéancier' : 'Tranche unique'
      ),
      ('Reçu par', '${e['recuPar'] ?? '—'}'),
    ],
    blocs: [
      BlocTexte(
          'Je soussigné(e) ${f['patient']}, reconnais devoir à la Clinique NASSIERA TOO la somme de ${montantEnLettres(montant)}, au titre de la facture ${f['numero']}, et m’engage à en effectuer le règlement selon l’échéancier ci-dessous.'),
      BlocTableau(TableauEtat(colonnes: [
        ColonneEtat(libelle: 'Échéance', valeur: (r) => r['tranche']),
        ColonneEtat(libelle: 'Date promise', valeur: (r) => r['echeance']),
        ColonneEtat(
            libelle: 'Montant',
            valeur: (r) => m(r['montant']),
            droite: true,
            somme: (r) => n(r['montant'])),
      ], lignes: lignes)),
      if ('${e['observation'] ?? ''}'.isNotEmpty)
        BlocTexte('Observation : ${e['observation']}'),
    ],
    signatures: [
      Signature('Le patient',
          nom: '${f['patient'] ?? ''}', mention: 'Lu et approuvé'),
      Signature('Le comptable', nom: '${e['recuPar'] ?? ''}')
    ],
  );
}

/// L'identifiant d'un avoir à émettre : la suite de la collection `avoirs` (les écritures de contre-passation le portent comme `pieceId`).
String idAvoirSuivant(Magasin m) =>
    'AVR${(m.collection('avoirs').toutes.length + 1).toString().padLeft(5, '0')}';

/// Écrit un avoir émis par le MOTEUR UNIQUE (`emettreAvoir`, décision B10 du 31/10/2026) : la fiche dans `avoirs`, ses deux écritures de
/// contre-passation en BROUILLON (RG-10), le cumul que la facture PORTE (elle n'est jamais réécrite), le journal (RG-12). [complement] s'ajoute à la
/// fiche (la transmission MECeF y pose son identifiant). Rend la fiche écrite et les gestes d'annulation (archivage, jamais suppression, RG-14).
({Fiche fiche, List<VoidCallback> annulations}) ecrireAvoirEmis(
    Magasin m, Fiche fac, AvoirEmis r, String idAvoir,
    {Fiche complement = const {}}) {
  final avoirs = m.collection('avoirs');
  final annulations = <VoidCallback>[];
  final ins = avoirs.inserer(
      {...r.avoir, ...complement, 'id': idAvoir, 'statut': 'actif'},
      prefixe: 'AVR');
  annulations.add(ins.annuler);
  final ecr = m.collection('ecritures');
  final ids = <String>[];
  for (final e in r.ecritures) {
    final x = ecr.inserer({...e, 'statut': 'brouillon'}, prefixe: 'ECR');
    ids.add('${x.fiche['id']}');
    annulations.add(x.annuler);
  }
  avoirs.mettreAJour(idAvoir, {'ecritureIds': ids});
  annulations.add(m.collection('factures').mettreAJour(fac['id'], {
    'avoirIds': [...((fac['avoirIds'] as List?) ?? const []), idAvoir],
    'montantAvoirs': r.montantAvoirs,
  }));
  m.journaliser('Facture d’avoir émise', 'M8', 'Avoir',
      '${r.avoir['reference']}', null, {
    'facture': fac['numero'],
    'montant': r.avoir['montant'],
    'motif': r.avoir['motif'],
    'origine': r.avoir['origine'],
  });
  return (fiche: ins.fiche, annulations: annulations);
}
