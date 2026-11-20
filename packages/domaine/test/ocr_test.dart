// Rejoue les vecteurs de la LECTURE OCR PRÉPARÉE (prototype_html/build/vecteurs-ocr.js) : la maquette réelle pilotée dans Chrome, avec un moteur FACTICE (lot OCR-prep). Ici, les RÈGLES : mots
// normalisés, identifiant déterministe d'une lecture, version courante, les six états d'indexation, le texte lu pour la recherche (la couche native prime, la zone 2 reste de zone 2),
// le réglage, la demande d'une lecture, la reprise après arrêt, la relance, les messages, la lecture d'un fichier de bout en bout et chaque refus nommé du moteur.
// AUCUN moteur réel n'est éprouvé ici et AUCUNE qualité d'OCR n'est mesurée.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];
final v = obj(jsonDecode(File('test/vecteurs/ocr.json').readAsStringSync()));
final dossierFixtures = '../../apps/poste/test/fixtures/fichiers';

/// Un moteur qui se comporte comme le moteur factice de la maquette : texte donné, refus, jamais de réponse, langues et formats.
class MoteurDeVecteur implements MoteurOcr {
  MoteurDeVecteur(M cfg)
      : texte = '${cfg['texte']}',
        confiance = cfg['confiance'] == null ? null : (cfg['confiance'] as num).toDouble(),
        refus = cfg['refus'] == null ? null : obj(cfg['refus']),
        jamais = cfg['jamais'] == true,
        langues = [for (final l in (cfg['langues'] as List)) '$l'],
        formats = [for (final l in (cfg['formats'] as List)) '$l'];
  @override
  final String id = 'factice';
  @override
  final String version = '0.1';
  @override
  final String libelle = 'Moteur factice de test';
  @override
  final List<String> langues;
  @override
  final List<String> formats;
  final String texte;
  final double? confiance;
  final M? refus;
  final bool jamais;

  @override
  Future<ResultatOcr> lire(EntreeOcr entree) {
    if (refus != null) {
      final code = '${refus!['code']}';
      if (ocrGestes.containsKey(code)) return Future.error(ErreurOcr(ocrRefus(code, '${refus!['motif']}')));
      return Future.error(StateError('${refus!['message']}'));
    }
    if (jamais) return Completer<ResultatOcr>().future;
    final mots = [for (final m in texte.split(RegExp(r'\s+'))) if (m.isNotEmpty) MotOcr(m, confiance)];
    return Future.value(ResultatOcr(texte: texte, mots: mots, langue: entree.langue, moteur: id, version: version));
  }
}

M copie(M x) => (jsonDecode(jsonEncode(x)) as Map).cast<String, Object?>();

void main() {
  group('mots normalisés et identifiant d’une lecture', () {
    test('les mots d’un texte lu : sans accent, minuscules, distincts, deux lettres au moins', () {
      for (final c in liste(v['mots'])) {
        expect(ocrMotsNormalises('${c['texte']}'), [for (final m in (c['mots'] as List)) '$m'], reason: '${c['texte']}');
      }
    });
    test('l’identifiant d’une lecture est celui de la maquette (déterministe : empreinte, moteur, version, langue, texte normalisé)', () {
      for (final c in liste(v['ids'])) {
        expect(ocrIdLecture('${c['sha']}', '${c['moteur']}', '${c['version']}', '${c['langue']}', '${c['mots']}'), c['id'], reason: '${c['texte']}');
      }
    });
    test('même moteur et même texte ne font qu’une version ; un autre moteur, une autre version du moteur, une autre langue ou un autre texte en font une autre', () {
      final ids = liste(v['ids']);
      expect(ids[5]['id'] == ids[0]['id'], isTrue, reason: 'la casse, les accents et la ponctuation ne changent pas les mots normalisés');
      for (final k in [1, 2, 3, 4, 6]) {
        expect(ids[k]['id'] == ids[0]['id'], isFalse, reason: 'cas $k');
      }
    });
  });

  group('versions : ordre et version courante', () {
    test('la plus récente qui porte du texte est la courante, l’identifiant départage les égalités', () {
      for (final c in liste(v['courante'])) {
        final vs = [
          for (final x in liste(c['versions'])) {...x, 'sha256': 'x'}
        ];
        expect([for (final x in ocrVersionsOrdonnees(vs)) x['id']], [for (final i in (c['ordre'] as List)) i], reason: '${c['nom']}');
        expect(ocrVersionCourante(vs)?['id'], c['courante'], reason: '${c['nom']}');
      }
    });
  });

  group('les six états d’indexation', () {
    test('la grille de la maquette : état, petit mot, phrase, raison, source, marquage, disponibilité', () {
      var n = 0;
      for (final c in liste(v['etats'])) {
        final e = obj(c['entree']);
        final s = obj(c['sortie']);
        final r = ocrEtatIndexation(
            natif: e['natif'] == true,
            versions: liste(e['versions']),
            file: e['file'] == null ? null : obj(e['file']),
            moteurInstalle: e['moteurInstalle'] == true,
            actif: e['actif'] == true,
            moteurActif: e['moteurActif'] == true);
        final cle = '${e['natif']}/${e['cleVersions']}/${e['cleFile']}/${e['moteurInstalle']}${e['actif']}${e['moteurActif']}';
        expect(r.code, s['code'], reason: cle);
        expect(r.court, s['court'], reason: cle);
        expect(r.libelle, s['libelle'], reason: cle);
        expect(r.raison, s['raison'], reason: cle);
        expect(r.source, s['source'], reason: cle);
        expect(r.marque, s['marque'], reason: cle);
        expect(r.disponible, s['disponible'], reason: cle);
        n++;
      }
      expect(n, greaterThan(100));
    });
    test('sans moteur, jamais « indexé » : « ' + ocrRaisonSansMoteur + ' »', () {
      final r = ocrEtatIndexation(natif: false, versions: const [], moteurInstalle: false, actif: false, moteurActif: false);
      expect(r.etat, EtatIndexation.nonIndexe);
      expect(r.raison, ocrRaisonSansMoteur);
      expect(r.disponible, isFalse);
      expect(r.source, isNull);
    });
    test('un texte lu est TOUJOURS marqué « à vérifier » ; une couche texte native ne l’est jamais', () {
      final lu = ocrEtatIndexation(natif: false, versions: [
        {'nbMots': 3, 'ocrLe': 'a', 'id': 'x'}
      ], moteurInstalle: true, actif: true, moteurActif: true);
      expect(lu.etat, EtatIndexation.ocrIndexe);
      expect(lu.marque, isTrue);
      expect(lu.court, contains('lu par machine, à vérifier'));
      final natif = ocrEtatIndexation(natif: true, versions: [
        {'nbMots': 3, 'ocrLe': 'a', 'id': 'x'}
      ], moteurInstalle: true, actif: true, moteurActif: true);
      expect(natif.etat, EtatIndexation.indexe, reason: 'la couche native prime même quand une lecture existe');
      expect(natif.marque, isFalse);
      expect(natif.source, 'couche_texte');
    });
  });

  group('texte lu pour la recherche', () {
    test('la couche native prime, la zone 2 reste de zone 2 (grille de la maquette : sept profils, trois types)', () {
      var n = 0;
      for (final c in liste(v['texteRecherche'])) {
        final natif = c['natif'] == true, lu = c['lu'] == true;
        final t = ocrTexteRecherche(
            natifIndexe: natif,
            natifTexte: natif ? 'natifmot natif2' : '',
            versions: lu
                ? [
                    {'id': 'OCR-x-1', 'texte': 'ocrmot ocr2', 'nbMots': 2, 'ocrLe': '2026-10-01T10:00:00.000Z'}
                  ]
                : const [],
            famille: '${c['famille']}',
            type: c['type'] as String?,
            role: '${c['role']}');
        expect(t, c['texte'], reason: '${c['famille']}/${c['type']}/${c['role']} natif=$natif lu=$lu');
        n++;
      }
      expect(n, greaterThan(100));
    });
  });

  group('réglage', () {
    test('qui règle, refus nommés, activer sans moteur (grille de la maquette)', () {
      for (final c in liste(v['reglage'])) {
        final moteurs = {
          for (final m in liste(c['moteurs'])) '${m['id']}': MoteurOcrFactice(id: '${m['id']}', langues: [for (final l in (m['langues'] as List)) '$l'])
        };
        final avant = obj(c['avant']);
        final dem = obj(c['demande']);
        final r = ocrDefinirReglage(
            role: '${c['role']}',
            actif: dem['actif'] == true,
            moteur: dem['moteur'] as String?,
            langue: '${dem['langue']}',
            motif: c['motif'] as String?,
            moteurs: moteurs,
            avant: ReglageOcr(actif: avant['actif'] == true, moteur: avant['moteur'] as String?, langue: '${avant['langue']}'),
            regleLe: '2026-10-30T10:00:00.000Z',
            reglePar: 'x');
        expect(r.ok, c['ok'], reason: '${c['nom']}');
        expect(r.refus?.code, c['code'], reason: '${c['nom']}');
        final apres = obj(c['apres']);
        final effectif = r.reglage ?? ReglageOcr(actif: avant['actif'] == true, moteur: avant['moteur'] as String?, langue: '${avant['langue']}');
        expect(effectif.actif, apres['actif'], reason: '${c['nom']}');
        expect(effectif.moteur, apres['moteur'], reason: '${c['nom']}');
        expect(effectif.langue, apres['langue'], reason: '${c['nom']}');
      }
    });
    test('par défaut : désactivé, aucun moteur choisi, le français', () {
      final r = ocrReglageLire(null);
      expect(r.actif, isFalse);
      expect(r.moteur, isNull);
      expect(r.langue, 'fra');
      expect(r.regle, isFalse);
      expect(r.delaiMs, ocrDelaiDefautMs);
    });
  });

  group('la file', () {
    final registres = <String, M?>{
      'natif': {'texteIndexe': true},
      'vide': {},
      'attente': {
        'ocr': {'etat': 'en_attente', 'demandeLe': '2026-10-01T09:00:00.000Z', 'famille': 'courrier', 'type': null, 'essais': 0}
      },
      'cours': {
        'ocr': {'etat': 'en_cours', 'demandeLe': '2026-10-01T09:00:00.000Z', 'debutLe': '2026-10-01T09:30:00.000Z', 'famille': 'courrier', 'type': null, 'essais': 1}
      },
      'echec': {
        'ocr': {'etat': 'echec', 'code': 'IMAGE_ILLISIBLE', 'raison': 'l’image est illisible', 'famille': 'courrier', 'type': null, 'essais': 1}
      },
      'lu': {},
      'absent': null,
    };
    final moteurs = <String, ({bool installe, bool actif, bool choisi})>{
      'aucun moteur': (installe: false, actif: false, choisi: false),
      'installé, désactivé': (installe: true, actif: false, choisi: true),
      'installé, activé, non choisi': (installe: true, actif: true, choisi: false),
      'prêt': (installe: true, actif: true, choisi: true),
    };
    final luVersion = {'id': 'OCR-x-1', 'texte': 'mot', 'nbMots': 1, 'ocrLe': '2026-10-01T10:00:00.000Z'};

    test('la demande d’une lecture : idempotente, refus nommés, la couche native n’entre jamais (grille de la maquette)', () {
      var n = 0;
      for (final c in liste(obj(v['file'])['demandes'])) {
        final reg = registres['${c['registre']}'];
        final mo = moteurs['${c['moteur']}']!;
        final r = ocrDemander(
            registre: reg == null ? null : copie(reg),
            versions: c['registre'] == 'lu' ? [luVersion] : const [],
            moteurInstalle: mo.installe,
            actif: mo.actif,
            moteurActif: mo.installe && mo.choisi,
            relance: c['relance'] == true,
            famille: 'courrier',
            type: null,
            maintenant: '2026-10-30T10:00:00.000Z',
            par: 'x');
        final cle = '${c['registre']}/${c['moteur']}/relance=${c['relance']}';
        expect(r.refus == null, c['ok'], reason: cle);
        expect(r.refus?.code, c['code'], reason: cle);
        expect(r.deja, c['deja'], reason: cle);
        expect(r.lu, c['lu'], reason: cle);
        expect(r.etat != null, c['demande'], reason: cle);
        M? etatFile;
        if (r.etat != null) {
          etatFile = {...r.etat!}..remove('demandeLe')..remove('demandePar');
        } else if (reg != null && reg['ocr'] != null) {
          etatFile = {...obj(reg['ocr'])}..remove('demandeLe')..remove('demandePar');
        }
        expect(etatFile, c['etatFile'], reason: cle);
        n++;
      }
      expect(n, 56);
    });

    test('la reprise après arrêt : laissé en cours si récent, remis en attente passé deux délais, en échec après trois essais', () {
      final maintenant = DateTime.parse('2026-10-30T10:00:00.000Z');
      for (final c in liste(obj(v['file'])['reprises'])) {
        final file = {'etat': 'en_cours', 'demandeLe': '2026-10-30T08:00:00.000Z', 'debutLe': c['debutLe'], 'essais': c['essais'], 'famille': 'courrier'};
        final r = ocrReprendre(file, maintenant: maintenant, delaiMs: c['delaiMs'] as int);
        expect(r != null, c['repris'] == 1, reason: '${c['nom']}');
        final apres = {...(r ?? file)}..remove('finLe');
        final attendu = obj(c['etatFile']);
        expect(apres['etat'], attendu['etat'], reason: '${c['nom']}');
        expect(apres['code'], attendu['code'], reason: '${c['nom']}');
        expect(apres['raison'], attendu['raison'], reason: '${c['nom']}');
        expect(apres['essais'], attendu['essais'], reason: '${c['nom']}');
      }
    });

    test('la relance : offerte avec le droit d’écrire et un moteur prêt, refusée par le moteur lui-même sinon (grille de la maquette)', () {
      var n = 0;
      for (final c in liste(obj(v['file'])['relances'])) {
        final reg = registres['${c['registre']}']!;
        final mo = moteurs['${c['moteur']}']!;
        final versions = c['registre'] == 'lu' ? [luVersion] : <M>[];
        final natif = reg['texteIndexe'] == true;
        final etat = ocrEtatIndexation(
            natif: natif,
            versions: versions,
            file: reg['ocr'] == null ? null : obj(reg['ocr']),
            moteurInstalle: mo.installe,
            actif: mo.actif,
            moteurActif: mo.installe && mo.choisi);
        final pret = ocrPret(actif: mo.actif, moteurActif: mo.installe && mo.choisi);
        final cle = '${c['peutDeposer']}/${c['moteur']}/${c['registre']}';
        expect(ocrRelancePossible(peutDeposer: c['peutDeposer'] == true, pret: pret, etat: etat.etat), c['possible'], reason: cle);
        var refus = ocrRefusRelance(peutDeposer: c['peutDeposer'] == true, moteurInstalle: mo.installe, actif: mo.actif, moteurActif: mo.installe && mo.choisi, sansPiece: false);
        var deja = false;
        if (refus == null) {
          final d = ocrDemander(
              registre: copie(reg),
              versions: versions,
              moteurInstalle: mo.installe,
              actif: mo.actif,
              moteurActif: mo.installe && mo.choisi,
              relance: true,
              famille: 'courrier',
              type: null,
              maintenant: 'x',
              par: 'x');
          refus = d.refus;
          deja = d.deja;
        }
        expect(refus == null, c['ok'], reason: cle);
        expect(refus?.code, c['code'], reason: cle);
        expect(deja, c['deja'], reason: cle);
        n++;
      }
      expect(n, 48);
    });

    test('un fichier à la fois : le plus ancien en attente, jamais un fichier écarté', () {
      final regs = [
        {'sha256': 'b', 'ocr': {'etat': 'en_attente', 'demandeLe': '2026-10-02T00:00:00.000Z'}},
        {'sha256': 'a', 'ocr': {'etat': 'en_attente', 'demandeLe': '2026-10-01T00:00:00.000Z'}},
        {'sha256': 'c', 'ocr': {'etat': 'en_cours', 'demandeLe': '2026-09-01T00:00:00.000Z'}},
        {'sha256': 'd'},
      ];
      expect(ocrChoisirSuivant(regs)?['sha256'], 'a');
      expect(ocrChoisirSuivant(regs, ecartes: {'a'})?['sha256'], 'b');
      expect(ocrChoisirSuivant(regs, ecartes: {'a', 'b'}), isNull);
    });
  });

  group('la correction signée du texte lu (lot C), vecteurs tirés du module réel de la maquette', () {
    final c = obj(v['corrections']);
    test('l’identifiant d’une correction est déterministe : empreinte, version de départ, texte sans blancs superflus', () {
      for (final x in liste(c['ids'])) {
        expect(ocrIdCorrection('${x['sha']}', '${x['corrigeDe']}', '${x['texte']}'), x['id'], reason: '${x['texte']}');
      }
      final ids = liste(c['ids']);
      expect(ids[0]['id'], ids[1]['id'], reason: 'les blancs de bord et répétés ne comptent pas');
      expect({ids[0]['id'], ids[2]['id'], ids[3]['id'], ids[4]['id']}, hasLength(4), reason: 'autre version, autre texte ou autre empreinte : autre identifiant');
    });

    test('version courante, têtes, conflit et état : la correction signée prime sur une lecture machine plus récente, deux têtes font un conflit', () {
      for (final g in liste(c['courant'])) {
        final vs = [for (final x in liste(g['versions'])) x];
        expect(ocrVersionCourante(vs)?['id'], g['courant'], reason: '${g['nom']}');
        expect([for (final t in ocrTetes(vs)) t['id']], (g['tetes'] as List).cast<String>(), reason: '${g['nom']} : têtes');
        expect(ocrConflit(vs).length, (g['tetes'] as List).length > 1 ? (g['tetes'] as List).length : 0, reason: '${g['nom']} : conflit');
        for (final e in liste(g['etats'])) {
          final f = e['file'] == null ? null : obj(e['file']);
          final r = ocrEtatIndexation(natif: false, versions: vs, file: f, moteurInstalle: true, actif: true, moteurActif: true);
          expect(r.code, e['code'], reason: '${g['nom']} $f');
          expect(r.court, e['court'], reason: '${g['nom']} $f');
          expect(r.libelle, e['libelle'], reason: '${g['nom']} $f');
          expect(r.source, e['source'], reason: '${g['nom']} $f');
          expect(r.marque, e['marque'], reason: '${g['nom']} $f');
          expect(r.disponible, e['disponible'], reason: '${g['nom']} $f');
          expect(r.conflit, e['conflit'], reason: '${g['nom']} $f');
        }
      }
    });

    test('corriger : refus nommés (code, motif, geste) et fiche écrite, rejoués sur chaque cas de la maquette', () {
      for (final k in liste(c['corriger'])) {
        final avant = liste(k['versionsAvant']);
        final r = ocrCorriger(
            sha: '${k['sha']}',
            texte: '${k['texte']}',
            natif: k['natif'] == true,
            versions: avant,
            corrigeDe: k['corrigeDe'] as String?,
            par: 'SONDE vec',
            le: '2026-10-30T10:00:00.000Z',
            peutDeposer: k['peutDeposer'] == true,
            zoneLue: k['zoneLue'] == true,
            gesteAccorde: k['geste'] == true);
        final nom = '${k['nom']}';
        if (k['ok'] == true) {
          expect(r.refus, isNull, reason: nom);
          if (k['nouvelle'] == true) {
            expect(r.deja, isFalse, reason: nom);
            final f = obj(k['fiche']);
            for (final cle in ['id', 'texteBrut', 'texte', 'nbMots', 'texteSource', 'corrigeDe', 'corrigePar', 'corrigeLe', 'ocrLe']) {
              expect(r.fiche![cle], f[cle], reason: '$nom : $cle');
            }
            expect(r.fiche!['remplace'], f['remplace'], reason: '$nom : remplace');
          } else {
            expect(r.deja, isTrue, reason: '$nom : rejeu, aucune seconde version');
            expect(r.fiche, isNull, reason: nom);
          }
        } else {
          expect(r.refus, isNotNull, reason: nom);
          expect(r.refus!.code, k['code'], reason: nom);
          expect(r.refus!.motif, k['motif'], reason: '$nom : motif');
          expect(r.refus!.geste, isNotEmpty, reason: '$nom : le geste de correction est dit');
          expect(r.fiche, isNull, reason: nom);
        }
      }
    });

    test('la commande « Corriger » est ABSENTE hors droit, sans lecture, ou sur une couche texte native', () {
      final machine = [
        {'id': 'M1', 'nbMots': 3, 'ocrLe': '2026-10-01T10:00:00.000Z', 'texteSource': 'ocr'}
      ];
      bool possible({bool d = true, bool z = true, bool g = true, EtatIndexation e = EtatIndexation.ocrIndexe, List<M>? vs}) =>
          ocrCorrectionPossible(peutDeposer: d, zoneLue: z, gesteAccorde: g, etat: e, versions: vs ?? machine);
      expect(possible(), isTrue);
      expect(possible(d: false), isFalse);
      expect(possible(z: false), isFalse);
      expect(possible(g: false), isFalse);
      expect(possible(e: EtatIndexation.indexe), isFalse);
      expect(possible(vs: const []), isFalse);
      expect(possible(e: EtatIndexation.ocrCorrige), isTrue);
    });

    test('la garde d’écriture refuse une correction sans signataire, sans date, sans version de départ ou sans texte ; une lecture machine passe', () {
      const ok = {'texteSource': 'correction', 'corrigePar': 'A', 'corrigeLe': '2026-10-30T10:00:00.000Z', 'corrigeDe': 'M1', 'texteBrut': 'x'};
      expect(ocrMotifCorrectionNonSignee(ok), isNull);
      for (final cle in ['corrigePar', 'corrigeLe', 'corrigeDe', 'texteBrut']) {
        expect(ocrMotifCorrectionNonSignee({...ok, cle: ' '}), isNotNull, reason: cle);
        expect(ocrMotifCorrectionNonSignee({...ok}..remove(cle)), isNotNull, reason: cle);
      }
      expect(ocrMotifCorrectionNonSignee({'texteSource': 'ocr'}), isNull);
    });

    test('le droit d’origine, rôle par rôle : celui du manifeste de la maquette, lu de rbac.json, jamais d’un nom de rôle en dur', () {
      final json = obj(jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()));
      final m = MatriceDroits.depuisJson(json);
      final droit = obj(c['droit']);
      expect(droit, isNotEmpty);
      droit.forEach((role, oui) => expect(m.droitGeste(role, ocrGesteCorriger), oui, reason: role));
      expect(m.droitGeste('role_inconnu', ocrGesteCorriger), isFalse);
      expect(m.droitGeste('admin', 'geste_inconnu'), isFalse);
    });

    test('le réglage de clinique non reçu se dit : la raison n’est jamais « désactivée » en silence', () {
      final e = ocrEtatIndexation(natif: false, versions: const [], moteurInstalle: true, actif: false, moteurActif: false, reglageRecu: false);
      expect(e.raison, ocrRaisonReglageNonRecu);
      expect(e.raison, isNot(contains('désactivée')));
      final r = ocrEtatIndexation(natif: false, versions: const [], moteurInstalle: true, actif: false, moteurActif: false);
      expect(r.raison, 'la lecture OCR est désactivée au réglage');
      // sans moteur, la raison première reste « aucun moteur installé », reçu ou non
      expect(ocrEtatIndexation(natif: false, versions: const [], moteurInstalle: false, actif: false, moteurActif: false, reglageRecu: false).raison, ocrRaisonSansMoteur);
    });
  });

  group('messages', () {
    test('sous « Aucun résultat » : ce que la recherche ne lit pas, avec le bon nombre (grille de la maquette)', () {
      for (final c in liste(obj(v['messages'])['vides'])) {
        final mo = obj(c['moteur']);
        final etats = <EtatIndexationOcr>[];
        for (final g in (c['genres'] as List)) {
          final genre = '$g';
          etats.add(ocrEtatIndexation(
              natif: genre == 'natif',
              versions: genre == 'lu'
                  ? [
                      {'id': 'x', 'nbMots': 2, 'ocrLe': '2026-10-01T10:00:00.000Z'}
                    ]
                  : const [],
              file: genre == 'attente'
                  ? {'etat': 'en_attente'}
                  : genre == 'cours'
                      ? {'etat': 'en_cours'}
                      : genre == 'echec'
                          ? {'etat': 'echec', 'raison': 'l’image est illisible'}
                          : null,
              moteurInstalle: mo['installe'] == true,
              actif: mo['actif'] == true,
              moteurActif: mo['installe'] == true && mo['choisi'] == true));
        }
        expect(ocrIndiceVide(etats), c['indice'], reason: '${c['nom']}');
      }
    });
    test('la phrase du brief : « N pièces sans texte lu : aucun moteur d’OCR n’est installé »', () {
      final etats = List.generate(3, (_) => ocrEtatIndexation(natif: false, versions: const [], moteurInstalle: false, actif: false, moteurActif: false));
      expect(ocrIndiceVide(etats), contains('3 pièces sans texte lu : aucun moteur d’OCR installé sur ce poste.'));
    });
    test('la note de recherche dit combien de résultats viennent d’un texte lu par machine', () {
      for (final c in liste(obj(v['messages'])['notes'])) {
        final n = c['note'] == null ? 0 : int.parse('${obj(c['note'])['n']}');
        final t = ocrNoteRecherche(n);
        expect(t, c['note'] == null ? null : obj(c['note'])['texte'], reason: '${c['nom']}');
      }
    });
  });

  group('la lecture d’un fichier, de bout en bout (moteur factice)', () {
    Uint8List octetsDe(String nom) => File('$dossierFixtures/$nom').readAsBytesSync();
    String formatDe(String nom) => fichierFormatDesOctets(octetsDe(nom))!;

    test('chaque cas de la maquette : la version écrite, ou le refus nommé (code, motif, geste)', () async {
      var nOk = 0, nRefus = 0;
      for (final c in liste(obj(v['lecture'])['cas'])) {
        final cfg = obj(c['moteur']);
        final moteur = MoteurDeVecteur(cfg);
        final nom = '${c['fichier']}';
        final lu = await ocrLireFichier(
            moteur: moteur,
            octets: octetsDe(nom),
            formatId: formatDe(nom),
            mime: null,
            langue: 'fra',
            delaiMs: cfg['jamais'] == true ? 400 : 5000);
        final cle = '${c['nom']}';
        if (c['versions'] != null && (c['versions'] as List).isNotEmpty) {
          expect(lu.ok, isTrue, reason: cle);
          final att = obj((c['versions'] as List).first);
          final f = ocrNouvelleLecture(
              sha: '${c['sha']}',
              texte: lu.texte,
              moteur: moteur.id,
              moteurVersion: moteur.version,
              langue: 'fra',
              ocrLe: 'x',
              ocrPar: 'x',
              declencheur: 'automatique',
              pages: lu.pages,
              dureeMs: 0,
              confiance: lu.confiance);
          expect(f['id'], c['id'], reason: cle);
          for (final k in ['texteBrut', 'brutTronque', 'texte', 'motsTronques', 'nbMots', 'confiance', 'texteSource', 'moteur', 'moteurVersion', 'langue', 'declencheur', 'pages']) {
            expect(f[k], att[k], reason: '$cle / $k');
          }
          nOk++;
        } else {
          final fil = obj(c['file']);
          expect(lu.ok, isFalse, reason: cle);
          expect(lu.refus!.code, fil['code'], reason: cle);
          expect(lu.refus!.geste, fil['geste'], reason: cle);
          if (fil['code'] == 'MOTEUR_EN_ECHEC') {
            expect(lu.refus!.motif, contains('plantage interne'), reason: cle);
          } else {
            expect(lu.refus!.motif, fil['raison'], reason: cle);
          }
          nRefus++;
        }
      }
      expect(nOk, greaterThanOrEqualTo(5));
      expect(nRefus, greaterThanOrEqualTo(8));
    });

    test('rejouer la même lecture avec le même moteur et le même texte donne la MÊME version (identifiant déterministe)', () {
      final r = obj(obj(v['lecture'])['rejoue']);
      expect(r['idAvant'], r['idApres']);
      expect(r['versionsAvant'], r['versionsApres']);
    });
  });

  group('le moteur factice (il ne prétend rien)', () {
    test('rend le texte donné pour l’empreinte du fichier, et seulement lui', () async {
      final octets = Uint8List.fromList([1, 2, 3, 4]);
      final m = MoteurOcrFactice(textes: {sha256Octets(octets): 'Hyperglycémie sévère'}, texteParDefaut: 'autre');
      final r = await m.lire(EntreeOcr(octets: octets, format: 'png', langue: 'fra'));
      expect(r.texte, 'Hyperglycémie sévère');
      expect(r.moteur, 'factice');
      expect(r.confiance, 0.9);
      final r2 = await m.lire(EntreeOcr(octets: Uint8List.fromList([9]), format: 'png', langue: 'fra'));
      expect(r2.texte, 'autre');
      expect(m.appels, 2);
    });
    test('un refus levé est nommé, jamais muet', () async {
      final m = MoteurOcrFactice(refus: ocrRefus(CodeOcr.imageIllisible, 'l’image est illisible'));
      expect(() => m.lire(EntreeOcr(octets: Uint8List(1), format: 'png', langue: 'fra')), throwsA(isA<ErreurOcr>()));
    });
    test('aucun moteur : la lecture est refusée en le nommant', () async {
      final r = await ocrLireFichier(moteur: null, octets: Uint8List(3), formatId: 'png', mime: null, langue: 'fra', delaiMs: 100);
      expect(r.ok, isFalse);
      expect(r.refus!.code, 'MOTEUR_ABSENT');
      expect(r.refus!.motif, ocrRaisonSansMoteur);
    });
  });
}
