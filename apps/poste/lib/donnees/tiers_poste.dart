import 'package:sigh_domaine/sigh_domaine.dart';

import 'aib_poste.dart';
import 'magasin.dart';
import 'mecef_poste.dart';

/// LA FACTURE À UN TIERS PAYEUR AU POSTE (lot TIERS, Direction, 16/11/2026, section AQ point 36) : la colle entre les fonctions pures de
/// `packages/domaine/lib/src/comptabilite/tiers_payeurs.dart` (rejouées sur les vecteurs de l'écran réel de la maquette) et le magasin du poste. Les règles
/// (acheteur, décision de l'AIB, contrôle d'émission, numéro, créance, lettrage, balance âgée) sont celles du domaine ; ICI on assemble les fiches, on écrit
/// ce que le domaine autorise et on journalise (RG-12). Le poste ne fabrique AUCUN numéro MECeF : une pièce émise reste EN ATTENTE de certification sous le
/// refus nommé de l'adaptateur (comme la vente d'un patient). Une pièce émise ne se réécrit jamais (garde du magasin, `gardeFactureTiersPoste`).
/// Les cinq collections voyagent (famille A à la mère, identité par le contenu, jamais vers un téléphone) : un fileul rattaché écrit sur son magasin comme la mère.
class TiersPoste {
  TiersPoste(this.m,
      {required this.auteur, required this.libelleRole, required this.droit, DateTime Function()? horloge})
      : _horloge = horloge ?? DateTime.now;
  final Magasin m;
  final String Function() auteur;
  final String libelleRole;

  /// Le geste réservé détenu par le rôle courant (fiche RBAC : `emettre_facture_tiers`, `corriger_facture_tiers`, `imputer_aib`).
  final bool Function(String geste) droit;
  final DateTime Function() _horloge;

  String get aujourdhui => parametreDateIso(_horloge());
  CollectionMagasin get colTiers => m.collection('tiersPayeurs');
  CollectionMagasin get colFactures => m.collection('facturesTiers');
  CollectionMagasin get colAvoirs => m.collection('avoirsTiers');
  CollectionMagasin get colReglements => m.collection('reglementsTiers');
  CollectionMagasin get colLettrages => m.collection('lettragesTiers');

  Map<String, Object?> _refusDroit(String geste, String quoi, String code) => aibRefus(
      code, '$quoi est un droit réservé de la fiche du rôle (« $geste ») : « $libelleRole » ne l’a pas.', 'Demander ce geste à un rôle qui détient le droit « $geste ».', {'droit': geste});

  bool get peutEmettre => droit(tiersGesteEmettre);
  bool get peutCorriger => droit(tiersGesteCorriger);
  bool get peutDeciderAib => droit('imputer_aib');

  AibDonnees get _aib {
    AibPoste.amorcer(m);
    return AibDonnees(situations: m.collection('situationsAib').toutes, bareme: m.collection('baremeAib').toutes);
  }

  // --- Les tiers ------------------------------------------------------------------------------------------------------------------------------
  List<Fiche> versions(String code) =>
      colTiers.actives.where((v) => v['code'] == code).toList()..sort((a, b) => '${a['dateEffet']}'.compareTo('${b['dateEffet']}'));
  Fiche? aLaDate(String code, String date) => tiersALaDate(colTiers.actives, code, date);
  List<String> codes() => ({for (final v in colTiers.toutes) '${v['code']}'}.toList()..sort());

  Map<String, Object?> creerTiers(Map<String, Object?> o) {
    if (!peutEmettre) return _refusDroit(tiersGesteEmettre, 'Tenir la fiche d’un tiers payeur', 'TIERS_RESERVE');
    final l = tiersLireChamps(o);
    if (l['ok'] != true) return l;
    final dateEffet = '${o['dateEffet'] ?? ''}'.isEmpty ? aujourdhui : '${o['dateEffet']}'.substring(0, 10);
    final clos = cfbControleDateEffet(dateEffet, exercices: m.collection('exercices').toutes, aujourdhui: _horloge());
    if (clos != null) return aibRefus(clos.code, clos.motif, clos.geste);
    final champs = (l['champs'] as Map).cast<String, Object?>();
    if (champs['ifu'] != null) {
      for (final v in colTiers.actives) {
        if (v['ifu'] == champs['ifu']) {
          return aibRefus('TIERS_IFU_DEJA_PRIS', 'L’IFU ${champs['ifu']} est déjà porté par le tiers payeur ${v['code']} (${v['nom']}).', 'Ouvrir la fiche de ${v['code']} et y poser une nouvelle version datée.');
        }
      }
    }
    final code = cpbReferenceSuivante('TP-', 3, [for (final v in colTiers.toutes) {'reference': v['code']}]);
    final fiche = {
      'code': code,
      'version': 1,
      'dateEffet': dateEffet,
      'dateFin': null,
      ...champs,
      'adresse': _t(o['adresse']),
      'contact': _t(o['contact']),
      'conditions': _t(o['conditions']),
      'creePar': auteur(),
      'creeLe': _horloge().toIso8601String(),
    };
    final ins = colTiers.inserer(fiche, prefixe: 'TPY');
    m.journaliser('Tiers payeur : création', 'M8', 'tiersPayeurs', '${ins.fiche['id']}', null, {'code': code, 'nom': champs['nom'], 'ifu': champs['ifu'], 'dateEffet': dateEffet});
    return {'ok': true, 'id': ins.fiche['id'], 'code': code, 'fiche': ins.fiche};
  }

  Map<String, Object?> nouvelleVersion(String code, Map<String, Object?> o) {
    if (!peutEmettre) return _refusDroit(tiersGesteEmettre, 'Tenir la fiche d’un tiers payeur', 'TIERS_RESERVE');
    final vs = versions(code);
    if (vs.isEmpty) return aibRefus('TIERS_INCONNU', 'Le tiers payeur « $code » n’existe pas.', 'Choisir un tiers de la liste.');
    final der = vs.last;
    final motif = '${o['motif'] ?? ''}'.trim();
    if (motif.isEmpty) return aibRefus('TIERS_MOTIF_ABSENT', 'Un motif est obligatoire pour poser une nouvelle version de la fiche d’un tiers payeur.', 'Dire ce qui change et pourquoi.');
    final dateEffet = '${o['dateEffet'] ?? ''}'.isEmpty ? aujourdhui : '${o['dateEffet']}'.substring(0, 10);
    final clos = cfbControleDateEffet(dateEffet, exercices: m.collection('exercices').toutes, aujourdhui: _horloge());
    if (clos != null) return aibRefus(clos.code, clos.motif, clos.geste);
    if (dateEffet.compareTo('${der['dateEffet']}') <= 0) {
      return aibRefus('TIERS_DATE_ANTERIEURE', 'La date d’effet (${aibDateFr(dateEffet)}) n’est pas postérieure à celle de la version en cours (${aibDateFr('${der['dateEffet']}')}) : une version ne se réécrit pas.', 'Choisir une date d’effet postérieure.');
    }
    final l = tiersLireChamps({...der, ...o});
    if (l['ok'] != true) return l;
    final champs = (l['champs'] as Map).cast<String, Object?>();
    if (champs['ifu'] != null) {
      for (final v in colTiers.actives) {
        if (v['ifu'] == champs['ifu'] && v['code'] != code) {
          return aibRefus('TIERS_IFU_DEJA_PRIS', 'L’IFU ${champs['ifu']} est déjà porté par le tiers payeur ${v['code']} (${v['nom']}).', 'Un IFU n’appartient qu’à un tiers payeur.');
        }
      }
    }
    final fiche = {
      'code': code,
      'version': (der['version'] as num) + 1,
      'dateEffet': dateEffet,
      'dateFin': null,
      'motif': motif,
      ...champs,
      'adresse': _t(o.containsKey('adresse') ? o['adresse'] : der['adresse']),
      'contact': _t(o.containsKey('contact') ? o['contact'] : der['contact']),
      'conditions': _t(o.containsKey('conditions') ? o['conditions'] : der['conditions']),
      'creePar': auteur(),
      'creeLe': _horloge().toIso8601String(),
    };
    final veille = DateTime.parse('${dateEffet}T00:00:00Z').subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
    if (der['dateFin'] == null || '${der['dateFin']}'.compareTo(dateEffet) >= 0) colTiers.mettreAJour(der['id'], {'dateFin': veille}, journaliser: false);
    final ins = colTiers.inserer(fiche, prefixe: 'TPY');
    m.journaliser('Tiers payeur : nouvelle version', 'M8', 'tiersPayeurs', '${ins.fiche['id']}', {'version': der['version'], 'nom': der['nom'], 'ifu': der['ifu']},
        {'code': code, 'version': fiche['version'], 'nom': fiche['nom'], 'ifu': fiche['ifu'], 'dateEffet': dateEffet, 'motif': motif});
    return {'ok': true, 'id': ins.fiche['id'], 'code': code, 'version': fiche['version'], 'fiche': ins.fiche};
  }

  String? _t(Object? v) => v == null || '$v'.trim().isEmpty ? null : '$v'.trim();

  // --- Les pièces -----------------------------------------------------------------------------------------------------------------------------
  Fiche? avoirDe(Object? factureTiersId) {
    final f = colFactures.parId(factureTiersId);
    return f == null ? null : tiersAvoirDe(colAvoirs.actives, f);
  }

  int _dejaAuxTiers(Object? factureId, Object? ligneId, Object? saufId) {
    var t = 0;
    for (final f in colFactures.actives) {
      if (f['id'] == saufId || avoirDe(f['id']) != null) continue;
      for (final l in (f['lignes'] as List? ?? const [])) {
        final x = (l as Map).cast<String, Object?>();
        if (x['factureId'] == factureId && x['ligneId'] == ligneId) t += (x['montant'] as num).toInt();
      }
    }
    return t;
  }

  /// Les lignes de la facture du patient, avec ce qui reste facturable à un tiers et la part restante du patient. Lecture seule.
  Map<String, Object?> lignesFacturables(Object? factureId, {Object? saufId}) {
    final fac = m.collection('factures').parId(factureId);
    if (fac == null || fac['statut'] == 'archive') {
      return aibRefus('FACTURE_PATIENT_INTROUVABLE', 'La facture du patient « ${factureId ?? ''} » n’existe pas.', 'Choisir une facture du registre.');
    }
    if (fac['proforma'] == true) return aibRefus('FACTURE_PATIENT_PROFORMA', 'Une pro-forma n’est pas une vente : elle ne se refacture pas à un tiers.', 'Choisir la facture de vente.');
    if (fac['type'] == 'Avoir' || ((fac['montantTTC'] as num?) ?? 0) < 0) return aibRefus('FACTURE_PATIENT_AVOIR', 'Un avoir ne se refacture pas à un tiers.', 'Choisir la facture de vente.');
    return {
      'ok': true,
      'facture': fac,
      'lignes': [
        for (final l0 in (fac['lignes'] as List? ?? const []))
          () {
            final l = (l0 as Map).cast<String, Object?>();
            final net = l['montant'] == null ? null : (l['montant'] as num).toInt();
            final ass = ((l['partAssureur'] as num?) ?? 0).toInt(), pers = ((l['partPersonnel'] as num?) ?? 0).toInt();
            final deja = _dejaAuxTiers(fac['id'], l['id'], saufId);
            final manque = l['prixManquant'] != null && l['prixManquant'] != false;
            final dispo = net == null || manque ? null : (net - ass - pers - deja < 0 ? 0 : net - ass - pers - deja);
            return {'ligneId': l['id'], 'designation': l['designation'], 'montant': net, 'dejaAuxTiers': deja, 'disponible': dispo};
          }()
      ]
    };
  }

  Map<String, Object?> _entreeMontants(Fiche f, num aibTaux) => {
        'lignes': [
          for (final l in (f['lignes'] as List)) {'id': (l as Map)['ligneId'], 'designation': l['designation'], 'quantite': 1, 'montantBrut': l['montant'], 'prixUnitaire': l['montant'], 'remise': 0}
        ],
        'totalAttendu': f['base'],
      };

  MontantsMecef? _montants(Fiche f, num aibTaux, List<Map<String, Object?>> refus) {
    final e = _entreeMontants(f, aibTaux);
    final r = mecefMontants(lignes: (e['lignes'] as List).cast<Map<String, Object?>>(), totalAttendu: e['totalAttendu'] as num, aibTaux: aibTaux);
    if (!r.ok) {
      refus.add(aibRefus(r.refus!.code, r.refus!.motif, r.refus!.geste));
      return null;
    }
    return r.montants;
  }

  /// PROPOSER la facture (brouillon, aucun numéro) : `{tiersCode, date?, lignes: [{factureId, ligneId, montant}]}`.
  Map<String, Object?> proposer(Map<String, Object?> o) {
    if (!peutEmettre) return _refusDroit(tiersGesteEmettre, 'Émettre une facture à un tiers payeur', 'FACTURE_TIERS_RESERVEE');
    final date = '${o['date'] ?? ''}'.isEmpty ? aujourdhui : '${o['date']}'.substring(0, 10);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) return aibRefus('FACTURE_TIERS_DATE_INVALIDE', 'La date de la pièce est illisible.', 'Choisir la date de la facture.');
    final clos = cfbControleDateEffet(date, exercices: m.collection('exercices').toutes, aujourdhui: _horloge());
    if (clos != null) return aibRefus(clos.code, clos.motif, clos.geste);
    final code = '${o['tiersCode'] ?? ''}';
    if (versions(code).isEmpty) return aibRefus('TIERS_INCONNU', 'Le tiers payeur « $code » n’existe pas.', 'Choisir un tiers payeur de la liste, ou le créer.');
    final t = aLaDate(code, date);
    if (t == null) return aibRefus('TIERS_SANS_VERSION', 'Le tiers payeur $code n’a pas de version en vigueur au ${aibDateFr(date)}.', 'Choisir une date postérieure à sa première version, ou poser une version.');
    final ach = tiersValiderAcheteur(ifu: t['ifu'], nom: t['nom']);
    if (ach['ok'] != true) return ach;
    final demandees = (o['lignes'] as List? ?? const []).map((x) => (x as Map).cast<String, Object?>()).toList();
    if (demandees.isEmpty) return aibRefus('FACTURE_TIERS_SANS_LIGNE', 'Une facture à un tiers payeur se rattache à au moins une prestation du patient.', 'Choisir une ou plusieurs lignes de la facture du patient.');
    final lignes = <Map<String, Object?>>[];
    Object? patientId, patientNom, patientCode;
    var reste = 0;
    final vus = <String>{};
    for (final d in demandees) {
      final cle = '${d['factureId']}#${d['ligneId']}';
      if (!vus.add(cle)) return aibRefus('FACTURE_TIERS_LIGNE_DOUBLE', 'La ligne ${d['ligneId']} est répétée dans la pièce.', 'Une ligne ne figure qu’une fois : saisir le montant en une fois.');
      final lf = lignesFacturables(d['factureId']);
      if (lf['ok'] != true) return lf;
      final fac = lf['facture'] as Fiche;
      if (patientId != null && fac['patientId'] != patientId) {
        return aibRefus('FACTURE_TIERS_PATIENTS_DIFFERENTS', 'Les lignes viennent de patients différents : une facture à un tiers payeur se rattache aux prestations d’UN patient.', 'Une facture par patient.');
      }
      patientId = fac['patientId'];
      patientNom = fac['patient'];
      patientCode = fac['patientCode'];
      final lg = [for (final l in (lf['lignes'] as List).cast<Map<String, Object?>>()) if (l['ligneId'] == d['ligneId']) l].firstOrNull;
      if (lg == null) return aibRefus('FACTURE_TIERS_LIGNE_INCONNUE', 'La ligne « ${d['ligneId']} » n’existe pas sur la facture ${fac['numero']}.', 'Choisir une ligne de la facture du patient.');
      if (lg['disponible'] == null) {
        return aibRefus('FACTURE_TIERS_PRIX_MANQUANT', 'La ligne « ${lg['designation']} » n’a pas de prix : son montant est non calculable (ce n’est pas zéro).', 'Poser le prix de la prestation avant de la facturer au tiers.');
      }
      final mt = d['montant'] is num ? d['montant'] as num : num.tryParse('${d['montant']}');
      if (mt == null || mt != mt.floor() || mt <= 0) {
        return aibRefus('FACTURE_TIERS_MONTANT_INVALIDE', 'Le montant pris en charge de « ${lg['designation']} » (« ${d['montant']} ») est un entier de FCFA strictement positif.', 'Saisir le montant que le tiers prend en charge.');
      }
      final dispo = (lg['disponible'] as num).toInt();
      if (mt > dispo) {
        return aibRefus('FACTURE_TIERS_MONTANT_DEPASSE', 'Le montant demandé pour « ${lg['designation']} » (${money(mt, avecDevise: false)}) dépasse ce qui reste facturable à un tiers (${money(dispo, avecDevise: false)} : montant de la ligne, moins la part de l’assureur, moins ce qui est déjà facturé à un tiers).', 'Réduire le montant.');
      }
      lignes.add({'factureId': fac['id'], 'factureNumero': fac['numero'], 'ligneId': lg['ligneId'], 'designation': lg['designation'], 'montant': mt.toInt()});
      reste += dispo - mt.toInt();
    }
    final base = lignes.fold<int>(0, (n, l) => n + (l['montant'] as int));
    final tmp = {'lignes': lignes, 'base': base};
    final refus = <Map<String, Object?>>[];
    final mm = _montants(tmp, 0, refus);
    if (mm == null) return refus.first;
    final cles = [for (final l in lignes) '${l['factureNumero']}#${l['ligneId']}:${l['montant']}']..sort();
    final fiche = <String, Object?>{
      'statut': 'brouillon',
      'tiersCode': t['code'],
      'tiersVersionId': t['id'],
      'tiersVersion': t['version'],
      'tiersNom': t['nom'],
      'ifuAcheteur': ach['ifu'],
      'nomAcheteur': ach['nom'],
      'tiersAdresse': t['adresse'],
      'delaiPaiementJours': t['delaiPaiementJours'],
      'patientId': patientId,
      'patientNom': patientNom,
      'patientCode': patientCode,
      'date': date,
      'lignes': lignes,
      'base': base,
      'ht': mm.ht,
      'tva': mm.tva,
      'partPatientRestante': reste,
      'sourcesCle': cles.join('|'),
      'numero': null,
      'aibDecision': null,
      'proposePar': auteur(),
      'proposeLe': _horloge().toIso8601String(),
    };
    final ins = colFactures.inserer(fiche, prefixe: 'FTP');
    m.journaliser('Facture tiers : brouillon proposé', 'M8', 'facturesTiers', '${ins.fiche['id']}', null, {'tiersCode': t['code'], 'ifu': ach['ifu'], 'base': base, 'lignes': lignes.length, 'date': date});
    return {'ok': true, 'id': ins.fiche['id'], 'fiche': ins.fiche};
  }

  /// La PROPOSITION de l'AIB (taux du barème de l'acheteur à la date de la pièce) : ne décide rien, n'écrit rien.
  Map<String, Object?> proposerAib(Object? id) {
    final f = colFactures.parId(id);
    if (f == null) return aibRefus('FACTURE_TIERS_INTROUVABLE', 'La facture à un tiers payeur « $id » n’existe pas.', 'Choisir une pièce de la liste.');
    return aibTauxPourAcheteur(_aib, ifu: f['ifuAcheteur'], date: '${f['date']}');
  }

  /// La DÉCISION du comptable (geste `imputer_aib`) : le domaine décide du refus nommé ou rend la décision signée ; ICI on l'écrit sur le brouillon.
  Map<String, Object?> deciderAib(Object? id, Map<String, Object?> saisie) {
    if (!peutDeciderAib) return tiersDeciderAib(_aib, droit: false, facture: const {}, saisie: saisie, acteur: auteur(), libelleRole: libelleRole, maintenant: _horloge());
    final f = colFactures.parId(id);
    if (f == null || f['statut'] == 'archive') return aibRefus('FACTURE_TIERS_INTROUVABLE', 'La facture à un tiers payeur « $id » n’existe pas.', 'Choisir une pièce de la liste.');
    final r = tiersDeciderAib(_aib, droit: peutDeciderAib, facture: f, saisie: saisie, acteur: auteur(), libelleRole: libelleRole, maintenant: _horloge());
    if (r['ok'] != true) return r;
    final d = (r['decision'] as Map).cast<String, Object?>();
    colFactures.mettreAJour(id, {'aibDecision': d}, journaliser: false);
    m.journaliser('Facture tiers : décision de l’AIB', 'M8', 'facturesTiers', '$id', {'aibDecision': f['aibDecision'] == null ? null : (f['aibDecision'] as Map)['appliquer']},
        {'appliquer': d['appliquer'], 'taux': d['taux'], 'horsProposition': d['horsProposition'] == true, 'motif': d['motif']});
    return {'ok': true, 'id': id, 'decision': d};
  }

  /// ÉMETTRE : droit, décision de l'AIB, acheteur revérifié, lignes encore facturables, exercice ouvert, numéro `FT-AAAA-nnnn`, puis certification (le poste n'invente aucun numéro).
  Map<String, Object?> emettre(Object? id) {
    final f = colFactures.parId(id);
    final ctrl = tiersControleEmission(droit: peutEmettre, libelleRole: libelleRole, facture: f ?? const {'statut': 'brouillon'});
    if (!peutEmettre) return ctrl!;
    if (f == null || f['statut'] == 'archive') return aibRefus('FACTURE_TIERS_INTROUVABLE', 'La facture à un tiers payeur « $id » n’existe pas.', 'Choisir une pièce de la liste.');
    if (ctrl != null) return ctrl;
    final clos = cfbControleDateEffet('${f['date']}', exercices: m.collection('exercices').toutes, aujourdhui: _horloge());
    if (clos != null) return aibRefus(clos.code, clos.motif, clos.geste);
    final taux = tiersTauxEffectif(f);
    final refus = <Map<String, Object?>>[];
    final mm = _montants(f, taux, refus);
    if (mm == null) return refus.first;
    for (final l0 in (f['lignes'] as List)) {
      final l = (l0 as Map).cast<String, Object?>();
      final lf = lignesFacturables(l['factureId'], saufId: f['id']);
      if (lf['ok'] != true) return lf;
      final lg = [for (final x in (lf['lignes'] as List).cast<Map<String, Object?>>()) if (x['ligneId'] == l['ligneId']) x].firstOrNull;
      if (lg == null || lg['disponible'] == null || (l['montant'] as num) > (lg['disponible'] as num)) {
        return aibRefus('FACTURE_TIERS_MONTANT_DEPASSE', 'La ligne « ${l['designation']} » n’a plus le montant facturable demandé : une autre pièce l’a prise.', 'Reprendre le brouillon.');
      }
    }
    final numero = tiersNumeroFacture(f['date'], colFactures.toutes, maintenant: _horloge());
    final mode = modeMecefDuPoste(m, _horloge());
    final patch = <String, Object?>{
      'statut': 'emise',
      'numero': numero,
      'aibTaux': taux,
      'aibMontant': mm.aib,
      'net': mm.net,
      'ht': mm.ht,
      'tva': mm.tva,
      'base': mm.base,
      'statutMecef': mode == 'desactive' ? 'sans_objet' : 'en_attente',
      'modeMecef': mode,
      'emisPar': auteur(),
      'emisLe': _horloge().toIso8601String(),
    };
    if (mode != 'desactive') {
      // Aucun adaptateur réel (lot M3) : la pièce RESTE en attente de certification sous le refus nommé, aucun numéro n'est fabriqué.
      final ad = adaptateurDuPoste(m, _horloge());
      if (ad.configure) {
        patch.addAll({'codeRetour': 'MECEF_EMISSION_ASYNCHRONE', 'motifRefusMecef': 'L’adaptateur est configuré : l’émission est asynchrone (lot M3).'});
      } else {
        patch.addAll(champsEnAttenteCertification(ad.refus!, ad.mode));
      }
    }
    colFactures.mettreAJour(id, patch, journaliser: false);
    m.journaliser('Facture tiers : émission', 'M8', 'facturesTiers', numero, {'statut': 'brouillon'}, {'statut': 'emise', 'tiersCode': f['tiersCode'], 'ifu': f['ifuAcheteur'], 'base': mm.base, 'aibTaux': taux, 'aib': mm.aib, 'net': mm.net});
    return {'ok': true, 'id': id, 'numero': numero, 'net': mm.net, 'aib': mm.aib, 'statutMecef': patch['statutMecef'], 'motifMecef': patch['motifRefusMecef']};
  }

  Map<String, Object?> abandonner(Object? id, String? motif) {
    if (!peutEmettre) return _refusDroit(tiersGesteEmettre, 'Abandonner un brouillon de facture à un tiers payeur', 'FACTURE_TIERS_RESERVEE');
    final f = colFactures.parId(id);
    if (f == null || f['statut'] == 'archive') return aibRefus('FACTURE_TIERS_INTROUVABLE', 'La facture à un tiers payeur « $id » n’existe pas.', 'Choisir une pièce de la liste.');
    if (f['statut'] != 'brouillon') return aibRefus('FACTURE_TIERS_EMISE', 'La facture ${f['numero']} est émise : elle ne se retire pas, elle se corrige par un avoir.', 'Émettre un avoir.');
    if ((motif ?? '').trim().isEmpty) return aibRefus('FACTURE_TIERS_MOTIF_ABSENT', 'Le motif est obligatoire.', 'Dire pourquoi le brouillon est abandonné.');
    colFactures.archiver(id, journaliser: false);
    m.journaliser('Facture tiers : brouillon abandonné', 'M8', 'facturesTiers', '$id', {'statut': 'brouillon'}, {'statut': 'archive', 'motif': motif!.trim()});
    return {'ok': true, 'id': id};
  }

  /// AVOIR TOTAL (geste `corriger_facture_tiers`, motif obligatoire), refusé après lettrage. Son état fiscal suit la règle des avoirs : « en attente » de régularisation si la pièce
  /// était certifiée, « sans objet » sinon ; AUCUN numéro n'est fabriqué (la régularisation MECeF de l'avoir n'est pas branchée).
  Map<String, Object?> avoir(Object? factureTiersId, String? motif) {
    if (!peutCorriger) return _refusDroit(tiersGesteCorriger, 'Corriger une facture à un tiers payeur par un avoir', 'AVOIR_TIERS_RESERVE');
    final f = colFactures.parId(factureTiersId);
    if (f == null || f['statut'] != 'emise') return aibRefus('AVOIR_TIERS_PIECE_NON_EMISE', 'Un avoir ne corrige qu’une facture à un tiers payeur ÉMISE.', 'Choisir une facture émise.');
    if (avoirDe(f['id']) != null) return aibRefus('AVOIR_TIERS_DEJA_EMIS', 'La facture ${f['numero']} est déjà annulée par un avoir.', 'Rien à faire.');
    if ((motif ?? '').trim().isEmpty) return aibRefus('AVOIR_TIERS_MOTIF_ABSENT', 'Le motif de l’avoir est obligatoire.', 'Dire pourquoi la facture est annulée.');
    if (colLettrages.actives.any((l) => tiersLieAFacture(l, f))) {
      return aibRefus('AVOIR_TIERS_APRES_LETTRAGE', 'Un règlement est lettré sur la facture ${f['numero']} : annuler la facture sans traiter ce règlement le ferait disparaître.', 'Délettrer d’abord le règlement (avec un motif), puis émettre l’avoir.');
    }
    final date = aujourdhui;
    final numero = referenceAnnuelle('AVT-', date, 4, colAvoirs.toutes, maintenant: _horloge(), champ: 'numero');
    final ins = colAvoirs.inserer({
      'numero': numero,
      'date': date,
      'factureTiersId': f['id'],
      'factureNumero': f['numero'],
      'tiersCode': f['tiersCode'],
      'montant': f['net'],
      'motif': motif!.trim(),
      'sourcesCle': f['numero'],
      'emisPar': auteur(),
      'emisLe': _horloge().toIso8601String(),
      'statutMecef': f['statutMecef'] == 'valide' ? 'en_attente' : 'sans_objet',
    }, prefixe: 'ATP');
    m.journaliser('Facture tiers : avoir', 'M8', 'avoirsTiers', '${ins.fiche['id']}', null, {'numero': numero, 'facture': f['numero'], 'montant': f['net'], 'motif': motif.trim()});
    return {'ok': true, 'id': ins.fiche['id'], 'numero': numero, 'montant': f['net']};
  }

  // --- La créance, le règlement, le lettrage -------------------------------------------------------------------------------------------------
  int creance(Fiche f) => tiersCreanceFacture(f, colLettrages.actives, colAvoirs.actives);
  int resteNonLettre(Fiche r) => tiersResteNonLettre(r, colLettrages.actives);
  List<Fiche> facturesEmises() => colFactures.actives.where((f) => f['statut'] == 'emise').toList();

  Map<String, Object?> creances(String date, TranchesCreances tranches) => tiersCreances(
      date: date, factures: colFactures.actives, lettrages: colLettrages.actives, avoirs: colAvoirs.actives, reglements: colReglements.actives, tranches: tranches);

  Map<String, Object?> reglement(Map<String, Object?> o) {
    if (!peutEmettre) return _refusDroit(tiersGesteEmettre, 'Enregistrer un règlement reçu d’un tiers payeur', 'REGLEMENT_TIERS_RESERVE');
    final code = '${o['tiersCode'] ?? ''}';
    if (versions(code).isEmpty) return aibRefus('TIERS_INCONNU', 'Le tiers payeur « $code » n’existe pas.', 'Choisir un tiers payeur de la liste.');
    final mt = o['montant'] is num ? o['montant'] as num : num.tryParse('${o['montant']}');
    if (mt == null || mt != mt.floor() || mt <= 0) return aibRefus('REGLEMENT_TIERS_MONTANT_INVALIDE', 'Le montant du règlement (« ${o['montant']} ») est un entier de FCFA strictement positif.', 'Saisir le montant reçu.');
    final ref = '${o['referencePaiement'] ?? ''}'.trim();
    if (ref.isEmpty) return aibRefus('REGLEMENT_TIERS_REFERENCE_ABSENTE', 'La référence du paiement (chèque, virement, bordereau) est obligatoire.', 'Saisir la référence portée par le moyen de paiement.');
    final date = '${o['date'] ?? ''}'.isEmpty ? aujourdhui : '${o['date']}'.substring(0, 10);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) return aibRefus('REGLEMENT_TIERS_DATE_INVALIDE', 'La date du règlement est illisible.', 'Choisir la date de réception.');
    final clos = cfbControleDateEffet(date, exercices: m.collection('exercices').toutes, aujourdhui: _horloge());
    if (clos != null) return aibRefus(clos.code, clos.motif, clos.geste);
    if ('${o['mode'] ?? ''}'.trim().isEmpty) return aibRefus('REGLEMENT_TIERS_MODE_ABSENT', 'Le mode de règlement est obligatoire (virement, chèque, espèces).', 'Choisir le mode.');
    for (final r in colReglements.actives) {
      if (r['tiersCode'] == code && '${r['referencePaiement']}'.toLowerCase() == ref.toLowerCase()) {
        return aibRefus('REGLEMENT_TIERS_DEJA_SAISI', 'Le règlement $ref de ce tiers est déjà enregistré (${r['numero']}).', 'Ne pas le saisir deux fois.');
      }
    }
    final numero = referenceAnnuelle('RGT-', date, 4, colReglements.toutes, maintenant: _horloge(), champ: 'numero');
    final ins = colReglements.inserer({
      'numero': numero,
      'tiersCode': code,
      'date': date,
      'montant': mt.toInt(),
      'mode': '${o['mode']}'.trim(),
      'referencePaiement': ref,
      'recuPar': auteur(),
      'recuLe': _horloge().toIso8601String(),
    }, prefixe: 'RTP');
    m.journaliser('Facture tiers : règlement reçu', 'M8', 'reglementsTiers', '${ins.fiche['id']}', null, {'numero': numero, 'tiersCode': code, 'montant': mt, 'reference': ref});
    return {'ok': true, 'id': ins.fiche['id'], 'numero': numero};
  }

  Map<String, Object?> lettrer(Object? reglementId, List<Map<String, Object?>> affectations) {
    final reglement = colReglements.parId(reglementId);
    final r = tiersLettrer(
        droit: peutCorriger,
        libelleRole: libelleRole,
        reglement: reglement,
        affectations: affectations,
        factures: colFactures.actives,
        lettrages: colLettrages.actives,
        avoirs: colAvoirs.actives);
    if (r['ok'] != true) return r;
    final ids = <Object?>[];
    for (final a in affectations) {
      final f = colFactures.parId(a['factureTiersId'])!;
      final mt = a['montant'] is num ? a['montant'] as num : num.parse('${a['montant']}');
      final ins = colLettrages.inserer({
        'reglementId': reglement!['id'],
        'reglementNumero': reglement['numero'],
        'reglementRef': reglement['referencePaiement'],
        'factureTiersId': f['id'],
        'factureNumero': f['numero'],
        'tiersCode': reglement['tiersCode'],
        'montant': mt.toInt(),
        'date': aujourdhui,
        'lettrePar': auteur(),
      }, prefixe: 'LTP');
      ids.add(ins.fiche['id']);
      m.journaliser('Facture tiers : lettrage', 'M8', 'lettragesTiers', '${ins.fiche['id']}', null, {'reglement': reglement['numero'], 'facture': f['numero'], 'montant': mt});
    }
    return {...r, 'ids': ids};
  }

  Map<String, Object?> delettrer(Object? id, String? motif) {
    if (!peutCorriger) return _refusDroit(tiersGesteCorriger, 'Délettrer un règlement de tiers payeur', 'LETTRAGE_TIERS_RESERVE');
    final l = colLettrages.parId(id);
    if (l == null || l['statut'] == 'archive') return aibRefus('LETTRAGE_TIERS_INTROUVABLE', 'Le lettrage « $id » n’existe pas ou est déjà défait.', 'Choisir un lettrage de la liste.');
    if ((motif ?? '').trim().isEmpty) return aibRefus('LETTRAGE_TIERS_MOTIF_ABSENT', 'Le motif du délettrage est obligatoire.', 'Dire pourquoi le lettrage est défait.');
    colLettrages.archiver(id, journaliser: false);
    m.journaliser('Facture tiers : lettrage défait', 'M8', 'lettragesTiers', '$id', {'montant': l['montant'], 'facture': l['factureNumero']}, {'statut': 'archive', 'motif': motif!.trim()});
    return {'ok': true, 'id': id};
  }
}

/// LA GARDE DU MAGASIN : une facture à un tiers payeur ÉMISE ne se réécrit jamais (mêmes champs que `refusRejeuFactureTiers`, tenue aussi par la mère au rejeu). Un brouillon se complète.
String? gardeFactureTiersPoste(Magasin m, String operation, Fiche apres) {
  if (operation != 'modifier') return null;
  final avant = m.collection('facturesTiers').parId(apres['id']);
  final r = refusRejeuFactureTiers(avant, apres);
  return r == null ? null : '${r['code']} : ${r['motif']}';
}

/// Les versions d'une fiche de tiers, une avoir, un règlement et un lettrage ne se réécrivent pas : seule la fermeture d'une version (dateFin) et l'archive passent.
String? gardeFigeePoste(String collection, Magasin m, String operation, Fiche apres, List<String> figes) {
  if (operation != 'modifier') return null;
  final avant = m.collection(collection).parId(apres['id']);
  if (avant == null) return null;
  for (final k in figes) {
    if ('${avant[k]}' != '${apres[k]}') return 'FICHE_TIERS_FIGEE : le champ « $k » d’une pièce ou d’une version ne se réécrit pas (nouvelle version datée, avoir ou délettrage motivé).';
  }
  return null;
}
