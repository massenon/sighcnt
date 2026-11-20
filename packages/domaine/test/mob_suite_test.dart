// Rejoue les vecteurs de la suite du mobile (prototype_html/build/vecteurs-mobile-suite.js) : CPN, CPoN, surveillance mère-bébé, orientation de la
// réception, réglages, lot de tournée et code PIN, PILOTÉS dans Chrome sur les pages du simulateur. Les écarts portés volontairement sont nommés
// dans le test qui les touche (ECARTS-MAQUETTE E1650 à E1660).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_domaine/src/mobile/mob_donnees.dart' show mobDonnees;
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

void main() {
  final v = lireVecteurs('mobile_suite');
  Map<String, String> saisie(Object? m) => {for (final e in (m as Map).entries) '${e.key}': '${e.value}'};
  Map<String, Object?> m(Object? o) => (o as Map).cast<String, Object?>();
  final maintenant = DateTime(2026, 10, 31, 10);

  group('CPN : bornes, messages, alerte, résumé mis en file', () {
    final cpn = m(v['cpn']);
    test('${liste(cpn['cas']).length} cas pilotés : erreurs par champ, libellé et détail de l\'opération, toast d\'alerte', () {
      for (final c in liste(cpn['cas'])) {
        final s = saisie(c['saisie']);
        final erreurs = mobErreursCpn(s);
        if (s['hu'] == 'texte') {
          // E1650 : le simulateur accepte « texte » comme hauteur utérine ; le mobile le refuse (message de `valider`).
          expect(c['erreurs'], isEmpty);
          expect(erreurs, {'hu': 'La hauteur utérine doit être un nombre.'});
          continue;
        }
        expect(erreurs, saisie(c['erreurs']), reason: 'saisie $s');
        final op = c['op'] as Map?;
        if (op == null) continue;
        final r = mobCpnResume('SOUROU Mariam', s);
        expect(r.libelle, op['libelle'], reason: '$s');
        expect(r.detail, op['detail'], reason: '$s');
        final toasts = (c['toasts'] as List).cast<String>();
        expect(mobCpnAlerte(s), toasts.length == 2, reason: '$s');
        if (toasts.length == 2) expect(toasts.first, mobCpnToastAlerte);
        expect(toasts.last, mobToastEnregistreEnLigne);
      }
    });

    test('âge à risque : la note de la page pour chacun des quatre patients du lot, fenêtre lue au rapport de maternité', () {
      final ages = {'p1': 67, 'p2': 29, 'p3': 8, 'p4': 31};
      for (final e in m(cpn['risque']).entries) {
        expect(mobCpnNoteAge(ages[e.key]), m(e.value)['note'], reason: e.key);
      }
      expect(mobCpnAgeARisque(17), isTrue);
      expect(mobCpnAgeARisque(18), isFalse);
      expect(mobCpnAgeARisque(35), isFalse);
      expect(mobCpnAgeARisque(36), isTrue);
      expect(mobCpnAgeARisque(null), isFalse, reason: 'un âge inconnu ne signale rien');
    });

    test('les champs obligatoires de la page sont ceux des règles', () {
      final requis = {for (final c in mobChampsEcran('cpn')) if (c.requis) c.id};
      expect(requis, {for (final r in mobReglesCpn) if (r.requis) r.champ});
      expect(mobChampsEcran('cpn').map((c) => c.id), ['sa', 'poids', 'sys', 'dia', 'hu', 'bcf', 'presentation', 'sp', 'milda', 'proteinurie', 'rdv']);
      expect(mobCartesEcran('cpn'), ['Examen', 'Prévention']);
    });

    test('la ligne de journal garde toutes les mesures, nomme l\'acteur, jamais une suppression', () {
      final f = mobChampsCpn(
          patient: {'code': 'CNT/913/25', 'nom': 'SOUROU', 'prenom': 'Mariam'},
          patientId: 'p4',
          saisie: {'sa': '28', 'poids': '62,5', 'sys': '140', 'dia': '80', 'bcf': '140', 'hu': '27', 'sp': 'SP 2', 'milda': 'Non', 'proteinurie': '+', 'rdv': '2026-11-14'},
          acteur: 'Sage-femme de garde',
          fonction: 'sage_femme',
          maintenant: maintenant);
      expect(f['termeSA'], 28);
      expect(f['poids'], 62.5);
      expect(f['tension'], '140/80');
      expect(f['aRisque'], isTrue);
      expect(f['sp'], 'SP 2');
      expect(f['milda'], 'Non');
      expect(f['presentation'], 'Céphalique', reason: 'une liste sans choix prend sa première entrée, comme le <select>');
      expect(f['prochainRdv'], '2026-11-14');
      expect(f['redigePar'], 'Sage-femme de garde');
      expect(f['origine'], 'mobile');
      expect(() => mobChampsCpn(patient: const {}, patientId: 'p', saisie: const {}, acteur: 'x', fonction: 'sage_femme', maintenant: maintenant),
          throwsA(isA<RefusMobile>().having((e) => e.code, 'code', 'SAISIE_INVALIDE').having((e) => e.champs.keys, 'champs', containsAll(['sa', 'poids', 'sys', 'dia']))));
      expect(mobErreursCpn({'sa': '28', 'poids': '60', 'sys': '120', 'dia': '80', 'sp': 'SP 9'}).keys, ['sp'], reason: 'un choix étranger à la liste est refusé en le nommant');
    });
  });

  group('CPoN', () {
    test('${liste(m(v['cpon'])['cas']).length} cas pilotés : erreurs, libellé et détail (« cordon » en minuscules)', () {
      for (final c in liste(m(v['cpon'])['cas'])) {
        final s = saisie(c['saisie']);
        expect(mobErreursCpon(s), saisie(c['erreurs']), reason: '$s');
        final op = c['op'] as Map?;
        if (op == null) continue;
        final r = mobCponResume('KPOGNON Rose', s);
        expect(r.libelle, op['libelle']);
        expect(r.detail, op['detail']);
      }
    });

    test('la ligne de journal : mère et nouveau-né, acteur nommé', () {
      final f = mobChampsCpon(
          patient: {'code': 'CNT/174/26', 'nom': 'KPOGNON', 'prenom': 'Rose'},
          patientId: 'p2',
          saisie: {'ta': '12/8', 't': '38,6', 'pb': '3200', 'jour': 'J7', 'cordon': 'Infecté'},
          acteur: 'Sage-femme de garde',
          fonction: 'sage_femme',
          maintenant: maintenant);
      expect(f['jourPostNatal'], 'J7');
      expect(f['temperature'], 38.6);
      expect(f['poidsNouveauNe'], 3200);
      expect(f['cordon'], 'Infecté');
      expect(f['lochies'], 'Normales');
      expect(f['allaitement'], 'Exclusif');
    });
  });

  group('surveillance mère-bébé', () {
    test('${liste(m(v['surveillance'])['cas']).length} cas pilotés : tout est facultatif, trois bornes, résumé « mère — · bébé FR — »', () {
      for (final c in liste(m(v['surveillance'])['cas'])) {
        final s = saisie(c['saisie']);
        expect(mobErreursSurveillance(s), saisie(c['erreurs']), reason: '$s');
        final op = c['op'] as Map?;
        if (op == null) continue;
        final r = mobSurveillanceResume(s);
        expect(r.libelle, op['libelle']);
        expect(r.detail, op['detail']);
      }
    });

    test('la ligne de journal se rattache à une patiente (E1652) et ne garde que les mesures données', () {
      final f = mobChampsSurveillance(
          patient: {'code': 'CNT/913/25', 'nom': 'SOUROU', 'prenom': 'Mariam'},
          patientId: 'p4',
          saisie: {'heure': 'H12', 'mta': '12/8', 'bfr': '40'},
          acteur: 'Sage-femme de garde',
          fonction: 'sage_femme',
          maintenant: maintenant);
      expect(f['patientId'], 'p4');
      expect(f['temps'], 'H12');
      expect(f['mereTension'], '12/8');
      expect(f['bebeFr'], 40);
      expect(f.containsKey('merePouls'), isFalse);
      expect(f['mereSaignement'], 'Normal');
    });
  });

  group('orientation de la réception', () {
    final o = m(v['orientation']);
    test('les listes de la page et le texte sans dossier', () {
      expect(mobOrientationDestinations, ['Médecin de garde', 'Laboratoire', 'Salle de soins', 'Maternité', 'Caisse (dès retour du courant)', 'Référence vers un autre établissement']);
      expect(mobOrientationDegres, ['Normal', 'Urgent', 'Très urgent']);
      expect(mobOrientationVide, m(o['sansDossier'])['vide']);
      expect(() => mobControlerOrientation(const []), throwsA(isA<RefusMobile>().having((e) => e.code, 'code', 'SANS_DOSSIER')));
      expect(() => mobControlerOrientation([<String, Object?>{}]), returnsNormally);
    });

    test('${liste(o['cas']).length} cas pilotés (6 destinations x 3 degrés) : libellé et détail de l\'opération', () {
      for (final c in liste(o['cas'])) {
        final dossier = {'code': 'PROV-1', 'nom': 'HOUNKPATIN', 'prenom': 'Ida'};
        expect(mobOrientationChoix(dossier), c['patient']);
        final f = mobChampsOrientation(dossier: dossier, dossierId: 'd2', destination: '${c['dest']}', degre: '${c['urg']}', acteur: 'OROU YO Edmond', maintenant: maintenant);
        final op = m(c['op']);
        expect(f['libelle'], op['libelle']);
        expect(f['detail'], op['detail']);
        expect(f['orientePar'], 'OROU YO Edmond');
        expect((c['toasts'] as List).single, mobToastEnregistreEnLigne);
      }
      expect(m(o['horsLigne'])['etat'], 'en_attente');
      expect((m(o['horsLigne'])['toasts'] as List).single, mobToastEnregistreHorsLigne);
      expect(() => mobChampsOrientation(dossier: const {}, dossierId: 'd', destination: 'Bloc', degre: 'Normal', acteur: 'x', maintenant: maintenant),
          throwsA(isA<RefusMobile>().having((e) => e.champs.keys, 'champs', ['dest'])));
    });
  });

  group('droits : le profil du simulateur ouvre ou ferme l\'écran', () {
    test('les dix écrans fermés relevés sur les pages : même motif, mot pour mot', () {
      for (final e in m(v['fermes']).entries) {
        final parts = e.key.split('/');
        expect(mobEcranOuvertAuProfil(parts[1], parts[0]), isFalse, reason: e.key);
        expect(mobRefusEcranFerme(parts[1], parts[0]).motif, m(e.value)['note'], reason: e.key);
        expect(() => mobControlerEcran(parts[1], parts[0]), throwsA(isA<RefusMobile>().having((r) => r.code, 'code', 'ECRAN_FERME_AU_PROFIL')));
      }
    });

    test('le profil réception de secours n\'écrit pas ce que le soignant écrit, et inversement', () {
      for (final e in ['cpn', 'cpon', 'surveillance', 'lot']) {
        expect(mobEcranOuvertAuProfil('reception', e), isFalse, reason: e);
      }
      expect(mobEcranOuvertAuProfil('reception', 'orientation'), isTrue);
      for (final p in ['soignant', 'medecin', 'sagefemme']) {
        expect(mobEcranOuvertAuProfil(p, 'orientation'), isFalse, reason: p);
        expect(mobEcranOuvertAuProfil(p, 'lot'), isTrue, reason: p);
      }
      expect(mobEcranOuvertAuProfil('sagefemme', 'cpn'), isTrue);
      expect(mobEcranOuvertAuProfil('sagefemme', 'cpon'), isTrue);
      expect(mobEcranOuvertAuProfil('sagefemme', 'surveillance'), isTrue);
      for (final p in ['soignant', 'medecin']) {
        for (final e in ['cpn', 'cpon', 'surveillance']) {
          expect(mobEcranOuvertAuProfil(p, e), isFalse, reason: '$p $e');
        }
      }
    });

    test('les écrans par profil concordent avec le relevé de la première vague (mob_donnees) pour les trois profils cliniques', () {
      for (final p in ['soignant', 'medecin', 'sagefemme']) {
        expect(mobEcransDuProfil(p), ((mobDonnees['profils'] as Map)[p] as Map)['ecrans'], reason: p);
      }
      expect(mobProfilDe(reception: true), 'reception');
      expect(mobProfilDe(reception: false, fonction: 'sage_femme'), 'sagefemme');
      expect(mobProfilDe(reception: false, fonction: 'infirmier'), 'soignant');
    });

    test('rbac.json (le poste) : le rôle de la sage-femme écrit la CPN et la CPoN, la réception n\'a aucun écran de maternité (E1659 : le mobile ferme CPN au médecin que le poste laisse écrire)', () {
      final rbac = m(jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()));
      final par = m(rbac['parRole']);
      for (final e in ['m4-cpn', 'm4-cpon']) {
        expect((m(par['infirmier'])[e] as List)[1], 1, reason: 'infirmier / sage-femme édite $e au poste');
        expect(m(par['reception']).containsKey(e), isFalse, reason: 'la réception n\'a pas $e');
        expect((m(par['medecin'])[e] as List)[1], 1, reason: 'le poste laisse le médecin écrire $e : le simulateur du mobile le lui ferme (plus restrictif)');
      }
      expect((m(par['reception'])['m1-patients'] as List)[1], 1, reason: 'la réception édite le répertoire : c\'est d\'elle que part l\'orientation');
    });
  });

  group('lot de tournée', () {
    final lot = m(v['lot']);
    test('${liste(lot['cas']).length} cas pilotés : validité restante arrondie comme la page, jamais négative', () {
      final base = DateTime(2026, 10, 31, 8);
      for (final c in liste(lot['cas'])) {
        final delta = (c['deltaMs'] as num).toInt();
        final vue = mobLotVue(expire: base.millisecondsSinceEpoch + delta, dossiers: 4, maintenant: base);
        expect(vue.validite, c['validite'], reason: '${c['nom']}');
        expect(vue.etat, delta <= 0 ? MobEtatLot.expire : MobEtatLot.valide, reason: '${c['nom']}');
      }
    });

    test('les textes de la page, et les trois états', () {
      expect(mobLotNote, (m(lot['defaut'])['notes'] as List).cast<Map>().first['texte']);
      expect(mobLotCarte, 'Lot du jour');
      expect(mobLotCompteurs, ['Dossiers', 'Validité restante']);
      final a = mobLotVue(expire: null, dossiers: 0, maintenant: maintenant);
      expect(a.etat, MobEtatLot.aucun);
      expect(a.texteExpiration, isNull);
      final b = mobLotVue(expire: DateTime(2026, 10, 31, 20, 30).millisecondsSinceEpoch, dossiers: 4, maintenant: maintenant);
      expect(b.texteExpiration, 'Expire le 31/10/2026 à 20h30');
      final c = mobLotVue(expire: DateTime(2026, 10, 31, 9).millisecondsSinceEpoch, dossiers: 4, maintenant: maintenant);
      expect(c.texteExpiration, 'A expiré le 31/10/2026 à 09h00');
      expect(c.etat, MobEtatLot.expire);
    });
  });

  group('réglages', () {
    test('lignes, confirmation et appareil par profil viennent de la page', () {
      final r = m(v['reglages']);
      expect(mobReglagesLignes.map((l) => l.titre), ['Verrouillage automatique', 'Effacement à distance', 'Notifications']);
      expect(mobReglagesLignes.map((l) => l.fin), ['Activé', 'Actif', 'Activées']);
      expect(mobReglagesConfirmation, m(r['confirmation'])['message']);
      expect(mobReglagesBouton, 'Réinitialiser l’appairage');
      expect(mobDelaiVerrouInactivite, const Duration(minutes: 5));
      final t = mobReglagesTelephone(profil: 'sagefemme', agent: 'Sage-femme de garde', appareil: 'u-09', version: '0.1.0+1');
      expect(t.profil, 'Sage-femme');
      expect(t.appareil, 'Appareil u-09 · version 0.1.0+1');
      expect(mobReglagesTelephone(profil: 'reception', agent: 'x', version: '1').appareil, startsWith('Appareil non communiqué'));
      for (final p in m(r['profils']).keys) {
        expect(mobLibelleProfil(p), ((m(m(r['profils'])[p])['textes']) as List)[1], reason: p);
      }
    });

    test('la réinitialisation est confirmée ; accepter ramène à l\'appairage ; des saisies non parties la REFUSENT en le disant (E1655)', () {
      final r = m(v['reglages']);
      expect(m(r['confirmation'])['urlApres'], 'parametres.php', reason: 'refuser la confirmation ne change rien');
      expect(m(r['acceptation'])['urlApres'], 'appairage.php');
      expect(() => mobControlerReinitialisation(0), returnsNormally);
      expect(() => mobControlerReinitialisation(3), throwsA(isA<RefusMobile>().having((e) => e.code, 'code', 'SAISIES_NON_ENVOYEES').having((e) => e.motif, 'motif', contains('3 saisies'))));
      expect(() => mobControlerReinitialisation(1), throwsA(isA<RefusMobile>().having((e) => e.motif, 'motif', contains('Une saisie n’est pas encore partie'))));
    });
  });

  group('code PIN', () {
    final pin = m(v['pin']);
    test('le pavé et l\'invite sont ceux de la page', () {
      expect(mobPinPave, pin['pave']);
      expect(mobPinInvite, 'Saisissez votre code à 4 chiffres.');
      expect(mobPinTitre, 'Code PIN');
    });

    test('${liste(pin['sequences']).length} séquences de touches pilotées : points, message, ouverture, blocage (touches ignorées une fois bloqué)', () async {
      for (final s in liste(pin['sequences'])) {
        final p = MobPin(CoffrePinMemoire('1234'), horloge: () => maintenant);
        for (final pas in liste(s['pas'])) {
          final e = await p.touche('${pas['touche']}');
          final reason = '${(s['touches'] as List).join()} à la touche ${pas['touche']}';
          if (pas['url'] != 'verrou.php') {
            expect(e.deverrouille, isTrue, reason: reason);
            expect(pas['url'], 'accueil-soignant.php');
          } else {
            expect(e.deverrouille, isFalse, reason: reason);
            expect(e.points, pas['points'], reason: reason);
            expect(e.message, pas['msg'], reason: reason);
          }
        }
      }
    });

    test('chaque profil arrive sur son accueil', () {
      expect(m(pin['accueilParProfil']).keys, ['soignant', 'medecin', 'sagefemme', 'reception']);
      for (final e in m(pin['accueilParProfil']).entries) {
        expect(mobAccueilDuProfil(e.key), e.value, reason: e.key);
      }
    });

    test('E1656 : la page ne levait jamais le blocage (le rechargement remettait trois essais) ; le téléphone retient les essais et lève au bout de 30 s', () async {
      expect(pin['apresBlocage'], 'Trop d’essais — réessayez dans 30 s.');
      expect(pin['apresRechargement'], '', reason: 'rechargée, la page redonnait trois essais sans rien retenir');
      var t = maintenant;
      final coffre = CoffrePinMemoire('1234');
      var p = MobPin(coffre, horloge: () => t);
      for (final k in '000000000000'.split('')) {
        await p.touche(k);
      }
      expect(p.etat.essais, 3);
      expect(p.etat.bloque(t), isTrue);
      expect(p.etat.secondesRestantes(t), 30);
      // Un redémarrage ne rend pas les essais.
      p = MobPin(coffre, horloge: () => t);
      await p.charger();
      expect(p.etat.bloque(t), isTrue);
      expect(p.etat.message, 'Trop d’essais — réessayez dans 30 s.');
      for (final k in '1234'.split('')) {
        await p.touche(k);
      }
      expect(p.etat.deverrouille, isFalse, reason: 'bloqué, même le bon code est ignoré');
      t = t.add(const Duration(seconds: 29));
      await p.touche('1');
      expect(p.etat.saisie, '');
      t = t.add(const Duration(seconds: 1));
      for (final k in '1234'.split('')) {
        await p.touche(k);
      }
      expect(p.etat.deverrouille, isTrue);
      expect((await coffre.compteur()).essais, 0);
    });

    test('E1657 : définir le code exige quatre chiffres identiques saisis deux fois', () async {
      final c = CoffrePinMemoire();
      expect(await c.aUnCode(), isFalse);
      for (final mauvais in ['123', '12345', 'abcd', '12 4']) {
        await expectLater(MobPin.definir(c, mauvais, mauvais), throwsA(isA<RefusMobile>().having((e) => e.code, 'code', 'PIN_FORMAT')), reason: mauvais);
      }
      await expectLater(MobPin.definir(c, '1234', '1235'), throwsA(isA<RefusMobile>().having((e) => e.code, 'code', 'PIN_DIFFERENT')));
      await MobPin.definir(c, '4321', '4321');
      expect(await c.verifier('4321'), isTrue);
      expect(await c.verifier('1234'), isFalse);
    });
  });
}
