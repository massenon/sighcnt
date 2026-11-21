/// ENCAISSEMENT — cœur arithmétique de `PR.encaisser` et de `ecrireEncaissement` (prototype_html/assets/js/parcours.js).
///
/// Porté ICI : quelles lignes un versement règle, l'état de la facture après versement (reliquat, solde, base MECeF),
/// et l'écriture comptable équilibrée (RG-10). Hors de ce fichier, dans l'orchestration du poste : le déblocage du
/// laboratoire, de l'imagerie et des tâches d'aval, la journalisation (RG-12), l'insertion en base.
///
/// Les vecteurs (`test/vecteurs/encaissement.json`) sont des SÉQUENCES de versements engendrées par la maquette.
///
/// Corrigés dans la maquette PUIS portés (docs/architecture/ECARTS-MAQUETTE.md, E1 et E3, décision du 30/10/2026) :
///   · la part assureur n'est constatée (411 / 706) qu'au PREMIER versement d'une facture ;
///   · le numéro de pièce est une série annuelle : millésime de la date, rang suivant, repris par les versements suivants.
/// Corrigé dans la maquette PUIS porté (E2, décision du 31/10/2026) : une pièce SANS lignes refuse un versement supérieur au dû, en nommant le défaut.
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import '../mecef/montants.dart';
import 'prix_manquant.dart';
import 'versements.dart';

const compteCaisse = '571000';
const compteClientsAssurance = '411110';
const comptePrestations = '706000';

class ResultatEncaissement {
  const ResultatEncaissement(
      {required this.facture,
      required this.deja,
      required this.lignesReglees,
      required this.montantRegle,
      required this.restantDu,
      required this.ecritures,
      this.refus,
      this.refusCode,
      this.versements = const [],
      this.ecrituresParVersement = const []});

  /// La facture APRÈS versement (copie ; l'entrée n'est jamais modifiée).
  final Map<String, Object?> facture;

  /// La facture était déjà soldée : rien ne bouge.
  final bool deja;
  final List<String> lignesReglees;
  final double? montantRegle;
  final double? restantDu;
  final List<Map<String, Object?>> ecritures;

  /// Versement REFUSÉ (E2) : le motif nomme le défaut, rien n'est écrit ; `facture` est inchangée.
  final String? refus;

  /// LOT PAIE-V : les fiches de versement à écrire (une par versement, sans identifiant ni lien d'écriture : le poste les pose) et, pour chacune, ses écritures.
  final List<Map<String, Object?>> versements;
  final List<List<Map<String, Object?>>> ecrituresParVersement;

  /// Le code nommé du refus de la fenêtre « Facture normalisée » (`IFU_INVALIDE`, `NOM_ACHETEUR_ABSENT`, `AIB_TAUX_INVALIDE`), sinon null.
  final String? refusCode;
}

bool _vrai(Object? v) => v != null && v != '' && v != 0 && v != false;

double _n(Object? v) => nombreOuZero(v);

/// `PR.encaisser(factureId, {lignes | montant, mode})`. `aujourdhui` : `YYYY-MM-DD` de l'écriture ; `maintenant` : ISO.
ResultatEncaissement encaisser(
  Map<String, Object?> facture, {
  List<String>? lignes,
  num? montant,
  String? mode,
  required String aujourdhui,
  required String maintenant,
  String utilisateur = '',
  List<Map<String, Object?>> ecritures = const [],
  Map<String, Object?>? acheteur,

  /// LOT TARIF-FIX-2 : le réglage de clinique « encaissement partiel d'une pièce en attente de prix » à la date du geste (défaut semé : non).
  bool encaissementPartiel = false,

  /// LOT PAIE-V : des versements successifs de modes différents (type, modalite, operateur, referenceTransaction, montant) au lieu d'un montant et d'un mode uniques ;
  /// [modalites] : les fiches de `modalitesVersement` (vide : la semence), [rangDepart] : le nombre de versements déjà enregistrés pour la pièce.
  List<Map<String, Object?>>? versements,
  List<Map<String, Object?>> modalites = const [],
  int rangDepart = 0,
  String agent = '',
}) {
  ResultatEncaissement refusV(RefusVersement r) => ResultatEncaissement(
      facture: facture,
      deja: false,
      lignesReglees: const [],
      montantRegle: 0,
      restantDu: resteDuPiece(facture),
      ecritures: const [],
      refus: '${r.code} : ${r.motif} ${r.geste ?? ''}',
      refusCode: r.code);
  if (facture['statutPaiement'] == 'soldee') {
    if (versements != null) return refusV(controlerVersements(facture, versements, aujourdhui, modalites).refus!);
    return ResultatEncaissement(
        facture: facture,
        deja: true,
        lignesReglees: const [],
        montantRegle: null,
        restantDu: null,
        ecritures: const []);
  }
  // LOT TARIF-FIX-2 : une ligne SANS PRIX refuse l'encaissement, NOMMÉ, avant toute écriture : la pièce entière par défaut, la seule ligne quand le réglage de
  // la clinique permet l'encaissement du reste. La valorisation (prix en vigueur à la date de la pièce) est faite AVANT par l'appelant (`valoriserLignes`).
  final manquesPrix = lignesPrixManquant(facture);
  if (manquesPrix.isNotEmpty) {
    final lesLignes = ((facture['lignes'] ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()).toList();
    List<Map<String, Object?>>? refusees;
    var partielRefus = encaissementPartiel;
    if (!encaissementPartiel) {
      refusees = manquesPrix;
    } else if (lignes != null && lignes.isNotEmpty) {
      final touchees = manquesPrix.where((l) => lignes.contains(l['id'])).toList();
      if (touchees.isNotEmpty) refusees = touchees;
    } else if (!lesLignes.any((l) => !ligneSansPrix(l) && l['statutPaiement'] != 'paye')) {
      refusees = manquesPrix;
      partielRefus = true;
    }
    if (refusees != null) {
      final r = refusEncaissementPrix(facture, [for (final l in refusees) (l['prixManquant'] as Map).cast<String, Object?>()], partielRefus, aujourdhui: aujourdhui);
      return ResultatEncaissement(
          facture: facture,
          deja: false,
          lignesReglees: const [],
          montantRegle: 0,
          restantDu: null,
          ecritures: const [],
          refus: '${r.code} : ${r.motif} ${r.geste}',
          refusCode: r.code);
    }
  }
  // LOT PAIE-V : les versements se contrôlent AVANT toute écriture, un par un, contre le reste dû de la part du patient ; un refus nomme le versement fautif.
  ControleVersements? cv;
  if (versements != null) {
    cv = controlerVersements(facture, versements, aujourdhui, modalites);
    if (!cv.ok) return refusV(cv.refus!);
  }
  // Un acheteur (IFU, nom) se contrôle AVANT toute écriture : un refus nommé n'écrit rien (E2299) ; un taux d'AIB demandé est refusé AIB_FACTURE_PATIENT (lot FISC-2).
  AcheteurMecef? acheteurSaisi;
  if (acheteur != null) {
    final v = validerAcheteurMecef(
        ifu: acheteur['ifu'],
        nom: acheteur['nom'],
        aibTaux: acheteur['aibTaux'],
        aibSituation: acheteur['aibSituation']);
    if (v.refus != null) {
      final lignesDues = ((facture['lignes'] ?? const []) as List)
          .map((l) => (l as Map).cast<String, Object?>())
          .where((l) => l['statutPaiement'] != 'paye');
      return ResultatEncaissement(
          facture: facture,
          deja: false,
          lignesReglees: const [],
          montantRegle: 0,
          restantDu: lignesDues.fold<double>(0, (n, l) => n + _n(l['partPatient'])),
          ecritures: const [],
          refus: '${v.refus!.code} : ${v.refus!.motif} ${v.refus!.geste}',
          refusCode: v.refus!.code);
    }
    acheteurSaisi = v.acheteur;
  }
  final toutes = ((facture['lignes'] ?? const []) as List)
      .map((l) => (l as Map).cast<String, Object?>())
      .toList();
  // Une pièce en attente de prix (encaissement partiel réglé) : le dû est celui des seules lignes valorisées ; une ligne sans prix n'est jamais allouée.
  final duTotal = manquesPrix.isNotEmpty
      ? toutes.where((l) => !ligneSansPrix(l) && l['statutPaiement'] != 'paye').fold(0.0, (n, l) => n + _n(l['partPatient']))
      : facture['partPatient'] != null
          ? _n(facture['partPatient'])
          : _n(facture['montantTTC']);

  final reglees = <Map<String, Object?>>[];
  var paye = 0.0;
  if (cv != null) {
    // Les versements s'ajoutent à ce que la pièce a déjà reçu ; une ligne n'est réglée que si le CUMUL la couvre ENTIÈREMENT, dans l'ordre de la pièce.
    // Ce qui ne couvre pas encore une ligne entière reste un acompte non affecté : il compte dans le réglé, il ne débloque rien.
    paye = cv.total;
    var credit = _n(facture['montantPaye']) + paye - toutes.where((l) => l['statutPaiement'] == 'paye').fold<double>(0, (n, l) => n + _n(l['partPatient']));
    for (final l in toutes) {
      if (l['statutPaiement'] == 'paye' || ligneSansPrix(l)) continue;
      final part = _n(l['partPatient']);
      if (part <= credit) {
        reglees.add(l);
        credit -= part;
      }
    }
  } else if (lignes != null && lignes.isNotEmpty) {
    final vises = lignes.toSet();
    for (final l in toutes) {
      if (l['statutPaiement'] == 'paye' || !vises.contains(l['id'])) continue;
      reglees.add(l);
      paye += _n(l['partPatient']);
    }
  } else if (toutes.isNotEmpty) {
    // Allocation d'un montant global : les lignes dues, dans l'ordre, tant que la somme versée les couvre ENTIÈREMENT.
    var reste = montant != null ? montant.toDouble() : duTotal;
    for (final l in toutes) {
      if (l['statutPaiement'] == 'paye' || ligneSansPrix(l)) continue;
      final part = _n(l['partPatient']);
      if (part <= reste) {
        reglees.add(l);
        reste -= part;
        paye += part;
      }
    }
  } else {
    // Pièce antérieure au modèle par lignes : on conserve le comportement par montant, mais JAMAIS au-delà du dû (E2, corrigé le 31/10/2026).
    final restantPiece = (duTotal - _n(facture['montantPaye'])) > 0
        ? duTotal - _n(facture['montantPaye'])
        : 0.0;
    final voulu = montant != null ? montant.toDouble() : restantPiece;
    if (!(voulu >= 0) || voulu > restantPiece) {
      final ref = _vrai(facture['numero']) ? facture['numero'] : facture['id'];
      return ResultatEncaissement(
          facture: facture,
          deja: false,
          lignesReglees: const [],
          montantRegle: 0,
          restantDu: restantPiece,
          ecritures: const [],
          refus:
              'Versement de ${money(voulu)} refusé : la pièce $ref ne porte aucune ligne et ne doit plus que ${money(restantPiece)}. '
              'Un versement ne dépasse jamais le dû.');
    }
    paye = voulu;
  }

  final lignesMaj = toutes.map((l) {
    if (!reglees.any((r) => identical(r, l))) return l;
    return {
      ...l,
      'statutPaiement': 'paye',
      'montantRegle': l['partPatient'],
      'payeLe': maintenant,
      'payePar': utilisateur
    };
  }).toList();
  final totalPaye = _n(facture['montantPaye']) + paye;
  final restantDu = cv != null
      // Avec des versements, le reste dû se CALCULE de ce qui a été versé (jamais des seules lignes payées).
      ? () {
          final du = lignesMaj.isNotEmpty ? lignesMaj.where((l) => !ligneSansPrix(l)).fold<double>(0, (n, l) => n + _n(l['partPatient'])) : duTotal;
          return du - totalPaye > 0 ? du - totalPaye : 0.0;
        }()
      : lignesMaj.isNotEmpty
          ? lignesMaj
              .where((l) => l['statutPaiement'] != 'paye')
              .fold(0.0, (n, l) => n + _n(l['partPatient']))
          : (duTotal - totalPaye) > 0
              ? duTotal - totalPaye
              : 0.0;
  // Une ligne sans prix restante : le reste dû est NON CALCULABLE et la pièce n'est jamais soldée.
  final resteSansPrix = lignesMaj.any((l) => ligneSansPrix(l) && l['statutPaiement'] != 'paye');
  final solde = !resteSansPrix && restantDu <= 0;
  // La base MECeF naît de la fonction unique des montants : seule la part PATIENT des lignes réglées par ce versement s'ajoute (ni part assureur,
  // ni remise). Une ligne que la fonction refuse (prix décimal d'une pièce ancienne) ne bloque pas l'encaissement : la base reste le total réglé,
  // et c'est la NORMALISATION qui refuse en nommant la ligne.
  double? baseVersement;
  if (reglees.isNotEmpty) {
    final mv = mecefMontants(lignes: [for (final l in reglees) ligneVersMecef(l)]);
    if (mv.ok) baseVersement = mv.montants!.base.toDouble();
  }
  var baseMecef = baseVersement != null
      ? _n(facture['montantPaye']) + baseVersement
      : totalPaye;
  if (cv != null) {
    // Avec des versements, la base normalisée est celle des lignes PAYÉES (un acompte non affecté n'est pas encore une vente normalisable).
    final payeesApres = lignesMaj.where((l) => l['statutPaiement'] == 'paye').toList();
    final mvApres = payeesApres.isNotEmpty ? mecefMontants(lignes: [for (final l in payeesApres) ligneVersMecef(l)]) : null;
    baseMecef = toutes.isEmpty ? totalPaye : (mvApres != null && mvApres.ok ? mvApres.montants!.base.toDouble() : (payeesApres.isNotEmpty ? totalPaye : 0.0));
  }
  final modeRetenu = cv != null ? modePieceDepuis(cv.lignes) : (_vrai(mode) ? mode! : 'especes');

  final apres = <String, Object?>{
    ...facture,
    'lignes': lignesMaj,
    'montantPaye': totalPaye,
    'reliquat': resteSansPrix ? null : restantDu,
    'modePaiement': modeRetenu,
    'statutPaiement':
        solde ? 'soldee' : (totalPaye > 0 ? 'partielle' : 'impayee'),
    // TOUTE VENTE EST NORMALISÉE (Direction, 07/11/2026) : un encaissement ne dit jamais « normalisée » de lui-même. La pièce attend sa
    // normalisation (geste du registre fiscal, appareil de la caisse) : l'état « normalisée » n'existe qu'avec un numéro rendu par l'appareil.
    'statutMecef': 'en_attente',
    // Le point fiscal : seule la part réglée par le patient est normalisée (ni la part assureur, ni les remises).
    'baseMecef': baseMecef,
    if (acheteurSaisi != null) ...{
      'ifuClient': acheteurSaisi.ifu,
      'acheteurNom': acheteurSaisi.nom,
      'aibTaux': acheteurSaisi.aibTaux,
    },
    'dernierReglement': {
      'date': maintenant,
      'montant': paye,
      'mode': modeRetenu,
      'lignes': reglees.map((l) => l['id']).toList(),
      'encaissePar': utilisateur
    },
  };

  if (cv != null) {
    // UNE écriture équilibrée PAR versement (RG-10), au compte de sa modalité ; puis la fiche de chaque versement.
    final parVersement = <List<Map<String, Object?>>>[];
    final toutesEcritures = <Map<String, Object?>>[];
    for (final l in cv.lignes) {
      final e = ecritureEncaissement(apres, _n(l['montant']), aujourdhui, [...ecritures, ...toutesEcritures], '${l['compte']}',
          '${l['modaliteLibelle']}${l['operateurLibelle'] != null ? ' ${l['operateurLibelle']}' : ''}${l['referenceTransaction'] != null ? ' réf. ${l['referenceTransaction']}' : ''}');
      parVersement.add(e);
      toutesEcritures.addAll(e);
    }
    var cumul = totalPaye - paye;
    final fiches = <Map<String, Object?>>[];
    for (var i = 0; i < cv.lignes.length; i++) {
      final l = cv.lignes[i];
      cumul += _n(l['montant']);
      fiches.add({
        ...l,
        'factureId': facture['id'],
        'factureNumero': facture['numero'],
        'patientId': facture['patientId'],
        'patient': facture['patient'],
        if (_vrai(facture['patientCode'])) 'patientCode': facture['patientCode'],
        'rang': rangDepart + i + 1,
        'date': aujourdhui,
        'horodatage': maintenant,
        'agent': agent.isEmpty ? utilisateur : agent,
        'origine': 'caisse',
        'resteApres': resteDuPiece(apres, montantPaye: cumul),
        if ('${facture['date'] ?? ''}'.length >= 10 && '${facture['date']}'.substring(0, 10) != aujourdhui) 'horsJour': true,
      });
    }
    return ResultatEncaissement(
      facture: apres,
      deja: false,
      lignesReglees: [for (final l in reglees) '${l['id']}'],
      montantRegle: paye,
      restantDu: resteSansPrix ? null : restantDu,
      ecritures: toutesEcritures,
      versements: fiches,
      ecrituresParVersement: parVersement,
    );
  }
  final posees = paye > 0
      ? ecritureEncaissement(apres, paye, aujourdhui, ecritures)
      : <Map<String, Object?>>[];
  return ResultatEncaissement(
    facture: apres,
    deja: false,
    lignesReglees: [for (final l in reglees) '${l['id']}'],
    montantRegle: paye,
    restantDu: resteSansPrix ? null : restantDu,
    ecritures: posees,
  );
}

/// La créance sur l'assureur est-elle déjà constatée pour cette facture (une écriture 411 non archivée) ?
bool creanceAssureurConstatee(
        Map<String, Object?> facture, List<Map<String, Object?>> ecritures) =>
    ecritures.any((e) =>
        e['pieceId'] == facture['id'] &&
        e['compte'] == compteClientsAssurance &&
        e['statut'] != 'archive');

/// Numéro de pièce de caisse : celui de la première écriture de la facture, sinon `CAI-AAAA-NNNNN` (rang suivant de l'année).
String numeroPieceCaisse(Map<String, Object?> facture, String date,
    List<Map<String, Object?>> ecritures) {
  for (final e in ecritures) {
    if (e['pieceId'] == facture['id'] &&
        e['journal'] == 'CAI' &&
        _vrai(e['numero'])) return '${e['numero']}';
  }
  final prefixe = 'CAI-${date.substring(0, 4)}-';
  var max = 0;
  for (final e in ecritures) {
    final n = e['numero'];
    if (n is String && n.startsWith(prefixe)) {
      final rang = int.tryParse(n.substring(prefixe.length)) ?? 0;
      if (rang > max) max = rang;
    }
  }
  return '$prefixe${(max + 1).toString().padLeft(5, '0')}';
}

/// Écriture d'encaissement : débit 571 de la part réglée, débit 411 de la part assureur (au premier versement seulement),
/// crédit 706 du total. Contrôlée ÉQUILIBRÉE avant d'exister (RG-10) : un déséquilibre rend une liste vide. Brouillon.
List<Map<String, Object?>> ecritureEncaissement(
    Map<String, Object?> facture, double montantRegle, String aujourdhui,
    [List<Map<String, Object?>> ecritures = const [], String? compte, String? libelleMode]) {
  // L'EN-TÊTE d'une facture porte `partAssurance` ; `partAssureur` n'existe que sur les LIGNES (E2260) : lire ce dernier sur l'en-tête donnait zéro,
  // et la créance de l'assureur (débit 411, crédit 706) n'entrait jamais au journal.
  final partAssureur = creanceAssureurConstatee(facture, ecritures)
      ? 0.0
      : _n(facture['partAssurance'] ?? facture['partAssureur']);
  final total = montantRegle + partAssureur;
  if (total <= 0) return const [];

  final ref = '${_vrai(facture['numero']) ? facture['numero'] : facture['id']}';
  final numero = numeroPieceCaisse(facture, aujourdhui, ecritures);
  final base = <String, Object?>{
    'numero': numero,
    'date': aujourdhui,
    'journal': 'CAI',
    'journalLibelle': 'Journal de caisse-dépenses',
    'libelle': 'Encaissement facture $ref — ${facture['patient'] ?? ''}${libelleMode != null ? ' : $libelleMode' : ''}',
    'pieceId': facture['id'],
    'pieceNumero': facture['numero'],
    'origine': 'Automatique — Caisse',
    'statut': 'brouillon',
  };
  final l = <Map<String, Object?>>[];
  if (montantRegle > 0)
    l.add({
      ...base,
      'compte': compte ?? compteCaisse,
      'debit': montantRegle,
      'credit': 0.0
    });
  if (partAssureur > 0) {
    l.add({
      ...base,
      'compte': compteClientsAssurance,
      'debit': partAssureur,
      'credit': 0.0,
      'libelle':
          '${base['libelle']} — part ${_vrai(facture['assureur']) ? facture['assureur'] : 'assureur'}'
    });
  }
  l.add({...base, 'compte': comptePrestations, 'debit': 0.0, 'credit': total});

  final debit = l.fold(0.0, (n, x) => n + (x['debit']! as double));
  final credit = l.fold(0.0, (n, x) => n + (x['credit']! as double));
  if (debit != credit) return const [];
  return l;
}
