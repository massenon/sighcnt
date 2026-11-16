// LOT TARIF-FIX-2 : rejoue les vecteurs engendrés par la maquette (prototype_html/build/vecteurs-prix-manquant.js) : manque nommé, totaux non
// calculables, réglage d'encaissement partiel daté, MECeF qui refuse une ligne sans prix, séquences d'encaissement d'une pièce en attente de prix,
// valorisation à la date de la pièce.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> m(Object? v) => (v! as Map).cast<String, Object?>();
List<Map<String, Object?>> l(Object? v) => ((v ?? const []) as List).map(m).toList();

void main() {
  final f = File('test/vecteurs/prix_manquant.json');
  if (!f.existsSync()) fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-prix-manquant.js`');
  final v = m(jsonDecode(f.readAsStringSync()));

  group('le manque d’une ligne (« prix à valoriser », « prix à définir »)', () {
    for (final c in l(v['manque'])) {
      test('${c['nom']}', () {
        final e = m(c['entree']);
        final r = e['r'] == null ? null : m(e['r']);
        expect(
            manqueDePrix('${e['nature']}', e['code'], e['libelle'],
                cause: r?['cause'] as String?, motif: r?['motif'] as String?, geste: r?['geste'] as String?, effectifLe: r?['effectifLe'] as String?),
            m(c['sortie']));
      });
    }
  });

  group('les totaux d’une pièce : la somme des lignes, ou NULS (non calculable)', () {
    for (final c in l(v['totaux'])) {
      test('${c['nom']}', () => expect(totauxPiece(l(c['lignes'])), m(c['sortie'])));
    }
  });

  group('le réglage « encaissement partiel » à la date (défaut semé « non »)', () {
    for (final c in l(v['reglage'])) {
      test('${c['nom']}', () {
        final r = encaissementPartielALaDate(c['versions'] == null ? null : l(c['versions']), '${c['jour']}');
        final s = m(c['sortie']);
        expect((r.valeur, r.partiel, r.dateEffet, r.version, r.source), (s['valeur'], s['partiel'], s['dateEffet'], s['version'], s['source']));
      });
    }
  });

  group('MECeF : une ligne sans prix ne part jamais au boîtier', () {
    for (final c in l(v['mecef'])) {
      test('${c['nom']}', () {
        final r = mecefMontants(lignes: l(c['lignes']));
        final s = m(c['sortie']);
        expect(r.ok, s['ok']);
        if (s['ok'] == false) {
          expect((r.refus!.code, r.refus!.motif, r.refus!.geste), (s['code'], s['motif'], s['geste']));
        } else {
          expect(r.montants!.total, s['total']);
        }
      });
    }
  });

  group('encaisser une pièce en attente de prix (séquences de la maquette)', () {
    for (final c in l(v['encaisser'])) {
      test('${c['nom']}', () {
        var facture = m(c['facture']);
        for (final e in l(c['etapes'])) {
          final o = m(e['opts']);
          final r = encaisser(facture,
              lignes: o['lignes'] == null ? null : [for (final x in o['lignes']! as List) '$x'],
              montant: o['montant'] as num?,
              aujourdhui: '2026-08-16',
              maintenant: '2026-08-16T10:00:00.000Z',
              encaissementPartiel: c['partiel'] == true);
          expect(r.refusCode == codeRefusEncaissementPrix ? r.refusCode : null, e['refusCode'], reason: 'code du refus');
          expect(r.refus, e['refus'], reason: 'motif et geste mot pour mot');
          expect(r.lignesReglees, e['lignesReglees']);
          expect(r.montantRegle, e['montantRegle']);
          expect(r.restantDu, e['restantDu']);
          final s = m(e['facture']);
          final apres = r.refus != null ? facture : r.facture;
          expect(apres['statutPaiement'], s['statutPaiement']);
          expect(apres['reliquat'], s['reliquat']);
          expect(apres['montantPaye'], s['montantPaye']);
          expect([for (final x in l(apres['lignes'])) {'id': x['id'], 'statutPaiement': x['statutPaiement']}], l(s['lignes']));
          if (r.refus == null) facture = r.facture;
        }
      });
    }
  });

  group('valoriser à la date de la pièce', () {
    for (final c in l(v['valoriser'])) {
      test('${c['nom']}', () {
        final facture = m(c['facture']);
        final prix = m(c['prix']);
        final tarifs = [for (final e in prix.entries) {'id': e.key, 'code': e.key, 'codeActe': e.key, 'libelle': 'Acte à valoriser', 'famille': 'ACTE', 'statut': 'actif'}];
        final versions = [
          for (final e in prix.entries)
            {'id': '${e.key}@${facture['date']}@1', 'code': e.key, 'version': 1, 'dateEffet': facture['date'], 'statut': 'valide', 'etatAssure': 'unique', 'prixNonAssure': e.value}
        ];
        final h = ReferentielTarifs(tarifs, versions);
        PrixEnAttente lire(Map<String, Object?> ligne) {
          final mq = m(ligne['prixManquant']);
          final jour = '${facture['date']}';
          final r = h.prixDeLigne(mq['code'], jour, false, voie: 'acte', aujourdhui: jour);
          if (!r.ok) return (ok: false, prixUnitaire: null, montant: null, version: null, manque: manqueDepuisLignePrix(r, mq['code'], mq['libelle'], voie: 'acte'));
          return (ok: true, prixUnitaire: r.montant, montant: r.montant, version: r.version, manque: null);
        }

        final r = valoriserLignes(facture, lire, maintenant: '2026-08-16T10:00:00.000Z', aujourdhui: '2026-08-16');
        final s = m(c['sortie']);
        expect(r.valorisees, l(s['valorisees']));
        expect(r.restantes, l(s['restantes']));
        final sf = m(s['facture']);
        expect([for (final x in l(r.facture['lignes'])) {...x}..remove('valoriseLe')], l(sf['lignes']));
        for (final k in ['montantTTC', 'montantHT', 'montantBrut', 'partAssurance', 'partPersonnel', 'partPatient', 'reliquat', 'enAttentePrix']) {
          expect(r.facture[k], sf[k], reason: k);
        }
      });
    }
  });

  test('le refus nommé porte le geste de la date de la pièce et ne dit jamais « 0 »', () {
    final r = refusEncaissementPrix({'numero': 'FP-1', 'date': '2026-08-14'}, [manqueDePrix(natureManqueTarif, 'X1', 'Acte', motif: '« X1 » Acte : prix à définir')], false,
        aujourdhui: '2026-08-16');
    expect(r.code, 'ENCAISSEMENT_PRIX_MANQUANT');
    expect(r.geste, contains('date d’effet du 14/08/2026 au plus tard'));
    expect(r.motif, isNot(contains(' 0 ')));
  });
}
