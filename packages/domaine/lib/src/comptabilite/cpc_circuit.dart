// LE CIRCUIT DE CLÔTURE ANNUELLE (PRD M12 clôture annuelle, réponses de la Direction du 11/11/2026 Q1 et Q2 ; lot CLO C1) : qui démarre, qui passe l'inventaire en clôture, qui clôture
// définitivement, qui rouvre, et à partir de quel mois l'exercice suivant s'ouvre. AUCUN nom de rôle n'est écrit dans le domaine : les listes se LISENT dans les paramètres du poste
// (registre `definitionsParametres`, famille `exercice`, défauts SEMÉS identiques à la maquette, versionnés par date, réglage de BRANCHE : la mère écrit, les fileuls lisent, jamais
// un mobile). Un refus nomme la liste LUE, jamais une liste recopiée dans la phrase.
//
// Les messages sont ceux de la maquette (`SIGH.exercice`, vecteurs de `vecteurs-m12-exercice.js`) : « <geste> : action réservée à : A, B ou C. ».

/// Les clés du registre des paramètres (une seule source : `definitions.dart` les déclare avec leur défaut semé).
const String cpcCleDemarrer = 'exercice.circuit.demarrer';
const String cpcCleInventaire = 'exercice.circuit.inventaire';
const String cpcCleCloturer = 'exercice.circuit.cloturer';
const String cpcCleRouvrir = 'exercice.circuit.rouvrir';
const String cpcCleMoisOuverture = 'exercice.ouverture.mois';
const String cpcCleDelaiPostes = 'exercice.postes.delaiEtatInconnuHeures';

/// Les libellés des cinq réglages (une seule source : le registre des paramètres et les refus nommés les lisent ici ; ce sont ceux de la maquette).
const String cpcLibelleDemarrer = 'Qui démarre la clôture (ou reprend la saisie)';
const String cpcLibelleInventaire = 'Qui passe les écritures d’inventaire en clôture';
const String cpcLibelleCloturer = 'Qui clôture définitivement';
const String cpcLibelleRouvrir = 'Qui rouvre un exercice clôturé';
const String cpcLibelleMoisOuverture = 'Mois à partir duquel l’exercice suivant s’ouvre';
const String cpcLibelleDelaiPostes = 'Délai sans contact au-delà duquel l’état d’un poste est inconnu (heures)';
const Map<String, String> cpcLibellesReglage = {
  cpcCleDemarrer: cpcLibelleDemarrer,
  cpcCleInventaire: cpcLibelleInventaire,
  cpcCleCloturer: cpcLibelleCloturer,
  cpcCleRouvrir: cpcLibelleRouvrir,
  cpcCleMoisOuverture: cpcLibelleMoisOuverture,
  cpcCleDelaiPostes: cpcLibelleDelaiPostes,
};

/// Le geste réservé de la fiche RBAC qui règle le circuit (déclaré au manifeste de la maquette, `N.GESTES`).
const String cpcGesteRegler = 'regler_circuit_cloture';

/// Le geste de correction cité par chaque refus de rôle.
const String cpcGesteCircuit = 'Demander à l’un de ces rôles, ou faire modifier le circuit (écran « Exercices & clôtures », onglet « Circuit de clôture »).';

/// Une liste de rôles lue d'un paramètre texte (identifiants séparés par des virgules), sans doublon, dans l'ordre.
List<String> cpcListeRoles(Object? v) {
  final out = <String>[];
  for (final p in '${v ?? ''}'.split(',')) {
    final r = p.trim();
    if (r.isNotEmpty && !out.contains(r)) out.add(r);
  }
  return out;
}

class CpcCircuit {
  const CpcCircuit({required this.demarrer, required this.inventaire, required this.cloturer, required this.rouvrir, this.moisOuvertureSuivant = 12, this.delaiEtatPosteHeures = 24, this.libelles = const {}});

  /// Lit le circuit par une fonction qui rend la valeur en vigueur d'un paramètre (le poste : `ServiceParametres.valeur(cle, aujourdhui)`).
  factory CpcCircuit.lire(Object? Function(String cle) valeur, {Map<String, String> libelles = const {}}) {
    final mois = valeur(cpcCleMoisOuverture);
    final delai = valeur(cpcCleDelaiPostes);
    return CpcCircuit(
        demarrer: cpcListeRoles(valeur(cpcCleDemarrer)),
        inventaire: cpcListeRoles(valeur(cpcCleInventaire)),
        cloturer: cpcListeRoles(valeur(cpcCleCloturer)),
        rouvrir: cpcListeRoles(valeur(cpcCleRouvrir)),
        moisOuvertureSuivant: mois is num && mois >= 1 && mois <= 12 ? mois.toInt() : 12,
        delaiEtatPosteHeures: delai is num && delai >= 1 ? delai.toInt() : 24,
        libelles: libelles);
  }

  final List<String> demarrer, inventaire, cloturer, rouvrir;
  final int moisOuvertureSuivant;

  /// Au-delà de ce délai sans contact, l'état d'un poste est INCONNU (défaut semé : 24 heures, lot CLO-2).
  final int delaiEtatPosteHeures;

  /// Identifiant de rôle vers libellé (la matrice des rôles) : sans libellé, l'identifiant.
  final Map<String, String> libelles;

  /// « A, B ou C » (un seul : « A » ; aucun : « aucun rôle »).
  String noms(List<String> roles) {
    final n = [for (final r in roles) libelles[r] ?? r];
    if (n.isEmpty) return 'aucun rôle';
    return n.length > 1 ? '${n.sublist(0, n.length - 1).join(', ')} ou ${n.last}' : n.first;
  }

  /// Le refus nommé d'un rôle absent de la liste lue, ou `null` s'il y figure. Une liste vide n'est PAS arrêtée : rien n'est supposé.
  CpcRefusCircuit? refus(List<String> liste, String role, {required String code, required String quoi}) {
    if (liste.isEmpty) {
      return CpcRefusCircuit('CIRCUIT_SANS_VERSION', 'Aucune version du réglage du circuit de clôture ne couvre ce jour : la liste n’est pas arrêtée, rien n’est supposé.',
          'Ajouter une version à l’écran « Exercices & clôtures », onglet « Circuit de clôture ».');
    }
    if (liste.contains(role)) return null;
    return CpcRefusCircuit(code, '$quoi : action réservée à : ${noms(liste)}.', cpcGesteCircuit);
  }

  bool peutDemarrer(String role) => demarrer.contains(role);
  bool peutInventaire(String role) => inventaire.contains(role);
  bool peutCloturer(String role) => cloturer.contains(role);
  bool peutRouvrir(String role) => rouvrir.contains(role);
}

class CpcRefusCircuit {
  const CpcRefusCircuit(this.code, this.motif, this.geste);
  final String code, motif, geste;
}

/// Le contrôle d'un RÉGLAGE du circuit (même verdict que `SIGH.exercice.definirCircuit` de la maquette) : `null` s'il est recevable, sinon le refus nommé.
/// [clesRolesConnus] : les rôles de la matrice, non archivés. [gesteAccorde] : le rôle de la session détient le geste réservé [cpcGesteRegler]. [motif] : au moins trois caractères.
CpcRefusCircuit? cpcControleReglageCircuit(
    {required String cle, required Object? valeur, required bool gesteAccorde, required String libelleRole, required String? motif, required Set<String> rolesConnus}) {
  final roles = (cle == cpcCleMoisOuverture || cle == cpcCleDelaiPostes) ? null : cpcListeRoles(valeur);
  if (!const [cpcCleDemarrer, cpcCleInventaire, cpcCleCloturer, cpcCleRouvrir, cpcCleMoisOuverture, cpcCleDelaiPostes].contains(cle)) {
    return CpcRefusCircuit('CIRCUIT_REGLAGE_INCONNU', 'Le réglage « $cle » n’existe pas parmi ceux de la clôture annuelle.',
        'Choisir un réglage listé à l’écran « Exercices & clôtures », onglet « Circuit de clôture ».');
  }
  if (!gesteAccorde) {
    return CpcRefusCircuit('CIRCUIT_REGLAGE_RESERVE', 'Régler le circuit de la clôture annuelle est un droit réservé de la fiche du rôle : « $libelleRole » ne l’a pas.',
        'Demander à un rôle qui détient le droit « Régler le circuit de la clôture annuelle » (matrice des droits).');
  }
  if ((motif ?? '').trim().length < 3) {
    return const CpcRefusCircuit('CIRCUIT_MOTIF_OBLIGATOIRE', 'Un motif est obligatoire pour changer le circuit de clôture.', 'Saisir le motif du changement.');
  }
  if (roles != null) {
    if (roles.isEmpty) {
      return CpcRefusCircuit('CIRCUIT_LISTE_VIDE', 'La liste « ${cpcLibellesReglage[cle]} » ne peut pas être vide : personne ne pourrait accomplir le geste.', 'Choisir au moins un rôle.');
    }
    final inconnus = [for (final r in roles) if (!rolesConnus.contains(r)) r];
    if (inconnus.isNotEmpty) {
      return CpcRefusCircuit('CIRCUIT_ROLE_INCONNU', 'Rôle inconnu ou archivé : ${inconnus.join(', ')}.', 'Choisir des rôles de la matrice des droits.');
    }
  } else {
    final n = valeur is num ? valeur : num.tryParse('${valeur ?? ''}');
    if (cle == cpcCleDelaiPostes) {
      if (n == null || n < 1 || n != n.truncate()) {
        return CpcRefusCircuit('CIRCUIT_DELAI_INVALIDE', 'Le délai est un nombre entier d’heures, au moins 1 (reçu « ${valeur ?? ''} »).', 'Saisir un nombre d’heures.');
      }
      return null;
    }
    if (n == null || n < 1 || n > 12 || n != n.truncate()) {
      return CpcRefusCircuit('CIRCUIT_MOIS_INVALIDE', 'Le mois doit être un entier de 1 à 12 (reçu « ${valeur ?? ''} »).', 'Saisir un mois de 1 à 12.');
    }
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// LES POSTES APPAIRÉS AVANT « DÉMARRER LA CLÔTURE » (lot CLO-2, C5, EF-CLO-5) : un AVERTISSEMENT, jamais un blocage
// ---------------------------------------------------------------------------------------------------------------------------------------------------

/// Ce que la mère sait d'un fileul (indicateurs de supervision RLS-SYNC : un horodatage et un compteur, aucune donnée de santé). [retardJournal] : opérations du journal que ce fileul
/// n'a pas encore rapprochées de la mère ; `null` : retard non calculable (jamais vu).
class CpcPosteAppaire {
  const CpcPosteAppaire({required this.nom, required this.dernierContact, required this.retardJournal});
  final String nom;
  final DateTime? dernierContact;
  final int? retardJournal;
}

class CpcAvertissementPoste {
  const CpcAvertissementPoste(this.nom, this.raison, this.detail);
  final String nom;

  /// `etat_inconnu` (jamais vu, ou aucun contact depuis le délai) ou `a_envoyer` (retard du journal non nul).
  final String raison, detail;
}

/// Les postes à vérifier avant de démarrer la clôture : ceux dont l'état est INCONNU (aucun contact depuis [delaiHeures] heures, ou jamais vu : inconnu n'est pas « à jour ») et ceux qui
/// ont des opérations à rapprocher. HYPOTHÈSE à confirmer par la Direction : « opérations à envoyer » = retard du journal non nul, la mère ne voyant pas la file du fileul. Une
/// liste vide dit « rien à signaler », jamais « tout est à jour » pour un poste qui ne répond pas. L'avertissement ne BLOQUE rien : la clôture démarre, et la mère refusera au rejeu
/// les pièces datées de l'exercice que ces postes enverraient.
List<CpcAvertissementPoste> cpcAvertissementsPostes(Iterable<CpcPosteAppaire> postes, DateTime maintenant, {required int delaiHeures}) {
  final out = <CpcAvertissementPoste>[];
  for (final p in postes) {
    final c = p.dernierContact;
    if (c == null) {
      out.add(CpcAvertissementPoste(p.nom, 'etat_inconnu', 'jamais vu de la mère : état inconnu'));
    } else if (maintenant.difference(c) > Duration(hours: delaiHeures)) {
      out.add(CpcAvertissementPoste(p.nom, 'etat_inconnu', 'aucun contact depuis plus de $delaiHeures h : état inconnu'));
    } else if (p.retardJournal == null) {
      out.add(CpcAvertissementPoste(p.nom, 'etat_inconnu', 'retard du journal non calculable : état inconnu'));
    } else if (p.retardJournal! > 0) {
      out.add(CpcAvertissementPoste(p.nom, 'a_envoyer', '${p.retardJournal} opération(s) du journal pas encore rapprochées'));
    }
  }
  return out;
}

/// Le texte de l'avertissement (vide : rien à signaler).
String cpcTexteAvertissementPostes(List<CpcAvertissementPoste> a, int annee) => a.isEmpty
    ? ''
    : 'Avertissement, non bloquant : ${a.map((x) => '« ${x.nom} » (${x.detail})').join(', ')}. Une fois $annee en clôture, la mère REFUSE les pièces datées de $annee que ces postes lui enverraient ; '
        'les faire synchroniser d’abord.';
