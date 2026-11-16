import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/service_parametres.dart';
import 'magasin.dart';

/// Un refus NOMMÉ de la passerelle SMS (code, motif, geste).
class RefusSmsPoste {
  const RefusSmsPoste(this.code, this.motif, this.geste);
  final String code, motif, geste;
  @override
  String toString() => '$code : $motif $geste';
}

class ErreurSmsPoste implements Exception {
  const ErreurSmsPoste(this.refus);
  final RefusSmsPoste refus;
}

/// Ce que le poste sait demander à la passerelle SMS de la MÈRE (le service local, routes `/admin/sms/*`). Une interface : un test la remplace par un double.
abstract class SourceSms {
  Future<Map<String, Object?>> etat();
  Future<Map<String, Object?>> passe(String role);
  Future<Map<String, Object?>> tester(String role, String numero);
  Future<List<Map<String, Object?>>> journal();
}

/// La source réelle : le service de la mère sur cette machine, avec son secret d'administration ET le rôle de l'agent (la mère contrôle le geste réservé à son tour).
class SourceSmsHttp implements SourceSms {
  SourceSmsHttp({required this.base, required this.admin, http.Client? client}) : _c = client ?? http.Client();
  final Uri base;
  final String admin;
  final http.Client _c;

  Future<Map<String, Object?>> _appel(String methode, String chemin, {String? role, Map<String, Object?>? corps}) async {
    final req = http.Request(methode, base.resolve(chemin))
      ..headers['x-admin'] = admin
      ..headers['content-type'] = 'application/json';
    if (role != null) req.headers['x-sigh-role'] = role;
    if (corps != null) req.body = jsonEncode(corps);
    final http.Response rep;
    try {
      rep = await http.Response.fromStream(await _c.send(req).timeout(const Duration(minutes: 2)));
    } catch (_) {
      throw const ErreurSmsPoste(RefusSmsPoste('MERE_INJOIGNABLE', 'le service du poste mère ne répond pas', 'Vérifier que le poste mère est démarré sur cette machine.'));
    }
    Map<String, Object?> j = {};
    try {
      j = (jsonDecode(utf8.decode(rep.bodyBytes)) as Map).cast<String, Object?>();
    } catch (_) {/* vide */}
    if (rep.statusCode >= 400) throw ErreurSmsPoste(RefusSmsPoste('${j['code'] ?? 'ERREUR_MERE'}', '${j['motif'] ?? 'réponse ${rep.statusCode}'}', '${j['geste'] ?? ''}'));
    return j;
  }

  @override
  Future<Map<String, Object?>> etat() => _appel('GET', '/admin/sms/etat');
  @override
  Future<Map<String, Object?>> passe(String role) => _appel('POST', '/admin/sms/passe', role: role, corps: {});
  @override
  Future<Map<String, Object?>> tester(String role, String numero) => _appel('POST', '/admin/sms/tester', role: role, corps: {'numero': numero});
  @override
  Future<List<Map<String, Object?>>> journal() async => [for (final m in ((await _appel('GET', '/admin/sms/journal'))['messages'] as List)) (m as Map).cast<String, Object?>()];
}

/// LA PASSERELLE SMS AU POSTE (lot SMS-R, ADR-0008). Le RÉGLAGE est un paramètre de clinique en base (famille `sms`, désactivé par défaut) ; l'ÉTAT, le calcul et le test passent par le service de la
/// mère ([SourceSms]) : un fileul n'en a pas, il lit le réglage sans commande. Le geste réservé `regler_passerelle_sms` est contrôlé ICI et par la mère : une commande interdite est ABSENTE à l'écran
/// et refusée par le moteur.
class SmsPoste extends ChangeNotifier {
  SmsPoste(this.magasin, {bool Function()? estFileul, bool Function()? estMere, SourceSms? source, bool Function(String role)? gesteDe})
      : estFileul = estFileul ?? (() => false),
        _source = source,
        _estMere = estMere ?? (() => source != null),
        gesteDe = gesteDe ?? ((_) => false);

  final Magasin magasin;
  final bool Function() estFileul;
  final SourceSms? _source;
  final bool Function() _estMere;
  final bool Function(String role) gesteDe;

  SourceSms? get source => _estMere() ? _source : null;

  static final Expando<SmsPoste> _installes = Expando<SmsPoste>('SmsPoste');
  static SmsPoste? de(Magasin m) => _installes[m];
  void installer() => _installes[magasin] = this;

  Map<String, Object?>? etatMere;
  List<Map<String, Object?>>? journalMere;
  RefusSmsPoste? erreurEtat;
  bool enCours = false;

  ServiceParametres get _parametres => serviceParametres(magasin, auteur: () => magasin.utilisateur, horloge: () => magasin.horloge());
  String get _aujourdhui => parametreDateIso(magasin.horloge());

  bool peutRegler(String role) => gesteDe(role);

  /// Le réglage est-il REÇU ? Sinon l'écran le DIT (jamais « désactivés » en silence).
  bool get reglageRecu => _parametres.versions(smsCleActif).isNotEmpty;

  bool get actif => reglageRecu && _parametres.valeur(smsCleActif, _aujourdhui) == true;

  int _entier(String cle, int defaut) {
    final v = _parametres.valeur(cle, _aujourdhui);
    return v is num ? v.toInt() : defaut;
  }

  int get rappelHeure => _entier(smsCleRappelHeure, smsRappelHeureDefaut);
  int get anniversaireHeure => _entier(smsCleAnniversaireHeure, smsAnniversaireHeureDefaut);
  int get calmeDebut => _entier(smsCleCalmeDebut, smsCalmeDebutDefaut);
  int get calmeFin => _entier(smsCleCalmeFin, smsCalmeFinDefaut);

  RefusSmsPoste get _sansMere => const RefusSmsPoste('MERE_REQUISE', 'la passerelle SMS se lit, et ses gestes se lancent, sur le poste mère', 'Ouvrir cet écran sur le poste mère.');
  RefusSmsPoste get _reserve => const RefusSmsPoste('GESTE_RESERVE', 'le réglage de la passerelle SMS est un droit réservé de la fiche RBAC', 'Demander à l\'administrateur ou à la Directrice Administrative.');

  /// Active ou désactive les envois automatiques : nouvelle version datée du paramètre, motivée, journalisée (RG-12). Refus nommé : fileul, geste réservé.
  RefusSmsPoste? definirActif({required String role, required bool actif}) {
    if (estFileul()) return const RefusSmsPoste('FILEUL_LECTURE_SEULE', 'les envois automatiques sont un réglage de la clinique, posé au poste mère', 'Régler la passerelle sur le poste mère : ce poste reçoit le réglage par le journal.');
    if (!peutRegler(role)) return _reserve;
    final p = _parametres;
    try {
      if (!reglageRecu) p.semerDefauts();
      final avant = this.actif;
      if (avant != actif) {
        final w = p.regler(smsCleActif, actif, _aujourdhui, motif: actif ? 'Activation des envois automatiques de SMS' : 'Désactivation des envois automatiques de SMS');
        if (!w.ok) return RefusSmsPoste('REGLAGE_REFUSE', '${w.refus!.code} : ${w.refus!.motif}', w.refus!.geste);
      }
      magasin.journaliser('Réglage de la passerelle SMS', 'CFG', 'reglage', 'sms', {'actif': avant}, {'actif': actif});
    } on EcritureRefusee catch (e) {
      return RefusSmsPoste('FILEUL_LECTURE_SEULE', e.motif, 'Régler la passerelle sur le poste mère.');
    }
    notifyListeners();
    return null;
  }

  Future<void> rafraichir() async {
    final s = source;
    if (s == null) {
      etatMere = null;
      erreurEtat = null;
      notifyListeners();
      return;
    }
    try {
      etatMere = await s.etat();
      erreurEtat = null;
    } on ErreurSmsPoste catch (e) {
      etatMere = null;
      erreurEtat = e.refus;
    }
    notifyListeners();
  }

  Future<void> rafraichirJournal() async {
    final s = source;
    if (s == null) {
      journalMere = null;
      erreurEtat = null;
      notifyListeners();
      return;
    }
    try {
      journalMere = await s.journal();
      erreurEtat = null;
    } on ErreurSmsPoste catch (e) {
      journalMere = null;
      erreurEtat = e.refus;
    }
    notifyListeners();
  }

  Future<(Map<String, Object?>?, RefusSmsPoste?)> _geste(String role, Future<Map<String, Object?>> Function(SourceSms s) f, String nom) async {
    final s = source;
    if (s == null) return (null, _sansMere);
    if (!peutRegler(role)) return (null, _reserve);
    enCours = true;
    notifyListeners();
    try {
      final r = await f(s);
      magasin.journaliser(nom, 'CFG', 'Passerelle SMS', 'sms', null, null);
      return (r, null);
    } on ErreurSmsPoste catch (e) {
      return (null, e.refus);
    } finally {
      enCours = false;
      await rafraichir();
    }
  }

  /// « Calculer et déposer maintenant » : la mère calcule et dépose au relais (jamais un envoi direct).
  Future<(Map<String, Object?>?, RefusSmsPoste?)> calculerMaintenant({required String role}) => _geste(role, (s) => s.passe(role), 'Calcul et dépôt des envois SMS');

  /// « Tester l'envoi » : message de contrôle imposé par le relais, résultat nommé.
  Future<(Map<String, Object?>?, RefusSmsPoste?)> tester({required String role, required String numero}) => _geste(role, (s) => s.tester(role, numero), 'Test d\'envoi SMS');
}

/// Les fermetures « écran non porté » que le lot SMS-R LÈVE : le journal des envois (MODP02) et la passerelle (MODP04). Un poste déjà installé garde leur fiche fermée dans son magasin (la reprise du jeu
/// livré n'écrase jamais une fiche existante) : au démarrage, la fiche est ROUVERTE, une fois. Seule la fermeture d'ORIGINE est levée (`fermeLe` du 11/11/2026, `proprePoste`) : un agent qui a refermé
/// l'écran depuis a posé une autre date, et sa décision est gardée. Idempotent. Rend les identifiants rouverts.
const List<String> fermeturesLeveesSms = ['MODP02', 'MODP04'];

List<String> reouvrirFermeturesLevees(Magasin magasin) {
  final col = magasin.collection('modulesActifs');
  final jour = parametreDateIso(magasin.horloge());
  final rouverts = <String>[];
  for (final id in fermeturesLeveesSms) {
    final f = col.parId(id);
    if (f == null || f['actif'] != false || f['proprePoste'] != true || f['fermeLe'] != '2026-11-11' || f['rouvertLe'] != null || f['statut'] == 'archive') continue;
    col.mettreAJour(id, {'actif': true, 'rouvertLe': jour, 'rouvertPar': 'Lot SMS-R (écran porté au poste)'});
    rouverts.add(id);
  }
  if (rouverts.isNotEmpty) magasin.journaliser('Réouverture d\'écrans portés', 'CFG', 'activités', 'sms', null, {'ecrans': rouverts});
  return rouverts;
}
