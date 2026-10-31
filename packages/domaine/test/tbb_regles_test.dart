// Rejoue les vecteurs des tableaux de bord « B » (prototype_html/build/vecteurs-dash-b.js) : les écrans RÉELS pilotés dans Chrome, sur le jeu du poste
// puis sur un jeu ENRICHI de fiches du jour (le jeu est daté d'août : la plupart des compteurs « du jour » y valent 0 et ne prouveraient rien).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];

const _jeu = '../../apps/poste/assets/donnees/jeu';
/// `texte()` de la maquette : toute espace (insécable, fine) devient une espace ordinaire.
String esp(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

List<M> jeu(String nom) {
  final f = File('$_jeu/$nom.json');
  return f.existsSync() ? liste(jsonDecode(f.readAsStringSync())) : <M>[];
}

void main() {
  final v = obj(jsonDecode(File('test/vecteurs/tbb_dash.json').readAsStringSync()));
  final auj = DateTime(2026, 10, 30, 10);
  final ajouts = obj(v['_ajouts']);

  // Les collections du jeu, avec (ou sans) les fiches synthétiques du vecteur enrichi.
  Map<String, List<M>> collections({required bool enrichi}) {
    final noms = {...ajouts.keys, 'consultations', 'personnel', 'echeancesFiscales', 'dossiersObstetricaux', 'partogrammes', 'examensImagerie'};
    return {for (final n in noms) n: [...jeu(n), if (enrichi) ...liste(ajouts[n] ?? const [])]};
  }

  String tonDe(TbbRegard r) => r.valeur == 0
      ? 'emerald'
      : switch (r.ton) { 'danger' => 'rose', 'warning' => 'amber', 'info' => 'sky', 'success' => 'emerald', _ => 'navy' };

  void verifier(String id, TbbReleve r, M lu) {
    final pr = obj(lu['premier']);
    expect(esp(r.regard.ligne), pr['ligne'], reason: '$id : ligne du premier regard');
    expect(tonDe(r.regard), pr['ton'], reason: '$id : ton du premier regard');
    expect(r.regard.note, pr['note'], reason: '$id : note du premier regard');
    // Le lien n'est posé que si le compte n'est pas nul.
    if (r.regard.valeur == 0) {
      expect(pr['lien'], isNull, reason: '$id : pas de lien quand rien n\'attend');
    } else {
      expect(obj(pr['lien'])['ecran'], r.regard.ecran);
      expect(obj(pr['lien'])['texte'], r.regard.lienLabel);
    }
    final kpis = liste(lu['kpis']);
    expect(r.kpis.length, kpis.length, reason: '$id : nombre de KPI');
    for (var i = 0; i < kpis.length; i++) {
      expect(r.kpis[i].libelle, kpis[i]['label'], reason: '$id : libellé KPI $i');
      expect(esp(r.kpis[i].valeur), kpis[i]['valeur'], reason: '$id : valeur KPI ${kpis[i]['label']}');
      expect(r.kpis[i].indice, kpis[i]['indice'], reason: '$id : indice KPI ${kpis[i]['label']}');
    }
  }

  for (final enrichi in [false, true]) {
    group(enrichi ? 'jeu enrichi des fiches du jour' : 'jeu du poste', () {
      final c = collections(enrichi: enrichi);
      M lu(String id) => obj(obj(v[id])[enrichi ? '_enrichi' : obj(v[id])['_proprio']]);

      test('dash-ambulancier', () {
        verifier('dash-ambulancier',
            tbbAmbulancier(ambulance: c['ambulance']!, consultations: c['consultations']!, auj: auj), lu('dash-ambulancier'));
        final lignes = liste(obj(liste(lu('dash-ambulancier')['tables'])[0])['lignes']);
        final dom = tbbDomicile(c['consultations']!).take(10).toList();
        expect(dom.length, lignes.length);
        for (var i = 0; i < dom.length; i++) {
          final cel = [for (final x in (lignes[i]['cellules'] as List)) '$x'];
          expect(tbbCellulesDomicile(dom[i]), cel.take(4).toList());
        }
      });
      test('dash-aide-soignant', () {
        verifier('dash-aide-soignant',
            tbbAideSoignant(admissions: c['admissions']!, releves: c['releves']!, visites: c['visitesHospi']!, auj: auj), lu('dash-aide-soignant'));
      });
      test('dash-echographiste', () {
        verifier(
            'dash-echographiste',
            tbbEchographiste(resultats: c['resultatsImagerie']!, examensAuCatalogue: tbbActives(c['examensImagerie']!).length, auj: auj),
            lu('dash-echographiste'));
      });
      test('dash-surveillant', () {
        verifier(
            'dash-surveillant',
            tbbSurveillant(presences: c['presences']!, planning: c['planning']!, conges: c['conges']!, personnel: c['personnel']!, auj: auj),
            lu('dash-surveillant'));
      });
      test('dash-assistant-comptable', () {
        verifier(
            'dash-assistant-comptable',
            tbbAssistantDirection(
                factures: c['factures']!, echeances: c['echeancesFiscales']!, ecritures: c['ecritures']!, produits: c['produits']!, auj: auj),
            lu('dash-assistant-comptable'));
      });
      test('dash-chirurgien', () {
        verifier(
            'dash-chirurgien',
            tbbChirurgien(checklists: c['checklistsBloc']!, comptesRendus: c['crOperatoires']!, admissions: c['admissions']!, auj: auj),
            lu('dash-chirurgien'));
      });
      test('dash-anesthesiste', () {
        verifier(
            'dash-anesthesiste',
            tbbAnesthesiste(checklists: c['checklistsBloc']!, comptesRendus: c['crOperatoires']!, admissions: c['admissions']!, auj: auj),
            lu('dash-anesthesiste'));
      });
      test('dash-aide-comptable', () {
        verifier('dash-aide-comptable', tbbAssistantComptable(ecritures: c['ecritures']!, factures: c['factures']!, auj: auj), lu('dash-aide-comptable'));
      });
      test('dash-maternite', () {
        final l = lu('dash-maternite');
        verifier(
            'dash-maternite',
            tbbMaternite(
                dossiers: c['dossiersObstetricaux']!,
                partogrammes: c['partogrammes']!,
                accouchements: c['accouchements']!,
                naissances: c['naissances']!,
                auj: auj),
            l);
        final tables = liste(l['tables']);
        List<List<String>> cel(M t) => [
              for (final r in liste(t['lignes'])) [for (final x in (r['cellules'] as List)) '$x']
            ];
        expect([for (final p in tbbTravauxEnCours(c['partogrammes']!)) tbbCellulesTravail(p)], cel(tables[0]));
        final termes = tbbTermesProches(c['dossiersObstetricaux']!, 15, auj).take(12).toList();
        expect([for (final d in termes) tbbCellulesTerme(d, auj)], cel(tables[1]));
        expect([for (final d in tbbGrossessesARisque(c['dossiersObstetricaux']!).take(10)) tbbCellulesRisque(d)], cel(tables[2]));
        // « Lecture du mois » : le classement des facteurs (second classement de la page) et les accouchements du mois par type.
        final classements = (l['classement'] as List).map((x) => x as List).toList();
        final lignesClassement = [for (final x in (classements.last[1] as List)) '$x'];
        expect([for (final f in tbbFacteursFrequents(c['dossiersObstetricaux']!)) '${f.$1} ${f.$2}'], lignesClassement);
        final parType = tbbAccouchementsParType(c['accouchements']!, auj);
        final vides = (l['vides'] as List).map((x) => x as List).toList();
        final videParType = vides.any((x) => x.first == 'Accouchements du mois par type');
        expect(videParType, parType.isEmpty);
        if (parType.isNotEmpty) {
          final g = obj(liste(l['graphiques']).first);
          expect([for (final t in parType) t.$1], g['etiquettes']);
          expect([for (final t in parType) t.$2], obj(liste(g['series']).first)['data']);
        }
      });
    });
  }

  test('termes : un terme dépassé reste dans la fenêtre, tri stable du plus ancien au plus proche', () {
    final d = <M>[
      {'id': 'a', 'dpa': '2026-11-05', 'statutDossier': 'suivi'},
      {'id': 'b', 'dpa': '2026-10-01', 'statutDossier': 'suivi'},
      {'id': 'c', 'dpa': '2026-10-01', 'statutDossier': 'suivi'},
      {'id': 'd', 'dpa': '2026-12-31', 'statutDossier': 'suivi'},
      {'id': 'e', 'dpa': '2026-11-01', 'statutDossier': 'clos'},
    ];
    expect([for (final x in tbbTermesProches(d, 15, auj)) x['id']], ['b', 'c', 'a']);
    expect(tbbEcheanceTerme(d[1], auj), (texte: 'dépassé de 29 j', ton: 'danger'));
    expect(tbbEcheanceTerme(d[0], auj).ton, 'warning');
  });
}
