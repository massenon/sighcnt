/// MOBILE SOIGNANT : les règles que l'application `apps/mobile` applique AVANT d'écrire une opération (spec §11, ADR-0005).
///
/// Sources, une par règle, aucune devinée :
///  - les messages de saisie, les bornes, les listes de choix et les écrans ouverts par profil sont RELEVÉS sur les pages du simulateur
///    (`prototype_html/mobile/`, piloté dans Chrome : `test/vecteurs/mobile.json`, `mob_donnees.dart`) ;
///  - « prescription selon droits » rejoue `PR.peutPrescrire` de la maquette complète (`D.CAPACITES`, matrice dans le même vecteur) ;
///  - l'orientation et les quatre temps de l'examen sont ceux de la FICHE de consultation (`cs_referentiels.dart`), la copie des constantes de
///    l'accueil est celle de la fiche (`csCopieReleve`), RG-09 se lit par le moteur de la caisse (`carteValide`).
///
/// Un refus est NOMMÉ (code, motif, geste). Une commande interdite est ABSENTE : les fonctions `mobPeut…` servent à ne pas la dessiner,
/// les fonctions `mobControler…` refont le contrôle au moteur (un bouton absent ne protège rien).
library;

import '../caisse/prise_en_charge.dart' show carteValide;
import '../consultation/ag_commun.dart' show agDate, agIsoLocal, agJour, agVrai;
import '../consultation/cs_moteur.dart' show csCopieReleve;
import '../consultation/cs_referentiels.dart' show csLibelleOrientation, csOrientations, csTempsExamen;
import '../format/format_fr.dart' show dateFR, heure, iso;
import '../labo/res_saisie.dart' show agePatient;
import '../patients/pat_patients.dart' show patListe;
import '../patients/pat_releves.dart' show patAnormale;
import '../securite/sec_donnees.dart' show secDonnees;
import 'mob_donnees.dart';

/// Fiche d'une collection telle que le lot la livre (`data` du journal).
typedef MobFiche = Map<String, Object?>;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le refus nommé
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Un refus du mobile : un `code` stable, un `motif` lisible, un `geste` de correction ; `champs` porte les erreurs par champ d'un formulaire.
class RefusMobile implements Exception {
  const RefusMobile(this.code, this.motif, this.geste, {this.champs = const {}});
  final String code;
  final String motif;
  final String geste;
  final Map<String, String> champs;
  @override
  String toString() => '$code : $motif';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Fonction du soignant, écrans ouverts, droit de prescrire
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les fonctions que le profil « soignant » du mobile peut porter (celles du simulateur : médecin, sage-femme, infirmier ; l'aide-soignant lit
/// comme l'infirmier, sans exécuter ni prescrire : `D.CAPACITES`).
const mobFonctions = ['medecin', 'sage_femme', 'infirmier', 'aide_soignant'];

Map<String, Object?> get _capacites => (secDonnees['capacites'] as Map).cast<String, Object?>();

/// Le libellé de la fonction (`D.CAPACITES[f].label`), ou son code si elle est inconnue.
String mobLibelleFonction(String fonction) {
  final c = _capacites[fonction];
  return c is Map ? '${c['label']}' : fonction;
}

/// Le profil du SIMULATEUR qui porte cette fonction (le simulateur distingue trois profils cliniques).
String mobProfilSimulateur(String fonction) => switch (fonction) {
      'medecin' => 'medecin',
      'sage_femme' => 'sagefemme',
      _ => 'soignant',
    };

/// Les écrans que le simulateur ouvre à cette fonction.
List<String> mobEcransOuverts(String fonction) {
  final p = ((mobDonnees['profils'] as Map)[mobProfilSimulateur(fonction)] as Map);
  return [for (final e in (p['ecrans'] as List)) '$e'];
}

bool mobEcranOuvert(String fonction, String ecran) => mobEcransOuverts(fonction).contains(ecran);

/// `PR.peutPrescrire(nature, session)` : la capacité de la FONCTION, rien d'autre. Une fonction inconnue ne prescrit rien (ce qu'on ne sait pas
/// n'ouvre rien).
bool mobPeutPrescrire(String fonction, String nature) {
  final c = _capacites[fonction];
  if (c is! Map) return false;
  return ((c['prescrire'] as List?) ?? const []).contains(nature);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Fonction AUTHENTIFIÉE (E1600) : fixée par le code d'appairage de la mère, relue par la mère à chaque dépôt, jamais déclarée par le téléphone
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les profils que la console de la mère peut affecter à un mobile : « soignant » (agenda, dossier, notes, prescription) ou « reception »
/// (réception de secours, qui n'a PAS de fonction de soignant).
const mobProfils = ['soignant', 'reception'];

/// Le contrôle d'un code d'appairage de mobile, à l'émission par la console : refus NOMMÉ (code, motif, geste) ou `null` quand l'affectation est bonne.
/// Un soignant porte UNE des fonctions de [mobFonctions] ; la réception de secours n'en porte aucune.
RefusMobile? mobRefusAffectation(String profil, String fonction) {
  if (!mobProfils.contains(profil)) {
    return const RefusMobile('profil_requis', 'Choisir le profil du téléphone : soignant ou réception de secours.', 'Choisir un profil avant de générer le code');
  }
  if (profil == 'reception') {
    return fonction.isEmpty
        ? null
        : const RefusMobile('fonction_non_applicable', 'La réception de secours n’a pas de fonction de soignant.', 'Laisser la fonction vide pour ce profil');
  }
  if (!mobFonctions.contains(fonction)) {
    return RefusMobile('fonction_inconnue', 'Fonction « ${fonction.isEmpty ? 'vide' : fonction} » inconnue : choisir parmi ${mobFonctions.join(', ')}.', 'Choisir la fonction du soignant dans la liste');
  }
  return null;
}

/// Le contrôle de la fonction ÉCRITE sur une pièce par un mobile soignant, refait par la mère à chaque dépôt avec la fonction qu'ELLE a fixée à
/// l'appairage ([fixee], lue dans sa table des appareils). `null` : la pièce est recevable (une fonction non déclarée sur la pièce reçoit celle de
/// l'appareil). Deux refus nommés : appareil appairé avant la fixation (`fonction_non_fixee`) et valeur du téléphone différente (`fonction_falsifiee`).
RefusMobile? mobRefusFonctionPiece({required String? fixee, required String declaree}) {
  if (fixee == null || fixee.isEmpty) {
    return const RefusMobile(
        'fonction_non_fixee',
        'Cet appareil a été appairé avant que la clinique fixe la fonction du soignant : la mère ne peut pas vérifier son habilitation.',
        'Réappairer le téléphone avec un nouveau code émis par la console (Appareils)');
  }
  if (declaree.isNotEmpty && declaree != fixee) {
    return RefusMobile(
        'fonction_falsifiee',
        'Le téléphone déclare « $declaree » mais la clinique l’a appairé comme « $fixee » : la fonction est fixée à l’appairage et ne se change pas depuis le téléphone.',
        'Faire corriger la fonction par la console de la mère : nouveau code d’appairage (Appareils)');
  }
  return null;
}

/// Le secteur de la fonction (`D.CAPACITES[f].secteurs[0]`, ex. « MATERNITE » pour la sage-femme) : le secteur demandeur d'une prescription du mobile
/// commande la visibilité du résultat (RBAC métier). `null` : la fonction n'a pas de secteur propre.
String? mobSecteurFonction(String fonction) {
  final c = _capacites[fonction];
  final l = c is Map ? c['secteurs'] : null;
  return l is List && l.isNotEmpty ? '${l.first}' : null;
}

/// Le motif d'une prescription refusée à une fonction non habilitée : la formulation de la maquette (`PR.prescrireSoins` : « X n’est pas habilité à
/// prescrire. »), complétée de la nature refusée (la capacité se règle nature par nature, `D.CAPACITES`).
String mobMotifFonctionNonHabilitee(String fonction, String nature) => '${mobLibelleFonction(fonction)} n’est pas habilité à prescrire « ${mobLibelleNature(nature)} ».';

/// Les natures que le mobile sait prescrire, et l'écran qui les porte.
const mobNaturesMobile = {'medicament': 'prescription', 'analyse': 'demande-analyse'};

String mobLibelleNature(String nature) {
  for (final n in (secDonnees['naturesPrescription'] as List)) {
    if ((n as Map)['id'] == nature) return '${n['label']}';
  }
  return nature;
}

/// Les natures que la commande « prescrire » propose : la capacité de la fonction ET l'écran ouvert au profil (le plus restrictif des deux).
/// Vide = la commande est ABSENTE.
List<String> mobNaturesPrescriptibles(String fonction) => [
      for (final e in mobNaturesMobile.entries)
        if (mobPeutPrescrire(fonction, e.key) && mobEcranOuvert(fonction, e.value)) e.key
    ];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Saisie : les règles de `mobile.js` (valider)
// ---------------------------------------------------------------------------------------------------------------------------------------------

class MobRegle {
  const MobRegle(this.champ, this.libelle, {this.requis = false, this.min, this.max});
  final String champ;
  final String libelle;
  final bool requis;
  final num? min, max;
}

String _nombre(num n) => n == n.truncate() ? '${n.truncate()}' : '$n';

/// `Number(v.replace(',', '.'))` : la conversion de JavaScript (hexadécimal, exposant, signe, `Infinity` compris).
num? _nombreJs(String v) {
  final n = num.tryParse(v.replaceFirst(',', '.'));
  return (n == null || (n is double && n.isNaN)) ? null : n;
}

/// La conversion de JavaScript, publique : les écrans de la suite du mobile (CPN, CPoN, surveillance) lisent les mêmes nombres que `valider`.
num? mobNombreJs(String v) => _nombreJs(v);

/// `valider(regles)` du simulateur : requis → « X est obligatoire. » ; non numérique → « X doit être un nombre. » ; hors bornes → « X : valeur
/// improbable (a à b). ». Une valeur hors bornes est REFUSÉE EN LA NOMMANT. Rend les erreurs par champ (vide = tout est bon).
Map<String, String> mobValider(List<MobRegle> regles, Map<String, String> saisie) {
  final erreurs = <String, String>{};
  for (final r in regles) {
    final v = (saisie[r.champ] ?? '').trim();
    if (r.requis && v.isEmpty) {
      erreurs[r.champ] = '${r.libelle} est obligatoire.';
    } else if (v.isNotEmpty && r.min != null && r.max != null) {
      final n = _nombreJs(v);
      if (n == null) {
        erreurs[r.champ] = '${r.libelle} doit être un nombre.';
      } else if (n < r.min! || n > r.max!) {
        erreurs[r.champ] = '${r.libelle} : valeur improbable (${_nombre(r.min!)} à ${_nombre(r.max!)}).';
      }
    }
  }
  return erreurs;
}

/// Écran « Constantes » : la température est la seule obligatoire.
const mobReglesConstantes = [
  MobRegle('temperature', 'La température', requis: true, min: 30, max: 45),
  MobRegle('sys', 'La systolique', min: 50, max: 260),
  MobRegle('dia', 'La diastolique', min: 30, max: 160),
  MobRegle('pouls', 'Le pouls', min: 20, max: 250),
  MobRegle('fr', 'La FR', min: 5, max: 80),
  MobRegle('spo2', 'La SpO₂', min: 50, max: 100),
  MobRegle('poids', 'Le poids', min: 0.5, max: 300),
];

/// Écran « Consultation à domicile » : le motif est obligatoire (le diagnostic est un choix, il a toujours une valeur).
const mobReglesNote = [MobRegle('motif', 'Le motif', requis: true)];

/// Écran « Prescription ».
const mobReglesPrescription = [
  MobRegle('med', 'Le médicament', requis: true),
  MobRegle('poso', 'La posologie', requis: true),
  MobRegle('duree', 'La durée', requis: true, min: 1, max: 90),
];

/// Le choix « Autre » du diagnostic : il exige sa précision (la FICHE refuse un diagnostic vide : « Rédiger le diagnostic retenu. »).
const mobDiagnosticAutre = 'Autre (à préciser)';
const mobMessageDiagnosticVide = 'Rédiger le diagnostic retenu.';

RefusMobile _refusSaisie(Map<String, String> erreurs) => RefusMobile(
    'SAISIE_INVALIDE', erreurs.values.first, 'Corriger le champ indiqué', champs: erreurs);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Lot et patient
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le lot de la tournée a-t-il expiré ? `lotExpire` en millisecondes d'époque (0 ou null : aucun lot reçu).
bool mobLotExpire(int? lotExpire, DateTime maintenant) =>
    lotExpire != null && lotExpire > 0 && maintenant.millisecondsSinceEpoch >= lotExpire;

/// Toute écriture sur un dossier du lot est refusée une fois le lot expiré : on le DIT, avec la date et le geste.
void mobControlerLot(int? lotExpire, DateTime maintenant) {
  if (!mobLotExpire(lotExpire, maintenant)) return;
  final fin = DateTime.fromMillisecondsSinceEpoch(lotExpire!);
  throw RefusMobile(
      'LOT_EXPIRE',
      'Le lot de la tournée a expiré le ${dateFR(fin)} à ${heure(fin)}. Passé ce délai, les dossiers s’effacent du téléphone, sauf ce qui n’est pas encore parti.',
      'Se connecter pour recevoir le lot du jour');
}

String mobNomPatient(MobFiche p) => '${p['nom'] ?? ''} ${p['prenom'] ?? ''}'.trim();

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------------------------------------------------------------------------

Map<String, String> mobErreursConstantes(Map<String, String> saisie) => mobValider(mobReglesConstantes, saisie);

/// La fiche des constantes que le mobile écrit (collection `constantes`, famille B : une LIGNE de plus, jamais une modification). Mêmes champs que
/// le relevé de l'accueil du poste (`tensionSys`, `tensionDia`, `tension`, `fr`, `spo2`) : la mère les range avec les siens.
Map<String, Object?> mobChampsConstantes({
  required MobFiche patient,
  required String patientId,
  required Map<String, String> saisie,
  required String acteur,
  required DateTime maintenant,
}) {
  final erreurs = mobErreursConstantes(saisie);
  if (erreurs.isNotEmpty) throw _refusSaisie(erreurs);
  num? n(String k) {
    final v = (saisie[k] ?? '').trim();
    return v.isEmpty ? null : _nombreJs(v);
  }

  final sys = n('sys'), dia = n('dia');
  return {
    'patientId': patientId,
    'patientCode': patient['code'],
    'patient': mobNomPatient(patient),
    'dateHeure': agIsoLocal(maintenant),
    'temperature': n('temperature'),
    if (sys != null) 'tensionSys': sys,
    if (dia != null) 'tensionDia': dia,
    if (sys != null && dia != null) 'tension': '${_nombre(sys)}/${_nombre(dia)}',
    if (n('pouls') != null) 'pouls': n('pouls'),
    if (n('fr') != null) 'fr': n('fr'),
    if (n('spo2') != null) 'spo2': n('spo2'),
    if (n('poids') != null) 'poids': n('poids'),
    'releveePar': acteur,
    'origine': 'mobile',
  };
}

/// Une fièvre se signale avec la saisie (seuil du simulateur : 38 °C).
bool mobFievre(Map<String, String> saisie) {
  final t = _nombreJs((saisie['temperature'] ?? '').trim());
  return t != null && t >= 38;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Note de consultation (« fiche » du mobile)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les quatre temps de l'examen, dans l'ordre de la fiche : inspection, palpation, percussion, auscultation.
List<({String code, String libelle})> get mobTempsExamen => [
      for (final t in csTempsExamen) (code: '${t['code']}', libelle: '${t['label']}')
    ];

/// Les orientations de la fiche (codées : la mère les range avec celles du poste).
List<({String valeur, String libelle})> get mobOrientations => csOrientations;

List<String> get mobDiagnostics => [for (final d in (mobDonnees['diagnostics'] as List)) '$d'];

/// La dernière constante de ce patient (la plus récente par `dateHeure`, comme `dernierReleve`).
MobFiche? mobDernierReleve(Iterable<MobFiche> constantes, String patientId, Object? patientCode) {
  final l = [
    for (final r in constantes)
      if (r['patientId'] == patientId || (agVrai(patientCode) && r['patientCode'] == patientCode)) r
  ]..sort((a, b) => '${b['dateHeure'] ?? ''}'.compareTo('${a['dateHeure'] ?? ''}'));
  return l.firstOrNull;
}

/// La fiche de consultation à domicile. Les constantes relevées sont REPRISES (copie datée, `csCopieReleve`), jamais ressaisies.
/// `saisie` : motif, anamnese, inspection, palpation, percussion, auscultation, diagnostic, precision (si « Autre »), orientation.
Map<String, Object?> mobChampsNote({
  required MobFiche patient,
  required String patientId,
  required Map<String, String> saisie,
  required String acteur,
  required String fonction,
  required DateTime maintenant,
  Iterable<MobFiche> constantes = const [],
}) {
  final erreurs = mobValider(mobReglesNote, saisie);
  final diagnostic = (saisie['diagnostic'] ?? '').trim();
  final precision = (saisie['precision'] ?? '').trim();
  final retenu = diagnostic == mobDiagnosticAutre ? precision : diagnostic;
  if (retenu.isEmpty) erreurs['diagnostic'] = mobMessageDiagnosticVide;
  final orientation = (saisie['orientation'] ?? '').trim();
  if (orientation.isNotEmpty && !csOrientations.any((o) => o.valeur == orientation)) {
    erreurs['orientation'] = 'L’orientation « $orientation » n’est pas dans la liste de la fiche.';
  }
  if (erreurs.isNotEmpty) throw _refusSaisie(erreurs);
  final releve = csCopieReleve(mobDernierReleve(constantes, patientId, patient['code']));
  return {
    'patientId': patientId,
    'patientCode': patient['code'],
    'patient': mobNomPatient(patient),
    'date': agIsoLocal(maintenant),
    'type': 'Domicile',
    'motif': (saisie['motif'] ?? '').trim(),
    if ((saisie['anamnese'] ?? '').trim().isNotEmpty) 'anamnese': saisie['anamnese']!.trim(),
    'examenClinique': {
      for (final t in csTempsExamen)
        if ((saisie['${t['code']}'] ?? '').trim().isNotEmpty) '${t['code']}': saisie['${t['code']}']!.trim()
    },
    'diagnostic': retenu,
    if (orientation.isNotEmpty) 'orientation': orientation,
    if (orientation.isNotEmpty) 'orientationLabel': csLibelleOrientation(orientation),
    if (releve != null) 'constantesAccueil': releve,
    'redigePar': acteur,
    'fonction': fonction,
    'origine': 'mobile',
  };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Prescription
// ---------------------------------------------------------------------------------------------------------------------------------------------

List<String> get mobExamensAnalyses => [for (final e in ((mobDonnees['analyses'] as Map)['examens'] as List)) '$e'];
List<String> get mobUrgencesAnalyses => [for (final e in ((mobDonnees['analyses'] as Map)['urgences'] as List)) '$e'];

/// Une note de consultation de CE patient, écrite le jour même (jour local) : la prescription se fait après l'enregistrement de la fiche
/// (« Dossier → fiche → prescription »). Le jour même est une PROPOSITION : le simulateur dit « après l'enregistrement de la fiche », sans durée.
MobFiche? mobNoteDuJour(Iterable<MobFiche> notes, String patientId, DateTime maintenant) {
  final jour = iso(maintenant);
  final l = [
    for (final n in notes)
      if (n['patientId'] == patientId && agJour(n['date']) == jour) n
  ]..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
  return l.firstOrNull;
}

/// Le contrôle de la prescription, REFAIT au moteur (un bouton absent ne protège rien). Dans l'ordre : lot expiré, fonction habilitée, écran ouvert
/// au profil, note enregistrée. Lève un [RefusMobile] nommé ; ne rend rien quand tout est bon.
void mobControlerPrescription({
  required String fonction,
  required String nature,
  required String patientId,
  required Iterable<MobFiche> notes,
  required DateTime maintenant,
  int? lotExpire,
}) {
  mobControlerLot(lotExpire, maintenant);
  if (!mobNaturesMobile.containsKey(nature)) {
    throw RefusMobile('NATURE_NON_PORTEE', 'Le mobile ne prescrit pas « ${mobLibelleNature(nature)} ».', 'Prescrire depuis un poste de la clinique');
  }
  if (!mobPeutPrescrire(fonction, nature)) {
    throw RefusMobile('FONCTION_NON_HABILITEE', mobMotifFonctionNonHabilitee(fonction, nature), 'Demander la prescription à un médecin');
  }
  if (!mobEcranOuvert(fonction, mobNaturesMobile[nature]!)) {
    final profil = ((mobDonnees['profils'] as Map)[mobProfilSimulateur(fonction)] as Map)['label'];
    // Formulation du simulateur (`mobile.js`, écran fermé au profil), reprise telle quelle.
    throw RefusMobile(
        'ECRAN_FERME_AU_PROFIL',
        'Écran fermé au profil « $profil ». Ce profil ne couvre pas cette fonction ; la clinique le refuserait aussi côté serveur.',
        'Prescrire depuis un poste de la clinique');
  }
  if (mobNoteDuJour(notes, patientId, maintenant) == null) {
    throw const RefusMobile(
        'SANS_NOTE',
        'Aucune note de consultation du jour pour ce patient : la prescription se fait après l’enregistrement de la fiche (dossier, fiche, prescription).',
        'Enregistrer d’abord la note de consultation');
  }
}

/// Un médicament du CATALOGUE de la clinique, tel que le lot de la tournée le livre (collection `produits`). Le téléphone ne tape plus un nom : il
/// CHOISIT dans cette liste. Le prix d'achat est celui du catalogue, sans marge (RG-02) ; le stock est celui du jour du lot.
class MobProduit {
  const MobProduit({required this.id, required this.designation, required this.unite, required this.prixAchat, required this.stock});
  final String id, designation, unite;
  final num prixAchat;
  final num stock;
}

/// Les médicaments prescriptibles du lot : les mêmes catégories que le choix de médicaments de l'ordonnance du poste (`optionsMedicamentsCs` :
/// médicament et consommable médical), par ordre alphabétique. Les fiches archivées sont écartées.
List<MobProduit> mobProduitsPrescriptibles(Iterable<MobFiche> produits) {
  final l = [
    for (final p in produits)
      if ((p['categorie'] == 'medicament' || p['categorie'] == 'conso_medical') && p['statut'] != 'archive' && '${p['id'] ?? ''}'.isNotEmpty)
        MobProduit(
          id: '${p['id']}',
          designation: '${p['designation'] ?? p['id']}',
          unite: '${p['unite'] ?? ''}',
          prixAchat: p['prixAchat'] is num ? p['prixAchat'] as num : 0,
          stock: (p['stockDetail'] ?? p['stock']) is num ? (p['stockDetail'] ?? p['stock']) as num : 0,
        )
  ]..sort((a, b) => a.designation.compareTo(b.designation));
  return l;
}

/// Le message d'un stock insuffisant : celui du refus de la pharmacie à la maquette (code `STOCK_INSUFFISANT`, « Stock disponible : 4 ; demandé : 6 (RG-03). »).
String mobMotifStock(String designation, num dispo, num demande) =>
    'Stock insuffisant pour « $designation » : disponible : ${_nombre(dispo)} ; demandé : ${_nombre(demande)} (RG-03).';

/// Le geste du refus de stock, repris de la maquette.
const mobGesteStock = 'Corriger la quantité ou demander un transfert du gros.';

/// Les champs d'une ordonnance de médicaments (collection `prescriptions`, famille C : pièce ÉMISE, immuable ; une correction est une pièce de plus).
/// `saisie` : `med` = identifiant du produit CHOISI dans le catalogue du lot [produits], `quantite`, `poso`, `duree`. Le prix ne part pas dans la pièce : le
/// poste le lit au catalogue (RG-02). Refus nommés : produit hors catalogue (`PRODUIT_INCONNU`), stock insuffisant (`STOCK_INSUFFISANT`, RG-03).
Map<String, Object?> mobChampsOrdonnance({
  required MobFiche patient,
  required String patientId,
  required String noteId,
  required Map<String, String> saisie,
  required String acteur,
  required String fonction,
  required DateTime maintenant,
  required Iterable<MobFiche> produits,
}) {
  final erreurs = mobValider(mobReglesPrescription, saisie);
  final q = (saisie['quantite'] ?? '').trim();
  final quantite = q.isEmpty ? null : _nombreJs(q);
  if (q.isEmpty) {
    erreurs['quantite'] = 'La quantité est obligatoire.';
  } else if (quantite == null || quantite < 1 || quantite != quantite.truncate()) {
    erreurs['quantite'] = 'La quantité doit être un entier d’au moins 1.';
  }
  if (erreurs.isNotEmpty) throw _refusSaisie(erreurs);
  final catalogue = mobProduitsPrescriptibles(produits);
  final choisi = catalogue.where((x) => x.id == saisie['med']!.trim()).firstOrNull;
  if (choisi == null) {
    final m = 'Médicament absent du catalogue du lot : « ${saisie['med']!.trim()} ».';
    throw RefusMobile('PRODUIT_INCONNU', m, 'Choisir le médicament dans la liste du lot', champs: {'med': m});
  }
  if (quantite! > choisi.stock) {
    final m = mobMotifStock(choisi.designation, choisi.stock, quantite);
    throw RefusMobile('STOCK_INSUFFISANT', m, mobGesteStock, champs: {'quantite': m});
  }
  return {
    'nature': 'medicament',
    'patientId': patientId,
    'patientCode': patient['code'],
    'patient': mobNomPatient(patient),
    'date': agIsoLocal(maintenant),
    'noteId': noteId,
    'lignes': [
      {
        'produitId': choisi.id,
        'medicament': choisi.designation,
        'quantite': quantite.truncate(),
        'posologie': saisie['poso']!.trim(),
        'dureeJours': _nombreJs(saisie['duree']!.trim()),
      }
    ],
    'prescripteur': acteur,
    'fonction': fonction,
    'emise': true,
    'origine': 'mobile',
  };
}

/// Les champs d'une demande d'analyses : au moins un examen. Rien ne se prélève avant le paiement (le texte du simulateur le dit).
Map<String, Object?> mobChampsDemandeAnalyses({
  required MobFiche patient,
  required String patientId,
  required String noteId,
  required List<String> examens,
  required String urgence,
  required String acteur,
  required String fonction,
  required DateTime maintenant,
}) {
  if (examens.isEmpty) {
    final m = '${(mobDonnees['analyses'] as Map)['aucunExamen']}';
    throw RefusMobile('SAISIE_INVALIDE', m, 'Corriger le champ indiqué', champs: {'examens': m});
  }
  final inconnus = [for (final e in examens) if (!mobExamensAnalyses.contains(e)) e];
  if (inconnus.isNotEmpty) {
    throw RefusMobile('EXAMEN_INCONNU', 'Examen hors catalogue du mobile : ${inconnus.join(', ')}.', 'Choisir dans la liste');
  }
  final u = urgence.isEmpty ? mobUrgencesAnalyses.first : urgence;
  if (!mobUrgencesAnalyses.contains(u)) {
    throw RefusMobile('SAISIE_INVALIDE', 'Degré d’urgence inconnu : $u.', 'Choisir dans la liste', champs: {'urgence': 'Degré d’urgence inconnu : $u.'});
  }
  return {
    'nature': 'analyse',
    'patientId': patientId,
    'patientCode': patient['code'],
    'patient': mobNomPatient(patient),
    'date': agIsoLocal(maintenant),
    'noteId': noteId,
    'examens': examens,
    'urgence': u,
    'prescripteur': acteur,
    'fonction': fonction,
    'emise': true,
    'origine': 'mobile',
  };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Ce que devient la prescription au poste (E1559) : transcrite en ordonnance et facture, ou refusée en le disant
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le texte de l'écran de prescription AVANT la transcription. La phrase du simulateur (« Prescrire génère l'ordonnance et la facture de la caisse »)
/// n'est vraie qu'APRÈS la transcription par un poste : elle s'affiche au dossier quand le compte rendu est revenu, pas avant. PROPOSITION à valider.
const mobTexteEnvoiPrescription =
    'La prescription part à la clinique par le relais. L’ordonnance et la facture de la caisse sont générées quand le poste de la clinique la transcrit : le dossier vous le confirme, ou vous dit pourquoi elle est refusée.';

/// Où en est une prescription : `attente` (aucun compte rendu du poste), `transcrite` (ordonnance et facture existent), `refusee` (code, motif, geste).
enum MobEtatTranscription { attente, transcrite, refusee }

class MobTranscription {
  const MobTranscription(this.etat, {this.ordonnance, this.facture, this.montant, this.code, this.motif, this.geste});
  final MobEtatTranscription etat;
  final String? ordonnance, facture, code, motif, geste;
  final num? montant;

  /// La ligne affichée au dossier. Transcrite : la phrase de la maquette, VRAIE puisque l'ordonnance et la facture existent, avec leurs numéros.
  String get libelle => switch (etat) {
        MobEtatTranscription.attente => 'En attente de transcription par la clinique.',
        MobEtatTranscription.transcrite => 'Transcrite par la clinique : ordonnance ${ordonnance ?? ''}, facture ${facture ?? ''}.',
        MobEtatTranscription.refusee => 'Refusée par la clinique : ${motif ?? ''}',
      };
}

/// Le compte rendu de transcription d'une prescription (collection `transcriptions`, écrite par le poste, rendue par la mère au seul téléphone
/// émetteur). Le dernier compte rendu fait foi ; aucun compte rendu : la prescription attend.
MobTranscription mobTranscriptionDe(String prescriptionId, Iterable<MobFiche> transcriptions) {
  final l = [
    for (final t in transcriptions)
      if ('${t['prescriptionId']}' == prescriptionId) t
  ]..sort((a, b) => '${b['date'] ?? ''}'.compareTo('${a['date'] ?? ''}'));
  if (l.isEmpty) return const MobTranscription(MobEtatTranscription.attente);
  final t = l.first;
  return t['etat'] == 'transcrite'
      ? MobTranscription(MobEtatTranscription.transcrite,
          ordonnance: t['ordonnance'] == null ? null : '${t['ordonnance']}', facture: t['facture'] == null ? null : '${t['facture']}', montant: t['montant'] is num ? t['montant'] as num : null)
      : MobTranscription(MobEtatTranscription.refusee, code: '${t['code'] ?? ''}', motif: '${t['motif'] ?? ''}', geste: '${t['geste'] ?? ''}');
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Agenda du jour
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les rendez-vous du lot pour aujourd'hui (jour LOCAL, comme l'agenda du poste), du plus tôt au plus tard ; les rendez-vous PLANIFIÉS d'un jour
/// passé sont SIGNALÉS à part, jamais tranchés (le décider tout seul inventerait une absence : même règle que l'agenda du poste).
class MobAgenda {
  const MobAgenda(this.duJour, this.enSouffrance);
  final List<MobFiche> duJour;
  final List<MobFiche> enSouffrance;
}

MobAgenda mobAgendaDuJour(Iterable<MobFiche> rendezVous, DateTime maintenant) {
  final jour = iso(maintenant);
  final jourDe = <MobFiche, String>{};
  final auJour = <MobFiche>[], retard = <MobFiche>[];
  for (final r in rendezVous) {
    final j = agJour(r['date']);
    jourDe[r] = j;
    if (j == jour) {
      auJour.add(r);
    } else if (r['statut'] == 'planifiee' && j.compareTo(jour) < 0 && agDate(r['date']) != null) {
      retard.add(r);
    }
  }
  int parDate(MobFiche a, MobFiche b) => agDate(a['date'])!.compareTo(agDate(b['date'])!);
  auJour.sort(parDate);
  retard.sort(parDate);
  return MobAgenda(auJour, retard);
}

/// L'heure d'un rendez-vous, « 09h30 » (heure locale), 
String mobHeureRendezVous(MobFiche r) {
  final d = agDate(r['date']);
  return d == null ? '' : heure(d);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Dossier en lecture
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les trois états de la couverture au bandeau du dossier (RG-09 se lit À LA DATE, par le moteur de la caisse).
enum MobCouverture { carteValide, carteNonValide, nonAssure }

const mobLibellesCouverture = {
  MobCouverture.carteValide: 'Carte valide',
  MobCouverture.carteNonValide: 'CARTE NON VALIDE',
  MobCouverture.nonAssure: 'Non assuré',
};

/// Le texte qui accompagne une carte non valide : la facturation sera intégrale au patient.
const mobExplicationCarteNonValide = 'La prise en charge ne s’applique pas : facturation intégrale au patient (RG-09).';

MobCouverture mobCouvertureDe(MobFiche patient, DateTime maintenant) {
  if (!agVrai(patient['assureur'])) return MobCouverture.nonAssure;
  return carteValide(patient, const [], iso(maintenant)) ? MobCouverture.carteValide : MobCouverture.carteNonValide;
}

class MobDossier {
  const MobDossier({
    required this.nom,
    required this.code,
    required this.age,
    required this.quartier,
    required this.telephone,
    required this.couverture,
    required this.allergies,
    required this.dernierReleve,
    required this.horsBornes,
    required this.notes,
    required this.prescriptions,
  });
  final String nom, code;
  final int? age;
  final String? quartier, telephone;
  final MobCouverture couverture;

  /// Vide = « Aucune connue. »
  final List<String> allergies;
  final MobFiche? dernierReleve;

  /// Les mesures hors des bornes de la feuille de température (`patAnormale`) : le logiciel signale, il ne diagnostique pas.
  final List<String> horsBornes;
  final List<MobFiche> notes, prescriptions;
}

/// Le dossier d'un patient du lot, en LECTURE. Notes et prescriptions : les plus récentes en tête.
MobDossier mobDossier({
  required MobFiche patient,
  required String patientId,
  required DateTime maintenant,
  Iterable<MobFiche> constantes = const [],
  Iterable<MobFiche> notes = const [],
  Iterable<MobFiche> prescriptions = const [],
}) {
  List<MobFiche> siens(Iterable<MobFiche> l) => [
        for (final x in l)
          if (x['patientId'] == patientId) x
      ]..sort((a, b) => '${b['date'] ?? b['dateHeure'] ?? ''}'.compareTo('${a['date'] ?? a['dateHeure'] ?? ''}'));
  final releve = mobDernierReleve(constantes, patientId, patient['code']);
  final age = agePatient({...patient, if (!agVrai(patient['age']) && agVrai(patient['ageDeclare'])) 'age': patient['ageDeclare']}, maintenant);
  return MobDossier(
    nom: mobNomPatient(patient),
    code: '${patient['code'] ?? 'en attente de numéro'}',
    age: age,
    quartier: agVrai(patient['quartier']) ? '${patient['quartier']}' : null,
    telephone: agVrai(patient['telephone']) ? '${patient['telephone']}' : null,
    couverture: mobCouvertureDe(patient, maintenant),
    allergies: patListe(patient['allergies']),
    dernierReleve: releve,
    horsBornes: releve == null ? const [] : patAnormale(releve),
    notes: siens(notes),
    prescriptions: siens(prescriptions),
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Textes relevés sur les écrans du simulateur
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Un texte de `mob_donnees.dart` (consultation, prescription, analyses, lot, allergiesAucune, constantesAucune, carteNonValide).
String mobTexte(String cle) => '${(mobDonnees['textes'] as Map)[cle]}';

/// Le libellé d'un écran du simulateur (« Consultation à domicile », « Dossier du patient »…).
String mobLibelleEcran(String id) => '${(mobDonnees['libellesEcrans'] as Map)[id] ?? id}';
