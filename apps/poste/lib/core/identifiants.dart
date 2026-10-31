import 'dart:convert';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';

/// AUTHENTIFICATION LOCALE DU POSTE (A5, décision de la Direction du 31/10/2026).
///
/// Le mot de passe est haché en ARGON2ID (paquet `cryptography`, implémentation Dart pure, aucun binaire natif) avec un SEL PAR COMPTE, et le haché vit dans
/// la collection technique `identifiants` : hash, sel, paramètres du calcul, dates, compteur d'échecs. JAMAIS le mot de passe : ni dans la fiche, ni dans
/// le journal d'audit (RG-12 y inscrit le geste, jamais la valeur), ni dans le jeu de démonstration, ni dans un export.
///
/// La collection est tenue par le magasin comme les autres ; la base locale chiffrée (plan S4) viendra derrière la même interface. Tant qu'elle n'est pas
/// là, le magasin est en mémoire et les identifiants ne survivent pas au processus : le poste ré-amorce alors son administrateur au démarrage suivant.
class ServiceIdentifiants {
  ServiceIdentifiants._(this._magasin);

  final Magasin _magasin;

  static final Expando<ServiceIdentifiants> _services = Expando<ServiceIdentifiants>('ServiceIdentifiants');

  /// Le service d'un magasin (un seul par magasin).
  static ServiceIdentifiants de(Magasin m) => _services[m] ??= ServiceIdentifiants._(m);

  /// Paramètres d'Argon2id appliqués aux NOUVEAUX hachés. Une suite de tests les RÉDUIT (`AccParametresHachage.tests`) pour rester rapide ; la production
  /// garde [AccParametresHachage.production]. La fiche garde ceux de sa création : un haché ancien reste vérifiable quand on durcit les paramètres.
  static AccParametresHachage parametres = AccParametresHachage.production;

  /// Le mot de passe provisoire de l'administrateur initial, à AFFICHER sur l'écran de connexion jusqu'à ce que l'administrateur ouvre sa session (ou que
  /// le poste s'arrête). Posé par `main` après [amorcerAdministrateur] ; jamais écrit ailleurs qu'en mémoire.
  static ProvisoireAdmin? provisoireAffiche;

  /// Source d'aléa du sel et des mots de passe provisoires : cryptographiquement sûre. Un test peut y poser une graine pour rejouer un tirage.
  static math.Random Function() aleatoire = math.Random.secure;

  CollectionMagasin get _col => _magasin.collection('identifiants');

  /// Le compte possède-t-il un mot de passe défini ?
  bool possede(String utilisateurId) => _col.parId(utilisateurId) != null;

  /// La fiche (sans secret exploitable hors du poste) : pour les tests et l'administration (dates, échecs, verrou), jamais pour l'affichage du haché.
  Fiche? fiche(String utilisateurId) => _col.parId(utilisateurId);

  Future<List<int>> _deriver(String mot, List<int> sel, AccParametresHachage p) async {
    final algo = Argon2id(parallelism: p.parallelisme, memory: p.memoireKio, iterations: p.iterations, hashLength: p.longueur);
    final cle = await algo.deriveKeyFromPassword(password: mot, nonce: sel);
    return cle.extractBytes();
  }

  List<int> _tirerSel() {
    final a = aleatoire();
    return [for (var i = 0; i < accLongueurSel; i++) a.nextInt(256)];
  }

  /// Comparaison en temps CONSTANT (la durée ne dit pas à partir de quel octet les deux hachés diffèrent).
  static bool _egaux(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }

  /// Définit (ou remplace) le mot de passe d'un compte. Aucun contrôle de politique ici : l'appelant l'applique AVANT (`accControlerNouveauMotDePasse`),
  /// parce que le mot de passe provisoire généré et la saisie d'un agent n'ont pas la même source d'erreur. Lève le verrou et remet les échecs à zéro.
  /// [doitChanger] : changement obligatoire à la première connexion (mot de passe provisoire).
  Future<void> definir(String utilisateurId, String motDePasse, {required String par, required bool doitChanger, required DateTime maintenant}) async {
    final p = parametres;
    final sel = _tirerSel();
    final hash = await _deriver(motDePasse, sel, p);
    final fiche = accFicheIdentifiant(
        utilisateurId: utilisateurId,
        hash: base64.encode(hash),
        sel: base64.encode(sel),
        parametres: p,
        maintenant: maintenant,
        definiPar: par,
        doitChanger: doitChanger);
    final existante = _col.parId(utilisateurId);
    if (existante == null) {
      _col.inserer(fiche, prefixe: 'IDF');
    } else {
      _col.mettreAJour(utilisateurId, fiche);
    }
    // Le compte se rouvre : le compteur d'échecs affiché à l'administrateur repart de zéro.
    final compte = _magasin.collection('utilisateurs').parId(utilisateurId);
    if (compte != null) _magasin.collection('utilisateurs').mettreAJour(utilisateurId, {'echecs': 0});
    _magasin.journaliser(existante == null ? 'Mot de passe défini' : 'Mot de passe changé', 'M14', 'Identifiant', utilisateurId, null,
        {'doitChanger': doitChanger, 'algorithme': 'argon2id'});
  }

  /// Vérifie un mot de passe contre le haché du compte. `true` ou `false`, sans effet de bord (le compteur d'échecs est tenu par [verifier]).
  Future<bool> _correspond(Fiche f, String motDePasse) async {
    final p = AccParametresHachage.depuisFiche(f);
    final calcule = await _deriver(motDePasse, base64.decode('${f['sel']}'), p);
    return _egaux(calcule, base64.decode('${f['hash']}'));
  }

  /// Contrôle, SANS rien modifier, qu'un mot de passe est celui du compte (changement de mot de passe : « le mot de passe actuel est vérifié »).
  Future<bool> motDePasseActuel(String utilisateurId, String motDePasse) async {
    final f = _col.parId(utilisateurId);
    if (f == null) return false;
    return _correspond(f, motDePasse);
  }

  /// Le HACHÉ factice d'un identifiant inconnu : on dépense le même temps de calcul, pour que la durée de la réponse ne distingue pas un identifiant
  /// inconnu d'un mot de passe erroné.
  Future<void> _leurre(String motDePasse) async {
    await _deriver(motDePasse, List<int>.filled(accLongueurSel, 7), parametres);
  }

  /// LA CONNEXION. Ordre des contrôles :
  ///  1. identifiant inconnu → refus générique (même message, même durée qu'un mot de passe erroné) ;
  ///  2. compte sans mot de passe défini → refus générique, motif nommé au journal ;
  ///  3. compte verrouillé → refus NOMMÉ (l'agent doit savoir pourquoi et jusqu'à quand), sans comparer le mot de passe ;
  ///  4. mot de passe erroné → échec compté ; au seuil, le verrou se pose (RG-12 : chaque tentative est écrite dans `tentativesConnexion`) ;
  ///  5. mot de passe juste → le compteur retombe, puis les contrôles d'état du compte (archivé, rôle archivé) par [accEvaluer].
  /// Rend la décision à afficher, et si le changement du mot de passe est obligatoire.
  Future<ResultatConnexion> verifier({
    required String identifiant,
    required String motDePasse,
    required Set<String> rolesArchives,
    required String Function(String role) libelleRole,
    required DateTime maintenant,
    String poste = 'Écran de connexion',
  }) async {
    final id = identifiant.trim();
    final comptes = _magasin.collection('utilisateurs').toutes;
    final decision = accEvaluer(
        identifiant: id,
        utilisateurs: comptes,
        rolesArchives: rolesArchives,
        libelleRole: libelleRole,
        personnel: _magasin.collection('personnel').actives,
        soignants: _magasin.collection('soignants').actives);
    final compte = comptes.where((u) => '${u['identifiant']}' == id).firstOrNull;
    if (compte == null) {
      await _leurre(motDePasse);
      _ecrireTentative(id, decision, maintenant, poste);
      return ResultatConnexion(decision: decision, motifJournal: decision.motif);
    }
    final cle = '${compte['id'] ?? id}';
    final f = _col.parId(cle);
    if (f == null) {
      await _leurre(motDePasse);
      final d = const AccDecision(AccIssue.refuse, message: accMessageRefus, motif: accMotifSansIdentifiant);
      _ecrireTentative(id, AccDecision(AccIssue.refuse, compte: decision.compte, message: d.message, motif: d.motif), maintenant, poste);
      return ResultatConnexion(decision: d, motifJournal: accMotifSansIdentifiant);
    }
    final fin = accVerrouJusqua(f, maintenant);
    if (fin != null) {
      final d = AccDecision(AccIssue.refuse, compte: decision.compte, message: accMessageVerrou(fin), motif: accMotifCompteVerrouille);
      _ecrireTentative(id, d, maintenant, poste);
      return ResultatConnexion(decision: d, verrouJusqua: fin, motifJournal: accMotifCompteVerrouille);
    }
    final bon = await _correspond(f, motDePasse);
    if (!bon) {
      final r = accApresEchec(f, maintenant);
      _col.mettreAJour(cle, r.patch);
      _magasin.collection('utilisateurs').mettreAJour(cle, {'echecs': ((compte['echecs'] is num ? compte['echecs'] as num : 0).toInt()) + 1});
      final DateTime? fin2 = r.verrouille ? DateTime.parse('${r.patch['verrouJusqua']}') : null;
      final d = AccDecision(AccIssue.refuse,
          compte: decision.compte,
          message: fin2 != null ? accMessageVerrou(fin2) : accMessageRefus,
          motif: fin2 != null ? accMotifVerrouPose : accMotifMotDePasseErrone);
      _ecrireTentative(id, d, maintenant, poste);
      return ResultatConnexion(decision: d, verrouJusqua: fin2, motifJournal: d.motif);
    }
    _col.mettreAJour(cle, accApresSucces(maintenant));
    if (decision.accepte) {
      _magasin.collection('utilisateurs').mettreAJour(cle, {'echecs': 0, 'dernierAcces': maintenant.toIso8601String().substring(0, 10)});
    } else {
      // Mot de passe juste mais compte ou rôle archivé : refus nommé (RG-14), tentative écrite.
      _ecrireTentative(id, decision, maintenant, poste);
    }
    return ResultatConnexion(
        decision: decision, doitChanger: decision.accepte && accChangementObligatoire(f, maintenant), motifJournal: decision.motif);
  }

  void _ecrireTentative(String identifiant, AccDecision d, DateTime maintenant, String poste) {
    _magasin.utilisateur = identifiant;
    _magasin
        .collection('tentativesConnexion')
        .inserer({...accTentative(identifiant: identifiant, decision: d, maintenant: maintenant), 'poste': poste}, prefixe: 'TNT');
  }

  /// BOOTSTRAP. À la première mise en service (aucun identifiant défini), le compte administrateur reçoit un mot de passe PROVISOIRE ALÉATOIRE, avec
  /// changement obligatoire. Il est rendu UNE fois à l'appelant, qui l'affiche à l'écran : il n'est ni dans le dépôt, ni dans un fichier, ni au journal.
  /// Rend `null` si le poste a déjà des identifiants, ou si le compte administrateur n'existe pas.
  Future<ProvisoireAdmin?> amorcerAdministrateur({required DateTime maintenant}) async {
    if (_col.toutes.isNotEmpty) return null;
    final admin = _magasin.collection('utilisateurs').toutes.where((u) => '${u['role']}' == 'admin' && '${u['statut'] ?? 'actif'}' == 'actif').firstOrNull;
    if (admin == null) return null;
    final mot = accGenererMotDePasseProvisoire(aleatoire());
    final cle = '${admin['id'] ?? admin['identifiant']}';
    await definir(cle, mot, par: 'Mise en service', doitChanger: true, maintenant: maintenant);
    return ProvisoireAdmin(identifiant: '${admin['identifiant']}', motDePasse: mot);
  }
}

/// Le mot de passe provisoire de l'administrateur initial. À afficher UNE fois, jamais à écrire.
class ProvisoireAdmin {
  const ProvisoireAdmin({required this.identifiant, required this.motDePasse});
  final String identifiant;
  final String motDePasse;
}

class ResultatConnexion {
  const ResultatConnexion({required this.decision, this.doitChanger = false, this.verrouJusqua, this.motifJournal});
  final AccDecision decision;

  /// Le mot de passe est juste mais son changement est obligatoire (première connexion, mot de passe provisoire ou renouvellement échu).
  final bool doitChanger;
  final DateTime? verrouJusqua;
  final String? motifJournal;
  bool get accepte => decision.accepte;
}
