// Lot MECEF-M : l'état de la caisse, l'imprimante de caisse datée, les gestes réservés et le port `Mecef`, rejoués sur les vecteurs tirés de la maquette pilotée
// (prototype_html/build/vecteurs-mecef-m.js).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> m(Object? x) => (x as Map).cast<String, Object?>();
List<Map<String, Object?>> lm(Object? o) => [for (final x in (o as List)) m(x)];

void main() {
  final f = File('test/vecteurs/mecef_m.json');
  if (!f.existsSync()) fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-mecef-m.js`');
  final j = m(jsonDecode(f.readAsStringSync()));
  final imp = m(j['imprimante']);
  final ref = m(imp['refus']);

  group('gestes réservés', () {
    test('les deux ids sont ceux du manifeste, détenus d\'origine par la liste de la maquette', () {
      final g = m(j['gestes']);
      expect(g.keys.toSet(), {mecefGesteMode, mecefGesteImprimante});
      final rbac = m(jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()));
      final jeux = lm(m(rbac['gestes'])['jeux']);
      for (final id in g.keys) {
        final d = jeux.firstWhere((x) => x['id'] == id);
        expect(d['rolesDefaut'], m(g[id])['rolesDefaut'], reason: id);
      }
    });
  });

  group('imprimante de caisse', () {
    test('le défaut semé est celui de la maquette (Xprinter XP-Q800, thermique 80 mm, liaison à vérifier)', () {
      final d = m(imp['defaut']);
      expect(imprimanteSemee.modele, d['modele']);
      expect(imprimanteSemee.type, d['type']);
      expect(imprimanteSemee.largeurMm, d['largeurMm']);
      expect(imprimanteSemee.liaison, d['liaison']);
      expect(imprimanteSemee.nom, d['nom']);
      expect(imprimanteSemee.liaisonLibelle, d['liaisonLibelle']);
      expect(imprimanteSemee.source, d['source']);
    });

    test('la lecture à la date : version en vigueur, jamais réécrite, défaut avant la première', () {
      final ok0 = m(imp['ok0']);
      final versions = [
        VersionImprimante(dateEffet: '${ok0['dateEffet']}', modele: 'Xprinter XP-Q800', liaison: '${ok0['liaison']}', nom: '${ok0['nom']}'),
        const VersionImprimante(dateEffet: '2026-12-01', modele: 'Xprinter XP-Q800', liaison: 'ethernet', nom: 'Caisse 1 réseau'),
      ];
      for (final l in lm(imp['lectures'])) {
        final v = imprimanteALaDate(versions, '${l['date']}');
        expect([v.source, v.nom, v.liaison, v.modele, v.dateEffet], [l['source'], l['nom'], l['liaison'], l['modele'], l['dateEffet']], reason: '${l['date']}');
      }
    });

    test('les refus : mêmes codes, motifs et gestes que la maquette, dans le même ordre', () {
      final ok0 = m(imp['ok0']);
      RefusMecef? ctrl({bool droit = true, bool fileul = false, String? motif, String? date, String? nom, String? liaison}) => imprimanteControler(
            aDroit: droit,
            fileul: fileul,
            motif: motif ?? '${ok0['motif']}',
            dateEffet: date ?? '${ok0['dateEffet']}',
            aujourdhui: '2026-10-30',
            nom: nom ?? '${ok0['nom']}',
            liaison: liaison ?? '${ok0['liaison']}',
            libelleRole: 'Caissier — Dispensaire (Pharmacie)',
            rolesQuiLeDetiennent: 'Administrateur système, Directrice de l’Administration et des Finances (DAF)',
          );
      void egal(RefusMecef? r, Map<String, Object?> attendu) {
        expect(r, isNotNull);
        expect([r!.code, r.motif, r.geste], [attendu['code'], attendu['motif'], attendu['geste']]);
      }

      egal(ctrl(droit: false), m(ref['reserve']));
      egal(ctrl(fileul: true), m(ref['fileul']));
      egal(ctrl(motif: ' '), m(ref['motif']));
      egal(ctrl(date: '2026-10-01'), m(ref['datePassee']));
      egal(ctrl(nom: '  '), m(ref['nom']));
      egal(ctrl(liaison: 'bluetooth'), m(ref['liaison']));
      egal(ctrl(liaison: 'a_verifier'), m(ref['liaisonAVerifier']));
      expect(ctrl(), isNull);
      // l'ordre : sans droit ET fileul, c'est le droit qui parle d'abord
      expect(ctrl(droit: false, fileul: true, motif: '')!.code, 'IMPRIMANTE_RESERVE');
    });
  });

  group('registre', () {
    test('le défaut semé du paramètre dit la même chose que le défaut du domaine ; la famille mecef n\'est pas au panneau générique', () {
      final d = definitionsParametres.firstWhere((x) => x.cle == mecefCleImprimante);
      expect(d.famille, 'mecef');
      expect(jsonDecode('${d.defaut}'),
          {'modele': imprimanteSemee.modele, 'type': imprimanteSemee.type, 'largeurMm': imprimanteSemee.largeurMm, 'liaison': imprimanteSemee.liaison, 'nom': imprimanteSemee.nom});
      expect(parFamillesReglageDedie, contains('mecef'));
      expect(parFamillesJamaisMobile, contains('mecef'));
      final v = imprimanteVersionDepuisRegistre('2026-11-15', imprimanteValeurJson(modele: 'M', type: 'thermique', largeurMm: 80, liaison: 'usb', nom: 'N'), motif: 'x')!;
      expect([v.dateEffet, v.liaison, v.nom, v.motif], ['2026-11-15', 'usb', 'N', 'x']);
      expect(imprimanteVersionDepuisRegistre('2026-11-15', 'pas du json'), isNull);
    });
    test('le changement de mode : inconnu, droit réservé, fileul, dans cet ordre (codes de la maquette)', () {
      final v = m(j['mode']);
      expect(mecefModeControler(mode: 'inconnu', aDroit: true, fileul: false)!.code, m(v['inconnu'])['code']);
      expect(mecefModeControler(mode: 'emecef', aDroit: false, fileul: false)!.code, m(v['refus'])['code']);
      expect(mecefModeControler(mode: 'emecef', aDroit: true, fileul: true)!.code, 'FILEUL_LECTURE_SEULE');
      expect(mecefModeControler(mode: 'inconnu', aDroit: false, fileul: true)!.code, 'MODE_INCONNU');
      expect(mecefModeControler(mode: 'emecef', aDroit: true, fileul: false), isNull);
    });
  });

  group('état de la caisse', () {
    for (final c in lm(j['caisse'])) {
      test('cas « ${c['nom']} »', () {
        final e0 = m(c['entrees']);
        final e = etatCaisse([for (final x in lm(e0['factures'])) PieceCaisse.depuisJson(x)], [for (final x in lm(e0['avoirs'])) AvoirCaisse.depuisJson(x)]);
        final a = m(c['attendu']);
        final v = m(a['ventes']), av = m(a['avoirs']);
        expect(e.ventes, v['nombre']);
        expect(e.parEtat, (m(v['parEtat'])).map((k, x) => MapEntry(k, (x as num).toInt())));
        expect(e.ventesIncalculables, v['incalculables']);
        expect(e.ventesMontant, v['montant'], reason: 'null = non calculable, jamais zéro');
        expect(e.avoirs, av['nombre']);
        expect(e.avoirsIncalculables, av['incalculables']);
        expect(e.avoirsMontant, av['montant']);
      });
    }
  });

  group('port Mecef : deux réalisations vides qui refusent nommément', () {
    test('boîtier : en attente des réponses du fournisseur ; e-MECeF : dossier d\'interface DGI requis', () async {
      final b = adaptateurPourMode('boitier');
      final e = adaptateurPourMode('emecef');
      expect(b, isA<MecefBoitierVide>());
      expect(e, isA<MecefEmecefVide>());
      expect(b.configure, isFalse);
      expect(e.configure, isFalse);
      expect(b.refus!.code, mecefCodeNonConfigure);
      expect(e.refus!.code, 'MECEF_NON_CONFIGURE');
      expect(b.refus!.motif, contains('en attente des réponses du fournisseur'));
      expect(e.refus!.motif, contains('dossier d’interface DGI requis'));
      const d = DemandeCertification(cle: 'k', total: 1000, base: 1000, aib: 0);
      for (final a in [b, e]) {
        final r = await a.emettre(d);
        expect(r.ok, isFalse);
        expect(r.numero, isNull, reason: 'aucun numéro n\'est fabriqué');
        expect(r.refus!.code, mecefCodeNonConfigure);
      }
    });
  });
}
