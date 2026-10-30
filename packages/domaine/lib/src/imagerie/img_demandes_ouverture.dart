/// OUVERTURE D'UNE DEMANDE D'IMAGERIE ET RESTITUTION DU COMPTE RENDU — port de `PR.ouvrirDemandeImagerie` (`parcours.js`) et de `rendreCR`
/// (`m2-consultations.js`), rejoués sur les vecteurs des écrans réels (`test/vecteurs/img_demandes.json`).
///
/// La demande naît BLOQUÉE par le paiement : c'est l'encaissement de SA ligne qui la rend exécutable (la ligne payable porte
/// `demandeImagerieId`). Un examen sans tarif est REFUSÉ en le nommant — un tiret n'est pas un zéro. RG-09 : la part de l'assureur ne se calcule
/// que si la carte est valide à la date (écart E101 de la maquette, corrigé avant ce port).
///
/// Pas de magasin ici : la fonction rend les fiches à écrire, l'appelant les insère (et peut les ARCHIVER en cas de refus — RG-14).
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import '../referentiels/regles.dart';
import '../caisse/prise_en_charge.dart' show carteValide;
import 'img_demandes_etats.dart';
import 'img_demandes_poste.dart' show FicheImg;


/// Refus NOMMÉ : [message] s'affiche tel quel. En cas de refus de tarif, les demandes déjà créées sont rendues [archivees] : la maquette les
/// écrit puis les archive (le numéro de série qu'elles ont consommé ne se réutilise pas).
class RefusImagerie implements Exception {
  const RefusImagerie(this.message, [this.archivees = const []]);
  final String message;
  final List<FicheImg> archivees;
  @override
  String toString() => message;
}

/// Le prix d'un examen : `montant == null` = tarif absent du catalogue ; [motif] explique une substitution (acte non couvert…).
class PrixImagerie {
  const PrixImagerie(this.montant, [this.motif]);
  final num? montant;
  final String? motif;
}

/// Ce que l'ouverture écrit.
class OuvertureImagerie {
  OuvertureImagerie(
      {required this.patient,
      required this.dossierCree,
      required this.demandes,
      required this.facture,
      required this.tacheEncaissement,
      required this.tacheExamen,
      required this.notification});

  /// La fiche patient utilisée ; si [dossierCree], elle est à INSÉRER (patient adressé de l'extérieur).
  final FicheImg patient;
  final bool dossierCree;
  final List<FicheImg> demandes;
  final FicheImg facture;
  final FicheImg tacheEncaissement;
  final FicheImg tacheExamen;
  final FicheImg notification;
}

bool _vrai(Object? v) => v != null && v != '' && v != 0 && v != false;
String _pad(int n, int l) => n.toString().padLeft(l, '0');

/// Référence suivante d'une série, lue sur les fiches EXISTANTES (archivées comprises) — jamais sur un compteur de page (écart E100).
String referenceSerie(String prefixe, int largeur, Iterable<FicheImg> fiches) {
  var max = 0;
  for (final f in fiches) {
    final r = '${f['reference'] ?? ''}';
    if (r.startsWith(prefixe)) {
      max = [max, int.tryParse(r.substring(prefixe.length)) ?? 0]
          .reduce((a, b) => a > b ? a : b);
    }
  }
  return '$prefixe${_pad(max + 1, largeur)}';
}

/// `PR.ouvrirDemandeImagerie(v)`.
///  · [examens] : codes cochés ; [catalogue] : `examensImagerie` ; [prixDe] : `D.tarifPrix(code, assure)` (le tarif vit au catalogue tarifaire).
///  · [patientId] : un patient du répertoire (cherché dans [patients], archivés compris) ; sinon l'identité [nom]/[prenom]… ouvre un dossier
///    externe, dont le code est `CNT/(900 + nombre de dossiers)/AA`.
///  · [date] : horodatage ISO de la demande ; [maintenant] : celui de la notification ; [nouvelId] attribue les identifiants.
OuvertureImagerie ouvrirDemandeImagerie({
  required List<String> examens,
  required Iterable<FicheImg> catalogue,
  required Iterable<FicheImg> patients,
  required Iterable<FicheImg> couvertures,
  required Iterable<FicheImg> demandesExistantes,
  required int nbFactures,
  required PrixImagerie Function(String code, bool assure) prixDe,
  required String Function(String prefixe) nouvelId,
  required String date,
  required String maintenant,
  String? patientId,
  String? nom,
  String? prenom,
  String? sexe,
  String? dateNaissance,
  Object? age,
  String? telephone,
  String? residence,
  String? prescripteur,
  String? indication,
  bool urgent = false,
  String? secteurDemandeur,
  String origine = 'consultation',
}) {
  if (examens.isEmpty) {
    throw const RefusImagerie('Cocher au moins un examen d’imagerie.');
  }
  final d = DateTime.parse(date).toLocal();

  // --- Le dossier : du répertoire, ou adressé de l'extérieur (fabrique unique `dossierExterne`). ---
  FicheImg patient;
  var cree = false;
  if (_vrai(patientId)) {
    final existant = patients.where((p) => p['id'] == patientId).firstOrNull;
    if (existant == null) {
      throw const RefusImagerie('Patient introuvable au répertoire.');
    }
    patient = existant;
  } else {
    if ((nom ?? '').trim().isEmpty || (prenom ?? '').trim().isEmpty) {
      throw const RefusImagerie('Nom et prénoms du patient obligatoires.');
    }
    final declare = !_vrai(dateNaissance) && _vrai(age);
    patient = {
      'id': nouvelId('PAT'),
      'code': codePatient(900 + patients.length, d.year),
      'nom': nom!.toUpperCase(),
      'prenom': prenom,
      'sexe': _vrai(sexe) ? sexe : 'M',
      'dateNaissance': _vrai(dateNaissance) ? dateNaissance : null,
      'age': declare ? age : null,
      'ageReferenceLe': declare ? iso(d) : null,
      'telephone': _vrai(telephone) ? telephone : null,
      'adresse': _vrai(residence) ? residence : null,
      'quartier': _vrai(residence) ? residence : null,
      'dateCreation': iso(d),
      'externe': true,
      'origineDossier': 'Patient externe — imagerie',
      'prescripteurExterieur': _vrai(prescripteur) ? prescripteur : null,
      'assure': false,
      'assureur': null,
      'tauxPriseEnCharge': 0,
      'statut': 'actif',
    };
    cree = true;
  }
  final nomComplet = '${patient['nom']} ${patient['prenom']}';

  // --- Les demandes : RG-09 décide du tarif ; un examen sans prix est refusé en le nommant. ---
  final assure = carteValide(patient, [for (final c in couvertures) c], date);
  final existantes = [...demandesExistantes];
  final demandes = <FicheImg>[];
  for (final code in examens) {
    final ex = catalogue
        .where((x) => x['statut'] != 'archive' && x['code'] == code)
        .firstOrNull;
    final pr = prixDe(code, assure);
    final demande = <String, Object?>{
      'id': nouvelId('IME'),
      'reference': referenceSerie('IME-', 5, existantes),
      'dateHeure': date,
      'patientId': patient['id'],
      'patientCode': patient['code'],
      'patient': nomComplet,
      'examenCode': code,
      'examen': ex != null ? '${ex['label']}' : code,
      'modalite': modaliteDeExamen(catalogue, code),
      'prescripteur': _vrai(prescripteur) ? prescripteur : '—',
      'indication': _vrai(indication) ? indication : '',
      'urgent': urgent,
      'secteurDemandeur': _vrai(secteurDemandeur) ? secteurDemandeur : null,
      'origine': origine,
      'ordonnanceId': null,
      'ordonnanceNumero': null,
      'dossierConsultationId': null,
      'prix': pr.montant,
      'motifTarif': pr.motif,
      'statut': 'demandee',
      'bloqueParPaiement': true,
    };
    existantes.add(demande);
    demandes.add(demande);
  }
  final sansPrix = demandes.where((x) => x['prix'] == null).toList();
  if (sansPrix.isNotEmpty) {
    throw RefusImagerie(
        'Tarif non renseigné pour : ${sansPrix.map((x) => x['examen']).join(', ')}. Le renseigner au référentiel tarifaire avant de facturer.',
        [for (final x in demandes) {...x, 'statut': 'archive'}]);
  }

  // --- La pièce : une ligne payable par examen, répartition au taux du dossier (RG-09) ou 100 % clinique pour un agent. ---
  final estAgent = _vrai(patient['personnelId']);
  final taux = (_vrai(patient['assureur']) && assure)
      ? nombreOuZero(patient['tauxPriseEnCharge'])
      : 0.0;
  final lignes = <FicheImg>[];
  for (final (i, x) in demandes.indexed) {
    final brut = arrondiJs(nombreOuZero(x['prix']));
    final partAssureur = estAgent ? 0 : arrondiJs(brut * taux / 100);
    final partPersonnel = estAgent ? brut : 0;
    lignes.add({
      'id': 'L${_pad(i + 1, 3)}',
      'categorie': 'imagerie',
      'designation': x['examen'],
      'quantite': 1,
      'prixUnitaire': x['prix'],
      'prixUnitaireNet': brut,
      'montantBrut': brut,
      'remise': 0,
      'motifRemise': null,
      'montant': brut,
      'partAssureur': partAssureur,
      'partPersonnel': partPersonnel,
      'partPatient': brut - partAssureur - partPersonnel,
      'demandeId': null,
      'produitId': null,
      'acteCode': null,
      'demandeImagerieId': x['id'],
      'statutPaiement': 'du',
      'montantRegle': 0,
      'payeLe': null,
      'payePar': null,
    });
  }
  num somme(String k) => lignes.fold<num>(0, (a, l) => a + (l[k] as num));
  final numero = 'FI-${d.year}-${_pad(nbFactures + 1, 5)}';
  final facture = <String, Object?>{
    'id': nouvelId('FAC'),
    'lignes': lignes,
    'numero': numero,
    'numeroMecef': null,
    'patientId': patient['id'],
    'patient': nomComplet,
    'patientCode': patient['code'],
    'date': iso(d),
    'type': 'Imagerie',
    'montantHT': somme('montant'),
    'montantTTC': somme('montant'),
    'montantBrut': somme('montantBrut'),
    'totalRemise': somme('remise'),
    'partPersonnel': somme('partPersonnel'),
    'priseEnChargePersonnel': estAgent,
    'personnelId': estAgent ? patient['personnelId'] : null,
    'assureur': _vrai(patient['assureur']) ? patient['assureur'] : null,
    'tauxPriseEnCharge': taux,
    'partAssurance': somme('partAssureur'),
    'partPatient': somme('partPatient'),
    'montantPaye': 0,
    'reliquat': somme('partPatient'),
    'modePaiement': null,
    'statutPaiement': 'impayee',
    'statutMecef': 'en_attente',
    'statut': 'actif',
  };
  for (final x in demandes) {
    x['factureId'] = facture['id'];
    x['factureNumero'] = numero;
  }

  // --- Les postes informés : la caisse encaisse, le poste d'imagerie attend (tâche BLOQUÉE jusqu'au règlement). ---
  final liste = demandes.map((x) => x['examen']).join(', ');
  final encaissement = <String, Object?>{
    'id': nouvelId('TCH'),
    'type': 'encaissement',
    'poste': 'caisse',
    'libelle': 'Imagerie — $nomComplet',
    'detail':
        '${demandes.length} examen(s) — ${money(facture['montantTTC'], avecDevise: false)}',
    'reference': numero,
    'factureId': facture['id'],
    'patientId': patient['id'],
    'patient': nomComplet,
    'montant': facture['montantTTC'],
    'statut': 'en_attente',
    'creeLe': date,
  };
  final examen = <String, Object?>{
    'id': nouvelId('TCH'),
    'type': 'imagerie',
    'poste': 'imagerie',
    'libelle': 'Examen d’imagerie — $nomComplet',
    'detail': liste,
    'reference': numero,
    'factureId': facture['id'],
    'patientId': patient['id'],
    'patient': nomComplet,
    'statut': 'bloque',
    'creeLe': date,
  };
  final notification = <String, Object?>{
    'id': nouvelId('NOT'),
    'type': 'demande_imagerie',
    'poste': 'imagerie',
    'destinataire': null,
    'libelle': 'Nouvelle demande d’imagerie — $nomComplet',
    'detail': '$liste — exécutable après passage en caisse',
    'priorite': urgent ? 'haute' : 'normale',
    'demandeId': null,
    'factureId': null,
    'ordonnanceId': null,
    'patientId': patient['id'],
    'reference': numero,
    'lue': false,
    'creeLe': maintenant,
    'statut': 'actif',
  };
  return OuvertureImagerie(
      patient: patient,
      dossierCree: cree,
      demandes: demandes,
      facture: facture,
      tacheEncaissement: encaissement,
      tacheExamen: examen,
      notification: notification);
}

/// `crDeDemande(dem)` : le compte rendu d'une demande, s'il existe (le premier non archivé qui la désigne).
FicheImg? compteRenduDeDemande(FicheImg demande, Iterable<FicheImg> comptesRendus) =>
    comptesRendus
        .where((r) =>
            r['statut'] != 'archive' && r['demandeImagerieId'] == demande['id'])
        .firstOrNull;

/// Ce que « Rendre » écrit : les deux mises à jour et la notification au poste du prescripteur.
class RenduImagerie {
  RenduImagerie(this.patchCompteRendu, this.patchDemande, this.notification);
  final FicheImg patchCompteRendu;

  /// `null` quand le compte rendu est saisi hors demande (voie « manuelle » du poste).
  final FicheImg? patchDemande;
  final FicheImg notification;
}

/// `rendreCR(r)` : la conclusion est obligatoire avant de rendre. Une correction ultérieure devra être signalée comme telle.
RenduImagerie rendreCompteRendu(FicheImg cr, {required String maintenant}) {
  if (!_vrai(cr['conclusion'])) {
    throw const RefusImagerie(
        'La conclusion est obligatoire avant de rendre le compte rendu.');
  }
  return RenduImagerie(
    {'statut': 'rendu', 'renduLe': maintenant},
    _vrai(cr['demandeImagerieId'])
        ? {'statut': 'validee', 'valideLe': maintenant}
        : null,
    {
      'type': 'imagerie_rendue',
      'poste': 'consultation',
      'destinataire': null,
      'libelle': 'Compte rendu d’imagerie rendu — ${cr['patient']}',
      'detail':
          '${cr['examen']} — ${cr['reference']} — prescripteur ${cr['prescripteur']}',
      'priorite': 'normale',
      'demandeId': null,
      'factureId': null,
      'ordonnanceId': null,
      'patientId': cr['patientId'],
      'reference': cr['reference'],
      'lue': false,
      'creeLe': maintenant,
      'statut': 'actif',
    },
  );
}

/// La valeur de la liste « Prescripteur » qui désigne un prescripteur du DEHORS (`K.champsPrescripteur`).
const prescripteurExterneImagerie = 'EXTERNE';

/// `K.nomPrescripteur(v, null, 'prescripteur')` : le nom à porter sur la demande. Pour un prescripteur extérieur, c'est le champ libre
/// (nom, qualification, structure) — il permet de lui RENVOYER le compte rendu ; sans lui, « Prescripteur extérieur ».
String? nomPrescripteurImagerie(Object? choix, Object? libre) {
  if ('${choix ?? ''}' == prescripteurExterneImagerie) {
    final l = '${libre ?? ''}'.trim();
    return l.isNotEmpty ? '$l (extérieur)' : 'Prescripteur extérieur';
  }
  return choix == null ? null : '$choix';
}

/// Le message (et son détail) du toast d'une demande émise.
({String message, String detail}) messageDemandeEmise(
        {required int examens, required String facture, String? dossier}) =>
    (
      message: 'Demande émise — $examens examen(s).',
      detail:
          'Facture $facture à la caisse ; l’examen sera exécutable après règlement.${dossier == null ? '' : ' Dossier ouvert : $dossier.'}'
    );

/// Le refus de la modale quand ni un patient du répertoire ni l'identité d'un patient adressé de l'extérieur n'est renseigné.
const refusIdentiteImagerie =
    'Sélectionner un patient du répertoire, ou renseigner le nom et les prénoms du patient adressé de l’extérieur.';
