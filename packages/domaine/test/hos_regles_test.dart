// Rejoue les vecteurs de l'hospitalisation (prototype_html/build/vecteurs-hospitalisation.js) : écrans M3 réels pilotés dans Chrome.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

String _s(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'[\s  ]'), '');

void main() {
  final d = lireVecteurs('hospitalisation');
  final auj = DateTime(2026, 8, 16, 10);
  Map<String, Object?> m(Object? x) => (x as Map).cast<String, Object?>();

  test('référentiels : chambres, lits, types, unités, orientations, relais', () {
    final r = m(d['referentiels']);
    final ch = liste(r['chambres']);
    expect(hosChambres.length, ch.length);
    for (var i = 0; i < ch.length; i++) {
      expect(hosChambres[i].code, ch[i]['code']);
      expect(hosChambres[i].type, ch[i]['type']);
      expect(hosChambres[i].aile, ch[i]['aile']);
      expect(hosChambres[i].lits, [for (final l in liste(ch[i]['lits'])) l['label']]);
    }
    expect([for (final t in hosTypesChambre) {'id': t.id, 'label': t.label, 'tarif': t.tarif}], liste(r['typesChambre']));
    expect([for (final u in hosUnitesObservation) '${u.id}|${u.label}|${u.places}'],
        [for (final u in liste(r['unitesObservation'])) '${u['id']}|${u['label']}|${u['places']}']);
    expect([for (final o in hosOrientations) '${o.id}|${o.label}|${o.ton}'],
        [for (final o in liste(r['orientations'])) '${o['id']}|${o['label']}|${o['tone']}']);
    expect(hosActesSoins, (r['actesSoins'] as List).cast<String>());
    expect(hosDureeObservationReference, r['dureeObservation']);
    for (final e in m(r['executerSoins']).entries) {
      expect(hosExecuteSoins[e.key] ?? false, e.value, reason: e.key);
    }
    for (final c in liste(r['relais'])) {
      final x = hosSecteurAdministrateur(c['modalite'], c['rang'] as int);
      expect(x.secteur, c['secteur']);
      expect(x.motif, c['motif']);
    }
  });

  test('admissions : KPI, lit occupé, référence', () {
    final a = m(d['admissions']);
    final jeu = liste(a['jeu']).where((f) => f['statut'] != 'archive').toList();
    final k = hosKpisAdmissions(jeu, auj);
    final kp = liste(m(a['ecran'])['kpis']);
    expect('${k.admissions}', kp[0]['valeur']);
    expect('${k.enCours}', kp[1]['valeur']);
    expect(_s(pourcent(k.taux, 1)), _s(kp[2]['valeur']));
    expect('${hosNum(k.dms)} j', kp[3]['valeur']);
    final refus = hosRefusAdmission('A1 LIT1', null, jeu);
    expect(refus, (m(a['creation'])['refusLitOccupe'] as Map)['toasts'][0][0]);
    expect(hosRefusAdmission('A1 LIT1', jeu.firstWhere((x) => x['id'] == 'ADM1'), jeu), isNull);
    final cree = hosConstruireAdmission({'patientCode': 'CNT/2/26', 'lit': 'A1 LIT2'}, null, liste(a['patients']),
        liste(a['jeu']),
        reference: referenceSuivante);
    expect(cree['reference'], 'H00008');
    expect(cree['chambre'], 'A1');
    expect(cree['typeChambre'], 'standard');
    expect(cree['statut'], 'en_cours');
    final modif = hosConstruireAdmission({'lit': 'A2 LIT2'}, jeu.first, const [], liste(a['jeu']), reference: referenceSuivante);
    expect(modif['reference'], jeu.first['reference']);
  });

  test('E370 : corriger une admission SORTIE ne la rouvre pas (le formulaire ne porte pas le statut)', () {
    final jeu = liste(m(d['admissions'])['jeu']);
    final sortie = jeu.firstWhere((x) => x['statut'] == 'sortie');
    final modif = hosConstruireAdmission({'diagnosticEntree': 'corrigé'}, sortie, const [], jeu, reference: referenceSuivante);
    expect(modif['statut'], 'sortie');
    // une création, elle, s'ouvre
    expect(hosConstruireAdmission({'lit': 'A1 LIT2'}, null, const [], jeu, reference: referenceSuivante)['statut'], 'en_cours');
  });

  test('courbe de température : axe borné 35–41 (graduations entières, bornes comprises)', () {
    final e = echelleVerticaleBornee(35, 41, hauteurAxe: 188);
    expect(e.graduations, [35, 36, 37, 38, 39, 40, 41]);
    expect(e.min, 35);
    expect(e.max, 41);
  });

  test('plan des lits : durée de séjour et occupation', () {
    final a = m(d['admissions']);
    final fin = liste(a['etatFinal']).where((f) => f['statut'] != 'archive').toList();
    final lits = liste(m(a['plan'])['lits']);
    final tous = hosTousLits();
    expect(tous.length, lits.length);
    for (var i = 0; i < tous.length; i++) {
      final occ = hosLitOccupePar(tous[i].label, fin);
      final txt = occ == null ? 'Disponible' : '${occ['patient']}${hosDureeSejour(occ, auj)} j';
      expect('${tous[i].label}$txt', lits[i]['texte']);
      final couleur = occ == null ? 'success' : (hosDureeSejour(occ, auj) > 5 ? 'warning' : 'danger');
      expect(couleur, lits[i]['couleur']);
    }
  });

  test('observation : heures écoulées, dépassement, admission ouverte', () {
    final o = m(d['observation']);
    final jeu = liste(o['jeu']);
    final att = {'OBS-2026-0001': 3, 'OBS-2026-0002': 20, 'OBS-2026-0003': 25, 'OBS-2026-0004': 48, 'OBS-2026-0005': 20, 'OBS-2026-0006': 30};
    for (final e in att.entries) {
      final f = jeu.firstWhere((x) => x['reference'] == e.key);
      expect(hosHeuresEcoulees(f, auj), e.value, reason: e.key);
      expect(hosDepasse(f, auj), e.value > 24);
    }
    final h = m(m(o['orientation'])['hospitalisation']);
    final src = jeu.firstWhere((x) => x['reference'] == 'OBS-2026-0001');
    final adm = hosAdmissionDepuisObservation(src, DateTime(2026, 8, 16, 9, 55), 'Aggravation constatée', 'H00001');
    memes(adm, h['admission'], 'admission', ignorer: {'id'});
  });

  test('surveillance : relevés réunis et courbe à cinq échelles', () {
    final s = m(d['surveillance']);
    final pats = liste(s['patients']);
    final adm = [
      for (var i = 0; i < 2; i++) {'id': 'ADM${i + 1}', 'patientId': pats[i]['id']}
    ];
    final rel = hosRelevesDe(pats[0]['id'] as String, constantes: liste(s['constantes']), admissions: adm, releves: liste(s['releves']));
    final dessin = m(m(s['premier'])['dessin']);
    final c = hosCourbe(rel);
    expect(c.largeurTotale, dessin['largeur']);
    expect(c.hauteurTotale, dessin['hauteur']);
    expect(c.graduations, [for (final t in liste(dessin['textes']).take(6)) t['t']]);
    final pl = liste(dessin['polylignes']);
    for (var i = 0; i < pl.length; i++) {
      final pts = c.polylignes[hosEchelles[i].code]!;
      final attendu = '${pl[i]['points']}'.split(' ').map((p) => p.split(',').map(double.parse).toList()).toList();
      expect(pts.length, attendu.length, reason: hosEchelles[i].code);
      for (var k = 0; k < pts.length; k++) {
        expect(pts[k].x, closeTo(attendu[k][0], 1e-6));
        expect(pts[k].y, closeTo(attendu[k][1], 1e-6));
      }
    }
    expect(hosPositionSurEchelle(hosEchelles[1], 160), closeTo(4.5 / 5, 1e-9));
  });

  test('Glasgow : le score est la somme des axes', () {
    final g = m(d['glasgow']);
    final cree = m(m(m(g['creation'])['cree'])['fiche']);
    final r = hosScoreGlasgow([2, 3, 4]);
    expect(r.score, cree['score']);
    memes(r.axes, cree['axes'], 'axes');
    final modif = m(m(m(g['modification'])['enregistre'])['fiche']);
    expect(hosScoreGlasgow([1, 2, 3]).score, modif['score']);
    expect([for (final f in liste(g['jeu'])) hosTonGlasgow(f['score'] as num)], ['success', 'warning', 'danger', 'danger', 'success', 'warning']);
  });

  test('transfusion : un temps compte dès qu\'un élément est rempli', () {
    final t = m(m(m(m(d['transfusion'])['creation'])['partielle'])['fiche']);
    final r = hosValeursTransfusion({'t0_temperature': '37.0', 't0_ta': '12/8', 't15_temperature': '37.2', 'fin_conscience': 'normale', 'h2_autre': 'x'});
    expect(r.releves, t['releves']);
    expect(r.valeurs['t0']!['ta'], '12/8');
  });

  test('administration : le rang décide du secteur, refus nommés', () {
    final a = m(d['administrations']);
    final pres = liste(a['prescriptions']);
    var ads = liste(a['administrations']).where((x) => x['statut'] != 'archive').toList();
    final soignants = [
      {'id': 'SOI01', 'nomComplet': 'BASSONGUI Chabi Séko', 'poste': 'Directeur Médical', 'execute': false},
      {'id': 'SOI06', 'nomComplet': 'IDRISSOU ANIKI Baba-Toundé', 'poste': 'Infirmier', 'execute': true},
      {'id': 'SOI07', 'nomComplet': 'NKOUÉ Jean', 'poste': 'Infirmier', 'execute': true},
    ];
    final dus = hosSoinsDuSecteur('hospitalisation', pres, ads);
    expect([for (final x in dus) '${x.prescription['reference']}|${x.rang}|${x.bloque}'], ['PRS-00001|2|false', 'PRS-00002|2|true']);
    var n = 5;
    for (final c in liste(a['moteur'])) {
      final o = m(c['opts']);
      final p = pres.where((x) => x['id'] == c['presId']).firstOrNull;
      final res = m(c['resultat']);
      try {
        final r = hosAdministrer(p, ads,
            soignants: soignants,
            ligneIndex: o['ligneIndex'] as int,
            secteur: o['secteur'] as String?,
            executantId: o['executantId'] as String?,
            observation: o['observation'] as String?,
            dateHeure: DateTime.utc(2026, 8, 16, 10),
            reference: 'ADM-${(n++).toString().padLeft(5, '0')}');
        expect(r.ok, res['ok'], reason: '${c['nom']}');
        if (!r.ok) expect(r.motif, res['motif'], reason: '${c['nom']}');
        if (r.ok) {
          expect(r.rang, res['rang']);
          expect(r.secteur, res['secteur']);
          ads = [...ads, r.fiche!];
        }
      } on HosErreur catch (e) {
        expect(e.message, res['erreur'], reason: '${c['nom']}');
      }
    }
  });
}
