// Les paramètres versionnés par date (lot L0) rejoués sur les vecteurs du banc (`packages/sync/banc/vecteurs-parametres.js`, exécutable de référence `parametres.js`).
// Trois obligations : (1) même résultat que la référence, refus compris (code, motif, geste) ; (2) l'ordre des versions ne change pas la valeur en vigueur ;
// (3) le registre des définitions est cohérent (défauts valides, aucun paramètre réservé envoyé au téléphone).
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

List<Parametre> versions(Object? v) => liste(v).map(Parametre.fromJson).toList();

Map<String, Object?> sortie(Object? o) => (o as Map).cast<String, Object?>();

void main() {
  final v = lireVecteurs('parametres');
  final cas = liste(v['cas']);

  test('la liste des familles fermées au téléphone est celle de la référence', () {
    expect(parFamillesJamaisMobile, (v['famillesJamaisMobile'] as List).cast<String>());
  });

  for (final c in cas) {
    test(c['nom'] as String, () {
      Map<String, Object?> attendu() => sortie(c['attendu']);
      switch (c['op']) {
        case 'resoudre':
          final def = c['definition'] == null ? null : DefinitionParametre.fromJson(sortie(c['definition']));
          final r = Parametres.resoudre(c['cle'] as String, versions(c['versions']), c['date'] as String, definition: def);
          memes(r.ok ? r.valeur!.toJson() : r.refus!.toJson(), attendu(), 'résoudre');
        case 'proposer':
          final def = c['definition'] == null ? null : DefinitionParametre.fromJson(sortie(c['definition']));
          final r = Parametres.proposer(
            definition: def,
            versions: versions(c['versions']),
            usages: liste(c['usages']),
            valeur: c['valeur'],
            dateEffet: c['dateEffet'] as String?,
            auteur: '${c['auteur']}',
            creeLe: c['creeLe'] as String?,
            motif: c['motif'] as String?,
          );
          if (r.ok) {
            memes({'ok': true, 'id': r.valeur!.id, 'fiche': r.valeur!.toJson()}, attendu(), 'proposer');
          } else {
            memes(r.refus!.toJson(), attendu(), 'proposer');
          }
        case 'valider':
          final r = Parametres.validerChamps(sortie(c['fiche']), liste(c['existantes']), liste(c['usages']));
          memes(r == null ? {'ok': true} : r.toJson(), attendu(), 'valider');
        case 'semer':
          final p = Parametres.semer(DefinitionParametre.fromJson(sortie(c['definition'])));
          memes({'id': p.id, 'fiche': p.toJson()}, attendu(), 'semer');
        case 'mobile':
          expect(Parametres.autoriseMobile(sortie(c['champs'])), c['attendu']);
        default:
          fail('opération inconnue : ${c['op']}');
      }
    });
  }

  test('l\'ordre des versions ne change jamais la valeur en vigueur (convergence)', () {
    final def = DefinitionParametre.fromJson(sortie(cas.firstWhere((c) => c['op'] == 'resoudre')['definition']));
    final toutes = versions(cas.firstWhere((c) => c['nom'] == 'résoudre : à date égale la version la plus haute')['versions']);
    final attendu = Parametres.resoudre(def.cle, toutes, '2026-12-02', definition: def).valeur!.valeur;
    var graine = 7;
    for (var i = 0; i < 40; i++) {
      final m = [...toutes];
      for (var j = m.length - 1; j > 0; j--) {
        graine = (graine * 1103515245 + 12345) & 0x7fffffff;
        final k = graine % (j + 1);
        final t = m[j];
        m[j] = m[k];
        m[k] = t;
      }
      expect(Parametres.resoudre(def.cle, m, '2026-12-02', definition: def).valeur!.valeur, attendu);
    }
  });

  group('registre des définitions', () {
    test('les clés sont uniques et chaque défaut est valide pour son type', () {
      expect(definitionsParametres.map((d) => d.cle).toSet().length, definitionsParametres.length);
      for (final d in definitionsParametres) {
        expect(Parametres.valeurValide(d.type, d.defaut, d.choix), isTrue, reason: d.cle);
        expect(d.source, isNotNull, reason: '${d.cle} : un défaut sans source se dit « proposition à valider »');
      }
    });
    test('chaque choix a son libellé', () {
      for (final d in definitionsParametres.where((d) => d.type == TypeParametre.choix)) {
        expect(d.libellesChoix.keys.toSet(), d.choix!.toSet(), reason: d.cle);
      }
    });
    test('chaque version 0 semée est recevable par la mère', () {
      for (final d in definitionsParametres) {
        expect(Parametres.validerFiche(Parametres.semer(d), const [], const []), isNull, reason: d.cle);
      }
    });
    test('aucun paramètre réservé (RG-13) n\'est déclaré pour le téléphone', () {
      for (final d in definitionsParametres) {
        expect(Parametres.autoriseMobile(Parametres.semer(d).toJson()), isFalse, reason: d.cle);
      }
    });
    test('deux semis indépendants de la même définition sont identiques', () {
      for (final d in definitionsParametres) {
        expect(Parametres.semer(d).toJson(), Parametres.semer(definitionDeParametre(d.cle)!).toJson());
      }
    });
  });
}
