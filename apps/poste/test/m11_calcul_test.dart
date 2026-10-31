import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm11_aide.dart';

/// M11 — le calcul de la paie, le tableau de bord, les cotisations et l'ORTB : les valeurs attendues sont celles que les écrans RÉELS de la maquette ont
/// affichées (pilote `vecteurs-paie.js`, horloge au 30/10/2026 10 h). Les gestes (génération des bulletins) sont accomplis par les boutons ; la fiche
/// écrite est comparée à celle que la maquette a écrite.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final v = vecteurs();
  final s0 = mm(mm(v['scenarios'])['S0']);
  M mois(int i) => mm(mm(s0['mois'])['$i']);
  Map<String, String> k(Object? l) => kpisVecteur(l);

  group('m11-dashboard', () {
    cas('huit KPI = le moteur au mois de l’horloge, et ils recoupent les écrans de calcul et de cotisations de la maquette', (t) async {
      await ouvrir(t, magasin(), 'm11-dashboard');
      expect(libellesKpi(t), ['Masse salariale brute', 'Net à payer', 'Total des primes', 'Sanctions (NS 131)', 'CNSS part ouvrière', 'CNSS part patronale', 'ITS retenu', 'Coût employeur total']);
      final lu = kpisAffiches(t);
      final calc = k(mm(mois(9)['calcul'])['kpis']);
      final cot = k(mm(mois(9)['cotisations'])['kpis']);
      expect(lu['Masse salariale brute'], calc['Masse salariale brute']);
      expect(lu['Net à payer'], calc['Net à payer']);
      expect(lu['CNSS part ouvrière'], cot['CNSS part ouvrière']);
      expect(lu['CNSS part patronale'], cot['CNSS part patronale']);
      expect(lu['ITS retenu'], cot['ITS retenu']);
      expect(lu['Coût employeur total'], cot['Coût employeur']);
      final lignes = [for (final l in mm(mm(mois(9)['calcul'])['table'])['lignes'] as List) (l as List).cast<String>()];
      int somme(int col) => lignes.fold<int>(0, (a, c) => a + (c[col] == '—' ? 0 : int.parse(RegExp(r'\d+(?: \d{3})*').firstMatch(c[col])!.group(0)!.replaceAll(' ', ''))));
      expect(lu['Total des primes'], sp(money(somme(5))));
      expect(lu['Sanctions (NS 131)'], sp(money(somme(7))));
      // le coût employeur et les retenues de l'agent sont DEUX grandeurs : le coût dépasse le brut (charges patronales), le net ne s'y additionne pas
      expect(lu['Coût employeur total'] != lu['Masse salariale brute'], true);
    });

    cas('les cartes et les accès rapides de la maquette', (t) async {
      await ouvrir(t, magasin(), 'm11-dashboard');
      for (final c in ['Accès rapides', 'Décomposition de la masse salariale', 'Répartition des charges et retenues', 'Masse salariale par service', 'Évolution de la masse salariale (12 mois)']) {
        expect(find.text(c), findsOneWidget, reason: c);
      }
      for (final r in ['Calculer la paie', 'Bulletins de paie', 'Cotisations', 'Validation Direction']) {
        expect(find.text(r), findsWidgets, reason: r);
      }
      await toucher(t, find.text('Cotisations'));
      await t.pumpAndSettle();
      expect(find.text('Cotisations CNSS / ITS / VPS'), findsWidgets);
    });
  });

  group('m11-calcul', () {
    cas('octobre : KPI, pied et première page du tableau = écran réel', (t) async {
      await ouvrir(t, magasin(), 'm11-calcul');
      final c = mm(mois(9)['calcul']);
      expect(kpisAffiches(t), k(c['kpis']));
      expect(find.text('Détail du calcul — octobre 2026'), findsOneWidget);
      expect(textes(t), contains(mm(c['table'])['pied']), reason: 'le pied de pagination de la maquette');
      final lignes = [for (final l in mm(c['table'])['lignes'] as List) (l as List).cast<String>()].take(20);
      for (final cel in lignes) {
        expect(textes(t).any((x) => cel[1].startsWith('$x ')), true, reason: 'agent ${cel[0]} : « ${cel[1]} » (nom puis fonction)');
        expect(texteSp(cel[12]), findsWidgets, reason: 'net à payer de ${cel[1]}');
        expect(texteSp(cel[6]), findsWidgets, reason: 'brut de ${cel[1]}');
      }
      expect(textes(t).any((x) => x.contains('44 enregistrements')), true);
    });

    cas('mars : la redevance ORTB Radio est retenue (1 000 F) sur chaque bulletin ; la Télé attend juin', (t) async {
      await ouvrir(t, magasin(), 'm11-calcul');
      await choisir(t, 'mois', 'Mars 2026');
      final c = mm(mois(2)['calcul']);
      expect(kpisAffiches(t), k(c['kpis']));
      expect(find.text('Détail du calcul — mars 2026'), findsOneWidget);
      // le tiroir de l'agent n° 1 : gains, retenues (ORTB Radio dû, Télé en juin), charges patronales
      await toucher(t, find.text('BASSONGUI Chabi Séko').first);
      await t.pumpAndSettle();
      expect(find.text('Paie de Mars 2026'), findsOneWidget, reason: 'la période du tiroir est le LIBELLÉ du mois, pas « 2026-03 » (E681)');
      final tiroir = mm(mm(c['tiroirs'])['1']);
      final tt = textes(t);
      for (final tb in lm(tiroir['tables'])) {
        for (final l in lm([for (final x in tb['lignes'] as List) {'c': x}])) {
          for (final cel in (l['c'] as List)) {
            if ('$cel'.isEmpty) continue;
            expect(tt, contains('$cel'), reason: 'cellule « $cel » du tiroir de la maquette');
          }
        }
      }
      expect(tt, contains('Annuelle, prélevée ce mois'));
      expect(tt, contains('Annuelle, prélevée en juin'));
    });

    cas('juin : la Télé s’ajoute à la radio (4 000 F sur l’exercice, 3 000 F ce mois pour qui dépasse 60 000 F)', (t) async {
      await ouvrir(t, magasin(), 'm11-calcul');
      await choisir(t, 'mois', 'Juin 2026');
      expect(kpisAffiches(t), k(mm(mois(5)['calcul'])['kpis']));
      await toucher(t, find.text('BASSONGUI Chabi Séko').first);
      await t.pumpAndSettle();
      final tt = textes(t);
      expect(tt, contains('Annuelle, prélevée en mars'));
      expect(tt, contains('Annuelle, prélevée ce mois'));
      expect(tt.where((x) => x == '3 000').length, 1, reason: 'la ligne Télé porte 3 000 en juin');
    });

    cas('le bulletin d’un agent s’imprime avec son détail ORTB (E682) : gains, retenues, net, charges patronales', (t) async {
      await ouvrir(t, magasin(), 'm11-calcul');
      await choisir(t, 'mois', 'Mars 2026');
      await toucher(t, find.byTooltip('Bulletin de paie').first);
      await t.pumpAndSettle();
      final pieceMaquette = mm(mm(mm(mois(2)['calcul'])['tiroirs'])['1'])['piece'] as Map;
      expect(find.text('Bulletin de paie'), findsWidgets);
      final tt = textes(t);
      expect(tt, contains('BASSONGUI Chabi Séko'));
      for (final tb in lm(pieceMaquette['tables'])) {
        for (final l in lm([for (final x in tb['lignes'] as List) {'c': x}])) {
          for (final cel in (l['c'] as List)) {
            if ('$cel'.isEmpty) continue;
            expect(tt, contains('$cel'), reason: 'cellule « $cel » du bulletin imprimé');
          }
        }
      }
      // la maquette d'avant la correction imprimait « Redevance ORTB — Non applicable — 0 » alors que le total retenait 1 000 F
      expect(tt, isNot(contains('Non applicable')));
      expect(tt, contains('Redevance ORTB / Radio'));
      expect(tt.any((x) => x.startsWith('Charges patronales (non déduites du net) : CNSS 16.4 %')), true);
    });

    cas('« Générer les bulletins » : un bulletin par agent, « à valider », la série suit le registre, l’annulation ARCHIVE (RG-14)', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm11-calcul');
      final g = mm(mm(mm(v['gestes'])['paie'])['generation9']);
      await toucher(t, find.text('Générer les bulletins'));
      await t.pumpAndSettle();
      expect(sp(textes(t).firstWhere((x) => x.startsWith('Les bulletins seront enregistrés'))), 'Les bulletins seront enregistrés pour la période octobre 2026 et soumis à la validation de la Direction avant diffusion.');
      expect(find.text('Générer 44 bulletin(s) de paie ?'), findsOneWidget);
      await toucher(t, find.text('Générer').last);
      await t.pumpAndSettle();
      final col = m.collection('bulletins');
      expect(col.actives.length, 44);
      expect(find.text('44 bulletin(s) généré(s).'), findsOneWidget);
      expect(find.text('En attente de validation par la Direction.'), findsOneWidget);
      expect(col.actives.every((b) => b['statutBulletin'] == 'a_valider' && b['periode'] == 'Octobre 2026'), true);
      expect(col.actives.first['reference'], 'BP-00044', reason: 'le dernier inséré est en tête (comme la maquette)');
      final attendus = {for (final b in lm(mm(mm(g['ecart'])['inserts'])['bulletins'])) b['employeId']: b};
      for (final b in col.actives) {
        final a = attendus[b['employeId']]!;
        for (final cle in ['reference', 'periode', 'brut', 'net', 'its', 'cnssOuvriere', 'cnssPatronale', 'vps', 'totalRetenues', 'coutEmployeur', 'primeAnciennete', 'salaireBase']) {
          expect(b[cle], a[cle], reason: '${b['employe']} · $cle');
        }
      }
      // une seconde génération CONTINUE la série (BP-00045…), jamais un doublon
      await toucher(t, find.text('Générer les bulletins'));
      await t.pumpAndSettle();
      await toucher(t, find.text('Générer').last);
      await t.pumpAndSettle();
      expect(col.actives.length, 88);
      expect({for (final b in col.actives) b['reference']}.length, 88, reason: 'aucune référence en double');
      expect(col.actives.first['reference'], 'BP-00088');
      // « Annuler » du message : les 44 derniers sont ARCHIVÉS, jamais supprimés
      await toucher(t, find.text('Annuler').last);
      expect(col.actives.length, 44);
      expect(col.archivees.length, 44);
      expect(col.toutes.length, 88);
    });

    cas('« Générer » annulé au dialogue : rien n’est écrit', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm11-calcul');
      await toucher(t, find.text('Générer les bulletins'));
      await t.pumpAndSettle();
      await toucher(t, find.text('Annuler').last);
      await t.pumpAndSettle();
      expect(m.collection('bulletins').toutes, isEmpty);
    });

    cas('droits : « Générer les bulletins » est ABSENT sans le droit d’écrire (RG-13) — et « Éditer le journal de paie » reste offert', (t) async {
      await ouvrir(t, magasin(), 'm11-calcul', role: 'direction');
      expect(find.text('Générer les bulletins'), findsNothing);
      expect(find.text('Lancer le calcul'), findsOneWidget);
      expect(find.text('Éditer le journal de paie'), findsOneWidget);
      await ouvrir(t, magasin(), 'm11-calcul', role: 'comptable');
      expect(find.text('Générer les bulletins'), findsOneWidget);
    });

    cas('le journal de paie : un total par colonne refait depuis les lignes imprimées, signatures de la maquette', (t) async {
      await ouvrir(t, magasin(), 'm11-calcul');
      await toucher(t, find.text('Éditer le journal de paie'));
      await t.pumpAndSettle();
      final piece = mm(mm(mm(s0['etats'])['9'])['journal']);
      final tt = textes(t);
      expect(tt, contains('Journal de paie'));
      for (final c in lm([for (final x in piece['cartouche'] as List) {'c': x}])) {
        final cel = c['c'] as List;
        if (cel[0] == 'Date d’édition') continue;
        expect(tt, contains(sp('${cel[0]} : ${cel[1]}')), reason: 'cartouche ${cel[0]}');
      }
      final pied = (mm((piece['tables'] as List).first)['pied'] as List).cast<String>();
      expect(pied.first, 'TOTAL GÉNÉRAL');
      for (final x in pied.skip(1).where((x) => x.isNotEmpty)) {
        expect(tt, contains(x), reason: 'total $x');
      }
      expect(tt, contains('TOTAL GÉNÉRAL'));
      expect(tt, contains('Validation'));
    });
  });

  group('m11-cotisations', () {
    cas('octobre : neuf KPI, détail et barème ITS = écran réel', (t) async {
      await ouvrir(t, magasin(), 'm11-cotisations');
      final c = mm(mois(9)['cotisations']);
      expect(kpisAffiches(t), k(c['kpis']));
      expect(find.text('Détail des cotisations — octobre 2026'), findsOneWidget);
      final bareme = mm(c['bareme']);
      for (final l in lm([for (final x in bareme['lignes'] as List) {'c': x}])) {
        for (final cel in (l['c'] as List)) {
          expect(textes(t), contains('$cel'), reason: 'barème ITS : $cel');
        }
      }
      expect(find.text('Barème ITS appliqué'), findsOneWidget);
    });

    cas('juin : ORTB Radio et Télé SE CUMULENT — 44 000 F et 114 000 F ce mois-là (KPI de l’écran réel)', (t) async {
      await ouvrir(t, magasin(), 'm11-cotisations');
      await choisir(t, 'mois', 'Juin 2026');
      final lu = kpisAffiches(t);
      expect(lu, k(mm(mois(5)['cotisations'])['kpis']));
      expect(lu['ORTB Radio'], '0 FCFA');
      expect(lu['ORTB Télé'], '114 000 FCFA');
      await choisir(t, 'mois', 'Mars 2026');
      expect(kpisAffiches(t)['ORTB Radio'], '44 000 FCFA');
      expect(kpisAffiches(t)['ORTB Télé'], '0 FCFA');
    });

    cas('« État ORTB » (juin) : cartouche et pièce de la maquette, SANS total de bruts', (t) async {
      await ouvrir(t, magasin(), 'm11-cotisations');
      await choisir(t, 'mois', 'Juin 2026');
      await toucher(t, find.text('État ORTB'));
      await t.pumpAndSettle();
      final piece = mm(mm(mm(s0['etats'])['5'])['ORTB']);
      final tt = textes(t);
      expect(tt, contains(piece['titre']));
      expect(tt, contains(piece['sousTitre']));
      for (final c in lm([for (final x in piece['cartouche'] as List) {'c': x}])) {
        final cel = c['c'] as List;
        if (cel[0] == 'Date d’édition') continue;
        expect(tt, contains(sp('${cel[0]} : ${cel[1]}')), reason: 'cartouche ${cel[0]}');
      }
      expect(tt, contains('Montant à verser : 114 000 FCFA'));
      expect(tt.where((x) => x == 'TOTAL'), isEmpty, reason: 'l’état de cotisations ne porte pas de pied de total (comme la maquette)');
    });

    cas('« État CNSS » : part ouvrière 3,6 % et patronale 16,4 % en en-têtes, montant à verser = somme des deux', (t) async {
      await ouvrir(t, magasin(), 'm11-cotisations');
      await toucher(t, find.text('État CNSS'));
      await t.pumpAndSettle();
      final piece = mm(mm(mm(s0['etats'])['9'])['CNSS']);
      final tt = textes(t);
      expect(tt, contains('Part ouvrière (3.6 %)'));
      expect(tt, contains('Part patronale (16.4 %)'));
      expect(tt, contains('État des cotisations CNSS'));
      expect(tt, contains(sp('Montant à verser : ${((piece['cartouche'] as List)[3] as List)[1]}')));
      expect(tt, contains('IFU employeur : 3201642748214'));
    });
  });

  group('m11-ortb', () {
    cas('mars : KPI et dû ce mois = écran réel ; filtre « Dû ce mois » = les 44 agents', (t) async {
      await ouvrir(t, magasin(), 'm11-ortb');
      await choisir(t, 'mois', 'mars 2026');
      final c = mm(mois(2)['ortb']);
      expect(kpisAffiches(t), k(c['kpis']));
      expect(find.text('Redevances par agent — mars 2026'), findsOneWidget);
      expect(kpisAffiches(t)['Dû sur mars'], '44 000 FCFA');
      expect(kpisAffiches(t)['Cumul par agent au-delà du seuil'], '4 000 FCFA');
      // la note de la maquette porte le total de l'exercice
      expect(textes(t).any((x) => x.contains('Total dû sur l’exercice 2026 : 158 000 FCFA — 44 000 FCFA en mars (radio) et 114 000 FCFA en juin (télé).')), true);
    });

    cas('octobre : tout est prélevé — « Dû sur octobre » vaut 0 et le dit', (t) async {
      await ouvrir(t, magasin(), 'm11-ortb');
      final c = mm(mois(9)['ortb']);
      expect(kpisAffiches(t), k(c['kpis']));
      expect(kpisAffiches(t)['Dû sur octobre'], '0 FCFA');
      expect(find.text('Aucun prélèvement ce mois'), findsOneWidget);
      expect(find.text('Déjà prélevée'), findsWidgets);
    });

    cas('« Imprimer l’état » (juin) : seuls les agents redevables, totaux Radio / Télé / annuel / dû refaits, jamais de total de bruts', (t) async {
      await ouvrir(t, magasin(), 'm11-ortb');
      await choisir(t, 'mois', 'juin 2026');
      await toucher(t, find.text('Imprimer l’état'));
      await t.pumpAndSettle();
      final piece = mm(mm(mm(s0['etats'])['5'])['ortb']);
      final tt = textes(t);
      expect(tt, contains('État des redevances ORTB'));
      for (final c in lm([for (final x in piece['cartouche'] as List) {'c': x}])) {
        final cel = c['c'] as List;
        expect(tt, contains(sp('${cel[0]} : ${cel[1]}')), reason: 'cartouche ${cel[0]}');
      }
      final pied = (mm((piece['tables'] as List).first)['pied'] as List).cast<String>();
      expect(pied.first, 'TOTAL');
      for (final x in pied.skip(1).where((x) => x.isNotEmpty)) {
        expect(tt, contains(x), reason: 'total $x');
      }
      expect(pied[2], '', reason: 'la colonne « Salaire brut » n’est pas totalisée');
    });

    cas('« Obligations » mène à la référence fiscale', (t) async {
      await ouvrir(t, magasin(), 'm11-ortb');
      await toucher(t, find.text('Obligations'));
      await t.pumpAndSettle();
      expect(find.textContaining('obligations'), findsWidgets);
    });
  });

  group('m11-calcul : heures supplémentaires validées et échéances de prêt du mois (scénario S1 de la maquette)', () {
    final s1 = mm(mm(v['scenarios'])['S1']);
    final e1 = mm(s1['entrees']);
    Magasin avecS1() {
      final m = magasin();
      for (final (nom, cle) in [
        ('evaluations', 'evaluations'),
        ('participations', 'participations'),
        ('avances', 'avances'),
        ('heuresSup', 'heuresSup'),
        ('pretsEtudes', 'pretsEtudes'),
        ('grillePrimes', 'grillePrimes'),
        ('historiquePrimes', 'historiquePrimes'),
      ]) {
        m.collection(nom).remplacerContenu(lm(e1[cle]));
      }
      return m;
    }

    cas('le tiroir d’octobre : « Heures supplémentaires » dans les gains, « Échéance de prêt » dans les retenues = l’écran réel', (t) async {
      await ouvrir(t, avecS1(), 'm11-calcul');
      final c = mm(mm(mm(s1['mois'])['9'])['calcul']);
      expect(kpisAffiches(t), kpisVecteur(c['kpis']));
      await toucher(t, find.text('BASSONGUI Chabi Séko').first);
      await t.pumpAndSettle();
      final tt = textes(t);
      final tiroir = mm(mm(c['tiroirs'])['1']);
      for (final tb in lm(tiroir['tables'])) {
        for (final l in tb['lignes'] as List) {
          for (final cel in (l as List)) {
            if ('$cel'.isEmpty) continue;
            expect(tt, contains('$cel'), reason: 'cellule « $cel » du tiroir de la maquette');
          }
        }
      }
      expect(tt, contains('Heures supplémentaires'));
      expect(tt, contains('Échéance de prêt'));
      expect(tt, contains('PRT-S1-A 2/3 · PRT-S1-B 1/2'));
    });

    cas('le bulletin imprimé porte les deux rubriques, et son total retombe sur celui du tiroir', (t) async {
      await ouvrir(t, avecS1(), 'm11-calcul');
      await toucher(t, find.text('BASSONGUI Chabi Séko').first);
      await t.pumpAndSettle();
      await toucher(t, find.text('Éditer le bulletin'));
      await t.pumpAndSettle();
      final piece = mm(mm(mm(mm(s1['mois'])['9'])['calcul'])['tiroirs'])['1'] as Map;
      final tt = textes(t);
      for (final tb in lm(mm(piece['piece'])['tables'])) {
        for (final l in tb['lignes'] as List) {
          for (final cel in (l as List)) {
            if ('$cel'.isEmpty) continue;
            expect(tt, contains('$cel'), reason: 'cellule « $cel » du bulletin imprimé');
          }
        }
      }
      expect(tt, contains('PRT-S1-A 2/3 ; PRT-S1-B 1/2'));
    });
  });
}
