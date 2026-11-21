// Rejoue `test/vecteurs/versements.json` (prototype_html/build/vecteurs-versements.js : le moteur RÉEL des versements de la maquette piloté dans Chrome, horloge d'extraction au
// 30/10/2026 midi) sur les règles du lot PAIE-V : le montant en lettres (règle unique de la mention « Arrêtée la présente facture à la somme de »), la résolution des types, modalités
// et opérateurs À LA DATE (versions datées, un archivé reste lisible), le contrôle d'un lot de versements (refus nommés), les séquences d'encaissement par versements (lignes
// réglées, reste dû, statut, mode de la pièce, base MECeF, une écriture équilibrée par versement) et le rejeu de la mère.
//
// Mutations rouges (voir le compte rendu du lot) : versement supérieur au dû accepté, mobile money sans référence accepté, prestation débloquée par un versement partiel,
// modalité écrite en dur, mode imprimé sur la facture normalisée, versement réécrit, versement envoyé à un téléphone.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];

void main() {
  final v = obj(jsonDecode(File('test/vecteurs/versements.json').readAsStringSync()));
  final fiches = liste(v['fiches']);

  group('le montant en lettres : la mention légale', () {
    test('la formule est celle de l’identité imprimée', () {
      expect(IdentiteClinique.formuleArrete, v['formuleArrete']);
    });
    for (final c in liste(v['lettres'])) {
      test('${c['valeur']}', () {
        expect(nombreEnLettres(c['valeur']), c['nombre']);
        expect(montantEnLettres(c['valeur']), c['montant']);
      });
    }
    test('les accords que l’ancienne règle ratait', () {
      expect(montantEnLettres(1), 'un franc CFA');
      expect(montantEnLettres(0), 'zéro franc CFA');
      expect(montantEnLettres(1000000), 'un million de francs CFA');
      expect(montantEnLettres(280000), 'deux cent quatre-vingt mille francs CFA');
      expect(montantEnLettres(200000), 'deux cent mille francs CFA');
      expect(montantEnLettres(23500), 'vingt-trois mille cinq cents francs CFA');
    });
  });

  group('les modalités de versement : la semence et les versions datées', () {
    test('la semence égale celle de la maquette (huit fiches, défaut à valider)', () {
      expect(semenceModalitesVersement(), [for (final x in liste(v['semence'])) x]);
    });
    test('le geste réservé est un droit de la fiche RBAC, jamais un nom de rôle', () {
      expect(gesteReglerModalitesVersement, v['geste']);
    });
    for (final c in liste(v['resolutions'])) {
      test('${c['famille']} ${c['code']} au ${c['date']}', () {
        final r = modaliteVersementALaDate(fiches, '${c['famille']}', c['code'], '${c['date']}');
        expect(r != null, c['existe']);
        if (r != null) {
          expect(r['actif'] != false, c['actif']);
          expect(r['libelle'], c['libelle']);
        }
      });
    }
    for (final c in liste(v['actives'])) {
      test('les codes proposés au ${c['date']}', () {
        for (final f in famillesVersement) {
          expect([for (final x in modalitesVersementActives(fiches, f, '${c['date']}')) x['code']], c[f]);
        }
      });
    }
    test('sans fiche en base, la semence tient lieu de défaut', () {
      expect([for (final x in modalitesVersementActives(const [], 'modalite', '2026-10-30')) x['code']], ['especes', 'mobile_money', 'tpe']);
    });
  });

  group('le contrôle d’un lot de versements : refus nommés (code, motif, geste)', () {
    for (final c in liste(v['controle'])) {
      test('${c['nom']}', () {
        final r = controlerVersements(obj(c['piece']), liste(c['versements']), '${c['date']}', fiches);
        final s = obj(c['sortie']);
        expect(r.ok, s['ok'] == true, reason: '${r.refus?.code}');
        if (s['ok'] == true) {
          expect(r.total, (s['total']! as num).toDouble());
          expect(r.lignes.length, (s['lignes']! as List).length);
          for (var i = 0; i < r.lignes.length; i++) {
            final a = r.lignes[i], b = obj((s['lignes']! as List)[i]);
            for (final k in b.keys) {
              expect(a[k], b[k] is num ? (b[k]! as num).toDouble() : b[k], reason: k);
            }
            expect(a.keys.toSet(), b.keys.toSet());
          }
        } else {
          expect(r.refus!.code, s['code']);
          expect(r.refus!.motif, s['motif']);
          expect(r.refus!.geste, s['geste']);
          expect(r.refus!.rang, s['rang']);
          expect(r.refus!.famille, s['famille']);
        }
      });
    }
  });

  group('les séquences d’encaissement par versements', () {
    for (final sq in liste(v['sequences'])) {
      test('${sq['nom']}', () {
        var facture = obj(sq['depart']);
        for (final e in liste(sq['etapes'])) {
          // L'état d'avant celui de la maquette : la pièce et ses écritures telles que le moteur les a vues.
          facture = obj(e['factureAvant']);
          final s = obj(e['sortie']);
          final r = encaisser(facture,
              versements: liste(e['versements']),
              modalites: fiches,
              rangDepart: e['rangDepart'] as int,
              aujourdhui: '2026-10-30',
              maintenant: '2026-10-30T12:00:00.000Z',
              utilisateur: 'Admin Vecteur',
              ecritures: liste(e['ecrituresAvant']));
          if (s['ok'] != true) {
            expect(r.refusCode, s['code'], reason: '${r.refus}');
            expect(r.refus, contains('${s['motif']}'));
            expect(r.ecritures, isEmpty);
            expect(r.versements, isEmpty);
            expect(identical(r.facture, facture), isTrue, reason: 'une pièce refusée reste inchangée');
            continue;
          }
          expect(r.refus, isNull);
          expect(r.montantRegle, (s['montantRegle']! as num).toDouble());
          expect(r.restantDu, (s['restantDu']! as num).toDouble());
          expect(r.lignesReglees, [for (final x in (s['lignesReglees']! as List)) '$x']);
          final f = obj(s['facture']);
          expect(r.facture['statutPaiement'], f['statutPaiement']);
          expect(r.facture['montantPaye'], (f['montantPaye']! as num).toDouble());
          expect(r.facture['reliquat'], (f['reliquat']! as num).toDouble());
          expect(r.facture['modePaiement'], f['modePaiement']);
          expect(r.facture['baseMecef'], (f['baseMecef']! as num).toDouble());
          expect([for (final l in (r.facture['lignes']! as List)) [obj(l)['id'], obj(l)['statutPaiement']]], [for (final l in (f['lignes']! as List)) l]);
          // Une écriture ÉQUILIBRÉE par versement (RG-10), au compte de sa modalité ; la maquette les range du plus récent au plus ancien.
          String cle(Iterable<Object?> x) => x.map((y) => y is num ? y.toDouble().toString() : '$y').join('|');
          final attendues = [for (final x in (s['ecritures']! as List)) cle(x as List)]..sort();
          final obtenues = [for (final x in r.ecritures) cle([x['compte'], x['debit'], x['credit']])]..sort();
          expect(obtenues, attendues);
          for (final par in r.ecrituresParVersement) {
            final d = par.fold<double>(0, (n, x) => n + (x['debit']! as double));
            final c = par.fold<double>(0, (n, x) => n + (x['credit']! as double));
            expect(d, c, reason: 'RG-10 : chaque versement a son écriture équilibrée');
          }
          expect(r.versements.length, (s['versements']! as List).length);
          for (var i = 0; i < r.versements.length; i++) {
            final a = r.versements[i], b = obj((s['versements']! as List)[i]);
            expect(a['rang'], b['rang']);
            expect(a['type'], b['type']);
            expect(a['modalite'], b['modalite']);
            expect(a['operateur'], b['operateur']);
            expect(a['referenceTransaction'], b['referenceTransaction']);
            expect(a['montant'], (b['montant']! as num).toDouble());
            expect(a['resteApres'], (b['resteApres']! as num).toDouble());
            expect(a['compte'], b['compte']);
            expect(a['horsJour'] == true, b['horsJour']);
          }
        }
      });
    }
  });

  group('le mode porté par la pièce', () {
    for (final c in liste(v['modes'])) {
      test('${c['mode']}', () {
        final lignes = controlerVersements(
            {'id': 'F', 'numero': 'F', 'statutPaiement': 'impayee', 'montantPaye': 0, 'partPatient': 100, 'lignes': const []}, liste(c['versements']), '2026-10-30', fiches);
        expect(modePieceDepuis(lignes.lignes), c['mode']);
      });
    }
  });

  group('la synchronisation : famille A, identité par le contenu, jamais vers un téléphone', () {
    test('versementsCaisse voyage (gestion synchronisée) et ne va JAMAIS vers un téléphone (RG-13) ; les modalités sont de la configuration de la mère, jamais vers un téléphone', () {
      expect(collectionsGestionSynchronisees, contains('versementsCaisse'));
      expect(collectionsGestionJamaisMobile, contains('versementsCaisse'));
      expect(collectionsGestionJamaisMobile, contains('modalitesVersement'));
      expect(collectionsVersementsConfiguration, {'modalitesVersement'});
    });
    test('l’identité est celle du CONTENU : le même versement rejoué est le même, deux versements différents ne fusionnent pas', () {
      M v(Object? montant, {String h = '2026-11-20T09:00:00.000Z', String? ref}) =>
          {'factureId': 'F1', 'horodatage': h, 'modalite': 'mobile_money', 'operateur': 'mtn', 'referenceTransaction': ref ?? 'M1', 'montant': montant};
      expect(identiteSyncGestion('versementsCaisse', v(15000)), identiteSyncGestion('versementsCaisse', v(15000)));
      expect(identiteSyncGestion('versementsCaisse', v(15000)), startsWith('VRS-'));
      expect(identiteSyncGestion('versementsCaisse', v(15000)), isNot(identiteSyncGestion('versementsCaisse', v(8500))));
      expect(identiteSyncGestion('versementsCaisse', v(15000)), isNot(identiteSyncGestion('versementsCaisse', v(15000, h: '2026-11-20T09:00:01.000Z'))));
      expect(identiteSyncGestion('versementsCaisse', v(15000)), isNot(identiteSyncGestion('versementsCaisse', v(15000, ref: 'M2'))));
      expect(identiteSyncGestion('versementsCaisse', {...v(5000), 'rang': 1}), isNot(identiteSyncGestion('versementsCaisse', {...v(5000), 'rang': 2})), reason: 'deux versements identiques d’un même lot restent deux');
      expect(identiteSyncGestion('versementsCaisse', {'factureId': 'F1', 'montant': 1}), isNull, reason: 'sans instant ni modalité, aucune identité inventée');
    });
  });

  group('le rejeu de la mère : un versement qui ferait dépasser le dû est refusé', () {
    for (final c in liste(v['rejeu'])) {
      test('${c['nom']}', () {
        final r = refusRejeuVersement(obj(c['piece']), {...obj(c['entrant']), 'date': c['date']}, (c['dejaVerse']! as num).toDouble(), fiches);
        final s = c['sortie'] == null ? null : obj(c['sortie']);
        expect(r?.code, s?['code']);
        expect(r?.motif, s?['motif']);
      });
    }
  });
}
