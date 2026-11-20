// Rejoue les vecteurs du moteur de validation commun des référentiels (prototype_html/build/vecteurs-validation.js) : le MOTEUR RÉEL de la maquette
// (`SIGH.validations`) piloté dans Chrome sur des fiches posées. Le registre, les comptes lus, les états, le geste (refus nommés compris), la remise à
// valider et la vue de chaque profil sont comparés champ par champ ; ce que le geste ÉCRIT est appliqué à la copie des fiches d'entrée puis comparé à
// l'état du magasin APRÈS le geste, et la ligne de journal à celle que la maquette a écrite (RG-12).
import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

typedef M = Map<String, Object?>;

M obj(Object? o) => (o as Map).cast<String, Object?>();

final v = lireVecteurs('validation');
final libelles = {for (final e in (v['libelles'] as Map).entries) '${e.key}': '${e.value}'};
const marqueur = '@@MAINTENANT@@';

LectureValidation lecture(Map<String, Object?> entree) =>
    (nom) => [for (final f in (entree[nom] as List? ?? const [])) (f as Map).cast<String, Object?>()];

/// Copie PROFONDE de l'état de toutes les collections, pour appliquer ce que le geste écrit sans toucher aux vecteurs.
Map<String, List<M>> copie(Object? brut) => {
      for (final e in (brut as Map).entries)
        '${e.key}': [for (final f in (e.value as List)) (jsonDecode(jsonEncode(f)) as Map).cast<String, Object?>()]
    };

/// Applique un verdict de validation (ce que le poste fait avec le magasin) : patch sur la fiche, ou création de la fiche VRF.
void appliquer(Map<String, List<M>> etat, VerdictValidation r) {
  final col = etat[r.collection!]!;
  if (r.creation != null) {
    col.add({...r.creation!});
  } else {
    final id = r.collection == valCollectionValidations ? 'VRF-${r.id}' : r.id;
    col.firstWhere((f) => f['id'] == id).addAll(r.patch);
  }
}

String extrait(Map<String, Object?> m) {
  final s = jsonEncode(m);
  return s.length > 100 ? s.substring(0, 100) : s;
}

void main() {
  test('le registre porte les 15 familles de la maquette, champ par champ', () {
    final reg = liste(v['registre']);
    expect(valFamilles.length, reg.length);
    expect(valFamilles.length, 15);
    for (var i = 0; i < reg.length; i++) {
      final f = valFamilles[i], r = reg[i];
      expect([f.id, f.libelle, f.module, f.mode, f.ecran], [r['id'], r['libelle'], r['module'], r['mode'], r['ecran']], reason: '${r['id']}');
      expect(f.roles, (r['roles'] as List).cast<String>(), reason: '${r['id']} : rôles');
      expect(f.collections, ((r['collections'] ?? const []) as List).cast<String>(), reason: '${r['id']} : collections');
      expect(f.champs, ((r['champs'] ?? const []) as List).cast<String>(), reason: '${r['id']} : champs');
      expect(f.champsChiffres, ((r['champsChiffres'] ?? const []) as List).cast<String>(), reason: '${r['id']} : champs chiffrés (motif obligatoire)');
      expect([for (final c in f.cibles) [c.id, c.libelle]], [for (final c in liste(r['cibles'])) [c['id'], c['libelle']]], reason: '${r['id']} : cibles');
    }
    expect(valVueComplete, (v['vueComplete'] as List).cast<String>());
  });

  group('compte lu (referentielsAValider)', () {
    for (final c in liste(v['comptes'])) {
      test(c['nom'] as String, () {
        final opts = c['opts'] as Map?;
        final r = valReferentielsAValider(lecture(obj(c['entree'])), libelles, role: opts?['role'] as String?);
        final attendu = liste(c['sortie']);
        expect(r.length, attendu.length);
        for (var i = 0; i < attendu.length; i++) {
          final a = attendu[i], x = r[i];
          expect(x.famille, a['famille']);
          expect([x.libelle, x.module, x.mode, x.ecran, x.profil], [a['libelle'], a['module'], a['mode'], a['ecran'], a['profil']], reason: x.famille);
          expect(x.collections, (a['collections'] as List).cast<String>(), reason: '${x.famille} : collections');
          expect(x.champs, (a['champs'] as List).cast<String>(), reason: '${x.famille} : champs');
          expect(x.roles, (a['roles'] as List).cast<String>());
          expect([x.enAttente, x.total, x.nonAmorce, x.ids], [a['enAttente'], a['total'], a['nonAmorce'], (a['ids'] as List).cast<String>()], reason: x.famille);
        }
      });
    }
  });

  test('chaque profil ne voit que les familles de son ressort ; la Direction, la DAF et l’administrateur voient tout', () {
    final vues = obj(v['vues']);
    for (final e in vues.entries) {
      final r = valReferentielsVisiblesPar(e.key, lecture(const {}), libelles);
      expect([for (final x in r) x.famille], (e.value as List).cast<String>(), reason: e.key);
    }
    expect(valPeutValider('pathologies', 'dm'), isTrue);
    expect(valPeutValider('pathologies', 'caissier'), isFalse);
    expect(valPeutValider('famille-inconnue', 'dm'), isFalse);
  });

  group('état lu (etatValidation)', () {
    for (final c in liste(v['etats'])) {
      test(c['nom'] as String, () {
        final e = valEtatValidation('${c['famille']}', '${c['id']}', lecture(obj(c['entree'])), libelles);
        final a = c['sortie'];
        if (a == null) {
          expect(e, isNull);
          return;
        }
        final s = obj(a);
        expect(e, isNotNull);
        expect([e!.famille, e.id, e.libelle, e.enAttente, e.valideLe, e.validePar, e.valideRole, e.profil],
            [s['famille'], s['id'], s['libelle'], s['enAttente'], s['valideLe'], s['validePar'], s['valideRole'], s['profil']]);
        expect(e.roles, (s['roles'] as List).cast<String>());
      });
    }
  });

  group('le geste (validerReferentiel)', () {
    for (final c in liste(v['gestes'])) {
      test(c['nom'] as String, () {
        final role = (c['role'] as String?) ?? (c['roleSession'] as String);
        final maintenant = DateTime.utc(2026, 10, 30, 10, 15, 30, 123);
        final r = valValiderReferentiel('${c['famille']}', '${c['id']}',
            role: role,
            acteur: '${c['acteurSession']}',
            maintenant: maintenant,
            lire: lecture(obj(c['entree'])),
            libelles: libelles);
        final s = obj(c['sortie']);
        expect(r.ok, s['ok'], reason: 'ok');
        if (!r.ok) {
          // Un refus se NOMME (code, motif, geste) et n'écrit RIEN.
          expect([r.refus!.code, r.refus!.motif, r.refus!.geste], [s['code'], s['motif'], s['geste']]);
          expect(r.patch, isEmpty);
          expect(r.journal, isNull);
          expect(c['journal'], isNull);
          expect(c['inchange'], isTrue, reason: 'la maquette n’a rien écrit non plus');
          return;
        }
        expect([r.famille, r.id, r.validePar, r.valideRole], [s['famille'], s['id'], s['validePar'], s['valideRole']]);
        expect(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$').hasMatch(r.valideLe!), isTrue);
        expect(r.valideLe, '2026-10-30T10:15:30.123Z', reason: 'horloge de l’appelant, à la milliseconde');
        // Ce que le geste écrit, appliqué aux fiches d'entrée, donne l'état APRÈS de la maquette (l'instant masqué).
        final etat = copie(c['avantFiches']);
        appliquer(etat, r);
        final apres = copie(c['apres']);
        for (final n in apres.keys) {
          final att = jsonDecode(jsonEncode(apres[n]).replaceAll(marqueur, r.valideLe!));
          memes(etat[n], att, n);
        }
        // UNE ligne de journal (RG-12), celle de la maquette.
        final j = obj(c['journal']);
        expect([r.journal!.action, r.journal!.module, r.journal!.entite, r.journal!.reference], [j['action'], j['module'], j['entite'], j['reference']]);
        expect(extrait(r.journal!.avant), j['avant']);
        expect(extrait(r.journal!.apres), '${j['apres']}'.replaceAll(marqueur, r.valideLe!));
        // Aucun autre champ que le marquage et ses trois traces n'est touché.
        final fiche = r.creation == null ? r.patch : r.creation!;
        final permis = {'valideLe', 'validePar', 'valideRole', 'id', 'statut', 'famille', 'cible', 'libelle', 'source', 'motifPrix', 'observation', 'motifCorrection', ...valFamille(r.famille!)!.champs};
        expect(fiche.keys.every(permis.contains), isTrue, reason: '${fiche.keys}');
      });
    }

    test('chaque famille se valide par son premier rôle, et se refuse hors de son ressort', () {
      for (final c in liste(v['parFamille'])) {
        final f = valFamille('${c['famille']}')!;
        final entree = <String, Object?>{};
        if (f.mode != 'fiche') {
          entree[f.collections.first] = [
            {'id': c['id'], 'statut': 'actif', 'libelle': 'Élément ${c['id']}', f.champs.first: true, 'prix': 1000}
          ];
        }
        final r = valValiderReferentiel(f.id, '${c['id']}',
            role: '${c['role']}', acteur: 'X', maintenant: DateTime.utc(2026, 10, 30), lire: lecture(entree), libelles: libelles);
        expect(r.ok, c['ok'], reason: f.id);
        expect(r.valideRole, c['valideRole'], reason: f.id);
        for (final h in liste(c['refusHorsFamille'])) {
          final x = valValiderReferentiel(f.id, '${c['id']}',
              role: '${h['role']}', acteur: 'X', maintenant: DateTime.utc(2026, 10, 30), lire: lecture(entree), libelles: libelles);
          expect(x.refus?.code, h['code'], reason: '${f.id} / ${h['role']}');
        }
      }
    });
  });

  group('lot L1 : le geste « Valider » (fileul, fiche VRF archivée réactivée, texte épuré, motif)', () {
    for (final c in liste(v['gestesL1'])) {
      test(c['nom'] as String, () {
        final maintenant = DateTime.utc(2026, 10, 30, 10, 15, 30, 123);
        final r = valValiderReferentiel('${c['famille']}', '${c['id']}',
            role: '${c['role']}',
            acteur: '${v['sessionActeur']}',
            maintenant: maintenant,
            lire: lecture(obj(c['entree'])),
            libelles: libelles,
            fileul: c['fileul'] == true,
            motif: c['motif'] as String?);
        final s = obj(c['sortie']);
        expect(r.ok, s['ok'], reason: 'ok');
        if (!r.ok) {
          expect([r.refus!.code, r.refus!.motif, r.refus!.geste], [s['code'], s['motif'], s['geste']]);
          expect(c['journal'], isNull);
          expect(r.patch, isEmpty);
          return;
        }
        final etat = copie(c['avantFiches']);
        appliquer(etat, r);
        final apres = copie(c['apres']);
        for (final n in apres.keys) {
          memes(etat[n], jsonDecode(jsonEncode(apres[n]).replaceAll(marqueur, r.valideLe!)), n);
        }
        expect(etat[valCollectionValidations]!.where((f) => f['id'] == 'VRF-${c['id']}').length, c['nbFichesVrf'], reason: 'UNE fiche VRF par cible, jamais deux');
        final j = obj(c['journal']);
        expect([r.journal!.action, r.journal!.module, r.journal!.entite, r.journal!.reference], [j['action'], j['module'], j['entite'], j['reference']]);
        expect(extrait(r.journal!.avant), j['avant']);
        expect(extrait(r.journal!.apres), '${j['apres']}'.replaceAll(marqueur, r.valideLe!));
      });
    }
  });

  group('lot L1 : enregistrer valide pour le profil de la famille (contrôle et marquage)', () {
    for (final c in liste(v['enregistrements'])) {
      test(c['nom'] as String, () {
        final famille = '${c['famille']}', role = '${c['role']}';
        final avant = c['avant'] == null ? null : obj(c['avant']);
        final valeurs = obj(c['valeurs']);
        final chiffres = valChiffresModifies(famille, avant, valeurs);
        expect(chiffres, (c['chiffres'] as List).cast<String>(), reason: 'champs chiffrés déplacés');
        final refus = valControlerEnregistrement(famille,
            role: role, chiffres: chiffres, motif: c['motif'] as String?, fileul: c['fileul'] == true);
        if (c['controle'] != null) {
          final s = obj(c['controle']);
          expect(refus, isNotNull, reason: 'refus attendu');
          expect([refus!.code, refus.motif, refus.geste], [s['code'], s['motif'], s['geste']]);
          expect(c['marquage'], isNull);
          return;
        }
        expect(refus, isNull);
        final maintenant = DateTime.utc(2026, 10, 30, 10, 15, 30, 123);
        final m = valMarquageEnregistrement(famille,
            role: role,
            acteur: '${c['acteurSession']}',
            maintenant: maintenant,
            libelles: libelles,
            avant: avant,
            valeurs: valeurs,
            motif: c['motif'] as String?,
            modifie: c['modifie'] as bool?);
        final a = obj(c['marquage']);
        expect([m.validateur, m.valide, m.nonValide], [a['validateur'], a['valide'], a['nonValide']]);
        final instant = m.valideLe ?? '@@jamais@@';
        memes(jsonDecode(jsonEncode(m.patch).replaceAll(instant, marqueur)), a['patch'], 'patch');
        expect(m.chiffres, (a['chiffres'] as List).cast<String>());
        final j = obj(a['journal']);
        expect([m.journal.action, m.journal.module, m.journal.entite], [j['action'], j['module'], j['entite']]);
        if (j['avant'] == null) {
          expect(m.journal.avant, isEmpty);
        } else {
          expect(jsonEncode(m.journal.avant), jsonEncode(j['avant']));
        }
        expect(jsonEncode(m.journal.apres).replaceAll(instant, marqueur), jsonEncode(j['apres']), reason: 'la ligne de journal porte l’état');
        // Une création par la famille naît validée (hors tarif absent), hors famille elle naît « à valider ».
        if (avant == null) {
          expect(m.valide, m.validateur && m.nonValide == null);
        }
      });
    }
  });

  group('lot L1 : le suivi d’un artefact tenu ailleurs que dans la fiche écrite', () {
    for (final c in liste(v['suivis'])) {
      test(c['nom'] as String, () {
        final maintenant = DateTime.utc(2026, 10, 30, 10, 15, 30, 123);
        final r = valSuivreEnregistrement('${c['famille']}', '${c['cible']}',
            role: '${c['role']}',
            acteur: '${v['sessionActeur']}',
            maintenant: maintenant,
            lire: lecture(obj(c['entree'])),
            libelles: libelles,
            modifie: c['modifie'] as bool?,
            motif: c['motif'] as String?,
            fileul: c['fileul'] == true);
        final s = obj(c['sortie']);
        expect(r.refus == null, s['ok'], reason: 'ok');
        if (r.refus != null) {
          expect([r.refus!.code, r.refus!.motif, r.refus!.geste], [s['code'], s['motif'], s['geste']]);
          expect(c['journal'], isNull);
          return;
        }
        final etat = copie(c['avantFiches']);
        var instant = '@@jamais@@';
        if (r.validation != null) {
          appliquer(etat, r.validation!);
          instant = r.validation!.valideLe!;
        } else if (r.remise != null && r.remise!.remis) {
          final id = r.remise!.collection == valCollectionValidations ? 'VRF-${r.remise!.id}' : r.remise!.id;
          etat[r.remise!.collection!]!.firstWhere((f) => f['id'] == id).addAll(r.remise!.patch);
        } else {
          expect(c['journal'], isNull, reason: 'rien à écrire : aucune ligne de journal');
        }
        final apres = copie(c['apres']);
        for (final n in apres.keys) {
          memes(etat[n], jsonDecode(jsonEncode(apres[n]).replaceAll(marqueur, instant)), n);
        }
        final jv = r.validation?.journal ?? r.remise?.journal;
        if (c['journal'] != null) {
          final j = obj(c['journal']);
          expect(jv, isNotNull);
          expect([jv!.action, jv.module, jv.entite, jv.reference], [j['action'], j['module'], j['entite'], j['reference']]);
          expect(extrait(jv.avant), j['avant']);
          expect(extrait(jv.apres), '${j['apres']}'.replaceAll(marqueur, instant));
        }
      });
    }
  });

  group('remise à valider (remettreAValider)', () {
    for (final c in liste(v['remises'])) {
      test(c['nom'] as String, () {
        final r = valRemettreAValider('${c['famille']}', '${c['id']}', lire: lecture(obj(c['entree'])));
        final s = obj(c['sortie']);
        expect(r.ok, s['ok']);
        if (!r.ok) {
          expect([r.refus!.code, r.refus!.motif, r.refus!.geste], [s['code'], s['motif'], s['geste']]);
          expect(c['journal'], isNull);
          return;
        }
        expect(r.remis, s['remis']);
        if (!r.remis) {
          expect(r.patch, isEmpty);
          expect(r.journal, isNull);
          expect(c['journal'], isNull);
          return;
        }
        final etat = copie(c['avantFiches']);
        final id = r.collection == valCollectionValidations ? 'VRF-${r.id}' : r.id;
        etat[r.collection!]!.firstWhere((f) => f['id'] == id).addAll(r.patch);
        final apres = copie(c['apres']);
        for (final n in apres.keys) {
          memes(etat[n], apres[n], n);
        }
        final j = obj(c['journal']);
        expect([r.journal!.action, r.journal!.module, r.journal!.entite, r.journal!.reference], [j['action'], j['module'], j['entite'], j['reference']]);
        expect(extrait(r.journal!.avant), j['avant']);
        expect(extrait(r.journal!.apres), j['apres']);
      });
    }
  });
}
