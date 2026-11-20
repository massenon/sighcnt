import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// LE RÉFÉRENTIEL DE PRIX ENTRE LA MÈRE ET UN FILEUL (lot T6, étape 5), contre la VRAIE mère et un VRAI moteur de fileul :
///  - `tarifs` et `versionsTarif` voyagent de la mère au fileul par le journal de configuration (famille R) ;
///  - un fileul ne peut PAS écrire une version (garde « réglé sur la mère », et `TarifsPoste` dépose une demande au lieu d'écrire) ;
///  - la proposition d'un fileul (famille B, `propositionsTarif`) est appliquée par la mère, qui refait les contrôles sous le rôle de son auteur, et le verdict revient ;
///  - JAMAIS un prix, une proposition, un refus ni un motif vers un téléphone ;
///  - hors ligne, le prix se calcule à la date de la pièce sans horloge ni connexion ; un fileul qui n'a pas reçu une version facture à l'ancien prix.
typedef M = Map<String, Object?>;
final auj = DateTime(2026, 10, 30, 10);
String plus(int n) => tarIso(auj.add(Duration(days: n)));

Magasin jeu() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

TarifsPoste poste(Magasin m, String role, String nom, {bool fileul = false, String etiquette = 'P'}) => TarifsPoste(m,
    role: role,
    auteur: () => nom,
    fileul: fileul,
    peutEditerEcran: true,
    peutEditerPour: (r) => const ['admin', 'da', 'direction'].contains(r),
    horloge: () => auj,
    etiquette: etiquette);

DemandeProposition prop(String code, num prix, {int jours = 3}) =>
    DemandeProposition(code: code, prixNonAssure: prix, etatAssure: 'unique', dateEffet: plus(jours), motif: 'Test synchronisation T6');

void main() {
  test('BOUT EN BOUT : la DAF (mère) décide ; le fileul reçoit les versions, ne peut pas les écrire, sa proposition est appliquée par la mère ; aucun prix vers un mobile', () async {
    const port = 19471;
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-tarifs'));
    await mere0.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteur = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1', nom: 'Direction');
    // La mère porte le jeu COMPLET ; le fileul démarre SANS référentiel (il le reçoit).
    final mm = jeu();
    final mf = Magasin({'actes': <M>[], 'notifications': <M>[]});
    final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero, collections: {...collectionsConfiguration()});
    final appl = ApplicateurConfiguration(mf, moteur.liste);
    final pontM = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M');
    final pontF = PontActivite(
        mf,
        TransportFileul(lire: moteur.liste, ecrireFiche: (c, f, {required existe, required champs}) => moteur.ecrire(c, f, existe: existe, champs: champs)),
        etiquette: 'F');
    final daf = poste(mm, 'da', 'Yvette DAF', etiquette: 'M');
    Future<void> converger(bool Function() fini, String quoi) async {
      final fin = DateTime.now().add(const Duration(seconds: 40));
      while (!fini()) {
        await pub.pousser();
        await appl.tirer();
        await pontF.cycle();
        await pontM.cycle();
        daf.appliquerDemandes();
        if (DateTime.now().isAfter(fin)) fail('$quoi : pas de convergence (pub ${pub.erreur.value}, appl ${appl.erreur.value}, pontF ${pontF.erreur.value}, pontM ${pontM.erreur.value})');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    try {
      expect(await pub.pousser(), greaterThan(400), reason: 'les 201 prestations et 240 versions partent avec la configuration');
      final code = await console.codeAppareil('Direction').timeout(const Duration(seconds: 20));
      await moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
      moteur.demarrer();
      await converger(() => mf.collection('versionsTarif').toutes.length >= 240 && mf.collection('tarifs').toutes.length >= 201, 'réception du référentiel par le fileul');
      expect(TarifsPoste.prixActe(mf, 'MG01', aujourdhui: auj), 5000, reason: 'le fileul lit le prix en vigueur reçu de la mère');

      // 1. Un fileul ne peut PAS écrire une version : la garde « réglé sur la mère » la refuse au moteur du magasin (masquer un bouton ne protège rien).
      appl.demarrer(intervalle: const Duration(hours: 1));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      appl.arreter();
      expect(() => mf.collection('versionsTarif').inserer({'id': 'MG01@2026-11-01@9', 'code': 'MG01', 'version': 9, 'statut': 'valide'}), throwsA(isA<EcritureRefusee>()));
      expect(() => mf.collection('versionsTarif').mettreAJour('MG01@origine@1', {'statut': 'retire'}), throwsA(isA<EcritureRefusee>()));
      // 2. Sa proposition est une DEMANDE (famille B) : rien n'est écrit chez lui, la mère l'applique après avoir refait les contrôles sous le rôle de son auteur.
      final f = poste(mf, 'direction', 'La Direction', fileul: true, etiquette: 'F');
      final avantF = mf.collection('versionsTarif').toutes.length;
      final dem = f.proposer(prop('MG01', 5300));
      expect(dem.ok && dem.depose, isTrue, reason: '${dem.refus}');
      expect(mf.collection('versionsTarif').toutes.length, avantF);
      await converger(() => mm.collection('versionsTarif').toutes.any((v) => v['code'] == 'MG01' && v['statut'] == 'propose'), 'la proposition du fileul devient une version proposée à la mère');
      final v = mm.collection('versionsTarif').toutes.firstWhere((x) => x['code'] == 'MG01' && x['statut'] == 'propose');
      expect([v['proposePar'], v['proposeRole']], ['La Direction', 'direction'], reason: 'la mère applique sous le NOM et le RÔLE de l\'auteur de la demande');
      // Le verdict revient au fileul par la même collection.
      await converger(() => mf.collection('propositionsTarif').toutes.any((d) => d['etat'] == 'appliquee'), 'le verdict revient au fileul');
      expect(mf.collection('propositionsTarif').toutes.single['versionId'], v['id']);
      // Une seconde proposition, sur une autre prestation : la mère l'applique aussi ; la Direction la refusera plus bas (sa décision est elle aussi une demande).
      final mauvaise = f.proposer(prop('MG02', 8100, jours: 4));
      expect(mauvaise.depose, isTrue);
      // Le fileul propose aussi un zéro : refusé AVANT le dépôt (même contrôle), rien n'est déposé.
      expect(f.proposer(DemandeProposition(code: 'MG02', prixNonAssure: 0, etatAssure: 'unique', dateEffet: plus(4), motif: 'x')).refus!.code, 'PRIX_ZERO');
      // 3. La DAF est la mère : elle décide. Le prix bascule le jour dit, chez la mère puis chez le fileul, sans horloge ni connexion.
      expect(daf.decider('${v['id']}', 'oui').ok, isTrue);
      await converger(() => mf.collection('versionsTarif').parId(v['id'])?['statut'] == 'valide', 'la décision de la mère arrive au fileul');
      expect(TarifsPoste.prixActe(mf, 'MG01', aujourdhui: auj, date: plus(2)), 5000, reason: 'la veille de la date d\'effet : l\'ancien prix');
      expect(TarifsPoste.prixActe(mf, 'MG01', aujourdhui: auj, date: plus(3)), 5300, reason: 'le jour dit : le nouveau prix, sans connexion ni horloge');
      // La décision de la Direction (fileul) est une demande, que la mère applique sous le rôle `direction`.
      await converger(() => mf.collection('versionsTarif').toutes.any((x) => x['code'] == 'MG02' && x['statut'] == 'propose'), 'la seconde proposition arrive au fileul, qui peut la trancher');
      final autre = f.decider('${mm.collection('versionsTarif').toutes.firstWhere((x) => x['code'] == 'MG02' && x['statut'] == 'propose')['id']}', 'non', motif: 'Prix hors grille');
      expect(autre.depose, isTrue, reason: '${autre.refus}');
      await converger(() => mm.collection('versionsTarif').toutes.any((x) => x['code'] == 'MG02' && x['statut'] == 'refuse'), 'le Non de la Direction (fileul) est appliqué par la mère');
      expect(mm.collection('versionsTarif').toutes.firstWhere((x) => x['code'] == 'MG02' && x['statut'] == 'refuse')['roleDecision'], 'direction');

      // 4. Un fileul qui n'a pas reçu une version déjà effective facture à l'ANCIEN prix : le prix se calcule à la date de la pièce, sans connexion.
      final hors = Magasin.depuisDossier(Magasin.collectionsDuJeu);
      expect(TarifsPoste.prixActe(hors, 'MG01', aujourdhui: auj, date: plus(3)), 5000, reason: 'avant réception : l\'ancien prix, jamais un prix inventé');

      // 5. JAMAIS un prix, une demande, un refus ni un motif vers un téléphone (RG-13).
      final http0 = HttpClient();
      Future<Map<String, Object?>> appel(String methode, String chemin, {Map<String, Object?>? corps, Map<String, String> entetes = const {}}) async {
        final req = await http0.openUrl(methode, Uri.parse('http://127.0.0.1:$port$chemin'));
        req.headers.contentType = ContentType.json;
        entetes.forEach(req.headers.set);
        if (corps != null) req.add(utf8.encode(jsonEncode(corps)));
        final rep = await req.close();
        return (jsonDecode(await utf8.decoder.bind(rep).join()) as Map).cast<String, Object?>();
      }

      Future<List<String>> recues(String role, Map<String, Object?> extra) async {
        final c = (await appel('POST', '/admin/code', corps: {'etiquette': role, 'role': role, ...extra}, entetes: {'x-admin': 'secret-test'}))['code'];
        final jetons = await appel('POST', '/appairage', corps: {'code': c, 'uuid': 'dev-$role', 'plateforme': 'test'});
        // Le journal est lu PAGE PAR PAGE jusqu'à sa fin : le jeu porte plus de 400 fiches de prix, la première page seule ne prouverait rien.
        final noms = <String>[];
        var depuis = 0;
        while (true) {
          final pull = await appel('GET', '/sync/pull?depuis=$depuis&limite=500&epoch=${jetons['epoch']}', entetes: {'authorization': 'Bearer ${jetons['jeton']}', 'x-sigh-format': '$formatDonneesCourant'});
          if (pull['ops'] == null) fail('pull de $role à $depuis : $pull');
          final ops = (pull['ops'] as List).cast<Map>();
          for (final o in ops) {
            noms.add('${o['collection']}');
            depuis = (o['seq'] as num).toInt();
          }
          if (pull['fin'] == true || ops.isEmpty) break;
        }
        return noms;
      }

      // La mère a écrit les versions, et les demandes ont voyagé : le journal les porte bien (un fileul les reçoit).
      final fileulOps = await recues('fileul', {});
      expect(fileulOps, containsAll(['tarifs', 'versionsTarif', 'propositionsTarif']), reason: 'un fileul reçoit tout');
      final mobileOps = await recues('mobile', {'profil': 'soignant', 'fonction': 'infirmier'});
      expect(mobileOps, isNotEmpty, reason: 'le téléphone lit bien le journal (le reste de la configuration lui est servi) : l\'absence des prix est une EXCLUSION, pas un journal vide');
      expect(mobileOps, isNot(contains('tarifs')), reason: 'le référentiel de prix ne part jamais vers un téléphone');
      expect(mobileOps, isNot(contains('versionsTarif')));
      expect(mobileOps, isNot(contains('propositionsTarif')), reason: 'ni les propositions, ni les refus, ni les motifs');
      http0.close(force: true);
    } finally {
      appl.arreter();
      pub.arreter();
      try {
        await mere0.arreter();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(seconds: 240)));
}
