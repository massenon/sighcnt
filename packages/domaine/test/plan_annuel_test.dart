import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// LOT PTA : les règles du plan annuel de travail rejouées sur les vecteurs tirés de l'écran réel `m13-plan-annuel` de la maquette
/// (`prototype_html/build/vecteurs-plan-annuel.js`, horloge figée au 30/10/2026).
final v = (jsonDecode(File('test/vecteurs/plan_annuel.json').readAsStringSync()) as Map).cast<String, Object?>();
final mq = (v['maquette'] as Map).cast<String, Object?>();
List<Map<String, Object?>> lm(Object? o) => [for (final x in (o as List)) (x as Map).cast<String, Object?>()];
Map<String, Object?> mm(Object? o) => (o as Map).cast<String, Object?>();

String? Function(String) natureDe(List<Map<String, Object?>> etats) => (c) {
      for (final e in etats) {
        if (e['code'] == c) return '${e['nature']}';
      }
      return null;
    };

void main() {
  final ctxJson = mm(mq['contexte']);
  final etats = lm(ctxJson['etats']);
  final nature = natureDe(etats);
  final ag = mm(ctxJson['agent']), po = mm(ctxJson['poste']);
  final ctx = ContextePlan(
    exercices: {for (final x in lm(ctxJson['exercices'])) x['annee'] as int},
    axes: {for (final x in lm(ctxJson['axes'])) '${x['code']}'},
    etats: {for (final x in etats) '${x['code']}'},
    agents: {'${ag['id']}'},
    postes: {'${po['id']}'},
    budgets: {'${mm(ctxJson['budget'])['id']}'},
  );

  test('la fin de chaque trimestre se calcule depuis le premier jour de l\'exercice (aucune date écrite)', () {
    final cas = lm(mq['finTrimestre']);
    expect(cas.length, greaterThanOrEqualTo(12));
    for (final c in cas) {
      expect(paFinTrimestre(c['debut'] as String?, c['q']), c['fin'], reason: '${c['debut']} T${c['q']}');
    }
  });

  test('le pourcentage d\'avancement est borné de 0 à 100 et « non renseigné » n\'est pas zéro', () {
    for (final c in lm(mq['pourcentage'])) {
      final raw = c['v'];
      final val = raw == '__undef' || raw == '__nan' ? (raw == '__nan' ? double.nan : null) : raw;
      final r = paPourcentage(val);
      final attendu = mm(c['r']);
      expect(r.ok, attendu['ok'], reason: '$raw');
      expect(r.valeur, attendu['valeur'], reason: '$raw');
      expect(r.code, attendu['code'], reason: '$raw');
    }
  });

  test('les nombres de budget et d\'indicateur : vide = non renseigné, négatif ou texte = invalide', () {
    for (final c in lm(mq['nombre'])) {
      final raw = c['v'];
      final r = paNombre(raw == '__undef' ? null : raw);
      final attendu = c['r'];
      if (attendu == '__invalide') {
        expect(r.invalide, isTrue, reason: '$raw');
      } else {
        expect(r.invalide, isFalse, reason: '$raw');
        expect(r.valeur, attendu, reason: '$raw');
      }
    }
  });

  test('l\'atteinte d\'un indicateur est NON CALCULABLE (jamais zéro) sans cible ou sans valeur', () {
    for (final c in lm(mq['atteinte'])) {
      final r = paAtteinteIndicateur(mm(c['a']));
      final a = mm(c['r']);
      expect(r.calculable, a['calculable'], reason: '${c['a']}');
      expect(r.pct, a['pct'], reason: '${c['a']}');
      expect(r.motif, a['motif'], reason: '${c['a']}');
    }
  });

  test('les totaux sont CALCULÉS : null sans aucune valeur, écart seulement si prévu et réalisé existent', () {
    for (final c in lm(mq['totaux'])) {
      final t = paTotaux(lm(c['actions']), nature);
      final a = mm(c['r']);
      expect(t.nb, a['nb']);
      expect(t.prevu, a['prevu']);
      expect(t.realise, a['realise']);
      expect(t.nbSansPrevu, a['nbSansPrevu']);
      expect(t.nbSansRealise, a['nbSansRealise']);
      expect(t.ecart, a['ecart']);
      expect(t.tauxMoyen, a['tauxMoyen']);
      expect(t.nbSansTaux, a['nbSansTaux']);
      expect(t.parNature, {for (final e in mm(a['parNature']).entries) e.key: e.value as int});
    }
  });

  test('le retard : non réalisée, trimestre de fin passé de plus de la tolérance ; réalisée, état inconnu, trimestre illisible : jamais', () {
    final cas = lm(mq['retard']);
    expect(cas.length, greaterThanOrEqualTo(12));
    for (final c in cas) {
      final r = paRetard(mm(c['a']), c['debut'] as String?, '${c['auj']}', c['grace'] as int, nature);
      final a = mm(c['r']);
      expect(r.enRetard, a['enRetard'], reason: '$c');
      expect(r.motif, a['motif'], reason: '$c');
      expect(r.finTrimestre, a['finTrimestre'], reason: '$c');
      expect(r.limite, a['limite'], reason: '$c');
      expect(r.jours, a['jours'], reason: '$c');
    }
  });

  test('la référence PA-<année de la date>-NNN : compteur par année lu sur les fiches existantes', () {
    for (final c in lm(mq['references'])) {
      if (c['ref'] == null) continue;
      expect(referenceAnnuelle('${c['prefixe']}', '${c['date']}', c['largeur'] as int, lm(c['fiches']), maintenant: DateTime(2026, 10, 30, 10)), c['ref'], reason: '${c['date']}');
    }
  });

  test('le contrôle d\'une fiche : mêmes refus nommés que la maquette (texte libre, responsable inconnu, hors bornes, exercice inconnu)', () {
    final cas = lm(mq['controles']);
    expect(cas.length, greaterThanOrEqualTo(21));
    for (final c in cas) {
      expect(paControler(mm(c['fiche']), ctx)?.code, c['code'], reason: '${c['nom']}');
    }
  });

  test('« Reconduire » copie les actions non réalisées, une seule fois, suivi remis à zéro ; la source n\'est pas réécrite', () {
    final rec = mm(mq['reconduction']);
    final source = lm(rec['sourceAvant']);
    final planifie = etats.firstWhere((e) => e['nature'] == 'planifiee')['code'] as String;
    final r = paReconduire(source, const [], etatPlanifie: planifie, natureDe: nature, responsableExiste: (f) => true);
    final fiches = lm(rec['fiches']);
    expect(r.copiees.length, fiches.length);
    for (var i = 0; i < r.copiees.length; i++) {
      final c = r.copiees[i], a = fiches[i];
      for (final k in ['action', 'axe', 'trimestreDebut', 'trimestreFin', 'avancement', 'responsableType', 'responsableRef', 'reconduiteDepuis', 'budgetPrevu', 'indicateur', 'cible']) {
        expect(c[k], a[k], reason: 'copie $i, $k');
      }
      expect(c.containsKey('tauxAvancement'), isFalse);
      expect(c.containsKey('budgetRealise'), isFalse);
    }
    final seconde = paReconduire(source, [for (final f in r.copiees) {...f}], etatPlanifie: planifie, natureDe: nature, responsableExiste: (f) => true);
    expect(seconde.copiees, isEmpty);
    expect(seconde.ignorees.length, r.copiees.length);
  });

  test('l\'écran réel après adoption : les totaux imprimés sont ceux du domaine (calculés, jamais fournis)', () {
    final bilan = mm(v['ecran']);
    final etat = mm(bilan['etatBilan']);
    expect(etat['titre'], 'Bilan du plan annuel de travail');
    final pied = lm(etat['tableaux'])[0]['pied'] as List;
    expect(pied, isNotEmpty);
  });

  test('le geste réservé et le paramètre de tolérance existent', () {
    expect(paGesteAdopter, 'adopter_plan_annuel');
    expect(pcBornesDe(pcCleGraceRetardPlan)!.min, 0);
    expect(pcBornesDe(pcCleGraceRetardPlan)!.max, 90);
    expect(pcControler(pcCleGraceRetardPlan, 0), isNull);
    expect(pcControler(pcCleGraceRetardPlan, 91)?.code, 'PARAMETRE_HORS_BORNES');
    expect(pcControler(pcCleGraceRetardPlan, -1)?.code, 'PARAMETRE_HORS_BORNES');
  });
}
