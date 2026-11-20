// Le mode de certification MECeF (lot L3) : rejoue les vecteurs de la maquette (prototype_html/build/vecteurs-mecef-mode.js) pour le mode e-MECeF, et
// éprouve ce que la maquette ne simule pas : l'adaptateur du boîtier, qui n'existe pas au poste.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> m(Object? x) => (x as Map).cast<String, Object?>();

void main() {
  final f = File('test/vecteurs/mecef_mode.json');
  if (!f.existsSync()) {
    fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-mecef-mode.js`');
  }
  final j = m(jsonDecode(f.readAsStringSync()));

  group('le mode en vigueur (vecteurs de la maquette)', () {
    for (final c in (j['modes'] as List).map(m)) {
      test('réglage ${c['reglage']} : mode ${c['mode']}', () {
        expect(mecefModeEnVigueur(c['reglage']), c['mode']);
      });
    }
    test('deux modes seulement, le boîtier par défaut', () {
      expect(mecefModes, ['boitier', 'emecef']);
      expect(mecefModeDefaut, 'boitier');
      expect(mecefModeEnVigueur(null), 'boitier');
      expect(mecefModeEnVigueur(42), 'boitier');
    });
  });

  group('e-MECeF non configuré (vecteurs de la maquette)', () {
    final ad = m(j['adaptateurEmecef']);
    test('l\'adaptateur refuse en nommant : code, motif, geste ; configuré faux', () {
      final a = adaptateurPourMode('emecef');
      expect(a.configure, isFalse);
      expect(a.mode, 'emecef');
      expect(ad['configure'], isFalse);
      expect(a.refus!.code, ad['code']);
      expect(a.refus!.motif, ad['motif']);
      expect(a.refus!.geste, ad['geste']);
    });
    test('une vente encaissée sous e-MECeF : refus nommé, pièce en attente, AUCUN numéro', () {
      final v = m(j['vente']);
      final piece = {...m(v['piece']), 'montantPaye': m(v['facture'])['montantPaye'], 'statutPaiement': m(v['facture'])['statutPaiement']};
      final prep = preparerNormalisation(piece, acheteurSaisi: m(v['acheteur']));
      expect(prep.ok, isTrue, reason: 'la préparation (acheteur, montants) précède l\'adaptateur');
      final refus = adaptateurPourMode('emecef').refus!;
      final norm = m(v['normalisation']);
      expect(norm['ok'], isFalse);
      expect(refus.code, norm['code']);
      expect(refus.motif, norm['motif']);
      expect(refus.geste, norm['geste']);
      expect(norm['etat'], 'en_attente');
      final champs = champsEnAttenteCertification(refus, 'emecef');
      final fac = m(v['facture']);
      expect(champs['statutMecef'], fac['statutMecef']);
      expect(champs['codeRetour'], fac['codeRetour']);
      expect(champs['motifRefusMecef'], fac['motifRefusMecef']);
      expect(champs['modeMecef'], fac['modeMecef']);
      expect(champs.containsKey('numeroMecef'), isFalse);
      expect(fac['numeroMecef'], isNull);
      expect(v['numerosFabriques'], 0);
      expect(v['emissionsAppareil'], 0);
      expect(fac['statutPaiement'], 'soldee', reason: 'l\'encaissement reste acquis');
    });
  });

  group('le boîtier : aucun adaptateur au poste (écart assumé de la maquette)', () {
    test('le mode boîtier refuse lui aussi, avec le même code et son propre motif', () {
      final a = adaptateurPourMode('boitier');
      expect(a.configure, isFalse);
      expect(a.refus!.code, mecefCodeNonConfigure);
      expect(a.refus!.motif, contains('Boîtier non configuré'));
      expect(a.refus!.geste, contains('en attente de certification'));
    });
    test('une valeur inconnue retombe sur le boîtier, jamais sur un adaptateur muet', () {
      expect(adaptateurPourMode('xyz').mode, 'boitier');
    });
    test('émettre ne répond jamais par un numéro', () async {
      for (final mode in mecefModes) {
        final r = await adaptateurPourMode(mode).emettre(const DemandeCertification(cle: 'F1', total: 14000, base: 14000, aib: 140));
        expect(r.ok, isFalse);
        expect(r.numero, isNull);
        expect(r.refus!.code, mecefCodeNonConfigure);
      }
    });
    test('les champs laissés par le refus : en attente, sans numéro, mode porté', () {
      final c = champsEnAttenteCertification(adaptateurPourMode('boitier').refus!, 'boitier');
      expect(c['statutMecef'], 'en_attente');
      expect(c['modeMecef'], 'boitier');
      expect(c.containsKey('numeroMecef'), isFalse);
    });
  });

  test('la définition du registre : clé, défaut boîtier, choix, branchée', () {
    final d = definitionsParametres.firstWhere((x) => x.cle == mecefCleMode);
    expect(d.defaut, 'boitier');
    expect(d.choix, mecefModes);
    expect(d.branche, isTrue);
    expect(d.famille, 'mecef');
  });
}
