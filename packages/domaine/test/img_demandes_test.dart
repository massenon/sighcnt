// Rejoue les vecteurs du poste d'imagerie engendrés par la maquette (prototype_html/build/vecteurs-img-demandes.js) :
// les trois écrans RÉELS (registre des demandes, poste, galerie) lus comme l'agent les lit, la fabrique d'ouverture d'une demande et « Rendre ».
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

void main() {
  final v = lireVecteurs('img_demandes');
  final examens = liste(v['examens']);
  final catalogue = [
    for (final x in examens) {'code': x['code'], 'label': x['label'], 'modalite': x['modalite'], 'statut': 'actif'}
  ];
  const ignorerIds = {'id', 'patientId', 'factureId', 'demandeImagerieId', 'creeLe', 'statutAvantArchivage'};

  group('états et modalités', () {
    test('les quatre états portent les libellés de la maquette', () {
      final lus = liste(v['etats']);
      expect([for (final e in etatsImagerie) e.id], [for (final e in lus) e['id']]);
      expect([for (final e in etatsImagerie) e.libelle], [for (final e in lus) e['label']]);
    });
    test('les cinq modalités : code, libellé, écran, icône', () {
      final lus = liste(v['modalites']);
      expect(modalitesImagerie.length, lus.length);
      for (final (i, m) in modalitesImagerie.indexed) {
        expect([m.code, m.libelle, m.ecran, m.icone], [lus[i]['code'], lus[i]['label'], lus[i]['ecran'], lus[i]['icone']]);
      }
    });
    test('un état inconnu s’affiche sous son identifiant, un examen inconnu reste à l’échographie', () {
      expect(etatImagerie('zzz').libelle, 'zzz');
      expect(etatImagerie('zzz').ton, 'neutral');
      expect(modaliteDeExamen(catalogue, 'IMG-INCONNU'), 'echographie');
      for (final x in examens) {
        expect(modaliteDeExamen(catalogue, x['code']), x['modalite']);
      }
    });
  });

  group('registre des demandes', () {
    for (final c in liste(v['registre'])) {
      test('${c['nom']} : les quatre indicateurs', () {
        final comptes = comptesParEtat(liste(c['demandes']));
        final lu = liste((c['lu']! as Map)['kpis']);
        expect(lu.length, 4);
        for (final (i, e) in etatsImagerie.indexed) {
          expect(lu[i]['label'], e.libelle);
          expect('${comptes[e.id]}', lu[i]['valeur'], reason: e.id);
        }
      });
    }
    test('une demande archivée ne compte pas (RG-14)', () {
      final d = liste(liste(v['registre'])[0]['demandes']);
      final avec = [...d, {...d.first, 'statut': 'archive'}];
      expect(comptesParEtat(avec), comptesParEtat(d));
    });
  });

  group('poste d’imagerie', () {
    for (final c in liste(v['poste'])) {
      test('${c['nom']}', () {
        final p = posteImagerie(
            demandes: liste(c['demandes']),
            comptesRendus: liste(c['comptesRendus']),
            catalogue: catalogue,
            moisCourant: v['moisCourant']! as String);
        final lu = (c['lu']! as Map).cast<String, Object?>();
        final kpis = liste(lu['kpis']);
        expect(kpis.map((k) => k['valeur']).toList(),
            ['${p.payees.length}', '${p.attente.length}', '${p.redaction.length}', '${p.rendusMois.length}']);
        final tables = liste(lu['tables']);
        // « À exécuter » (si des examens sont payés) : les plus anciens d'abord.
        if (p.payees.isNotEmpty) {
          final t = tables.firstWhere((t) => (t['entetes']! as List).first == 'N°');
          expect([for (final l in liste(t['lignes'])) (l['cellules']! as List).first],
              [for (final d in p.payees) d['reference']]);
        } else {
          expect(lu['cartes'], contains('À exécuter'));
        }
        final modal = tables.firstWhere((t) => (t['entetes']! as List).first == 'MODALITÉ');
        final lignes = liste(modal['lignes']);
        expect(lignes.length, p.parModalite.length);
        for (final (i, l) in p.parModalite.indexed) {
          expect((lignes[i]['cellules']! as List),
              [l.modalite.libelle, '${l.attente}', '${l.payees}', '${l.redaction}', '${l.rendus}']);
        }
      });
    }
  });

  group('galerie des clichés', () {
    for (final c in liste(v['galerie'])) {
      test('${c['nom']}', () {
        final cl = liste(c['cliches']);
        final s = statsGalerie(cl);
        final lu = (c['lu']! as Map).cast<String, Object?>();
        expect(liste(lu['kpis']).map((k) => k['valeur']).toList(),
            ['${s.conserves}', '${s.patients}', '${s.lies}', '${s.sansLien}']);
        final cartes = liste(lu['cliches']);
        final tries = clichesRecentsDabord(cl);
        expect(tries.length, cartes.length);
        for (final (i, x) in tries.indexed) {
          final t = (cartes[i]['texte']! as List).cast<String>();
          expect(t.first, x['patient']);
          expect(t[1], '${x['examen']} — ${dateFR(DateTime.parse('${x['date']}').toLocal())}');
        }
      });
    }
  });

  group('ouverture d’une demande (fabrique unique)', () {
    final tarifs = (v['tarifs']! as Map).cast<String, Object?>();
    for (final c in liste(v['ouverture'])) {
      final e = (c['entree']! as Map).cast<String, Object?>();
      final p = (e['v']! as Map).cast<String, Object?>();
      test('${e['nom']}', () {
        var n = 0;
        PrixImagerie prix(String code, bool assure) {
          final t = tarifs[code] as Map?;
          if (t == null) return const PrixImagerie(null, 'Acte absent du catalogue tarifaire.');
          final r = (t[assure ? 'assure' : 'nonAssure']! as Map);
          return PrixImagerie(r['montant'] as num?, r['motif'] as String?);
        }

        OuvertureImagerie ouvrir() => ouvrirDemandeImagerie(
              examens: [for (final x in (p['examens']! as List)) '$x'],
              catalogue: catalogue,
              patients: [
                ...liste(c['patientsAvant']),
                // Le rang d'un dossier externe compte TOUS les dossiers (archivés compris) : des fiches inertes complètent le compte.
                for (var i = liste(c['patientsAvant']).length; i < (e['nbPatients']! as int); i++) {'id': '_$i'}
              ],
              couvertures: const [],
              demandesExistantes: [for (final r in (e['referencesExistantes']! as List)) {'reference': r}],
              nbFactures: e['rangFactures']! as int,
              prixDe: prix,
              nouvelId: (pre) => '$pre${++n}',
              date: p['date']! as String,
              maintenant: p['date']! as String,
              patientId: p['patientId'] as String?,
              nom: p['nom'] as String?,
              prenom: p['prenom'] as String?,
              sexe: p['sexe'] as String?,
              dateNaissance: p['dateNaissance'] as String?,
              age: p['age'],
              telephone: p['telephone'] as String?,
              residence: p['residence'] as String?,
              prescripteur: p['prescripteur'] as String?,
              indication: p['indication'] as String?,
              urgent: p['urgent'] == true,
              secteurDemandeur: p['secteurDemandeur'] as String?,
              origine: (p['origine'] ?? 'consultation') as String,
            );

        List<Map<String, Object?>> parRef(Iterable<Map<String, Object?>> l) =>
            ([...l]..sort((a, b) => '${a['reference']}'.compareTo('${b['reference']}')));

        if (c['erreur'] != null) {
          Object? err;
          try {
            ouvrir();
          } on RefusImagerie catch (x) {
            err = x;
            expect(x.message, c['erreur']);
            final attendues = parRef(liste(c['demandes']));
            final archivees = parRef(x.archivees);
            expect(archivees.length, attendues.length, reason: 'demandes écrites puis archivées');
            for (final (i, a) in attendues.indexed) {
              memes(archivees[i], {...a, 'statut': 'archive'}, 'archivée[$i]', ignorer: {...ignorerIds, '_archivee'});
            }
          }
          expect(err, isNotNull, reason: 'un refus était attendu');
          return;
        }
        final r = ouvrir();
        final ign = {...ignorerIds, '_archivee'};
        final attendues = parRef(liste(c['demandes']));
        final obtenues = parRef(r.demandes);
        expect(obtenues.length, attendues.length);
        for (final (i, a) in attendues.indexed) {
          memes(obtenues[i], a, 'demande[$i]', ignorer: ign);
        }
        memes(r.facture, liste(c['factures']).single, 'facture', ignorer: ign);
        final taches = liste(c['taches']);
        memes(r.tacheEncaissement, taches.firstWhere((t) => t['type'] == 'encaissement'), 'tâche encaissement', ignorer: ign);
        memes(r.tacheExamen, taches.firstWhere((t) => t['type'] == 'imagerie'), 'tâche imagerie', ignorer: ign);
        memes(r.notification, liste(c['notifications']).single, 'notification', ignorer: ign);
        final crees = liste(c['patientsCrees']);
        expect(r.dossierCree, crees.isNotEmpty);
        if (crees.isNotEmpty) memes(r.patient, crees.single, 'dossier externe', ignorer: ign);
        // Les liens : la ligne payable désigne SA demande, la demande la facture, la tâche la facture.
        for (final (i, l) in (r.facture['lignes']! as List).indexed) {
          expect((l as Map)['demandeImagerieId'], r.demandes[i]['id']);
          expect(r.demandes[i]['factureId'], r.facture['id']);
        }
        expect(r.tacheExamen['factureId'], r.facture['id']);
      });
    }
    test('RG-09 : carte expirée → tarif non assuré ET aucune part à l’assureur', () {
      final c = liste(v['ouverture'])[2];
      final f = liste(c['factures']).single;
      expect(f['partAssurance'], 0);
      expect(f['partPatient'], f['montantTTC']);
    });
  });

  group('modale « Nouvelle demande » (pilotée dans la maquette)', () {
    test('le nom du prescripteur : la liste de la maison, ou le champ libre du prescripteur extérieur (E102)', () {
      for (final c in liste(v['nomsPrescripteur'])) {
        final q = (c['v']! as Map).cast<String, Object?>();
        expect(nomPrescripteurImagerie(q['prescripteur'], q['prescripteurExterne']), c['attendu'], reason: '${c['nom']}');
      }
    });
    final modales = liste(v['modale']);
    test('toast d’une demande émise, avec ou sans dossier ouvert', () {
      for (final m in modales.where((m) => (m['demandes']! as List).isNotEmpty)) {
        final d = liste(m['demandes']);
        final cree = liste(m['patientsCrees']);
        final t = messageDemandeEmise(
            examens: d.length, facture: liste(m['factures']).single['numero'] as String, dossier: cree.isEmpty ? null : cree.single['code'] as String);
        expect('${t.message} ${t.detail}', m['toast'], reason: '${m['nom']}');
      }
    });
    test('refus sans identité : le message de la maquette, rien d’écrit', () {
      final m = modales.firstWhere((m) => '${m['nom']}'.startsWith('ni patient'));
      expect(m['toast'], refusIdentiteImagerie);
      expect(m['demandes'], isEmpty);
    });
    test('l’âge déclaré est transmis au dossier externe (E103) et daté du jour', () {
      final m = modales.firstWhere((m) => '${m['nom']}'.contains('âge déclaré'));
      final p = liste(m['patientsCrees']).single;
      expect(p['age'], 33);
      expect(p['dateNaissance'], isNull);
      expect(p['ageReferenceLe'], isNotNull);
      expect(p['prescripteurExterieur'], 'Dr SALIFOU Aminou, CS de Perma (extérieur)');
    });
  });

  group('prix d’un examen (RG-09) — tout le catalogue tarifaire de la maquette', () {
    final cas = liste(v['tarifPrix']);
    test('${cas.length} entrées, non assuré et assuré', () {
      expect(cas.length, greaterThan(100));
      for (final c in cas) {
        final entree = c['entree'] == null ? null : (c['entree']! as Map).cast<String, Object?>();
        for (final assure in [false, true]) {
          final attendu = (c[assure ? 'assure' : 'nonAssure']! as Map).cast<String, Object?>();
          final r = prixTarif(entree, assure);
          final nom = '${entree?['code'] ?? c['code']} assuré=$assure';
          expect(r.montant, attendu['montant'], reason: nom);
          expect(r.motif, attendu['motif'], reason: nom);
        }
      }
    });
    test('les trois natures de colonne assurée sont couvertes par le catalogue', () {
      final natures = {for (final c in cas) if (c['entree'] != null) '${(c['entree']! as Map)['assurable']}/${(c['entree']! as Map)['nonCouvert']}'};
      expect(natures, containsAll(['true/false', 'false/true', 'sos/false']));
    });
  });

  group('« Rendre » au prescripteur', () {
    final r = liste(v['rendre']);
    test('${r[0]['nom']}', () {
      expect(() => rendreCompteRendu({'conclusion': '', 'demandeImagerieId': 'X'}, maintenant: 'm'),
          throwsA(isA<RefusImagerie>().having((e) => e.message, 'message', 'La conclusion est obligatoire avant de rendre le compte rendu.')));
      expect((r[0]['toast']! as String), contains('La conclusion est obligatoire avant de rendre le compte rendu.'));
    });
    test('${r[1]['nom']}', () {
      final avant = (r[0]['crApres']! as Map).cast<String, Object?>();
      final cr = {...avant, 'conclusion': 'Examen sans particularité.', 'patientId': 'PX'};
      final x = rendreCompteRendu(cr, maintenant: '2026-10-30T10:00:00.000Z');
      final apres = (r[1]['crApres']! as Map).cast<String, Object?>();
      expect({...cr, ...x.patchCompteRendu}['statut'], apres['statut']);
      expect(x.patchCompteRendu.keys.toSet(), {'statut', 'renduLe'});
      expect(x.patchDemande!['statut'], (r[1]['demandeApres']! as Map)['statut']);
      memes(x.notification, liste(r[1]['notifications']).single, 'notification', ignorer: {...ignorerIds, 'creeLe'});
      expect(rendreCompteRendu({...cr, 'demandeImagerieId': null}, maintenant: 'm').patchDemande, isNull);
    });
    test('compte rendu d’une demande : le premier non archivé qui la désigne', () {
      final crs = [
        {'id': 'a', 'demandeImagerieId': 'D1', 'statut': 'archive'},
        {'id': 'b', 'demandeImagerieId': 'D1', 'statut': 'brouillon'},
        {'id': 'c', 'demandeImagerieId': 'D2', 'statut': 'brouillon'},
      ];
      expect(compteRenduDeDemande({'id': 'D1'}, crs)!['id'], 'b');
      expect(compteRenduDeDemande({'id': 'D3'}, crs), isNull);
    });
  });
}
