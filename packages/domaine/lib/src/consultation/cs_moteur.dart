/// MOTEUR DE LA CONSULTATION — port de `SIGH.consultationZone2` (`enregistrerDossier`, `enregistrerFiche`) et du parcours (`PR.prescrire`,
/// `PR.prescrireSoins`, `PR.administrer`, `PR.soinsDuSecteur`), rejoués sur les vecteurs ENGENDRÉS EN PILOTANT la maquette
/// (`test/vecteurs/consultation.json`).
///
/// La chronologie est STRICTE : Zone 1 (accueil : constantes) → DOSSIER de consultation → FICHE → PRESCRIPTION → CAISSE. La fiche REFUSE sans dossier
/// enregistré (code `SANS_DOSSIER`) et c'est la SEULE porte de prescription ; un échec de prescription DÉFAIT la consultation. UNE facture globale
/// pour médicaments, analyses, actes et imagerie ; les tâches d'aval naissent BLOQUÉES, l'encaissement seul les libère.
///
/// Le moteur n'a pas de magasin : il écrit par l'interface [StockCs] (le magasin du poste, ou une mémoire de test). Les références (`DOS-`,
/// `C`, `PRS-`, `ADM-`, `LAB-`, `IME-`) suivent le REGISTRE (plus grand rang + 1) et non le compteur de page de la maquette (écart E341, même
/// famille que E100 / E142).
library;

import '../caisse/prise_en_charge.dart' show carteValide;
import '../format/format_fr.dart';
import '../format/js.dart';
import '../imagerie/img_demandes_etats.dart' show modaliteDemandeDeExamen;
import '../imagerie/img_demandes_ouverture.dart' show referenceSerie;
import '../labo/dem_regles.dart' show demCodeAnalyse;
import '../referentiels/regles.dart' show joursEntre;
import 'cs_referentiels.dart';

/// Refus NOMMÉ : [message] s'affiche tel quel ; [code] distingue `SANS_DOSSIER`.
class RefusCs implements Exception {
  const RefusCs(this.message, [this.code]);
  final String message;
  final String? code;
  @override
  String toString() => message;
}

/// Ce que le moteur lit et écrit. Les collections de la maquette (`patients`, `produits`, `actes`, `catalogueTarifs`, `examensImagerie`, `soignants`,
/// `pathologies`, `constantes`, `couverturesAssurance`, `dossiersConsultation`, `consultations`, `ordonnances`, `demandesAnalyses`,
/// `demandesImagerie`, `factures`, `taches`, `notifications`, `prescriptions`, `administrations`) et le référentiel statique `analyses`.
abstract interface class StockCs {
  List<FicheCs> actives(String col);
  List<FicheCs> toutes(String col);
  FicheCs? parId(String col, Object? id);

  /// Insère EN TÊTE (comme `db[name].unshift`), attribue l'identifiant, rend la fiche écrite.
  FicheCs inserer(String col, FicheCs fiche);
  void mettreAJour(String col, Object? id, FicheCs patch);
  void archiver(String col, Object? id);

  /// Défait une insertion (`ins.undo()`) : la maquette retire la fiche ; le poste l'ARCHIVE (RG-14, jamais de suppression physique — écart E342).
  void defaire(String col, Object? id);
  List<FicheCs> referentiel(String nom);
  DateTime get maintenant;
}

/// La session qui agit : sa fonction décide de l'écriture des rubriques chirurgicales ; son secteur est celui des demandes.
class SessionCs {
  const SessionCs({this.role = '', this.fonction = '', this.secteur});
  final String role, fonction;

  /// Libellé du secteur de la session (`secteurCourant().libelle`) : renseigné sur la demande d'analyse / d'imagerie quand la prescription n'en
  /// porte pas — sans lui, aucune sage-femme ne voit rien (RBAC métier).
  final String? secteur;
}

double _n(Object? v) => nombreOuZero(v);
String _iso(DateTime d) => d.toUtc().toIso8601String();
String _pad(int n, int l) => n.toString().padLeft(l, '0');
List<FicheCs> _liste(Object? v) =>
    [for (final x in (v as List? ?? const [])) (x as Map).cast<String, Object?>()];

/// `a || b` de JavaScript pour des valeurs quelconques.
Object? _ou(Object? a, Object? b) => csVrai(a) ? a : b;

FicheCs? csPatientParCode(StockCs s, Object? code) =>
    s.actives('patients').where((p) => p['code'] == code).firstOrNull;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le dossier de consultation
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `dossierEnregistre(d)` : « en attente » = inscrit, jamais examiné ; seuls « en consultation » et « en attente labo » sont ENREGISTRÉS.
bool csDossierEnregistre(FicheCs? d) =>
    d != null &&
    d['statut'] != 'archive' &&
    (d['etat'] == 'consultation' || d['etat'] == 'attente_labo');

/// `dossierActifDe(patientCode)` : le plus récent des dossiers enregistrés du patient.
FicheCs? csDossierActifDe(StockCs s, Object? patientCode) {
  final l = [
    for (final d in s.actives('dossiersConsultation'))
      if (d['patientCode'] == patientCode && csDossierEnregistre(d)) d
  ];
  String cle(FicheCs d) =>
      '${_ou(d['dossierSaisiLe'], _ou(d['ouvertLe'], _ou(d['dateArrivee'], '')))}';
  l.sort((a, b) => cle(b).compareTo(cle(a)));
  return l.firstOrNull;
}

/// `dernierReleve(patientCode, patientId)` : le relevé de constantes de l'accueil le plus récent (par `dateHeure`, comparaison de chaînes).
FicheCs? csDernierReleve(StockCs s, Object? patientCode, Object? patientId) {
  final l = [
    for (final r in s.actives('constantes'))
      if (r['patientCode'] == patientCode ||
          (csVrai(patientId) && r['patientId'] == patientId))
        r
  ];
  String cle(FicheCs r) => '${r['dateHeure'] ?? ''}';
  l.sort((a, b) => cle(b).compareTo(cle(a)));
  return l.firstOrNull;
}

/// `copieReleve(r)` : la COPIE datée que le dossier garde — le médecin a examiné sur ces valeurs.
FicheCs? csCopieReleve(FicheCs? r) {
  if (r == null) return null;
  Object? nn(Object? v) => v;
  Object? imc;
  if (r['imc'] != null) {
    imc = r['imc'];
  } else if (csVrai(r['poids']) && csVrai(r['taille'])) {
    final t = _n(r['taille']) / 100;
    imc = arrondiJs(_n(r['poids']) / (t * t) * 10) / 10;
  }
  return {
    'releveId': _ou(r['id'], null),
    'dateHeure': _ou(r['dateHeure'], null),
    'releveePar': _ou(r['releveePar'], null),
    'temperature': nn(r['temperature']),
    'poids': nn(r['poids']),
    'taille': nn(r['taille']),
    'tension': _ou(r['tension'], null),
    'pouls': nn(r['pouls']),
    'spo2': nn(r['spo2']),
    'imc': imc,
  };
}

/// `constantesDuDossier(d)` : la copie figée à l'enregistrement, ou — pour un dossier d'AVANT la refonte — ses constantes à plat.
({Map<String, Object?> valeurs, String source})? csConstantesDuDossier(FicheCs? d) {
  if (d == null) return null;
  if (csVrai(d['constantesAccueil'])) {
    return (
      valeurs: (d['constantesAccueil'] as Map).cast<String, Object?>(),
      source: 'copie'
    );
  }
  if (d['temperature'] != null || csVrai(d['tension']) || d['pouls'] != null) {
    return (valeurs: csCopieReleve(d)!, source: 'ancienne');
  }
  return null;
}

int? _age(Object? naissance, DateTime maintenant) {
  final d = DateTime.tryParse('${naissance ?? ''}');
  if (!csVrai(naissance) || d == null) return null;
  final j = joursEntre(d, maintenant);
  final a = (j / 365.25).floor();
  return a < 0 ? 0 : a;
}

/// Résultat de l'enregistrement d'un dossier.
class ResultatDossier {
  const ResultatDossier(this.dossier, this.cree);
  final FicheCs dossier;
  final bool cree;
}

/// `enregistrerDossier(v, record)` — le MOTEUR de l'enregistrement du dossier, séparé de l'écran pour être sondé. Refuse EN LE DISANT ; ne devine
/// rien. [v] est modifié (rubriques chirurgicales reprises du dossier existant pour qui n'est pas chirurgien).
ResultatDossier csEnregistrerDossier(StockCs s, Map<String, Object?> v,
    FicheCs? record, SessionCs session) {
  final p = csPatientParCode(s, v['patientCode']);
  if (p == null) {
    throw RefusCs(
        'Patient introuvable au répertoire : ${v['patientCode']}.');
  }
  if (record != null && record['etat'] == 'cloture') {
    throw RefusCs(
        'Le dossier ${_ou(record['reference'], record['id'])} est CLÔTURÉ : il ne se réécrit pas. Ouvrir un nouveau dossier pour une nouvelle venue.');
  }
  if (record == null) {
    final ouvert = csDossierActifDe(s, p['code']);
    if (ouvert != null) {
      throw RefusCs(
          'Un dossier est déjà ouvert pour ${p['nom']} ${p['prenom']} : ${_ou(ouvert['reference'], ouvert['id'])} (${csEtatDossier(ouvert['etat'])['label']}). Le compléter plutôt que d’en ouvrir un second, ou le clôturer d’abord.');
    }
  }
  // Le contrôle d'écriture des rubriques chirurgicales est REFAIT au moteur : un champ désactivé dans l'interface ne protège rien.
  final capacite = '${_ou(session.fonction, session.role)}';
  for (final rub in csRubriquesChirurgicales) {
    final permis = csPeutEcrireRubrique(
        rub,
        (capacite == 'chirurgien' || session.role == 'chirurgien')
            ? 'chirurgien'
            : capacite);
    if (!permis.ok) v[rub] = record != null ? record[rub] : null;
  }
  final releve = csDernierReleve(s, p['code'], p['id']);
  final maj = <String, Object?>{
    ...v,
    'patientId': p['id'],
    'patient': '${p['nom']} ${p['prenom']}',
    'patientCode': p['code'],
    'nip': p['code'],
    'age': csVrai(p['dateNaissance']) ? _age(p['dateNaissance'], s.maintenant) : null,
    'sexe': p['sexe'],
    'assureur': _ou(p['assureurNom'], _ou(p['assureur'], null)),
    // La copie des constantes de l'accueil : posée une fois — une ré-édition ne la remplace pas.
    'constantesAccueil': (record != null && csVrai(record['constantesAccueil']))
        ? record['constantesAccueil']
        : csCopieReleve(releve),
    'dossierSaisiLe': _iso(s.maintenant),
  };
  if (record != null) {
    // C'est la SAISIE qui fait avancer un dossier inscrit en attente : attente → consultation.
    if (record['etat'] == 'attente') maj['etat'] = 'consultation';
    s.mettreAJour('dossiersConsultation', record['id'], maj);
    return ResultatDossier(s.parId('dossiersConsultation', record['id'])!, false);
  }
  final ins = s.inserer('dossiersConsultation', {
    ...maj,
    'reference': referenceSerie('DOS-', 5, s.toutes('dossiersConsultation')),
    'etat': 'consultation',
    'ouvertLe': _iso(s.maintenant),
  });
  return ResultatDossier(ins, true);
}

/// `changerEtatDossier` : transition ordonnée, sauts refusés. Rend le patch à écrire (ou lève un refus nommé).
FicheCs csPatchEtatDossier(FicheCs dossier, String vers, String? motif,
    DateTime maintenant) {
  if (!csTransitionPermise(dossier['etat'], vers)) {
    throw RefusCs(
        'Transition refusée : « ${csEtatDossier(dossier['etat'])['label']} » ne mène pas à « ${csEtatDossier(vers)['label']} ».');
  }
  return {
    'etat': vers,
    'motifEtat': motif,
    'cloturLe': vers == 'cloture' ? _iso(maintenant) : null,
  };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La fiche de consultation
// ---------------------------------------------------------------------------------------------------------------------------------------------

const csMessageSansDossier =
    'Aucun dossier de consultation enregistré pour ce patient. La fiche fait le RÉCAPITULATIF du dossier : ouvrir d’abord « Soins › Consultations & prescriptions › Dossiers de consultation », y enregistrer l’anamnèse et l’examen clinique, puis revenir à la fiche.';

/// Ce que l'enregistrement d'une fiche a produit.
class ResultatFiche {
  const ResultatFiche(this.consultation, this.prescription, this.dossier,
      this.suites, this.rendezVous);
  final FicheCs consultation, dossier;
  final ResultatPrescription? prescription;
  final List<({String label, String ecran})> suites;
  final FicheCs? rendezVous;
}

/// `enregistrerFiche(v)` : la fiche est le RÉCAPITULATIF d'un dossier enregistré et la SEULE porte de prescription (médicaments, analyses,
/// imagerie). Un échec de prescription DÉFAIT la consultation — rien n'est écrit à moitié.
ResultatFiche csEnregistrerFiche(
    StockCs s, Map<String, Object?> v, SessionCs session) {
  final p = csPatientParCode(s, v['patientCode']);
  if (p == null) {
    throw RefusCs('Patient introuvable au répertoire : ${v['patientCode']}.');
  }
  FicheCs? d = csVrai(v['dossierConsultationId'])
      ? s.parId('dossiersConsultation', v['dossierConsultationId'])
      : csDossierActifDe(s, p['code']);
  if (d != null && d['patientCode'] != p['code']) d = null;
  if (d == null || !csDossierEnregistre(d)) {
    throw RefusCs(
        d != null && d['etat'] == 'cloture'
            ? 'Le dossier ${_ou(d['reference'], d['id'])} est clôturé. $csMessageSansDossier'
            : (d != null && d['etat'] == 'attente'
                ? 'Le dossier ${_ou(d['reference'], d['id'])} est encore EN ATTENTE — l’examen n’y est pas consigné. $csMessageSansDossier'
                : csMessageSansDossier),
        'SANS_DOSSIER');
  }
  final pathologies = [for (final x in (v['pathologies'] as List? ?? const [])) '$x'];
  if (pathologies.isEmpty) {
    throw const RefusCs('Coder au moins une pathologie retenue (référentiel de morbidité).');
  }
  if ('${v['diagnostic'] ?? ''}'.trim().isEmpty) {
    throw const RefusCs('Rédiger le diagnostic retenu.');
  }
  final listePath = s.actives('pathologies');
  FicheCs? pathologie(String code) =>
      listePath.where((y) => y['code'] == code).firstOrNull;
  final cv = csConstantesDuDossier(d)?.valeurs ?? const <String, Object?>{};
  final typeCons = {
        'urgence': 'Urgence',
        'controle': 'Contrôle',
        'suivi': 'Contrôle'
      }['${d['typeVenue']}'] ??
      'Consultation';
  final date = csVrai(v['date'])
      ? _iso(DateTime.parse('${v['date']}'))
      : _iso(s.maintenant);
  final consult = <String, Object?>{
    'patientCode': p['code'],
    'medecin': v['medecin'],
    'date': date,
    'type': typeCons,
    'statut': 'terminee',
    'motif': _ou(d['motifVenue'], ''),
    'diagnostic': v['diagnostic'],
    'resumeSyndromique': _ou(v['resumeSyndromique'], ''),
    'hypotheses': _ou(v['hypotheses'], ''),
    'traitementEmblee': _ou(v['traitementEmblee'], ''),
    'conduite': _ou(v['conduite'], ''),
    'pathologies': pathologies,
    'pathologiePrincipale': pathologies.first,
    'pathologiesLibelles': [
      for (final c in pathologies) pathologie(c)?['libelle'] ?? c
    ],
    'notifiable': pathologies.any((c) => csVrai(pathologie(c)?['notifiable'])),
    // Les constantes de l'accueil : posées là où les lecteurs de `consultations` (dossier patient, statistiques) les ont toujours lues.
    'temperature': cv['temperature'],
    'tension': _ou(cv['tension'], null),
    'poids': cv['poids'],
    'fc': cv['pouls'],
    'orientation': _ou(v['orientation'], null),
    'orientationLabel': csLibelleOrientation(v['orientation']),
    'tarif': v['tarif'] ?? 3000,
    'dossierConsultationId': d['id'],
    'dossierReference': _ou(d['reference'], null),
    'patientId': p['id'],
    'patient': '${p['nom']} ${p['prenom']}',
    'reference': referenceSerie('C', 5, s.toutes('consultations')),
  };
  final ins = s.inserer('consultations', consult);

  final medicaments = [
    for (final l in _liste(v['medicaments']))
      if (csVrai(l['produitId']) && _n(l['quantite']) > 0) l
  ];
  final analyses = [for (final x in (v['analyses'] as List? ?? const [])) '$x'];
  final imagerie = [for (final x in (v['imagerie'] as List? ?? const [])) '$x'];
  ResultatPrescription? prescription;
  if (medicaments.isNotEmpty || analyses.isNotEmpty || imagerie.isNotEmpty) {
    try {
      prescription = csPrescrire(
          s,
          {
            'patientCode': p['code'],
            'medecin': v['medecin'],
            'diagnostic': v['diagnostic'],
            'date': date,
            'consultationId': ins['id'],
            'dossierConsultationId': d['id'],
            'indication': v['diagnostic'],
            'origine': 'consultation',
            'medicaments': medicaments,
            'analyses': analyses,
            'imagerie': imagerie,
          },
          session);
    } on RefusCs catch (e) {
      s.defaire('consultations', ins['id']);
      throw RefusCs(
          'Prescription refusée — rien n’a été enregistré : ${e.message}');
    }
    s.mettreAJour('consultations', ins['id'], {
      'ordonnanceId': prescription.ordonnance['id'],
      'ordonnanceNumero': prescription.ordonnance['numero'],
      'factureId': prescription.facture['id'],
      'factureNumero': prescription.facture['numero'],
    });
  }

  final cible = (analyses.isNotEmpty || imagerie.isNotEmpty) ? 'attente_labo' : 'cloture';
  final patch = <String, Object?>{
    'derniereFicheId': ins['id'],
    'fichesIds': [...(d['fichesIds'] as List? ?? const []), ins['id']],
    'ordonnanceIds': [
      ...(d['ordonnanceIds'] as List? ?? const []),
      if (prescription != null) prescription.ordonnance['id']
    ],
    'diagnosticRetenu': v['diagnostic'],
    'pathologiesRetenues': pathologies,
    'orientation': _ou(v['orientation'], null),
  };
  if (cible != d['etat'] && csTransitionPermise(d['etat'], cible)) {
    patch['etat'] = cible;
    if (cible == 'cloture') patch['cloturLe'] = _iso(s.maintenant);
  }
  s.mettreAJour('dossiersConsultation', d['id'], patch);

  // Les SUITES de l'orientation : on NOTIFIE ce qui revient à un autre service — l'admission et la mise en observation ont leurs propres écrans.
  final suites = <({String label, String ecran})>[];
  FicheCs? rdv;
  final orientation = v['orientation'];
  if (orientation == 'domicile' && csVrai(v['prochainRdv'])) {
    rdv = s.inserer('consultations', {
      'patientCode': p['code'],
      'patientId': p['id'],
      'patient': '${p['nom']} ${p['prenom']}',
      'medecin': v['medecin'],
      'type': 'Contrôle',
      'statut': 'planifiee',
      'date': v['prochainRdv'],
      'motif': 'Contrôle — ${v['diagnostic']}',
      'reference': referenceSerie('C', 5, s.toutes('consultations')),
      'origine': 'fiche de consultation',
      'dossierConsultationId': d['id'],
    });
    suites.add((
      label:
          'Rendez-vous de contrôle le ${dateFR(DateTime.parse('${v['prochainRdv']}'))}',
      ecran: 'm2-rendezvous'
    ));
  }
  if (orientation == 'hospitalisation' || orientation == 'observation') {
    final hospi = orientation == 'hospitalisation';
    csNotifier(s, {
      'type': hospi ? 'orientation_hospitalisation' : 'orientation_observation',
      'poste': hospi ? 'hospitalisation' : 'observation',
      'priorite': 'haute',
      'libelle':
          '${hospi ? 'Admission demandée — ' : 'Mise en observation demandée — '}${p['nom']} ${p['prenom']}',
      'detail':
          '${v['diagnostic']} — prescrit par ${v['medecin']} (dossier ${_ou(d['reference'], d['id'])})',
      'patientId': p['id'],
      'reference': _ou(d['reference'], null),
      'ordonnanceId': prescription?.ordonnance['id'],
    });
    suites.add((
      label: hospi ? 'Ouvrir l’admission' : 'Ouvrir la mise en observation',
      ecran: hospi ? 'm3-admissions' : 'm3-observation'
    ));
  }
  if (orientation == 'reference') {
    suites.add((label: 'Établir la fiche de référence', ecran: 'm1-reference'));
  }
  return ResultatFiche(s.parId('consultations', ins['id'])!, prescription,
      s.parId('dossiersConsultation', d['id'])!, suites, rdv);
}

/// `PR.notifier(o)` : une notification s'adresse à un POSTE, non à une personne.
FicheCs csNotifier(StockCs s, Map<String, Object?> o) =>
    s.inserer('notifications', {
      'type': o['type'],
      'poste': _ou(o['poste'], 'tous'),
      'destinataire': _ou(o['destinataire'], null),
      'libelle': o['libelle'],
      'detail': _ou(o['detail'], null),
      'priorite': _ou(o['priorite'], 'normale'),
      'demandeId': _ou(o['demandeId'], null),
      'factureId': _ou(o['factureId'], null),
      'ordonnanceId': _ou(o['ordonnanceId'], null),
      'patientId': _ou(o['patientId'], null),
      'reference': _ou(o['reference'], null),
      'lue': false,
      'creeLe': _iso(s.maintenant),
      'statut': 'actif',
    });

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La prescription (ordonnance + analyses + actes + imagerie → UNE facture)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Ce que `PR.prescrire` écrit.
class ResultatPrescription {
  const ResultatPrescription(this.ordonnance, this.demandes,
      this.demandesImagerie, this.facture, this.taches);
  final FicheCs ordonnance, facture;
  final List<FicheCs> demandes, demandesImagerie, taches;
}

/// Les tâches d'aval (`TACHES` de `parcours.js`) : poste, module, écran, titre, pictogramme.
const _tachesDef = <String, ({String role, String module, String ecran, String titre, String icon})>{
  'encaissement': (role: 'caissier', module: 'M8', ecran: 'm8-caisse', titre: 'Encaisser la prescription', icon: 'coins'),
  'dispensation': (role: 'pharmacien', module: 'M6', ecran: 'm6-dispensation', titre: 'Délivrer les médicaments', icon: 'pill'),
  'prelevement': (role: 'laborantin', module: 'M5', ecran: 'm5-demandes', titre: 'Prélever et analyser', icon: 'flask-conical'),
  'acte': (role: 'infirmier', module: 'M3', ecran: 'm3-soins', titre: 'Exécuter les actes prescrits', icon: 'stethoscope'),
  'imagerie': (role: 'echographiste', module: 'M2', ecran: 'm2-dashboard-imagerie', titre: 'Réaliser l’examen d’imagerie', icon: 'scan-line'),
};

FicheCs _creerTache(StockCs s, String type, FicheCs ord, FicheCs? facture,
    FicheCs extra) {
  final def = _tachesDef[type]!;
  return s.inserer('taches', {
    'type': type,
    'role': def.role,
    'module': def.module,
    'ecran': def.ecran,
    'titre': def.titre,
    'icon': def.icon,
    'reference': ord['numero'],
    'ordonnanceId': ord['id'],
    'factureId': facture?['id'],
    'factureNumero': facture?['numero'],
    'patient': ord['patient'],
    'patientCode': ord['patientCode'],
    'date': ord['date'],
    'urgent': csVrai(ord['urgent']),
    'statut': 'en_attente',
    'faitLe': null,
    'faitPar': null,
    ...extra,
  });
}

/// Le tarif d'un code : le catalogue tarifaire (`D.CATALOGUE`) — RG-09, le prix applicable dépend de la VALIDITÉ de la carte à la date.
({num? montant, String? tarif, String? motif, FicheCs? entree}) csTarifPrix(
    StockCs s, Object? code, bool assure) {
  final e = s
      .actives('catalogueTarifs')
      .where((t) => t['code'] == code)
      .firstOrNull;
  if (e == null) {
    return (montant: null, tarif: null, motif: 'Acte absent du catalogue tarifaire.', entree: null);
  }
  if (!assure) {
    return (montant: e['prixNonAssure'] as num?, tarif: 'non assuré', motif: null, entree: e);
  }
  if (e['assurable'] == false || csVrai(e['nonCouvert'])) {
    return (
      montant: e['prixNonAssure'] as num?,
      tarif: 'non assuré',
      motif: 'Acte NON COUVERT par les assurances — facturé au patient au tarif non assuré.',
      entree: e
    );
  }
  if (e['assurable'] == 'sos') {
    return (
      montant: e['prixNonAssure'] as num?,
      tarif: 'non assuré',
      motif: 'Les certificats ne sont couverts que par SOS — vérifier la compagnie.',
      entree: e
    );
  }
  return (montant: e['prixAssure'] as num?, tarif: 'assuré', motif: null, entree: e);
}

/// Rang suivant d'une SÉRIE ANNUELLE de pièces de caisse (`FP-2026-`) : le plus grand rang déjà porté par les factures du même préfixe
/// (archivées comprises, RG-14), plus un. Port de `PR.rangSerieFactures`.
int csRangSerieFactures(StockCs s, String prefixe) {
  var max = 0;
  for (final f in s.toutes('factures')) {
    final n = '${f['numero'] ?? ''}';
    if (!n.startsWith(prefixe)) continue;
    final r = int.tryParse(RegExp(r'^\d+').stringMatch(n.substring(prefixe.length)) ?? '') ?? 0;
    if (r > max) max = r;
  }
  return max + 1;
}

bool _carteValide(StockCs s, FicheCs p, String date) =>
    carteValide(p, s.toutes('couverturesAssurance'), date);

/// `construireLignes(v)` : UNE ligne payable par prestation, qui connaît ce qu'elle couvre (`demandeId`, `produitId`, `acteCode`,
/// `demandeImagerieId`) — c'est ce lien qui permet à l'encaissement de libérer exactement ce qui est payé. RG-02 : jamais de remise sur un
/// médicament. Un agent de la clinique : prise en charge du personnel, jamais une créance.
List<FicheCs> csConstruireLignes(
    {List<FicheCs> medicaments = const [],
    List<FicheCs> analyses = const [],
    List<FicheCs> demandes = const [],
    List<FicheCs> actes = const [],
    List<FicheCs> autres = const [],
    num taux = 0,
    Object? personnelId}) {
  final lignes = <FicheCs>[];
  final estAgent = csVrai(personnelId);
  var n = 0;
  void ajouter(FicheCs o) {
    n++;
    final brut = arrondiJs(_n(o['montant'])).toInt();
    var remise = arrondiJs(_n(o['remise'])).toInt();
    if (o['categorie'] == 'medicament') remise = 0;
    final montant = brut - remise;
    final partAssureur = estAgent ? 0 : arrondiJs(montant * taux / 100).toInt();
    final partPersonnel = estAgent ? montant : 0;
    final q = o['quantite'] ?? 1;
    final qq = _ou(o['quantite'], 1);
    lignes.add({
      'id': 'L${_pad(n, 3)}',
      'categorie': o['categorie'],
      'designation': o['designation'],
      'quantite': q,
      'prixUnitaire': o['prixUnitaire'] ?? brut,
      'prixUnitaireNet':
          csVrai(qq) ? arrondiJs(montant / _n(qq)).toInt() : montant,
      'montantBrut': brut,
      'remise': remise,
      'motifRemise': remise != 0 ? _ou(o['motifRemise'], 'Remise accordée') : null,
      'montant': montant,
      'partAssureur': partAssureur,
      'partPersonnel': partPersonnel,
      'partPatient': montant - partAssureur - partPersonnel,
      'demandeId': _ou(o['demandeId'], null),
      'produitId': _ou(o['produitId'], null),
      'acteCode': _ou(o['acteCode'], null),
      'demandeImagerieId': _ou(o['demandeImagerieId'], null),
      'statutPaiement': 'du',
      'montantRegle': 0,
      'payeLe': null,
      'payePar': null,
    });
  }

  for (final m in medicaments) {
    ajouter({
      'categorie': 'medicament',
      'designation': m['produit'],
      'quantite': m['quantite'],
      'prixUnitaire': m['prix'],
      'montant': m['total'],
      'produitId': m['produitId'],
    });
  }
  for (var i = 0; i < analyses.length; i++) {
    final dem = i < demandes.length ? demandes[i] : null;
    ajouter({
      'categorie': 'analyse',
      'designation': analyses[i]['designation'],
      'quantite': 1,
      'prixUnitaire': analyses[i]['prix'],
      'montant': analyses[i]['prix'],
      'demandeId': dem?['id'],
    });
  }
  for (final a in actes) {
    ajouter({
      'categorie': 'acte',
      'designation': a['libelle'],
      'quantite': 1,
      'prixUnitaire': a['prix'] ?? 0,
      'montant': a['prix'] ?? 0,
      'acteCode': a['code'],
    });
  }
  autres.forEach(ajouter);
  return lignes;
}

double _somme(Iterable<FicheCs> l, String cle) =>
    l.fold(0.0, (a, x) => a + _n(x[cle]));

/// `PR.prescrire(v)` : engendre D'UN SEUL GESTE l'ordonnance, les demandes d'analyses, les demandes d'imagerie, UNE facture globale (lignes
/// payables) et les tâches d'aval, qui naissent BLOQUÉES. Un examen d'imagerie sans tarif est refusé EN LE NOMMANT, et le refus ne laisse derrière
/// lui ni ordonnance ni facture.
ResultatPrescription csPrescrire(
    StockCs s, Map<String, Object?> v, SessionCs session) {
  final p = csPatientParCode(s, v['patientCode']);
  if (p == null) throw RefusCs('Patient introuvable : ${v['patientCode']}');
  final date = csVrai(v['date']) ? '${v['date']}' : _iso(s.maintenant);
  final annee = DateTime.parse(date).toLocal().year;
  final numero = 'ORD-$annee-${_pad(s.toutes('ordonnances').length + 1, 5)}';

  final medicaments = <FicheCs>[
    for (final l in _liste(v['medicaments']))
      () {
        final prod = s
                .actives('produits')
                .where((x) => x['id'] == l['produitId'])
                .firstOrNull ??
            const <String, Object?>{};
        final pu = prod['prixAchat'] != null ? prod['prixAchat'] as num : 0;
        final q = _n(l['quantite']);
        return <String, Object?>{
          'produitId': l['produitId'],
          'produit': _ou(prod['designation'], _ou(l['produit'], '—')),
          'unite': _ou(prod['unite'], ''),
          'quantite': q == q.truncateToDouble() ? q.toInt() : q,
          'posologie': _ou(l['posologie'], ''),
          'duree': _ou(l['duree'], ''),
          'prix': pu,
          'total': pu * q == (pu * q).truncateToDouble() ? (pu * q).toInt() : pu * q,
        };
      }()
  ].where((l) => _n(l['quantite']) > 0).toList();

  final referentielAnalyses = s.referentiel('analyses');
  final analyses = <FicheCs>[
    for (final code in (v['analyses'] as List? ?? const []))
      () {
        final a = referentielAnalyses.where((x) => x['code'] == code).firstOrNull ??
            const <String, Object?>{};
        return <String, Object?>{
          'code': code,
          'designation': _ou(a['designation'], code),
          'categorie': _ou(a['categorie'], ''),
          'echantillon': _ou(a['echantillon'], ''),
          'delai': _ou(a['delai'], ''),
          'prix': _ou(a['prix'], 0),
        };
      }()
  ];

  // C3 (corrigé dans la maquette le 31/10/2026, puis porté) : le tarif ASSURÉ d'un acte (pansement : 6 000 contre 9 000, colonnes inversées)
  // s'applique réellement quand la carte est valide à la date (RG-09). Seule la colonne assurée change le prix (`prixAssure` de l'acte du catalogue) :
  // sans carte valide, ou pour un acte que la grille exclut de l'assurance, le catalogue administrable reste la référence.
  final assureActes = csVrai(p['assureur']) && _carteValide(s, p, date);
  final actes = <FicheCs>[
    for (final code in (v['actes'] as List? ?? const []))
      () {
        final a = s.actives('actes').where((x) => x['code'] == code).firstOrNull ??
            const <String, Object?>{};
        final tarifAssure = assureActes &&
            a['assurable'] == true &&
            !csVrai(a['nonCouvert']) &&
            a['prixAssure'] != null;
        final Object? prixActe = tarifAssure ? a['prixAssure'] : a['prix'];
        return <String, Object?>{
          'code': code,
          'libelle': _ou(a['libelle'], code),
          'secteur': _ou(a['secteur'], ''),
          'prix': csVrai(prixActe) ? prixActe : 0,
          'tarifValide': prixActe != null,
        };
      }()
  ];

  final mMed = _somme(medicaments, 'total');
  final mAna = _somme(analyses, 'prix');
  final mAct = _somme(actes, 'prix');

  // L'imagerie est prescrite DANS LE MÊME GESTE : UNE facture globale. Les demandes sont créées AVANT l'ordonnance.
  final secteurDemandeur = _ou(v['secteurDemandeur'], session.secteur);
  final imagerieCree = (v['imagerie'] as List? ?? const []).isNotEmpty
      ? csCreerDemandesImagerie(s, p, [for (final c in v['imagerie'] as List) '$c'], date, {
          'prescripteur': v['medecin'],
          'indication': _ou(v['indication'], _ou(v['diagnostic'], '')),
          'urgent': csVrai(v['urgent']),
          'secteurDemandeur': secteurDemandeur,
          'origine': _ou(v['origine'], 'consultation'),
          'dossierConsultationId': _ou(v['dossierConsultationId'], null),
        })
      : (demandes: <FicheCs>[], lignes: <FicheCs>[]);
  final demandesImagerie = imagerieCree.demandes;
  final imagerie = <FicheCs>[
    for (final d in demandesImagerie)
      {
        'code': d['examenCode'],
        'examen': d['examen'],
        'modalite': d['modalite'],
        'prix': d['prix'],
        'demandeImagerieId': d['id'],
      }
  ];
  final mImg = _somme(imagerie, 'prix');

  final ord = s.inserer('ordonnances', {
    'numero': numero,
    'date': date,
    'patientId': p['id'],
    'patientCode': p['code'],
    'patient': '${p['nom']} ${p['prenom']}',
    'medecin': v['medecin'],
    'diagnostic': _ou(v['diagnostic'], ''),
    'consultationId': _ou(v['consultationId'], null),
    'dossierConsultationId': _ou(v['dossierConsultationId'], null),
    'medicaments': medicaments,
    'analyses': analyses,
    'actes': actes,
    'imagerie': imagerie,
    'montantMedicaments': mMed,
    'montantAnalyses': mAna,
    'montantActes': mAct,
    'montantImagerie': mImg,
    'montant': mMed + mAna + mAct + mImg,
    'urgent': csVrai(v['urgent']),
    'statutPaiement': 'impayee',
    'statutDispensation': medicaments.isNotEmpty ? 'en_attente' : 'sans_objet',
    'statutAnalyses': analyses.isNotEmpty ? 'en_attente' : 'sans_objet',
    'statutActes': actes.isNotEmpty ? 'en_attente' : 'sans_objet',
    'statutImagerie': imagerie.isNotEmpty ? 'en_attente' : 'sans_objet',
  });
  for (final d in demandesImagerie) {
    s.mettreAJour('demandesImagerie', d['id'],
        {'ordonnanceId': ord['id'], 'ordonnanceNumero': numero});
  }

  // Une demande d'analyse PAR examen, bloquée par le paiement.
  final demandes = <FicheCs>[];
  for (final a in analyses) {
    demandes.add(s.inserer('demandesAnalyses', {
      'reference': referenceSerie('LAB-', 5, s.toutes('demandesAnalyses')),
      'codeAnalyse': demCodeAnalyse(date, s.toutes('demandesAnalyses'),
          maintenant: s.maintenant),
      'patientId': p['id'],
      'patientCode': p['code'],
      'patient': '${p['nom']} ${p['prenom']}',
      'analyseCode': a['code'],
      'analyse': a['designation'],
      'categorie': a['categorie'],
      'echantillon': a['echantillon'],
      'delai': a['delai'],
      'prix': a['prix'],
      'dateHeure': date,
      'prescripteur': v['medecin'],
      'laborantin': null,
      'urgent': csVrai(v['urgent']),
      'etatAnalyse': 'en_attente',
      'origine': 'ordonnance',
      'ordonnanceId': ord['id'],
      'ordonnanceNumero': numero,
      'dossierConsultationId': _ou(v['dossierConsultationId'], null),
      'secteurDemandeur': secteurDemandeur,
      'bloqueParPaiement': true,
    }));
  }

  // RG-09 : la prise en charge ne s'applique que si la carte est valide À LA DATE (écart E340 corrigé dans la maquette).
  final taux = (csVrai(p['assureur']) && _carteValide(s, p, date))
      ? _ou(p['tauxPriseEnCharge'], 0) as num
      : 0;
  final montant = mMed + mAna + mAct + mImg;
  final lignesFacture = csConstruireLignes(
      medicaments: medicaments,
      analyses: analyses,
      demandes: demandes,
      actes: actes,
      autres: imagerieCree.lignes,
      taux: taux,
      personnelId: p['personnelId']);
  final totalLignes = _somme(lignesFacture, 'montant');
  final totalAssureur = _somme(lignesFacture, 'partAssureur');
  final totalPersonnel = _somme(lignesFacture, 'partPersonnel');
  final totalRemise = _somme(lignesFacture, 'remise');
  final duPatient = totalLignes - totalAssureur - totalPersonnel;

  final facture = s.inserer('factures', {
    'lignes': lignesFacture,
    // E6 (corrigé dans la maquette le 31/10/2026) : le rang est celui de la série de l'année, plus le nombre total de factures.
    'numero': 'FP-$annee-${_pad(csRangSerieFactures(s, 'FP-$annee-'), 5)}',
    'numeroMecef': null,
    'patientId': p['id'],
    'patient': '${p['nom']} ${p['prenom']}',
    'patientCode': p['code'],
    'date': iso(DateTime.parse(date).toLocal()),
    'type': 'Prescription',
    'montantHT': totalLignes,
    'montantTTC': totalLignes,
    'montantBrut': _somme(lignesFacture, 'montantBrut'),
    'totalRemise': totalRemise,
    'partPersonnel': totalPersonnel,
    'priseEnChargePersonnel': csVrai(p['personnelId']),
    'personnelId': _ou(p['personnelId'], null),
    'assureur': _ou(p['assureur'], null),
    'tauxPriseEnCharge': taux,
    'partAssurance': totalAssureur,
    'partPatient': duPatient,
    'montantPaye': 0,
    'reliquat': duPatient,
    'modePaiement': null,
    'statutPaiement': 'impayee',
    'statutMecef': 'en_attente',
    'ordonnanceId': ord['id'],
    'ordonnanceNumero': numero,
    'dossierConsultationId': _ou(v['dossierConsultationId'], null),
  });
  s.mettreAJour('ordonnances', ord['id'],
      {'factureId': facture['id'], 'factureNumero': facture['numero']});
  for (final d in demandesImagerie) {
    s.mettreAJour('demandesImagerie', d['id'],
        {'factureId': facture['id'], 'factureNumero': facture['numero']});
  }

  final ordFiche = s.parId('ordonnances', ord['id'])!;
  final taches = <FicheCs>[];
  final resume = [
    if (medicaments.isNotEmpty) '${medicaments.length} médicament(s)',
    if (analyses.isNotEmpty) '${analyses.length} analyse(s)',
    if (actes.isNotEmpty) '${actes.length} acte(s)',
    if (imagerie.isNotEmpty) '${imagerie.length} examen(s) d’imagerie',
  ].join(' · ');
  taches.add(_creerTache(s, 'encaissement', ordFiche, facture, {
    'detail': resume.isEmpty ? 'Prescription sans ligne' : resume,
    'montant': montant,
    'statut': 'en_attente',
  }));
  if (imagerie.isNotEmpty) {
    taches.add(_creerTache(s, 'imagerie', ordFiche, facture, {
      'poste': 'imagerie',
      'detail': imagerie.map((i) => i['examen']).join(', '),
      'montant': mImg,
      'statut': 'bloque',
    }));
    csNotifier(s, {
      'type': 'demande_imagerie',
      'poste': 'imagerie',
      'libelle': 'Nouvelle demande d’imagerie — ${p['nom']} ${p['prenom']}',
      'detail':
          '${imagerie.map((i) => i['examen']).join(', ')} — exécutable après passage en caisse',
      'priorite': csVrai(v['urgent']) ? 'haute' : 'normale',
      'patientId': p['id'],
      'reference': facture['numero'],
      'ordonnanceId': ord['id'],
    });
  }
  if (medicaments.isNotEmpty) {
    taches.add(_creerTache(s, 'dispensation', ordFiche, facture, {
      'detail': '${medicaments.length} médicament(s) — ${money(mMed, avecDevise: false)}',
      'montant': mMed,
      'statut': 'bloque',
    }));
  }
  if (analyses.isNotEmpty) {
    taches.add(_creerTache(s, 'prelevement', ordFiche, facture, {
      'detail':
          '${analyses.length} analyse(s) — ${analyses.map((a) => a['designation']).join(', ')}',
      'montant': mAna,
      'statut': 'bloque',
    }));
  }
  if (actes.isNotEmpty) {
    taches.add(_creerTache(s, 'acte', ordFiche, facture, {
      'detail': actes.map((a) => a['libelle']).join(', '),
      'montant': mAct,
      'statut': 'bloque',
    }));
  }

  // Le registre unique des prescriptions : les médicaments y figurent aussi (`inscrireOrdonnance`).
  if (medicaments.isNotEmpty) {
    s.inserer('prescriptions', {
      'reference': ordFiche['numero'],
      'type': 'ordonnance',
      'origine': _ou(v['origine'], 'consultation'),
      'date': ordFiche['date'],
      'patientId': ordFiche['patientId'],
      'patientCode': ordFiche['patientCode'],
      'patient': ordFiche['patient'],
      'prescripteurId': _ou(ordFiche['prescripteurId'], null),
      'prescripteur': ordFiche['medecin'],
      'secteurDestinataire': 'pharmacie',
      'modalite': _ou(ordFiche['modalite'], 'ambulatoire'),
      'premierAdministrateur': csSecteurAdministrateur(
              _ou(ordFiche['modalite'], 'ambulatoire'), 1)
          .secteur,
      'ordonnanceId': ordFiche['id'],
      'lignes': [
        for (final m in _liste(ordFiche['medicaments']))
          {
            'produitId': m['produitId'],
            'libelle': m['produit'],
            'quantite': m['quantite'],
            'posologie': m['posologie'],
            'duree': m['duree'],
            'prix': m['prix'],
            'nbAdministrations': _n(m['nbAdministrations']) != 0
                ? _n(m['nbAdministrations'])
                : 1,
          }
      ],
      'montant': _ou(ordFiche['montantMedicaments'], 0),
      'statut': 'en_cours',
      'statutPaiement': _ou(ordFiche['statutPaiement'], 'impayee'),
    });
  }

  return ResultatPrescription(
      ordFiche,
      demandes,
      [for (final d in demandesImagerie) s.parId('demandesImagerie', d['id'])!],
      facture,
      taches);
}

/// `creerDemandesImagerie(p, codes, date, v)` : une demande par examen, BLOQUÉE par le paiement ; un examen sans tarif est refusé en le nommant
/// (les demandes déjà créées sont ARCHIVÉES — RG-14, le numéro qu'elles ont consommé ne se réutilise pas).
({List<FicheCs> demandes, List<FicheCs> lignes}) csCreerDemandesImagerie(
    StockCs s, FicheCs p, List<String> codes, String date, FicheCs v) {
  final assure = _carteValide(s, p, date);
  final catalogue = s.actives('examensImagerie');
  final demandes = <FicheCs>[];
  for (final code in codes) {
    final ex = catalogue.where((x) => x['code'] == code).firstOrNull;
    final pr = csTarifPrix(s, _ou(ex?['tarifCode'], code), assure);
    demandes.add(s.inserer('demandesImagerie', {
      'reference': referenceSerie('IME-', 5, s.toutes('demandesImagerie')),
      'dateHeure': date,
      'patientId': p['id'],
      'patientCode': p['code'],
      'patient': '${p['nom']} ${p['prenom']}',
      'examenCode': code,
      'examen': ex != null ? ex['label'] : code,
      'modalite': modaliteDemandeDeExamen(catalogue, code),
      'prescripteur': _ou(v['prescripteur'], '—'),
      'indication': _ou(v['indication'], ''),
      'urgent': csVrai(v['urgent']),
      'secteurDemandeur': _ou(v['secteurDemandeur'], null),
      'origine': _ou(v['origine'], 'consultation'),
      'ordonnanceId': _ou(v['ordonnanceId'], null),
      'ordonnanceNumero': _ou(v['ordonnanceNumero'], null),
      'dossierConsultationId': _ou(v['dossierConsultationId'], null),
      'prix': pr.montant,
      'motifTarif': pr.motif,
      'statut': 'demandee',
      'bloqueParPaiement': true,
    }));
  }
  final sansPrix = demandes.where((d) => d['prix'] == null).toList();
  if (sansPrix.isNotEmpty) {
    for (final d in demandes) {
      s.archiver('demandesImagerie', d['id']);
    }
    throw RefusCs(
        'Tarif non renseigné pour : ${sansPrix.map((d) => d['examen']).join(', ')}. Le renseigner au référentiel tarifaire avant de facturer.');
  }
  return (
    demandes: demandes,
    lignes: [
      for (final d in demandes)
        {
          'categorie': 'imagerie',
          'designation': d['examen'],
          'quantite': 1,
          'prixUnitaire': d['prix'],
          'montant': d['prix'],
          'demandeImagerieId': d['id'],
        }
    ]
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La prescription de SOINS, son administration et la règle de relais
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `PR.prescrireSoins(v)` : des actes à exécuter, adressés à un secteur ; ne consomme pas le stock. Seuls médecins et sages-femmes prescrivent —
/// le contrôle est AU MOTEUR, pas à l'écran. Le tarif suit RG-09 (carte valide à la date).
FicheCs csPrescrireSoins(StockCs s, Map<String, Object?> v) {
  final p = csPatientParCode(s, v['patientCode']);
  if (p == null) throw RefusCs('Patient introuvable : ${v['patientCode']}');
  final soignant =
      s.actives('soignants').where((x) => x['id'] == v['prescripteurId']).firstOrNull;
  if (soignant != null && !csVrai(soignant['prescrit'])) {
    throw RefusCs(
        '${soignant['nomComplet']} (${soignant['poste']}) n’est pas habilité à prescrire.');
  }
  final date = csVrai(v['date']) ? '${v['date']}' : _iso(s.maintenant);
  final assure = _carteValide(s, p, date);
  final lignes = <FicheCs>[
    for (final a in (v['actes'] as List? ?? const []))
      () {
        final obj = a is Map ? a.cast<String, Object?>() : null;
        final code = obj != null ? obj['code'] : a;
        final t = s
            .actives('catalogueTarifs')
            .where((e) => e['code'] == code)
            .firstOrNull;
        final pr = csTarifPrix(s, code, assure);
        return <String, Object?>{
          'acteCode': code,
          'libelle': t != null ? t['libelle'] : code,
          'famille': t != null ? t['famille'] : null,
          'quantite': csVrai(obj?['quantite']) ? obj!['quantite'] : 1,
          'frequence': _ou(obj?['frequence'], ''),
          'duree': _ou(obj?['duree'], ''),
          // Le NOMBRE d'administrations fait vivre le relais : une administration unique ne quitte jamais la salle de soins.
          'nbAdministrations': csVrai(obj?['nbAdministrations']) ? obj!['nbAdministrations'] : 1,
          'prix': pr.montant,
          'tarif': pr.tarif,
          'motifTarif': pr.motif,
          'prixAValider': pr.montant == null,
        };
      }()
  ];
  final modalite = '${_ou(v['modalite'], 'ambulatoire')}';
  final pres = s.inserer('prescriptions', {
    'reference': referenceSerie('PRS-', 5, s.toutes('prescriptions')),
    'type': 'soins',
    'origine': _ou(v['origine'], 'consultation'),
    'date': date,
    'patientId': p['id'],
    'patientCode': p['code'],
    'patient': '${p['nom']} ${p['prenom']}',
    'prescripteurId': _ou(v['prescripteurId'], null),
    'prescripteur': soignant != null ? soignant['nomComplet'] : _ou(v['prescripteur'], '—'),
    'secteurDestinataire': _ou(v['secteurDestinataire'], 'salle_soins'),
    'modalite': modalite,
    'premierAdministrateur': csSecteurAdministrateur(modalite, 1).secteur,
    'admissionId': _ou(v['admissionId'], null),
    'indication': _ou(v['indication'], ''),
    'lignes': lignes,
    'montant': lignes.fold<num>(
        0, (t, l) => t + _n(l['prix']) * _n(l['quantite'])),
    'assure': assure,
    'statut': 'en_cours',
    'statutPaiement': 'impayee',
  });
  csNotifier(s, {
    'type': 'prescription_soins',
    'poste': _ou(v['secteurDestinataire'], 'salle_soins'),
    'libelle': 'Nouvelle prescription de soins — ${pres['patient']}',
    'detail':
        '${pres['reference']} — ${lignes.length} acte(s) — ${pres['prescripteur']}',
    'priorite': csVrai(v['urgent']) ? 'haute' : 'normale',
    'patientId': p['id'],
    'reference': pres['reference'],
  });
  return pres;
}

/// `PR.rangSuivant(prescriptionId, ligneIndex)` : le rang de la prochaine administration de la ligne.
int csRangSuivant(StockCs s, Object? prescriptionId, int ligneIndex) =>
    s.actives('administrations').where((a) =>
        a['prescriptionId'] == prescriptionId &&
        a['ligneIndex'] == ligneIndex).length +
    1;

/// Ce que `PR.administrer` rend : [ok] ou un refus NOMMÉ ([motif]) — jamais une exception pour un refus attendu.
class ResultatAdministration {
  const ResultatAdministration(
      {required this.ok,
      this.rang,
      this.secteur,
      this.secteurAttendu,
      this.motif,
      this.administration});
  final bool ok;
  final int? rang;
  final String? secteur, secteurAttendu, motif;
  final FicheCs? administration;
}

/// `PR.administrer(prescriptionId, opts)` : une prescription non réglée reste visible mais non exécutable ; le SECTEUR est décidé par le RANG
/// (règle de relais), jamais par l'organisation du service ; un exécutant doit exécuter (le médecin prescrit, il n'exécute pas les soins).
ResultatAdministration csAdministrer(StockCs s, Object? prescriptionId,
    {int ligneIndex = 0,
    String? secteur,
    Object? executantId,
    String? executant,
    String? observation,
    String? dateHeure,
    bool forcer = false}) {
  final pres = s.parId('prescriptions', prescriptionId);
  if (pres == null) throw const RefusCs('Prescription introuvable.');
  final lignes = _liste(pres['lignes']);
  if (ligneIndex < 0 || ligneIndex >= lignes.length) {
    throw const RefusCs('Ligne de prescription introuvable.');
  }
  final ligne = lignes[ligneIndex];
  if (pres['statutPaiement'] != 'payee' && !forcer) {
    return const ResultatAdministration(
        ok: false,
        motif:
            'Prescription non réglée — l’administration reste bloquée jusqu’à l’encaissement.');
  }
  final rang = csRangSuivant(s, prescriptionId, ligneIndex);
  final attendu = csSecteurAdministrateur(pres['modalite'], rang);
  if (csVrai(secteur) && secteur != attendu.secteur) {
    return ResultatAdministration(
        ok: false, rang: rang, secteurAttendu: attendu.secteur, motif: attendu.motif);
  }
  final exec = s.actives('soignants').where((x) => x['id'] == executantId).firstOrNull;
  if (exec != null && !csVrai(exec['execute'])) {
    return ResultatAdministration(
        ok: false,
        rang: rang,
        motif: '${exec['nomComplet']} (${exec['poste']}) n’exécute pas les soins.');
  }
  final rec = s.inserer('administrations', {
    'reference': referenceSerie('ADM-', 5, s.toutes('administrations')),
    'prescriptionId': prescriptionId,
    'prescriptionRef': pres['reference'],
    'ligneIndex': ligneIndex,
    'libelle': ligne['libelle'],
    'patientId': pres['patientId'],
    'patientCode': pres['patientCode'],
    'patient': pres['patient'],
    'dateHeure': _ou(dateHeure, _iso(s.maintenant)),
    'rang': rang,
    'total': _n(ligne['nbAdministrations']) != 0 ? ligne['nbAdministrations'] : 1,
    'secteur': attendu.secteur,
    'motifSecteur': attendu.motif,
    'executantId': _ou(executantId, null),
    'executant': exec != null ? exec['nomComplet'] : _ou(executant, '—'),
    'observation': _ou(observation, ''),
    'modalite': pres['modalite'],
  });
  var reste = false;
  for (var i = 0; i < lignes.length; i++) {
    final nb = _n(lignes[i]['nbAdministrations']) != 0 ? _n(lignes[i]['nbAdministrations']) : 1;
    if (csRangSuivant(s, prescriptionId, i) <= nb) reste = true;
  }
  if (!reste) s.mettreAJour('prescriptions', prescriptionId, {'statut': 'termine'});
  return ResultatAdministration(
      ok: true, rang: rang, secteur: attendu.secteur, administration: rec);
}

/// Une ligne de soin due à un secteur.
class SoinDu {
  const SoinDu(this.index, this.ligne, this.rang, this.total, this.secteur,
      this.motif, this.du, this.bloque);
  final int index, rang;
  final num total;
  final FicheCs ligne;
  final String secteur, motif;
  final bool du, bloque;
}

/// `PR.soinsDuSecteur(secteur)` : les administrations dues à un poste — le rang décide du secteur, le règlement de l'exécutabilité.
List<({FicheCs prescription, List<SoinDu> lignes})> csSoinsDuSecteur(
    StockCs s, String secteur) {
  final sortie = <({FicheCs prescription, List<SoinDu> lignes})>[];
  for (final pres in s.actives('prescriptions')) {
    if (pres['statut'] != 'en_cours') continue;
    final lignes = <SoinDu>[];
    final ls = _liste(pres['lignes']);
    for (var i = 0; i < ls.length; i++) {
      final l = ls[i];
      final rang = csRangSuivant(s, pres['id'], i);
      final att = csSecteurAdministrateur(pres['modalite'], rang);
      final total = _n(l['nbAdministrations']) != 0 ? _n(l['nbAdministrations']) : 1;
      final du = rang <= total && att.secteur == secteur;
      if (du) {
        lignes.add(SoinDu(i, l, rang, total, att.secteur, att.motif, du,
            pres['statutPaiement'] != 'payee'));
      }
    }
    if (lignes.isNotEmpty) sortie.add((prescription: pres, lignes: lignes));
  }
  return sortie;
}
