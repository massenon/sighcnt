import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/core/plages_codes.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/etat_sync.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/reservation_stock.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// PANNE DE CONNEXION (exigence de la Direction, 06/11/2026) : « les activités fileul et mère doivent continuer ». Les VRAIES pièces, dans le processus de test :
/// la mère (service sur fichier), un moteur fileul réel, le pont d'activité et la réservation de stock. La mère s'arrête ; le fileul saisit un dossier, sort du
/// stock dans sa part, la pastille dit « hors ligne » depuis quand ; la mère revient : tout remonte, une seule fois, et la pastille redit « synchronisé ».
typedef M = Map<String, Object?>;
const cleSqlite = '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';

Magasin poste() => Magasin({
      'produits': [
        {'id': 'PRD1', 'designation': 'Paracétamol', 'stockGros': 10, 'stockDetail': 0, 'stock': 10}
      ],
      'patients': <M>[],
    });

Future<void> _attendre(bool Function() condition, String quoi, {int secondes = 30}) async {
  final fin = DateTime.now().add(Duration(seconds: secondes));
  while (!condition()) {
    if (DateTime.now().isAfter(fin)) fail('délai dépassé : $quoi');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  test('COUPURE puis RETOUR : le fileul coupé de la mère saisit, sort du stock dans sa part, la pastille le dit ; la mère revient, tout remonte UNE fois', () async {
    const port = 19461;
    final d = Directory.systemTemp.createTempSync('panne');
    addTearDown(() => d.deleteSync(recursive: true));
    ConfigMere config() => ConfigMere(port: port, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '${d.path}/sauvegardes', cleStockage: cleSqlite);
    var mere = await Mere.creer(config());
    await mere.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteur = MoteurFileul.creer(dbChemin: '${d.path}/f.db', mere: 'http://127.0.0.1:$port', nom: 'Caisse', cleStockage: cleSqlite);
    final source = moteur.source(intervalle: const Duration(milliseconds: 200));
    final mm = poste(), mf = poste();
    final pm = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M');
    final pf = PontActivite(
        mf,
        TransportFileul(lire: moteur.liste, ecrireFiche: (c, f, {required existe, required champs}) => moteur.ecrire(c, f, existe: existe, champs: champs)),
        enLectureSeule: collectionsDeLaMereSeule,
        etiquette: 'F',
        liaison: () async {
          final i = await moteur.instantane();
          return !i.horsLigne && !i.suspendu;
        });
    // L'horloge de la réservation de stock est INJECTÉE : « hors ligne » se déduit de l'âge de la dernière synchronisation (fraîcheur de quelques minutes),
    // et la coupure doit donc « durer » ; on avance l'horloge comme le ferait le temps.
    var horloge = DateTime.now();
    ReservationStock.de(mf)
      ..actif = true
      ..maintenant = (() => horloge)
      ..installer(mf);
    try {
      // 1. appairage et liaison
      final code = await console.codeAppareil('Caisse');
      await moteur.appairer(code);
      moteur.demarrer();
      await _attendre(() => source.value.niveau == NiveauSync.synchronise, 'pastille synchronisée');
      for (var i = 0; i < 3; i++) {
        await pf.cycle();
        await pm.cycle();
      }
      expect(ReservationStock.de(mf).horsLigne, isFalse, reason: 'en liaison, aucune part ne s’applique');
      // La plage de numéros (RG-01) est RÉSERVÉE auprès de la mère pendant la liaison : hors ligne, le poste numérote dedans.
      PlagesCodes.de(mf).obtenir = (t, mi) => moteur.demanderPlage(taille: t, minimum: mi);
      await PlagesCodes.de(mf).recharger(maintenant: horloge);
      expect(PlagesCodes.de(mf).restants, 50, reason: 'le poste détient sa plage avant la coupure');

      // 2. COUPURE : la mère s'arrête. Le poste continue, et le DIT.
      await mere.arreter();
      await _attendre(() => source.value.niveau == NiveauSync.horsLigne, 'pastille hors ligne');
      expect(source.value.depuis, isNotNull, reason: 'depuis quand, jamais un voyant muet');
      final codePatient = PlagesCodes.de(mf).prochainCode(mf.collection('patients').toutes, horloge);
      expect(codePatient, matches(RegExp(r'^CNT/\d+/\d{2}$')), reason: 'un numéro de SA plage, pas un provisoire');
      final patient = mf.collection('patients').inserer({'nom': 'ADJOVI', 'prenom': 'Rose', 'code': codePatient}, prefixe: 'PAT').fiche;
      expect(mf.collection('patients').toutes, hasLength(1), reason: 'la saisie locale ne dépend d’aucun réseau');
      horloge = horloge.add(const Duration(minutes: 10));
      await pf.cycle(); // le pont écrit dans la file LOCALE du moteur : il réussit sans la mère
      expect(ReservationStock.de(mf).horsLigne, isTrue, reason: 'la liaison dit la vérité : la mère n’est pas atteinte');
      // le stock sort dans la PART du poste (un seul poste connu : toute la quantité connue), jamais au-delà
      mf.collection('produits').mettreAJour('PRD1', {'stockGros': 7});
      expect(() => mf.collection('produits').mettreAJour('PRD1', {'stockGros': -1}), throwsA(isA<EcritureRefusee>()), reason: 'RG-03 : jamais négatif');
      await pf.cycle();
      final enAttente = (await moteur.instantane()).enAttente;
      expect(enAttente, greaterThan(0), reason: 'les gestes hors ligne attendent dans la file persistée, rien n’est perdu');
      expect(mm.collection('patients').toutes, isEmpty, reason: 'la mère coupée n’a rien reçu');

      // 3. RETOUR : la mère repart sur SA base (fichier) ; le moteur rattrape seul.
      mere = await Mere.creer(config());
      await mere.demarrer();
      await _attendre(() => source.value.niveau == NiveauSync.synchronise, 'pastille synchronisée après le retour', secondes: 45);
      final fin = DateTime.now().add(const Duration(seconds: 45));
      while (mm.collection('patients').toutes.length != 1 || mm.collection('produits').parId('PRD1')!['stockGros'] != 7) {
        await pf.cycle();
        await pm.cycle();
        if (DateTime.now().isAfter(fin)) {
          final i = await moteur.instantane();
          fail('pas de convergence : mère ${mm.collection('patients').toutes.length} dossier(s), stock ${mm.collection('produits').parId('PRD1')!['stockGros']} ; attente ${i.enAttente} refus ${i.aTraiter} ${i.derniereErreur} ; refusées : ${await moteur.refusees()}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(mm.collection('patients').toutes.single['nom'], 'ADJOVI');
      expect(mm.collection('patients').toutes.single['code'], codePatient, reason: 'le code attribué hors ligne, dans la plage du poste, n’est pas renuméroté (RG-01)');
      horloge = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await pf.cycle();
        await pm.cycle();
      }
      expect(mm.collection('patients').toutes, hasLength(1), reason: 'remonté UNE fois, pas deux');
      expect(mf.collection('patients').toutes, hasLength(1), reason: 'aucun écho chez l’auteur');
      expect((await moteur.instantane()).enAttente, 0, reason: 'plus rien en attente');
      expect((await moteur.instantane()).aTraiter, 0, reason: 'aucun refus');
      expect(ReservationStock.de(mf).horsLigne, isFalse);
      expect(patient['id'], isNotNull);
    } finally {
      pf.arreter();
      pm.arreter();
      source.dispose();
      try {
        await mere.arreter();
      } catch (_) {/* déjà arrêtée */}
    }
  }, timeout: const Timeout(Duration(seconds: 180)));
}
