/// M1 — LE PATIENT EXTERNE : la demande naît à l'ACCUEIL (`PR.ouvrirDemandeExterne`), le dossier par la fabrique UNIQUE (`PR.dossierExterne`).
/// Rejoué sur `test/vecteurs/pat_externe.json`.
///
/// L'accueil TRANSCRIT une ordonnance extérieure, il ne prescrit pas ; les examens se cochent au catalogue — jamais un montant libre ; la caisse ne
/// crée jamais la demande. Le prélèvement n'a lieu qu'après règlement.
library;

import '../format/format_fr.dart';
import '../format/js.dart' show arrondiJs, nombreOuZero;
import '../labo/dem_regles.dart' show demCodeAnalyse, demReferenceSuivante;
import '../referentiels/regles.dart' show codePatient, resultatRendu;
import 'pat_patients.dart';

String _pad(int n, int l) => n.toString().padLeft(l, '0');
num? _nombre(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');

/// `PR.dossierExterne(v, date)` : le dossier d'un patient adressé de l'extérieur — UNE SEULE fabrique, pour l'accueil, le laboratoire, l'imagerie et
/// la délivrance d'une pièce. Le code suit `C.codePatient()` (`CNT/(900 + nombre de dossiers)/AA`). L'âge DÉCLARÉ est daté du jour de la
/// déclaration : sans cette date il se figerait. Rend la fiche à INSÉRER (sans identifiant : le magasin l'attribue).
FichePat patDossierExterne(FichePat v, DateTime date, int effectifRepertoire) {
  if ('${v['nom'] ?? ''}'.trim().isEmpty || '${v['prenom'] ?? ''}'.trim().isEmpty) {
    throw const PatRefus('Nom et prénoms du patient obligatoires.');
  }
  final age = _nombre(v['age']);
  final declare = !patVrai(v['dateNaissance']) && age != null;
  return {
    'code': codePatient(900 + effectifRepertoire, date.year),
    'nom': '${v['nom']}'.toUpperCase(),
    'prenom': v['prenom'],
    'sexe': patVrai(v['sexe']) ? v['sexe'] : 'M',
    'dateNaissance': patVrai(v['dateNaissance']) ? v['dateNaissance'] : null,
    'age': declare ? age : null,
    'ageReferenceLe': declare ? iso(date) : null,
    'telephone': patVrai(v['telephone']) ? v['telephone'] : null,
    'adresse': patVrai(v['residence']) ? v['residence'] : null,
    'quartier': patVrai(v['residence']) ? v['residence'] : null,
    'dateCreation': iso(date),
    'externe': true,
    'origineDossier': patVrai(v['origineDossier']) ? v['origineDossier'] : 'Patient externe — accueil',
    'prescripteurExterieur': patVrai(v['prescripteur']) ? v['prescripteur'] : null,
    'assure': patVrai(v['assureur']),
    'assureur': patVrai(v['assureur']) ? v['assureur'] : null,
    'tauxPriseEnCharge': patVrai(v['assureur']) ? (nombreOuZero(v['taux'])) : 0,
    'statut': 'actif',
  };
}

/// Un refus NOMMÉ : [message] s'affiche tel quel.
class PatRefus implements Exception {
  const PatRefus(this.message);
  final String message;
  @override
  String toString() => message;
}

class PatDemandeExterne {
  PatDemandeExterne(this.patient, this.dossierCree, this.demandes, this.facture, this.taches, this.montant);
  final FichePat patient;
  final bool dossierCree;
  final List<FichePat> demandes;
  final FichePat facture;

  /// Dans l'ordre d'écriture : encaissement (caisse) puis prélèvement (laboratoire, BLOQUÉ jusqu'au règlement).
  final List<FichePat> taches;
  final num montant;
}

/// `PR.ouvrirDemandeExterne(v)` : le dossier, les demandes (bloquées par le paiement), la facture à lignes payables, la caisse saisie et le
/// prélèvement en attente. [analyses] : le catalogue (`D.ANALYSES`) ; [demandesExistantes] : le registre entier, archivées comprises.
/// Écart E312 (porté fidèlement) : la compagnie déclarée au guichet est gardée par son NOM et le taux saisi s'applique sans contrôle de validité
/// de carte — l'accueil externe ne saisit aucune carte (RG-09 ne peut pas s'y vérifier).
PatDemandeExterne patOuvrirDemandeExterne({
  required FichePat saisie,
  required List<String> codesAnalyses,
  required Iterable<FichePat> catalogue,
  required Iterable<FichePat> patients,
  required Iterable<FichePat> demandesExistantes,
  required int nbFactures,
  required String Function(String prefixe) nouvelId,
  required DateTime date,
  FichePat? patientRepertoire,
}) {
  final v = saisie;
  if (patientRepertoire == null &&
      (!patVrai(v['nom']) || !patVrai(v['prenom']))) {
    throw const PatRefus('Nom et prénoms du patient obligatoires.');
  }
  if (codesAnalyses.isEmpty) throw const PatRefus('Cocher au moins un examen au catalogue.');

  var cree = false;
  FichePat p;
  if (patientRepertoire != null) {
    p = patientRepertoire;
  } else {
    p = {...patDossierExterne(v, date, patients.length), 'id': nouvelId('PAT')};
    cree = true;
  }
  final nomComplet = '${p['nom']} ${p['prenom']}';
  final analyses = [
    for (final code in codesAnalyses)
      () {
        final a = catalogue.where((x) => x['code'] == code).firstOrNull ?? const <String, Object?>{};
        return <String, Object?>{
          'code': code,
          'designation': a['designation'] ?? code,
          'categorie': a['categorie'] ?? '',
          'echantillon': a['echantillon'] ?? '',
          'delai': a['delai'] ?? '',
          'prix': a['prix'] ?? 0,
        };
      }()
  ];
  final montant = analyses.fold<num>(0, (s, a) => s + nombreOuZero(a['prix']));
  final jour = date.toUtc().toIso8601String();

  // Les demandes, marquées EXTERNE : le résultat se remet au patient.
  final existantes = [...demandesExistantes];
  final demandes = <FichePat>[];
  for (final a in analyses) {
    final urgent = v['urgence'] == 'bilan' ||
        (v['urgence'] == 'examen' && v['examenUrgent'] == a['code']);
    final d = <String, Object?>{
      'id': nouvelId('DEM'),
      'reference': demReferenceSuivante(existantes),
      'codeAnalyse': demCodeAnalyse(jour, existantes, maintenant: date),
      'patientId': p['id'],
      'patientCode': p['code'],
      'patient': nomComplet,
      'analyseCode': a['code'],
      'analyse': a['designation'],
      'categorie': a['categorie'],
      'echantillon': a['echantillon'],
      'delai': a['delai'],
      'prix': a['prix'],
      'dateHeure': jour,
      'prescripteur': patVrai(v['prescripteur']) ? v['prescripteur'] : 'Médecin extérieur',
      'laborantin': null,
      'urgent': urgent,
      'etatAnalyse': 'en_attente',
      'origine': patVrai(v['origineFiche']) ? v['origineFiche'] : 'accueil-externe',
      'origineDemande': patVrai(v['origineDemande']) ? v['origineDemande'] : 'externe',
      'serviceDemandeur': patVrai(v['serviceDemandeur']) ? v['serviceDemandeur'] : null,
      'secteurDemandeur': patVrai(v['secteurDemandeur']) ? v['secteurDemandeur'] : null,
      'indication': patVrai(v['indication']) ? v['indication'] : null,
      'hospitalise': patVrai(v['hospitalise']),
      'bloqueParPaiement': true,
      'statut': 'actif',
    };
    existantes.add(d);
    demandes.add(d);
  }

  // La facture, avec ses lignes payables (une par examen).
  final taux = patVrai(p['assureur']) ? nombreOuZero(p['tauxPriseEnCharge']) : 0.0;
  final estAgent = patVrai(p['personnelId']);
  final lignes = <FichePat>[];
  for (final (i, a) in analyses.indexed) {
    final brut = arrondiJs(nombreOuZero(a['prix'])).toInt();
    final partAssureur = estAgent ? 0 : arrondiJs(brut * taux / 100).toInt();
    final partPersonnel = estAgent ? brut : 0;
    lignes.add({
      'id': 'L${_pad(i + 1, 3)}',
      'categorie': 'analyse',
      'designation': a['designation'],
      'quantite': 1,
      'prixUnitaire': a['prix'],
      'prixUnitaireNet': brut,
      'montantBrut': brut,
      'remise': 0,
      'motifRemise': null,
      'montant': brut,
      'partAssureur': partAssureur,
      'partPersonnel': partPersonnel,
      'partPatient': brut - partAssureur - partPersonnel,
      'demandeId': demandes[i]['id'],
      'produitId': null,
      'acteCode': null,
      'demandeImagerieId': null,
      'statutPaiement': 'du',
      'montantRegle': 0,
      'payeLe': null,
      'payePar': null,
    });
  }
  num somme(String k) => lignes.fold<num>(0, (s, l) => s + (l[k] as num));
  final numero = 'FE-${date.year}-${_pad(nbFactures + 1, 5)}';
  final idFacture = nouvelId('FAC');
  final facture = <String, Object?>{
    'id': idFacture,
    'lignes': lignes,
    'numero': numero,
    'numeroMecef': null,
    'patientId': p['id'],
    'patient': nomComplet,
    'patientCode': p['code'],
    'date': iso(date),
    'type': 'Analyses — patient externe',
    'montantHT': somme('montant'),
    'montantTTC': somme('montant'),
    'montantBrut': somme('montantBrut'),
    'totalRemise': somme('remise'),
    'partPersonnel': somme('partPersonnel'),
    'priseEnChargePersonnel': estAgent,
    'personnelId': estAgent ? p['personnelId'] : null,
    'assureur': patVrai(p['assureur']) ? p['assureur'] : null,
    'tauxPriseEnCharge': taux,
    'partAssurance': somme('partAssureur'),
    'partPatient': somme('partPatient'),
    'montantPaye': 0,
    'reliquat': somme('partPatient'),
    'modePaiement': null,
    'statutPaiement': 'impayee',
    'statutMecef': 'en_attente',
    'origineDemande': 'externe',
    'prescripteurExterieur': patVrai(v['prescripteur']) ? v['prescripteur'] : null,
    'statut': 'actif',
  };
  for (final d in demandes) {
    d['factureId'] = idFacture;
    d['factureNumero'] = numero;
  }

  // La caisse est saisie, le prélèvement attend le règlement.
  final taches = <FichePat>[
    {
      'id': nouvelId('TCH'),
      'type': 'encaissement',
      'poste': 'caisse',
      'libelle': 'Patient externe — $nomComplet',
      'detail': '${nombre(analyses.length)} examen(s) — ${money(montant, avecDevise: false)}',
      'reference': numero,
      'factureId': idFacture,
      'patientId': p['id'],
      'patient': nomComplet,
      'montant': montant,
      'statut': 'en_attente',
      'creeLe': jour,
    },
    {
      'id': nouvelId('TCH'),
      'type': 'prelevement',
      'poste': 'laboratoire',
      'libelle': 'Patient externe — $nomComplet',
      'detail': '${nombre(analyses.length)} examen(s)',
      'reference': numero,
      'factureId': idFacture,
      'patientId': p['id'],
      'patient': nomComplet,
      'statut': 'bloque',
      'creeLe': jour,
    },
  ];
  return PatDemandeExterne(p, cree, demandes, facture, taches, montant);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le registre : verrous, états, vues
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `blocageResultat(d)` — RIEN NE SE SAISIT AVANT LA CAISSE. Le bouton reste VISIBLE et VERROUILLÉ et dit chez qui la balle se trouve.
({String motif, String suite})? patBlocageResultat(FichePat d) {
  if (patVrai(d['examenCode']) || patVrai(d['examen'])) {
    if (d['statut'] == 'demandee') {
      return (
        motif: 'Examen non réglé.',
        suite: 'Le patient doit passer à la CAISSE ; l’échographiste ne saisit qu’un examen payé.'
      );
    }
    return null;
  }
  if (patVrai(d['bloqueParPaiement'])) {
    return (
      motif: 'Analyse non réglée.',
      suite: 'Le patient doit passer à la CAISSE ; le biologiste ne saisit qu’un examen payé.'
    );
  }
  if (!patVrai(d['recuLaboLe'])) {
    return (
      motif: 'Échantillon non parvenu au laboratoire.',
      suite: 'Le prélèvement puis l’acheminement doivent précéder la saisie.'
    );
  }
  return null;
}

/// `ligneEtat(d)` : (libellé, ton). Le verrou a DEUX causes — la caisse, ou l'échantillon qui n'est pas parvenu (écart E309 : dire « en attente de
/// caisse » d'une analyse RÉGLÉE envoyait le patient payer deux fois).
(String, String) patEtatLigne(FichePat d) {
  final bloc = patBlocageResultat(d);
  if (bloc != null) {
    return (
      patVrai(d['examenCode']) || patVrai(d['bloqueParPaiement'])
          ? 'En attente de caisse'
          : 'Échantillon non parvenu',
      'warning'
    );
  }
  if (patVrai(d['examenCode'])) {
    if (d['statut'] == 'validee') return ('Compte rendu rendu', 'success');
    if (d['statut'] == 'executee') return ('Exécuté — CR à rendre', 'info');
    return ('À exécuter', 'info');
  }
  if (resultatRendu(d['etatAnalyse'] as String?)) return ('Résultat rendu', 'success');
  return ('À saisir', 'info');
}

bool patResultatRendu(FichePat d) => patVrai(d['examenCode'])
    ? d['statut'] == 'validee'
    : resultatRendu(d['etatAnalyse'] as String?);

List<FichePat> patDemandesExternes(Iterable<FichePat> analyses) => [
      for (final d in analyses)
        if (d['origineDemande'] == 'externe') d
    ];

/// Les demandes d'imagerie d'un patient venu de l'extérieur : la demande elle-même, ou le dossier du patient.
List<FichePat> patImagerieExterne(Iterable<FichePat> demandes, Iterable<FichePat> patients) => [
      for (final d in demandes)
        if (d['origine'] == 'externe' ||
            (patients.where((p) => p['id'] == d['patientId']).firstOrNull?['externe'] == true))
          d
    ];

/// `duService(rows, motif)` : l'ordonnance extérieure porte un service — vue des registres, jamais un second registre.
List<FichePat> patDuService(Iterable<FichePat> rows, RegExp motif) => [
      for (final d in rows)
        if (motif.hasMatch('${d['serviceDemandeur'] ?? ''} ${d['secteurDemandeur'] ?? ''}')) d
    ];

final patMotifMaternite = RegExp('maternit|obst|gyn', caseSensitive: false);
final patMotifHospitalisation = RegExp('hospit|soins|observation', caseSensitive: false);

class PatKpisExterne {
  const PatKpisExterne(this.demandes, this.enAttente, this.rendus, this.patients);
  final int demandes;
  final int enAttente;
  final int rendus;
  final int patients;
}

PatKpisExterne patKpisExterne(List<FichePat> dem) => PatKpisExterne(
    dem.length,
    dem.where((d) => patVrai(d['bloqueParPaiement'])).length,
    dem.where((d) => d['etatAnalyse'] == 'valide').length,
    {for (final d in dem) '${d['patientId']}'}.length);
