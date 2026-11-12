import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/demandes_import_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/port_magasin.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/service_demandes_import.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// LA DEMANDE D'IMPORT ENTRE UN FILEUL ET LA MÈRE (lot IMP-C, réponse Q5), contre la VRAIE mère et un VRAI moteur de fileul :
///  - la demande vérifiée d'un fileul (famille A, `demandesImport`) arrive à la mère par le pont, qui la TRAITE (analyse rejouée sous le rôle de l'auteur) ;
///  - le lot est écrit à la mère au nom de l'auteur, puis voyage au fileul par la configuration ; le VERDICT nommé revient sur la même fiche, les lignes du fichier effacées ;
///  - un autre poste a créé la même fiche entre-temps : la mère refuse en nommant, rien n'est écrit ;
///  - JAMAIS une demande d'import, ses lignes ni son verdict vers un téléphone (RG-13) : l'exclusion est posée, le journal du téléphone n'est pas vide.
typedef M = Map<String, Object?>;
final donnees = DonneesNavigation.depuisDossier();
final vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/import.json').readAsStringSync()) as Map).cast<String, Object?>();

Magasin vide() => Magasin({
      for (final e in (vecteurs['magasin'] as Map).entries) '${e.key}': [for (final f in (e.value as List)) (f as Map).cast<String, Object?>()],
      'audit': const [],
    });

void main() {
  test('BOUT EN BOUT : le fileul dépose, la mère traite et répond sur la même fiche ; le lot descend au fileul ; une fiche créée ailleurs refuse la seconde demande ; rien vers un mobile', () async {
    const port = 19472;
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-demandes-import'));
    await mere0.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteur = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1', nom: 'Gestionnaire');
    final mm = vide(), mf = vide();
    final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero, collections: {...collectionsConfiguration()});
    final appl = ApplicateurConfiguration(mf, moteur.liste);
    final pontM = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M');
    final pontF = PontActivite(
        mf,
        TransportFileul(lire: moteur.liste, ecrireFiche: (c, f, {required existe, required champs}) => moteur.ecrire(c, f, existe: existe, champs: champs)),
        etiquette: 'F');
    final service = ServiceDemandesImport(mm, donnees: () async => donnees, horloge: () => DateTime(2026, 11, 1));
    Future<void> converger(bool Function() fini, String quoi) async {
      final fin = DateTime.now().add(const Duration(seconds: 40));
      while (!fini()) {
        await pub.pousser();
        await appl.tirer();
        await pontF.cycle();
        await pontM.cycle();
        await service.traiter();
        if (DateTime.now().isAfter(fin)) fail('$quoi : pas de convergence (pub ${pub.erreur.value}, appl ${appl.erreur.value}, pontF ${pontF.erreur.value}, pontM ${pontM.erreur.value}, service ${service.derniereErreur})');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    // Le fileul vérifie le fichier (même analyse que la mère), puis dépose. Le fichier est celui de la maquette (`fo-valide`) ; ici le jeu `assureurs` (la compagnie SUNU et OLEA).
    final lignes = [
      for (final l in (vecteurs['cas'] as List).cast<Map>().firstWhere((c) => c['id'] == 'as-valide')['lignes'] as List) [for (final x in l as List) x]
    ];
    Fiche deposer(String jeu, List<List<Object?>> l, String id) {
      final profil = ProfilImport(role: 'comptable', libelleRole: 'Comptable', matrice: donnees.matrice.matriceImport);
      final a = analyserLignes(jeuImportParId(jeu)!, l, 'compagnies.xlsx', PortMagasin(mf, aujourdhui: () => DateTime(2026, 11, 1), nomAgent: 'LE COMPTABLE', profil: profil));
      expect(a.accepte, isTrue, reason: '${[for (final p in a.problemes) '${p.code}:${p.motif}']}');
      final d = DemandesImportPoste(mf, role: 'comptable', auteur: () => 'LE COMPTABLE', matrice: donnees.matrice, aujourdhui: () => DateTime(2026, 11, 1), etiquette: id).deposer(jeuImportParId(jeu)!, a);
      return d;
    }

    try {
      final code = await console.codeAppareil('Gestionnaire').timeout(const Duration(seconds: 20));
      await moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
      moteur.demarrer();
      final d1 = deposer('assureurs', lignes, 'F1');
      expect(mf.collection('assureurs').actives.where((a) => a['code'] == 'SUNU'), isEmpty, reason: 'rien n\'est écrit chez le fileul');
      await converger(() => mf.collection(demandesImportCollection).parId('${d1['id']}')?['etat'] == demandeImportAppliquee, 'le verdict de la mère revient au fileul');
      final v = mf.collection(demandesImportCollection).parId('${d1['id']}')!;
      expect(v['resultatEcrits'], 2);
      expect(v['lignes'], isEmpty, reason: 'les lignes du fichier sont effacées au verdict, chez le fileul aussi');
      expect(v['traitePar'], 'Mère');
      // La mère a écrit le lot AU NOM de l'auteur (RG-12) ; il descend au fileul par la configuration (famille R).
      final surMere = mm.collection('assureurs').actives.where((a) => a['lotImport'] == v['resultatLot']).toList();
      expect(surMere.map((a) => a['code']).toSet(), {'SUNU', 'OLEA'});
      expect(surMere.every((a) => a['validePar'] == 'LE COMPTABLE'), isTrue);
      await converger(() => mf.collection('assureurs').actives.any((a) => a['code'] == 'OLEA'), 'le lot écrit par la mère arrive au fileul');

      // UN AUTRE POSTE A CRÉÉ LA MÊME FICHE entre la vérification du fileul et le traitement par la mère : la mère REJOUE, refuse en nommant, n'écrit rien.
      final lignes2 = [
        [for (final c in jeuAssureurs.colonnes) c.label],
        [for (final c in jeuAssureurs.colonnes) const {'code': 'GAB', 'nom': 'GAB ASSURANCES', 'convention': 'Signée'}[c.cle] ?? ''],
      ];
      final d2 = deposer('assureurs', lignes2, 'F2');
      mm.collection('assureurs').inserer({'id': 'ASS-AILLEURS', 'code': 'GAB', 'nom': 'GAB (créée par un autre poste)', 'statut': 'actif'}, prefixe: 'ASS');
      final avant = mm.collection('assureurs').toutes.length;
      await converger(() => mf.collection(demandesImportCollection).parId('${d2['id']}')?['etat'] == demandeImportRefusee, 'le refus nommé de la mère revient au fileul');
      final r = mf.collection(demandesImportCollection).parId('${d2['id']}')!;
      expect(r['resultatCode'], 'DOUBLON_MAGASIN');
      expect(r['resultatMotif'], contains('rejoué à la mère'));
      expect(r['resultatGeste'], isNotEmpty);
      expect(mm.collection('assureurs').toutes.length, avant, reason: 'rien n\'a été écrit');

      // JAMAIS vers un téléphone (RG-13) : ni les lignes d'un fichier, ni le verdict.
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
        final noms = <String>[];
        var depuis = 0;
        while (true) {
          final pull = await appel('GET', '/sync/pull?depuis=$depuis&limite=500&epoch=${jetons['epoch']}', entetes: {'authorization': 'Bearer ${jetons['jeton']}'});
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

      final fileulOps = await recues('fileul', {});
      expect(fileulOps, contains(demandesImportCollection), reason: 'un fileul reçoit les demandes et leur verdict');
      final mobileOps = await recues('mobile', {'profil': 'soignant', 'fonction': 'infirmier'});
      expect(mobileOps, isNotEmpty, reason: 'le téléphone lit bien le journal : l\'absence des demandes est une EXCLUSION, pas un journal vide');
      expect(mobileOps, isNot(contains(demandesImportCollection)), reason: 'ni les lignes d\'un fichier, ni le verdict ne partent vers un téléphone');
      http0.close(force: true);
    } finally {
      appl.arreter();
      pub.arreter();
      service.arreter();
      try {
        await mere0.arreter();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(seconds: 240)));
}
