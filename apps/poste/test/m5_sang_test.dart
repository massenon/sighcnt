import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';
import 'parite/extracteur.dart';

/// La banque de sang, les donneurs et les statistiques de réactifs (M5). Les règles sont rejouées sur les vecteurs de la maquette
/// (packages/domaine/test/sang_regles_test.dart) ; ici, l'ÉCRAN : ce qu'il affiche pour chaque jeu du vecteur, ce qu'il écrit, refuse, annule.
final donneesTelles = DonneesNavigation.depuisDossier();

/// La matrice des droits EXTRAITE de la maquette ne porte ni la banque de sang ni les donneurs : l'activité y est fermée (`modulesActifs`) et la
/// fermeture retire l'écran à TOUS les rôles, administrateur compris (écart E203). Pour exercer les écrans portés, ce banc les ouvre comme le ferait
/// la réouverture de l'activité : administrateur et laborantin en écriture, direction en lecture. Rien d'autre ne change.
DonneesNavigation _activiteRouverte() {
  final rbac = (jsonDecode(File('assets/donnees/rbac.json').readAsStringSync()) as Map).cast<String, Object?>();
  final par = (rbac['parRole'] as Map).cast<String, Object?>();
  for (final id in ['m5-banque-sang', 'm5-donneurs']) {
    (par['admin'] as Map)[id] = [1, 1, 1];
    (par['laborantin'] as Map)[id] = [1, 1, 1];
    (par['direction'] as Map)[id] = [1, 0, 0];
  }
  return DonneesNavigation.depuisJson(
      manifeste: File('assets/donnees/manifeste.json').readAsStringSync(),
      rbac: jsonEncode(rbac),
      parite: File('assets/donnees/parite.json').readAsStringSync());
}

final donnees = _activiteRouverte();
final aujourdhui = DateTime(2026, 8, 16);

final Map<String, Object?> vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/sang.json').readAsStringSync()) as Map).cast<String, Object?>();
List<Fiche> liste(Object? v) => [for (final x in (v as List)) (x as Map).cast<String, Object?>()];

Magasin magasin({
  List<Fiche> produits = const [],
  List<Fiche> lots = const [],
  List<Fiche> demandes = const [],
  List<Fiche> poches = const [],
  List<Fiche> donneurs = const [],
}) =>
    Magasin({
      'produits': [for (final p in produits) {...p}],
      'lots': [for (final p in lots) {...p}],
      'demandesAnalyses': [for (final p in demandes) {...p}],
      'poches': [for (final p in poches) {...p}],
      'donneurs': [for (final p in donneurs) {...p}],
      'examensLabo': liste(vecteurs['examens']),
      'audit': const [],
    }, 'POSTE');

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => aujourdhui));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> saisir(WidgetTester t, String champ, String valeur) async {
  await t.enterText(find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(TextField)), valeur);
  await t.pump();
}

String kpi(WidgetTester t, String libelle) =>
    t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == libelle)).valeur;

String? indice(WidgetTester t, String libelle) =>
    t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == libelle)).indice;

String _s(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'[\s  ]'), '');

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

/// L'icône de ligne (par son infobulle) qui se trouve à la hauteur du texte donné : la ligne de ce libellé.
Finder icone(WidgetTester t, String libelleLigne, String infobulle) {
  final dy = t.getCenter(find.text(libelleLigne)).dy;
  final e = find.byTooltip(infobulle).evaluate().firstWhere((e) => (t.getCenter(find.byWidget(e.widget)).dy - dy).abs() < 22);
  return find.byWidget(e.widget);
}

Fiche poche(Magasin m, String ref) => m.collection('poches').toutes.firstWhere((p) => p['reference'] == ref);

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  group('m5-reactifs-stats — les indicateurs rejouent la maquette sur chacun de ses jeux', () {
    for (final (i, c) in liste(vecteurs['stats']).indexed) {
      cas('jeu $i : ${c['nom']}', (t) async {
        final m = magasin(produits: liste(c['produits']), lots: liste(c['lots']), demandes: liste(c['demandes']));
        await ouvrir(t, m, 'm5-reactifs-stats');
        final k = liste(c['kpis']);
        for (final x in k) {
          expect(_s(kpi(t, '${x['libelle']}')), _s(x['valeur']), reason: '${x['libelle']}');
          expect(indice(t, '${x['libelle']}'), x['indice'], reason: 'indice de ${x['libelle']}');
        }
        // le bandeau « sans seuil » n'existe que s'il y a des références sans seuil
        expect(find.textContaining('sans seuil d’alerte. Sans seuil, aucune alerte').evaluate().length, (c['notes'] as List).length);
        // le tableau, dans l'ordre de la maquette (stock croissant, stable)
        final tab = liste(c['tableaux']);
        if (tab.isEmpty) {
          expect(find.text('Aucun enregistrement.'), findsOneWidget);
        } else {
          final lignes = (tab.single['lignes'] as List).cast<List>();
          final noms = lignes.map((l) => '${l[0]}').toList();
          final positions = [for (final n in noms) t.getTopLeft(find.text(n).first).dy];
          for (var j = 1; j < positions.length; j++) {
            expect(positions[j] > positions[j - 1], isTrue, reason: 'ordre des lignes : ${noms[j - 1]} avant ${noms[j]}');
          }
        }
      });
    }

    cas('le graphique porte les sections de la maquette, du plus fréquent au moins fréquent', (t) async {
      final c = liste(vecteurs['stats']).first;
      final m = magasin(produits: liste(c['produits']), lots: liste(c['lots']), demandes: liste(c['demandes']));
      await ouvrir(t, m, 'm5-reactifs-stats');
      final g = t.widget<GraphiqueBarres>(find.byType(GraphiqueBarres));
      final args = (liste(c['graphiques']).single['args'] as List);
      expect(g.horizontal, isTrue);
      expect(g.etiquettes, (args[0] as List).cast<String>());
      expect(g.series.single.donnees, ((args[1] as List).single as Map)['data']);
      expect(find.text('Demandes d’analyses par section — activité qui consomme les réactifs'), findsOneWidget);
    });

    cas('l\'écran est en lecture seule : aucune commande d\'écriture', (t) async {
      final c = liste(vecteurs['stats']).first;
      await ouvrir(t, magasin(produits: liste(c['produits'])), 'm5-reactifs-stats');
      for (final mot in ['Nouveau', 'Modifier', 'Archiver', 'Enregistrer']) {
        expect(find.text(mot), findsNothing);
      }
    });

    cas('un stock modifié se reflète aussitôt dans la valeur et le seuil', (t) async {
      final c = liste(vecteurs['stats']).first;
      final m = magasin(produits: liste(c['produits']), lots: liste(c['lots']), demandes: liste(c['demandes']));
      await ouvrir(t, m, 'm5-reactifs-stats');
      expect(_s(kpi(t, 'Valeur du stock')), _s('17 750 FCFA'));
      m.collection('produits').mettreAJour('R2', {'stock': 5});
      await t.pump();
      // R2 : 50 → 5 (seuil 10) : -45 × 200 = -9 000 ; et il passe sous le seuil
      expect(_s(kpi(t, 'Valeur du stock')), _s('8 750 FCFA'));
      expect(kpi(t, 'Sous le seuil d’alerte'), '5');
    });
  });

  group('m5-banque-sang', () {
    final b = (vecteurs['banque'] as Map).cast<String, Object?>();
    Magasin jeu() => magasin(poches: liste(b['poches']));

    cas('indicateurs, disponibilité par groupe et tableau rejouent la maquette', (t) async {
      await ouvrir(t, jeu(), 'm5-banque-sang');
      for (final x in liste(b['kpis'])) {
        expect(kpi(t, '${x['libelle']}'), x['valeur'], reason: '${x['libelle']}');
      }
      for (final g in liste(b['grille'])) {
        // la carte d'un groupe : « O+ », puis le nombre, puis « poche(s) » — le nombre est unique dans la carte
        expect(find.text('${g['groupe']}'), findsWidgets);
      }
      expect(find.text('Disponibilité par groupe sanguin'), findsOneWidget);
      expect(find.text('Poches de sang'), findsOneWidget);
      final lignes = (liste(b['tableaux']).single['lignes'] as List).cast<List>();
      final refs = lignes.map((l) => '${l[0]}').toList();
      final ys = [for (final r in refs) t.getTopLeft(find.text(r)).dy];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i] > ys[i - 1], isTrue, reason: 'tri par péremption : ${refs[i - 1]} avant ${refs[i]}');
      }
      expect(find.text('PS-0015'), findsNothing, reason: 'une poche archivée n\'est pas au registre');
      expect(find.text('Périmée'), findsWidgets);
      expect(find.text('Réservée'), findsWidgets);
    });

    cas('la carte d\'un groupe sans poche disponible est rouge et dit « 0 poche »', (t) async {
      await ouvrir(t, jeu(), 'm5-banque-sang');
      expect(find.text('poche'), findsNWidgets(4), reason: 'A-, B+ et AB- n\'ont aucune poche disponible, B- en a une : « poche » au singulier');
    });

    cas('le bon de demande de sang s\'imprime avec la disponibilité du jour', (t) async {
      await ouvrir(t, jeu(), 'm5-banque-sang');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Bon de demande de sang'));
      expect(find.text('Bon de demande de sang'), findsWidgets);
      final dispo = (b['bon'] as Map)['texte'] as String;
      final attendu = RegExp(r'Disponibilité au [^:]+ : (.*)$').firstMatch(dispo)!.group(1)!;
      expect(find.textContaining(attendu), findsWidgets);
    });

    cas('modifier : une poche sans date de péremption ne s\'enregistre pas tant que la date manque, rien n\'est écrit', (t) async {
      // Le sélecteur de date du kit ne se vide pas (il ne propose que des dates) : le refus se joue sur une fiche qui n'en porte pas.
      final sans = [for (final p in liste(b['poches'])) if (p['reference'] == 'PS-0001') {...p}..remove('datePeremption') else p];
      final m = magasin(poches: sans);
      await ouvrir(t, m, 'm5-banque-sang');
      await toucher(t, icone(t, 'PS-0001', 'Modifier'));
      expect(find.text('Modifier l’enregistrement'), findsOneWidget);
      for (final l in ['Groupe sanguin', 'Volume (ml)', 'Date de prélèvement', 'Date de péremption', 'Donneur', 'Observations']) {
        expect(find.textContaining(l), findsWidgets, reason: l);
      }
      await saisir(t, 'volume', '300');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
      expect(poche(m, 'PS-0001')['volume'], 450);
      expect(poche(m, 'PS-0001').containsKey('datePeremption'), isFalse);
    });

    cas('modifier : les valeurs sont écrites, le geste est annulable ; E201 — l\'état enregistré ne bouge pas', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-banque-sang');
      final avant = [for (final x in liste(b['kpis'])) kpi(t, '${x['libelle']}')];
      await toucher(t, icone(t, 'PS-0001', 'Modifier'));
      await saisir(t, 'volume', '350');
      await saisir(t, 'donneur', 'Donneur modifié');
      await saisir(t, 'observations', 'Contrôle');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final p = poche(m, 'PS-0001');
      expect(p['volume'], 350);
      expect(p['donneur'], 'Donneur modifié');
      expect(p['observations'], 'Contrôle');
      expect(find.text('Modifications enregistrées.'), findsOneWidget);
      expect(p['etat'], 'actif');
      expect([for (final x in liste(b['kpis'])) kpi(t, '${x['libelle']}')], avant);
      await toucher(t, find.text('Annuler').last);
      expect(poche(m, 'PS-0001')['volume'], 450);
      expect(poche(m, 'PS-0001').containsKey('observations'), isFalse);
    });

    cas('archiver exige un motif, retire la poche du registre, et s\'annule', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-banque-sang');
      await toucher(t, icone(t, 'PS-0003', 'Archiver'));
      expect(find.text('Archiver cet enregistrement ?'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      expect(find.text('Le motif est obligatoire.'), findsOneWidget);
      expect(poche(m, 'PS-0003')['statut'], 'actif');
      await t.enterText(find.byType(TextField).last, 'Poche contaminée');
      await t.pump();
      await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      expect(poche(m, 'PS-0003')['statut'], 'archive');
      expect(find.text('Enregistrement archivé.'), findsOneWidget);
      expect(kpi(t, 'Poches en stock'), '13');
      await toucher(t, find.text('Annuler').last);
      expect(poche(m, 'PS-0003')['statut'], 'actif');
      expect(kpi(t, 'Poches en stock'), '14');
    });

    cas('un registre vide : zéro partout, quatre cartes « 0 poche » de plus, aucune erreur', (t) async {
      await ouvrir(t, magasin(), 'm5-banque-sang');
      expect(kpi(t, 'Poches en stock'), '0');
      expect(kpi(t, 'Disponibles'), '0');
      expect(find.text('poche'), findsNWidgets(8));
    });

    cas('un jeu de 17 poches : première page de 15, tri par péremption', (t) async {
      final g = (b['grand'] as Map).cast<String, Object?>();
      await ouvrir(t, magasin(poches: liste(g['poches'])), 'm5-banque-sang');
      for (final x in liste(g['kpis'])) {
        expect(kpi(t, '${x['libelle']}'), x['valeur']);
      }
      final lignes = (liste(g['tableaux']).single['lignes'] as List).cast<List>();
      expect(find.text('${lignes.first[0]}'), findsOneWidget);
      expect(find.text('${lignes.last[0]}'), findsOneWidget);
      final hors = liste(g['poches']).map((p) => '${p['reference']}').where((r) => !lignes.any((l) => l[0] == r));
      for (final r in hors) {
        expect(find.text(r), findsNothing, reason: '$r est sur la deuxième page');
      }
    });
  });

  group('m5-donneurs', () {
    final d = (vecteurs['donneurs'] as Map).cast<String, Object?>();
    Magasin jeu() => magasin(donneurs: liste(d['donneurs']));

    cas('indicateurs, onglets et tableau rejouent la maquette', (t) async {
      await ouvrir(t, jeu(), 'm5-donneurs');
      for (final x in liste(d['kpis'])) {
        expect(kpi(t, '${x['libelle']}'), x['valeur'], reason: '${x['libelle']}');
      }
      expect(find.textContaining('Tous les donneurs'), findsWidgets);
      expect(find.textContaining('Archivés'), findsWidgets);
      final lignes = (liste(d['tableaux']).first['lignes'] as List).cast<List>();
      final ys = [for (final l in lignes) t.getTopLeft(find.text('${l[1]}')).dy];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i] > ys[i - 1], isTrue, reason: 'tri par dernier don décroissant : ${lignes[i - 1][1]} avant ${lignes[i][1]}');
      }
      for (final l in lignes) {
        expect(find.text('${l[8]}'), findsWidgets, reason: 'éligibilité de ${l[1]}');
      }
      expect(find.text('DON-0009'), findsNothing, reason: 'un donneur archivé n\'est pas au registre');
    });

    cas('la fiche en tiroir porte les huit rubriques de la maquette', (t) async {
      await ouvrir(t, jeu(), 'm5-donneurs');
      await toucher(t, find.text('DON-0003'));
      for (final l in ['N°', 'Donneur', 'Groupe', 'Téléphone', 'Type de don', 'Dons', 'Dernier don', 'Éligibilité']) {
        expect(find.text(l), findsWidgets, reason: l);
      }
      expect(find.text('CHABI Rock'), findsWidgets);
      expect(find.text('Délai 1 j'), findsWidgets);
      expect(find.widgetWithText(BoutonSigh, 'Modifier'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Archiver'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Imprimer'), findsOneWidget);
    });

    cas('la carte de donneur s\'imprime', (t) async {
      await ouvrir(t, jeu(), 'm5-donneurs');
      await toucher(t, icone(t, 'DON-0003', 'Imprimer l’état'));
      expect(find.text('Carte de donneur de sang'), findsWidgets);
      expect(find.textContaining('remercie chaleureusement ce donneur'), findsWidgets);
    });

    cas('créer : valeurs par défaut, refus du formulaire vide, E200 — référence au rang suivant', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-donneurs');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      expect(find.text('Nouveau donneur'), findsOneWidget);
      final def = ((d['creation'] as Map)['defauts'] as Map).cast<String, Object?>();
      expect(find.text('${def['type']}'), findsWidgets);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(m.collection('donneurs').toutes.length, 9);
      await saisir(t, 'nom', 'IMOROU Zaki');
      await saisir(t, 'telephone', '97111111');
      await saisir(t, 'nbDons', '6');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final f = m.collection('donneurs').toutes.first;
      expect(f['nom'], 'IMOROU Zaki');
      expect(f['nbDons'], 6);
      expect(f['groupe'], 'O+');
      expect(f['eligible'], true);
      expect(f['reference'], 'DON-0010', reason: 'le rang suit DON-0009 (archivé) : jamais un compteur de page');
      expect(find.text('Nouveau donneur créé.'), findsOneWidget);
      await toucher(t, find.text('Annuler').last);
      expect(m.collection('donneurs').actives.any((x) => x['nom'] == 'IMOROU Zaki'), isFalse);
    });

    cas('modifier : la référence est conservée, le nombre de dons redevient un nombre', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-donneurs');
      await toucher(t, icone(t, 'DON-0003', 'Modifier'));
      await saisir(t, 'nbDons', '13');
      await saisir(t, 'telephone', '97999999');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final f = m.collection('donneurs').toutes.firstWhere((x) => x['id'] == 'DON0003');
      expect(f['reference'], 'DON-0003');
      expect(f['nbDons'], 13);
      expect(f['telephone'], '97999999');
      expect(find.text('Modifications enregistrées.'), findsOneWidget);
    });

    cas('archiver est annulable ; l\'onglet Archivés les montre', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm5-donneurs');
      await toucher(t, icone(t, 'DON-0001', 'Archiver'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      expect(find.text('Le motif est obligatoire.'), findsOneWidget, reason: 'requireMotif de K.crud');
      await t.enterText(find.byType(TextField).last, 'Doublon');
      await t.pump();
      await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      expect(m.collection('donneurs').toutes.firstWhere((x) => x['id'] == 'DON0001')['statut'], 'archive');
      expect(kpi(t, 'Donneurs enregistrés'), '7');
      await toucher(t, find.text('Annuler').last);
      expect(kpi(t, 'Donneurs enregistrés'), '8');
    });
  });

  group('parité N1 (contenu) contre la fiche de la maquette', () {
    Future<void> mesurer(WidgetTester t, String id, Magasin m) async {
      final fiche = (jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()) as Map).cast<String, Object?>();
      expect(fiche['acces'], 'ouvert', reason: 'la fiche doit avoir été extraite activité rouverte');
      await ouvrir(t, m, id);
      final p = comparerContenu(id, fiche, textesVisibles(t));
      expect(p.manquants, isEmpty, reason: '$id : ${p.presents}/${p.attendus} — manque ${p.manquants}');
    }

    cas('m5-reactifs-stats : 100 %', (t) async {
      final c = liste(vecteurs['stats']).first;
      await mesurer(t, 'm5-reactifs-stats', magasin(produits: liste(c['produits']), lots: liste(c['lots']), demandes: liste(c['demandes'])));
    });
    cas('m5-banque-sang : 100 %', (t) async {
      await mesurer(t, 'm5-banque-sang', magasin(poches: liste((vecteurs['banque'] as Map)['poches'])));
    });
    cas('m5-donneurs : 100 %', (t) async {
      await mesurer(t, 'm5-donneurs', magasin(donneurs: liste((vecteurs['donneurs'] as Map)['donneurs'])));
    });
  });

  group('droits', () {
    cas('la direction (lecture) consulte sans Nouveau, Modifier ni Archiver — commandes absentes', (t) async {
      final b = (vecteurs['banque'] as Map).cast<String, Object?>();
      await ouvrir(t, magasin(poches: liste(b['poches'])), 'm5-banque-sang', role: 'direction');
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.text('Poches de sang'), findsOneWidget);
      final d = (vecteurs['donneurs'] as Map).cast<String, Object?>();
      await ouvrir(t, magasin(donneurs: liste(d['donneurs'])), 'm5-donneurs', role: 'direction');
      expect(find.text('Nouveau'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.textContaining('Lecture seule'), findsOneWidget);
    });
  });

  group('activité fermée', () {
    cas('banque de sang et donneurs sont absents de la matrice des droits : la coque ne les ouvre à aucun rôle', (t) async {
      // E203 : l'activité est fermée dans la maquette (`modulesActifs`) ; la fermeture retire l'écran pour TOUS les rôles, administrateur compris.
      for (final id in ['m5-banque-sang', 'm5-donneurs']) {
        for (final role in ['admin', 'laborantin', 'medecin']) {
          expect(donneesTelles.matrice.peutVoir(role, id), isFalse, reason: '$id / $role');
        }
      }
    });
  });
}
