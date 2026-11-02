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
    if (accTemporairePerime(f, maintenant)) {
      // Le mot de passe est juste mais son délai de 24 h est passé : refus NOMMÉ (l'agent doit savoir quoi faire), tentative écrite (RG-12).
      const d = AccDecision(AccIssue.refuse, message: accMessageTemporairePerime, motif: accMotifTemporairePerime);
      _ecrireTentative(id, AccDecision(AccIssue.refuse, compte: decision.compte, message: d.message, motif: d.motif), maintenant, poste);
      return const ResultatConnexion(decision: d, motifJournal: accMotifTemporairePerime);
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

/// LE CODE DE SECOURS DE L'ADMINISTRATEUR (PRD-POSTE-premiere-installation, EF-INST-09). Règles pures : `packages/domaine/lib/src/acces/acc_secours.dart`.
/// Seule l'EMPREINTE du code est gardée (collection `codesSecours`), jamais le code : un code perdu ne se retrouve pas.
extension SecoursAdministrateur on ServiceIdentifiants {
  CollectionMagasin get _codes => _magasin.collection('codesSecours');
  CollectionMagasin get _etatChemin => _magasin.collection('etatSecours');

  /// Le compte a-t-il un code de secours utilisable ?
  bool secoursDisponible(String utilisateurId) => accSecoursUtilisable(_codes.parId('SEC-$utilisateurId'));

  /// Engendre un NOUVEAU code de secours pour l'administrateur (le précédent, s'il y en avait un, cesse de valoir) et le rend à l'affichage, groupé par cinq.
  /// Il ne sera plus jamais relisible : l'appelant l'affiche UNE fois.
  Future<String> genererCodeSecours(String utilisateurId, {required String par, required DateTime maintenant}) async {
    final code = accGenererCodeSecours(ServiceIdentifiants.aleatoire());
    final sel = _tirerSel();
    final hash = await _deriver(code, sel, ServiceIdentifiants.parametres);
    final fiche = accFicheSecours(
        utilisateurId: utilisateurId,
        hash: base64.encode(hash),
        sel: base64.encode(sel),
        parametres: ServiceIdentifiants.parametres,
        maintenant: maintenant,
        creePar: par);
    if (_codes.parId(fiche['id']) == null) {
      _codes.inserer(fiche, prefixe: 'SEC');
    } else {
      _codes.mettreAJour(fiche['id'], fiche);
    }
    // Le journal dit le GESTE, jamais le code (RG-12).
    _magasin.journaliser('Code de secours généré', 'M14', 'Identifiant', utilisateurId, null, null);
    return accFormaterCodeSecours(code);
  }

  /// « J'ai perdu mon mot de passe administrateur » : identifiant + code de secours + nouveau mot de passe. Un essai faux (identifiant inconnu, compte qui n'est
  /// pas administrateur, code faux ou déjà consommé) coûte le même temps de calcul, compte pareil, et reçoit LE MÊME message. Au cinquième, le chemin est
  /// bloqué quinze minutes. La politique du mot de passe est contrôlée AVANT de consommer le code : un mot de passe refusé ne brûle pas le code.
  Future<ResultatSecours> recuperer({
    required String identifiant,
    required String code,
    required String nouveau,
    required String confirmation,
    required DateTime maintenant,
  }) async {
    final etat = _etatChemin.parId('CHEMIN') ?? <String, Object?>{};
    final bloque = accSecoursBloqueJusqua(etat, maintenant);
    if (bloque != null) {
      return ResultatSecours.refus(accMessageSecoursBloque(bloque), bloqueJusqua: bloque);
    }
    final id = identifiant.trim();
    final compte = _magasin.collection('utilisateurs').toutes.where((u) => '${u['identifiant']}' == id && '${u['statut'] ?? 'actif'}' == 'actif').firstOrNull;
    final fiche = compte == null ? null : _codes.parId('SEC-${compte['id'] ?? id}');
    final valide = compte != null &&
        accSecoursPourRole('${compte['role']}') &&
        accSecoursUtilisable(fiche) &&
        accCodeSecoursBienForme(code);
    var bon = false;
    if (valide) {
      final p = AccParametresHachage.depuisFiche(fiche!);
      final calcule = await _deriver(accNormaliserCodeSecours(code), base64.decode('${fiche['sel']}'), p);
      bon = ServiceIdentifiants._egaux(calcule, base64.decode('${fiche['hash']}'));
    } else {
      await _leurre(code); // même durée qu'un vrai contrôle
    }
    if (!bon) {
      final r = accSecoursApresEchec(etat, maintenant);
      _ecrireEtat({...etat, ...r.patch});
      _magasin.utilisateur = id.isEmpty ? 'Inconnu' : id;
      _magasin.collection('tentativesConnexion').inserer({
        'identifiant': id,
        'nom': '${compte?['nomComplet'] ?? id}',
        'role': '${compte?['role'] ?? '—'}',
        'motif': 'Code de secours refusé',
        'horodatage': maintenant.toIso8601String(),
        'poste': 'Récupération administrateur',
        'traitee': false,
      }, prefixe: 'TNT');
      final fin = r.bloque ? maintenant.add(accDureeBlocageSecours) : null;
      return ResultatSecours.refus(fin != null ? accMessageSecoursBloque(fin) : accMessageSecoursRefus, bloqueJusqua: fin);
    }
    final refusPolitique = accControlerNouveauMotDePasse(nouveau, confirmation, identifiant: id);
    if (refusPolitique != null) return ResultatSecours.refus(refusPolitique, codeBon: true);
    final cle = '${compte!['id'] ?? id}';
    await definir(cle, nouveau, par: 'Code de secours', doitChanger: false, maintenant: maintenant);
    _codes.mettreAJour(fiche!['id'], {'consommeLe': maintenant.toIso8601String()});
    _ecrireEtat({...etat, ...accSecoursApresSucces()});
    _magasin.journaliser('Récupération administrateur', 'M14', 'Identifiant', cle, null, {'codeConsomme': true});
    final nouveauCode = await genererCodeSecours(cle, par: 'Récupération administrateur', maintenant: maintenant);
    return ResultatSecours.ok(nouveauCode);
  }


  /// RÉINITIALISATION PAR UN ADMINISTRATEUR (EF-INST-09). Le moteur décide qui peut ([accRefusReinitialisation]) : masquer un bouton ne protège rien. Rend le mot
  /// de passe TEMPORAIRE (14 caractères, valable 24 h), à afficher UNE fois ; le compte devra le remplacer à sa prochaine connexion, et ses sessions ouvertes
  /// sont CLÔTURÉES (la clôture se voit au registre des sessions). Le journal dit le geste (qui, quel compte, quand), jamais le mot de passe. Le haché de l'ancien
  /// mot de passe est gardé pour refuser qu'il soit remis tel quel (`precedentHash`) ; il disparaît au prochain changement.
  Future<ResultatReinit> reinitialiser({
    required String cibleId,
    required String acteurRole,
    required String acteurId,
    required String acteurNom,
    required DateTime maintenant,
    bool acteurSuper = false,
    bool cibleSuper = false,
  }) async {
    final refus = accRefusReinitialisation(acteurRole: acteurRole, acteurId: acteurId, cibleId: cibleId, acteurSuper: acteurSuper, cibleSuper: cibleSuper);
    if (refus != null) return ResultatReinit.refus(refus);
    final compte = _magasin.collection('utilisateurs').parId(cibleId);
    if (compte == null || '${compte['statut'] ?? 'actif'}' != 'actif') {
      return const ResultatReinit.refus(RefusReinit('reinit_compte_inconnu', 'Ce compte n’existe pas ou est archivé.', 'Actualiser la liste des comptes.'));
    }
    // Copie AVANT `definir` : la fiche du magasin est mise à jour sur place, le haché d'avant serait perdu.
    final ancienne = _col.parId(cibleId);
    final ancien = ancienne == null ? null : <String, Object?>{...ancienne};
    final temporaire = accGenererMotDePasseTemporaire(ServiceIdentifiants.aleatoire());
    await definir(cibleId, temporaire, par: acteurNom, doitChanger: true, maintenant: maintenant);
    _col.mettreAJour(cibleId, {
      'temporaireJusqua': accEcheanceTemporaire(maintenant).toIso8601String(),
      if (ancien != null) ...{
        'precedentHash': ancien['hash'],
        'precedentSel': ancien['sel'],
        'precedentParametres': {for (final k in ['memoireKio', 'iterations', 'parallelisme', 'longueur']) k: ancien[k]},
      },
    });
    var fermees = 0;
    final sessions = _magasin.collection('sessionsUtilisateur');
    for (final f in sessions.actives.where((f) => '${f['identifiant']}' == '${compte['identifiant']}' && '${f['etat']}' != 'cloturee').toList()) {
      sessions.mettreAJour(f['id'], {
        'etat': 'cloturee',
        'clotureLe': maintenant.toIso8601String(),
        'cloturePar': acteurNom,
        'clotureParIdentifiant': acteurId,
        'clotureMotif': 'Mot de passe réinitialisé',
        'cloturePropre': false,
      });
      fermees++;
    }
    _magasin.journaliser('Mot de passe réinitialisé', 'M14', 'Identifiant', cibleId, null, {'par': acteurNom, 'sessionsFermees': fermees});
    return ResultatReinit.ok(temporaire, accEcheanceTemporaire(maintenant));
  }

  /// Le mot de passe proposé est-il celui d'AVANT la réinitialisation ? (refusé au changement obligatoire.) Faux si aucun précédent n'est gardé.
  Future<bool> memeQuePrecedent(String utilisateurId, String motDePasse) async {
    final f = _col.parId(utilisateurId);
    if (f == null || f['precedentHash'] == null || f['precedentSel'] == null) return false;
    final pr = (f['precedentParametres'] is Map) ? (f['precedentParametres'] as Map).cast<String, Object?>() : <String, Object?>{};
    final calcule = await _deriver(motDePasse, base64.decode('${f['precedentSel']}'), AccParametresHachage.depuisFiche(pr));
    return ServiceIdentifiants._egaux(calcule, base64.decode('${f['precedentHash']}'));
  }

  void _ecrireEtat(Map<String, Object?> e) {
    if (_etatChemin.parId('CHEMIN') == null) {
      _etatChemin.inserer({'id': 'CHEMIN', ...e}, prefixe: 'CHEMIN');
    } else {
      _etatChemin.mettreAJour('CHEMIN', e);
    }
  }
}

/// Le résultat d'une réinitialisation : le mot de passe temporaire et son échéance, ou le refus nommé.
class ResultatReinit {
  const ResultatReinit.ok(String this.temporaire, DateTime this.jusqua) : refus = null;
  const ResultatReinit.refus(RefusReinit this.refus)
      : temporaire = null,
        jusqua = null;
  final String? temporaire;
  final DateTime? jusqua;
  final RefusReinit? refus;
  bool get ok => temporaire != null;
}

/// Le résultat de la récupération : le nouveau code (affiché une fois), ou un refus NOMMÉ.
class ResultatSecours {
  const ResultatSecours.ok(String this.nouveauCode)
      : message = null,
        bloqueJusqua = null,
        codeBon = true;
  const ResultatSecours.refus(String this.message, {this.bloqueJusqua, this.codeBon = false}) : nouveauCode = null;
  final String? nouveauCode;
  final String? message;
  final DateTime? bloqueJusqua;

  /// Le code était bon mais le nouveau mot de passe a été refusé : le code n'est pas consommé.
  final bool codeBon;
  bool get ok => nouveauCode != null;
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
