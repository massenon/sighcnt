import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// Lot MAJ : les règles pures de la mise à jour sans perte (PRD-MISE-A-JOUR). Vecteurs avant et après écrits ici (le format des données est une règle du domaine, pas un écran de la maquette).
CollectionsMaj jeu() => {
      'patients': [
        {'id': 'p1', 'nom': 'Awa', 'telephone': null, 'archive': false},
        {'id': 'p2', 'nom': 'Koffi', 'telephone': '97000000'},
      ],
      'factures': [
        {'id': 'f1', 'total': 5000, 'remise': null, 'lignes': [{'code': 'A', 'note': null}]},
      ],
    };

final maintenant = DateTime(2026, 11, 17, 10);

void main() {
  group('chaîne de migrations', () {
    test('un poste sans version (0) passe par M001 puis M002, vecteur avant et après', () {
      final p = planifierMigration(formatSansVersion);
      expect(p.refus, isNull);
      expect([for (final m in p.etapes) m.id], ['M001', 'M002']);
      final r = executerMigrations(jeu(), p);
      expect(r.formatApres, formatDonneesCourant);
      expect(r.collections['patients']![0], {'id': 'p1', 'nom': 'Awa', 'archive': false}, reason: 'le champ nul est retiré');
      expect(r.collections['patients']![1], {'id': 'p2', 'nom': 'Koffi', 'telephone': '97000000'});
      expect(r.collections['factures']![0]['remise'], isNull);
      expect(r.collections['factures']![0].containsKey('remise'), isFalse);
      expect(r.modifiees, {'patients', 'factures'});
    });

    test('RG-14 : le nom du champ retiré est conservé en ajout seul', () {
      final r = executerMigrations(jeu(), planifierMigration(1));
      final a = r.collections[collectionArchiveMigrations]!;
      expect(a, hasLength(2));
      expect(a.firstWhere((x) => x['collection'] == 'patients')['champsNulsRetires'], ['telephone']);
    });

    test('IDEMPOTENCE : migrer deux fois donne le même résultat (et ne duplique pas l’archive)', () {
      final une = executerMigrations(jeu(), planifierMigration(0));
      final deux = executerMigrations(une.collections, planifierMigration(1)); // on rejoue M002 sur sa propre sortie
      expect(jsonCanonique(deux.collections), jsonCanonique(une.collections));
      expect(deux.collections[collectionArchiveMigrations], hasLength(2));
      expect(planifierMigration(formatDonneesCourant).aRien, isTrue);
    });

    test('IDEMPOTENCE après coupure : rejouer M002 sur les données d’AVANT, archive déjà écrite, ne duplique rien', () {
      final une = executerMigrations(jeu(), planifierMigration(1));
      final rejeu = jeu()..[collectionArchiveMigrations] = [for (final a in une.collections[collectionArchiveMigrations]!) {...a}];
      final deux = executerMigrations(rejeu, planifierMigration(1));
      expect(deux.collections[collectionArchiveMigrations], hasLength(2));
      expect(jsonCanonique(deux.collections), jsonCanonique(une.collections));
    });

    test('l’entrée n’est jamais modifiée (essai à blanc : rien n’est écrit)', () {
      final avant = jsonEncode(jeu());
      final e = jeu();
      final r = executerMigrations(e, planifierMigration(0));
      expect(jsonEncode(e), avant);
      expect(r.notes.join(' '), contains('champ(s) nul(s) retiré(s)'));
    });

    test('DONNEES_PLUS_RECENTES : jamais lues par un logiciel plus ancien', () {
      final p = planifierMigration(formatDonneesCourant + 1);
      expect(p.refus!.code, CodeMaj.donneesPlusRecentes);
      expect(() => executerMigrations(jeu(), p), throwsStateError);
    });

    test('chaîne incomplète : refus nommé, rien n’est inventé', () {
      final p = planifierMigration(0, formatLogiciel: 3, chaine: [migrationsDonnees.first]);
      expect(p.refus!.code, CodeMaj.ecartDeVersion);
    });
  });

  group('comptes et empreintes', () {
    test('« 18 204 avant, 18 204 après »', () {
      final avant = {'patients': const ReleveCollection(18204, 'a')};
      final r = comparerReleves(avant, {'patients': const ReleveCollection(18204, 'a')});
      expect(r.ok, isTrue);
      expect(r.phrase, '18 204 fiches avant, 18 204 après');
    });

    test('un compte différent est NOMMÉ, jamais passé sous silence', () {
      final r = comparerReleves({'patients': const ReleveCollection(10, 'a'), 'factures': const ReleveCollection(5, 'b')}, {'patients': const ReleveCollection(9, 'a'), 'factures': const ReleveCollection(5, 'b')});
      expect(r.ok, isFalse);
      expect(r.differences.single.collection, 'patients');
      expect(r.differences.single.statut, 'COMPTE_DIFFERENT');
      expect(r.phrase, contains('patients (COMPTE_DIFFERENT, 10 avant, 9 après)'));
    });

    test('une empreinte qui change hors migration est une anomalie ; déclarée par la migration, elle passe', () {
      final a = {'p': const ReleveCollection(1, 'x')}, b = {'p': const ReleveCollection(1, 'y')};
      expect(comparerReleves(a, b).differences.single.statut, 'EMPREINTE_DIFFERENTE');
      expect(comparerReleves(a, b, modifieesParMigration: {'p'}).ok, isTrue);
    });

    test('une collection absente après est une anomalie ; ajoutée par la migration, elle est nommée', () {
      expect(comparerReleves({'p': const ReleveCollection(1, 'x')}, {}).differences.single.statut, 'ABSENTE_APRES');
      final r = comparerReleves({'p': const ReleveCollection(1, 'x')}, {'p': const ReleveCollection(1, 'x'), 'archiveMigrations': const ReleveCollection(2, 'z')});
      expect(r.ok, isTrue);
      expect(r.lignes.last.statut, 'AJOUTEE_PAR_MIGRATION');
    });

    test('empreinte indépendante de l’ordre des fiches et des clés', () {
      final a = releverCollections({'c': [{'id': '1', 'a': 1, 'b': 2}, {'id': '2'}]});
      final b = releverCollections({'c': [{'id': '2'}, {'b': 2, 'id': '1', 'a': 1}]});
      expect(a['c']!.empreinte, b['c']!.empreinte);
    });

    test('après la vraie migration, le contrôle des comptes passe : mêmes comptes, empreintes changées seulement là où déclaré', () {
      final c = jeu();
      final avant = releverCollections(c);
      final r = executerMigrations(c, planifierMigration(0));
      final rap = comparerReleves(avant, releverCollections(r.collections), modifieesParMigration: r.modifiees);
      expect(rap.ok, isTrue, reason: rap.phrase);
    });
  });

  group('gardes', () {
    test('MAJ_SANS_SAUVEGARDE : aucune copie, copie trop ancienne, copie du futur', () {
      expect(jugerLancement(geste: true, copieVerifieeLe: null, maintenant: maintenant)!.code, CodeMaj.sansSauvegarde);
      expect(jugerLancement(geste: true, copieVerifieeLe: maintenant.subtract(const Duration(hours: 25)), maintenant: maintenant)!.code, CodeMaj.sansSauvegarde);
      expect(jugerLancement(geste: true, copieVerifieeLe: maintenant.add(const Duration(hours: 1)), maintenant: maintenant)!.code, CodeMaj.sansSauvegarde);
      expect(jugerLancement(geste: true, copieVerifieeLe: maintenant.subtract(const Duration(hours: 23)), maintenant: maintenant), isNull);
    });

    test('l’ancienneté exigée est un réglage, pas une constante', () {
      final r = jugerLancement(geste: true, copieVerifieeLe: maintenant.subtract(const Duration(hours: 5)), maintenant: maintenant, reglages: const ReglagesMaj(ageMaxCopieHeures: 4));
      expect(r!.code, CodeMaj.sansSauvegarde);
    });

    test('le geste réservé est exigé par le moteur', () {
      expect(jugerLancement(geste: false, copieVerifieeLe: maintenant, maintenant: maintenant)!.code, CodeMaj.geste);
    });

    test('MAJ_ECART_DE_VERSION : une version d’écart tolérée, deux refusées, dans les deux sens', () {
      expect(jugerEcartVersion(formatMere: 2, formatFileul: 1), isNull);
      expect(jugerEcartVersion(formatMere: 2, formatFileul: 0)!.code, CodeMaj.ecartDeVersion);
      expect(jugerEcartVersion(formatMere: 2, formatFileul: 0)!.geste, contains('saisies hors ligne sont gardées'));
      expect(jugerEcartVersion(formatMere: 0, formatFileul: 2)!.geste, contains('la mère d’abord'));
      expect(jugerEcartVersion(formatMere: 2, formatFileul: null)!.code, CodeMaj.ecartDeVersion, reason: 'non calculable n’est pas compatible');
      expect(jugerEcartVersion(formatMere: 3, formatFileul: 1, reglages: const ReglagesMaj(ecartVersionTolere: 2)), isNull);
    });
  });

  group('import', () {
    JugementImport j({bool geste = true, bool cle = true, String? exp = 'K', String? loc = 'K', bool sig = true, int fmt = 2, bool copie = true, bool fileul = false, DateTime? exporte, DateTime? synchro}) =>
        jugerImport(geste: geste, cleLocalePresente: cle, empreinteCleExport: exp, empreinteCleLocale: loc, signatureValide: sig, formatExport: fmt, copieLocaleVerifiee: copie, fileulRattache: fileul, exporteLe: exporte, derniereSynchro: synchro);

    test('accepté quand tout est réuni', () => expect(j().accepte, isTrue));
    test('sans clé : IMPORT_SANS_CLE', () {
      expect(j(cle: false).refus!.code, CodeMaj.importSansCle);
      expect(j(loc: null).refus!.code, CodeMaj.importSansCle);
    });
    test('autre clinique', () => expect(j(exp: 'AUTRE').refus!.code, CodeMaj.importAutreClinique));
    test('altéré', () => expect(j(sig: false).refus!.code, CodeMaj.importAltere));
    test('plus récent que le logiciel', () => expect(j(fmt: 3).refus!.code, CodeMaj.donneesPlusRecentes));
    test('sans copie préalable', () => expect(j(copie: false).refus!.code, CodeMaj.importSansCopie));
    test('geste réservé', () => expect(j(geste: false).refus!.code, CodeMaj.geste));
    test('fileul : base plus ancienne que la dernière synchro = avertissement NON bloquant', () {
      final r = j(fileul: true, exporte: DateTime(2026, 11, 10), synchro: DateTime(2026, 11, 16));
      expect(r.accepte, isTrue);
      expect(r.avertissements.single, startsWith('IMPORT_PLUS_ANCIEN_QUE_SYNC'));
      expect(j(fileul: true, exporte: DateTime(2026, 11, 17), synchro: DateTime(2026, 11, 16)).avertissements, isEmpty);
      expect(j(fileul: false, exporte: DateTime(2026, 11, 10), synchro: DateTime(2026, 11, 16)).avertissements, isEmpty);
    });
  });

  group('retour arrière', () {
    test('liste les saisies postérieures : créées, modifiées, jamais écrasées en silence', () {
      final copie = jeu();
      final actuel = jeu();
      actuel['patients']!.add({'id': 'p3', 'nom': 'Nouveau'});
      actuel['patients']![1]['nom'] = 'Koffi Modifié';
      final s = saisiesPosterieures(copie, actuel);
      expect([for (final x in s) '${x.collection}/${x.fiche}:${x.nature}'], unorderedEquals(['patients/p3:creee', 'patients/p2:modifiee']));
    });

    test('une fiche qui a disparu est nommée (RG-14 : ne devrait jamais arriver)', () {
      final actuel = jeu()..['patients']!.removeAt(0);
      expect(saisiesPosterieures(jeu(), actuel).single.nature, 'absente_maintenant');
    });

    test('refus sans copie vérifiée et sans geste', () {
      expect(jugerRetourArriere(geste: true, copieVerifiee: false, copie: jeu(), actuel: jeu()).refus!.code, CodeMaj.retourSansCopie);
      expect(jugerRetourArriere(geste: true, copieVerifiee: true, copie: null, actuel: jeu()).refus!.code, CodeMaj.retourSansCopie);
      expect(jugerRetourArriere(geste: false, copieVerifiee: true, copie: jeu(), actuel: jeu()).refus!.code, CodeMaj.geste);
      expect(jugerRetourArriere(geste: true, copieVerifiee: true, copie: jeu(), actuel: jeu()).saisies, isEmpty);
    });
  });
}
