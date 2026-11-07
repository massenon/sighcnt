/// Règles de la console du poste mère, lot (b) : journal technique, sauvegardes, clé de clinique, intégrité, réinitialisation de production,
/// relais, indicateurs publiés. Aucune de ces règles n'est inventée : chacune cite sa source (spec du protocole de synchronisation, moteur
/// `packages/sync_dart`, banc `packages/sync/banc`). Une valeur sans source reste `null` : l'écran dit « non disponible », jamais zéro.
library;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Journal technique (M-08)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Une ligne du journal technique de la mère (`GET /admin/journal` : `quand` en millisecondes, niveau `info`, `alerte` ou `erreur`).
class MrbLigneJournal {
  const MrbLigneJournal({required this.quand, required this.niveau, required this.source, required this.message});
  final int quand;
  final String niveau;
  final String source;
  final String message;
}

/// Compte des dernières 24 h. `tronque` : le journal lu s'arrête à `limite` lignes ET sa ligne la plus ancienne est encore dans la fenêtre :
/// le compte est alors un MINIMUM, jamais un total (l'écran l'annonce « au moins »).
class MrbCompteJournal {
  const MrbCompteJournal({required this.evenements, required this.alertes, required this.erreurs, required this.tronque});
  final int evenements;
  final int alertes;
  final int erreurs;
  final bool tronque;
}

const int mrbFenetreJournalMs = 24 * 3600 * 1000;

MrbCompteJournal mrbCompterJournal(List<MrbLigneJournal> lignes, {required int maintenantMs, required int limite, int fenetreMs = mrbFenetreJournalMs}) {
  final depuis = maintenantMs - fenetreMs;
  final dans = lignes.where((l) => l.quand >= depuis).toList();
  final plusAncienne = lignes.isEmpty ? null : lignes.map((l) => l.quand).reduce((a, b) => a < b ? a : b);
  return MrbCompteJournal(
    evenements: dans.length,
    alertes: dans.where((l) => l.niveau == 'alerte').length,
    erreurs: dans.where((l) => l.niveau == 'erreur').length,
    tronque: lignes.length >= limite && plusAncienne != null && plusAncienne >= depuis,
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Intégrité et altérations (M-11)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les alertes d'intégrité que le pont de la mère lève (`pont.dart`, `relever`) : `authentification` (le déchiffrement GCM échoue : enveloppe
/// altérée, mauvaise clé ou métadonnées déplacées) et `trou` (le rang reçu n'est pas le rang attendu : enveloppe manquante).
/// `null` : type que le moteur ne connaît pas, l'écran l'affiche tel quel.
String? mrbCauseAlteration(String type) => switch (type) {
      'authentification' => 'Enveloppe altérée (authentification GCM échouée)',
      'trou' => 'Enveloppe manquante (trou dans les rangs)',
      'appareil_inconnu' => 'Appareil inconnu ou code d’appairage invalide',
      _ => null,
    };

/// Le rang concerné, tel que le moteur le porte : `n` pour une altération, `attendu` puis `recu` pour un trou. `null` : le moteur ne le dit pas.
String? mrbRangAlteration(Map<String, Object?> alerte) {
  switch (alerte['type']) {
    case 'authentification':
      return alerte['n'] == null ? null : '${alerte['n']}';
    case 'trou':
      return alerte['attendu'] == null ? null : 'attendu ${alerte['attendu']}, reçu ${alerte['recu']}';
  }
  return null;
}

class MrbCompteAlterations {
  const MrbCompteAlterations({required this.alterees, required this.trous});
  final int alterees;
  final int trous;
}

/// Compte, sur `jours` jours, les alertes d'intégrité dont le message de journal est celui du moteur (`Alerte authentification …`, `Alerte trou …`
/// posé par `Pont.alerter` : source PERSISTANTE, contrairement à la liste des alertes tenue en mémoire).
MrbCompteAlterations mrbCompterAlterations(List<MrbLigneJournal> lignes, {required int maintenantMs, int jours = 30}) {
  final depuis = maintenantMs - jours * 24 * 3600 * 1000;
  var a = 0, t = 0;
  for (final l in lignes) {
    if (l.quand < depuis || l.niveau != 'alerte') continue;
    if (l.message.startsWith('Alerte authentification')) a++;
    if (l.message.startsWith('Alerte trou')) t++;
  }
  return MrbCompteAlterations(alterees: a, trous: t);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Clé de clinique (M-10)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les 8 premiers caractères de l'empreinte SHA-256 (64 hexadécimaux) : tout ce que l'écran montre de la clé. Une valeur qui n'est pas une empreinte
/// SHA-256 est refusée (`null`) : on n'affiche jamais un texte quelconque dans la case réservée à l'empreinte.
String? mrbEmpreinteCourte(String? hex) {
  if (hex == null) return null;
  final h = hex.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(h)) return null;
  return h.substring(0, 8).toUpperCase();
}

/// Le contenu du QR d'appairage d'un mobile : le code à usage unique ET la clé de clinique (le téléphone en a besoin pour chiffrer). C'est le SEUL
/// endroit où la clé quitte le serveur sous une forme exploitable, et seulement sous forme de QR : jamais en caractères lisibles à l'écran.
String mrbPayloadQrMobile({required String code, required String cleBase64}) => 'sigh-mobile:1:$code:$cleBase64';

/// Retire la clé de tout texte destiné à un message, un toast ou un journal. À appliquer aux messages d'erreur qui pourraient citer la requête.
String mrbSansCle(String texte, String? cleBase64) {
  if (cleBase64 == null || cleBase64.length < 8) return texte;
  return texte.replaceAll(cleBase64, '[clé masquée]');
}

/// Une attestation de copie papier doit nommer le détenteur, le numéro de scellé et la personne qui a contrôlé (spec Q2 : « la réponse oui ne désigne
/// personne »). Rend les champs manquants, dans l'ordre du formulaire.
List<String> mrbChampsAttestationManquants({String? detenteur, String? scelle, String? controlePar}) => [
      if ((detenteur ?? '').trim().isEmpty) 'Détenteur',
      if ((scelle ?? '').trim().isEmpty) 'Scellé n°',
      if ((controlePar ?? '').trim().isEmpty) 'Contrôlé par',
    ];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Réinitialisation de production (M-12), spec §10
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Durée de la fenêtre d'ouverture portée par la fiche (« Ouvrir la fenêtre (30 min) »). Le service de la mère ne la limite pas lui-même
/// (`reinit-fenetre` pose un drapeau sans échéance) : la console la referme à l'échéance tant qu'elle reste ouverte.
const Duration mrbDureeFenetreReinit = Duration(minutes: 30);

/// Un refus NOMMÉ : `code` stable, `motif` lisible. Jamais un bouton muet.
class MrbRefus {
  const MrbRefus(this.code, this.motif);
  final String code;
  final String motif;
  @override
  String toString() => motif;
}

/// Les gardes de la réinitialisation, dans l'ordre où le moteur les pose (`POST /admin/reinitialiser`), plus celles de la spec §10 que le moteur
/// ne tient pas seul :
///  1. droit d'annuler sur l'écran (la commande est ABSENTE sans lui : ce refus ne sert qu'à une écriture hors interface) ;
///  2. fenêtre ouverte (`reinit_fermee`) ;
///  3. nom de la clinique saisi à l'identique (`confirmation_invalide`) ;
///  4. second profil renseigné (`second_profil_requis`) ET différent de l'auteur du geste (spec : le geste ne repose pas sur une seule personne).
MrbRefus? mrbRefusReinit({
  required bool droitAnnuler,
  required bool fenetreOuverte,
  required String confirmation,
  required String nomClinique,
  required String second,
  required String auteur,
}) {
  if (!droitAnnuler) return const MrbRefus('droit_refuse', 'Votre profil ne permet pas la réinitialisation de production.');
  if (!fenetreOuverte) return const MrbRefus('reinit_fermee', 'La réinitialisation est fermée : l’administrateur doit ouvrir la fenêtre.');
  if (nomClinique.trim().isEmpty || confirmation.trim() != nomClinique.trim()) {
    return const MrbRefus('confirmation_invalide', 'Saisir le nom de la clinique, à l’identique, pour confirmer.');
  }
  if (second.trim().isEmpty) return const MrbRefus('second_profil_requis', 'Un second profil (DAF ou Direction) doit confirmer.');
  if (second.trim().toLowerCase() == auteur.trim().toLowerCase()) {
    return const MrbRefus('second_profil_identique', 'Le second profil doit être une autre personne que celle qui réinitialise.');
  }
  return null;
}

/// Temps restant de la fenêtre. `null` : on ne sait pas depuis quand elle est ouverte (ouverte par une autre console, ou avant celle-ci).
Duration? mrbFenetreRestante({required DateTime? ouverteLe, required DateTime maintenant, Duration duree = mrbDureeFenetreReinit}) {
  if (ouverteLe == null) return null;
  final reste = duree - maintenant.difference(ouverteLe);
  return reste.isNegative ? Duration.zero : reste;
}

/// Ce qui est conservé par le MOTEUR de synchronisation de la mère (`essentielles` dans `mere.dart`) : les référentiels que la mère seule écrit.
const List<String> mrbEssentielsMoteur = ['tarifs', 'chambres'];

/// Ce qui est conservé côté poste, selon la spec §10 (liste `COLLECTIONS_ESSENTIELLES` de la maquette, une donnée du dictionnaire et non du code).
const List<String> mrbEssentielsSpec = [
  'Paramétrage et référentiels',
  'Comptes et droits (matrice RBAC)',
  'Modules actifs',
  'Catalogues du laboratoire et de l’imagerie',
  'Tarifs et grilles',
  'Règles datées',
  'Modèles',
];

/// Ce qui est vidé (spec §10) : l'activité.
const List<String> mrbVideSpec = [
  'Patients et consultations',
  'Factures et encaissements',
  'Stocks mouvementés',
  'Écritures et journaux d’activité',
];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Indicateurs publiés (M-14) et opacité du relais (M-13), spec §12
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// La liste FERMÉE des champs que la mère publie au relais en clair (`POST /mere/indicateurs`, `Pont.demarrer`). Un test lit `pont.dart` et vérifie
/// que cette liste est exactement celle du moteur : elle ne peut pas dériver sans que la suite de tests l'annonce.
const List<String> mrbChampsPublies = ['patients_actifs', 'seq_max', 'retard_replication'];

class MrbVerdictIndicateurs {
  const MrbVerdictIndicateurs({required this.horsListe, required this.nonNumeriques});
  final List<String> horsListe;
  final List<String> nonNumeriques;

  /// Sans champ libre et sans valeur textuelle : aucun nom de patient ne peut s'y loger.
  bool get sansDonneeDeSante => horsListe.isEmpty && nonNumeriques.isEmpty;
}

MrbVerdictIndicateurs mrbVerifierIndicateurs(Map<String, Object?> publies) => MrbVerdictIndicateurs(
      horsListe: [for (final k in publies.keys) if (!mrbChampsPublies.contains(k)) k],
      nonNumeriques: [for (final e in publies.entries) if (e.value is! num) e.key],
    );

/// Le relais est OPAQUE : une enveloppe déposée ne porte que `id`, `appareil`, `dir`, `n`, `nonce` et `ct` (Base64), jamais un contenu métier, pas
/// même le nom d'une collection (spec §12). Rend les défauts trouvés dans le CORPS réellement expédié ; liste vide = opaque.
List<String> mrbDefautsOpacite(Map<String, Object?> corps, {List<String> interdits = const []}) {
  final defauts = <String>[];
  final env = corps['enveloppe'];
  if (env is! Map) return ['pas d’enveloppe'];
  const permis = {'id', 'appareil', 'dir', 'n', 'nonce', 'ct'};
  for (final k in env.keys) {
    if (!permis.contains(k)) defauts.add('champ en clair : $k');
  }
  final b64 = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');
  for (final k in ['nonce', 'ct']) {
    final v = env[k];
    if (v is! String || !b64.hasMatch(v)) defauts.add('$k n’est pas du Base64');
  }
  final texte = corps.toString();
  for (final i in interdits) {
    if (i.isNotEmpty && texte.contains(i)) defauts.add('contient « $i » en clair');
  }
  return defauts;
}

/// Sens d'un échange avec le relais, pour le tableau des derniers échanges.
String mrbLibelleSens(String sens) => switch (sens) {
      'depot' || 'vers_relais' => 'Mère vers relais',
      'releve' || 'vers_mere' => 'Relais vers mère',
      _ => sens,
    };
