import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm9_aide.dart';

/// Conventions & garanties : les valeurs attendues sont celles de l'écran réel de la maquette (pilote `vecteurs-m9.js`). Le jeu ne porte AUCUNE
/// grille : le geste fondateur est la saisie depuis le barème de référence, accompli ici par les boutons ; les 20 garanties écrites sont comparées
/// à celles que la maquette a écrites, et le simulateur rejoue `repartir` (RG-09) sur la convention qu'on vient de saisir.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final v = vecteurs();
  final conv = m9(m9(v['ecrans'])['m9-conventions']);

  Future<void> saisirBareme(WidgetTester t, {bool modifier = true}) async {
    await toucher(t, find.text('CNSS Atacora').first);
    await t.pumpAndSettle();
    await toucher(t, find.text('Saisir la grille depuis le barème de référence'));
    await t.pumpAndSettle();
    await saisir(t, 'taux_0', '75');
    await saisir(t, 'plafond_0', '6000');
    await saisir(t, 'plafond_1', '');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer la convention'));
    await t.pumpAndSettle();
  }

  cas('avant toute saisie : 9 souscripteurs, aucune convention, l’avertissement dit pourquoi', (t) async {
    await ouvrir(t, magasin(), 'm9-conventions');
    expect(kpis(t), [for (final k in lm(conv['kpis'])) '${k['valeur']}']);
    expect(kpis(t), ['9', '0', '9', '0']);
    expect(find.textContaining('9 convention(s) non saisie(s).'), findsOneWidget);
    expect(find.textContaining('mieux vaut une facture juste qu’une prise en charge supposée'), findsOneWidget);
    expect(find.text('Contrats sous 13 compagnies'), findsOneWidget);
    await toucher(t, find.text('Grilles de garanties').first);
    expect(find.text('Aucune convention saisie. Ouvrir un souscripteur pour saisir sa grille.'), findsOneWidget);
  });

  cas('filtres : catégorie et convention (« Saisie » est vide tant que rien n’est saisi)', (t) async {
    await ouvrir(t, magasin(), 'm9-conventions');
    await filtrer(t, 'Catégorie', 'Entreprise');
    final res = m9(conv['filtresResultats']);
    for (final x in (res['Catégorie|entreprise'] as List)) {
      expect(find.textContaining('$x'.split(' ').first), findsWidgets);
    }
    expect(find.text('Souscripteurs particuliers'), findsNothing);
    await filtrer(t, 'Catégorie', 'Catégorie');
    await filtrer(t, 'Convention', 'Saisie');
    expect(find.text('CNSS Atacora'), findsNothing);
  });

  cas('la fiche d’un souscripteur sans grille dit que ses assurés sont facturés intégralement', (t) async {
    await ouvrir(t, magasin(), 'm9-conventions');
    await toucher(t, find.text('CNSS Atacora').first);
    await t.pumpAndSettle();
    expect(find.text('Convention non saisie — les assurés de ce souscripteur sont facturés intégralement.'), findsOneWidget);
    expect(find.text('Aucune — tout est couvert dans cette catégorie.'), findsNWidgets(3));
    expect(find.text('Saisir la grille depuis le barème de référence'), findsOneWidget);
  });

  cas('saisie depuis le barème : 20 garanties ajustées, exclusions reprises, compteurs à jour', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm9-conventions');
    await saisirBareme(t);
    final posees = m.collection('garanties').actives.where((g) => g['souscripteurId'] == 'SOU006').toList();
    expect(posees.length, 20);
    final attendues = lm(m9(m9(m9(conv['saisieBareme'])['ecart'])['inserts'])['garanties']);
    final parCode = {for (final g in attendues) g['code']: g};
    for (final g in posees) {
      final a = parCode[g['code']]!;
      for (final k in ['libelle', 'categorie', 'taux', 'plafond', 'unitePlafond', 'zone', 'source', 'assureur']) {
        expect(g[k], a[k], reason: '${g['code']}.$k');
      }
    }
    final s = m.collection('souscripteurs').parId('SOU006')!;
    expect(s['grilleSaisie'], isTrue);
    expect((s['actesExclus'] as List).length, 14);
    expect((s['produitsExclus'] as List).length, 23);
    expect((s['accordPrealable'] as List).length, 15);
    expect(find.text('Convention de CNSS Atacora enregistrée.'), findsOneWidget);
    expect(find.text('20 garanties, exclusions et accords préalables repris.'), findsOneWidget);
    expect(kpis(t), ['9', '1', '8', '20']);
  });

  cas('« Modifier la grille » ne change que les taux et plafonds saisis', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm9-conventions');
    await saisirBareme(t);
    final avant = m.collection('garanties').actives.map((g) => g['taux']).toList();
    await toucher(t, find.text('Modifier la grille'));
    await t.pumpAndSettle();
    await saisir(t, 'taux_2', '55');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    await t.pumpAndSettle();
    final apres = m.collection('garanties').actives.map((g) => g['taux']).toList();
    expect([for (var i = 0; i < avant.length; i++) if (avant[i] != apres[i]) i], [2]);
    expect(apres[2], 55);
    expect(find.text('Grille mise à jour.'), findsOneWidget);
  });

  cas('simulateur : la convention saisie s’applique ligne par ligne, avec plafond et motif (écran réel)', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm9-conventions');
    await saisirBareme(t);
    await t.tapAt(const Offset(20, 500)); // le fond du tiroir le referme
    await t.pumpAndSettle();
    await toucher(t, find.text('Simulateur de répartition'));
    await t.pumpAndSettle();
    final sim = lm(conv['simulations']);
    // Carte valide, souscripteur CNSS Atacora : 75 % plafonné à 6 000, hospitalisation plafonnée à 15 000 par jour.
    await choisir(t, 'assure', 'ADAM Salifou');
    final tt = textes(t);
    expect(tt, contains('Part assureur 23 130 FCFA'.replaceAll('Part assureur ', '')));
    expect(tt, contains('35 600 FCFA'));
    expect(tt, contains('Garantie Consultation généraliste — 75 %'));
    expect(tt, contains('Garantie Hospitalisation — frais de chambre — 80 %, plafonnée à 15 000 par jour'));
    expect(sim[0]['texte'], contains('Part assureur 23 130 FCFA'));
    // Carte expirée : RG-09, rien n'est couvert.
    await choisir(t, 'assure', 'BAKO Boukari');
    final t2 = textes(t);
    expect(t2, contains('NON VALIDE — expirée le 21/07/2026'));
    expect(t2.where((x) => x == 'Carte non valide à la date de facturation (RG-09)').length, 5);
    expect(t2, contains('0 FCFA'));
  });

  cas('simulateur sans convention : « Convention non saisie pour … », tout au patient', (t) async {
    await ouvrir(t, magasin(), 'm9-conventions');
    await toucher(t, find.text('Simulateur de répartition'));
    await t.pumpAndSettle();
    await choisir(t, 'assure', 'ADAM Salifou');
    final tt = textes(t);
    expect(tt.where((x) => x.startsWith('Convention non saisie pour ') || x.startsWith('Carte non valide')).length, 5);
    expect(tt, contains('à collecter'));
    expect(tt, contains('35 600 FCFA'));
  });

  cas('« Nouveau » souscripteur : compagnie nommée, listes d’exclusions vides, provenance — comme la maquette', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm9-conventions');
    await toucher(t, find.text('Nouveau'));
    await saisir(t, 'nom', 'Employeur de test');
    await choisir(t, 'assureur', 'NSIA ASSURANCE');
    await saisir(t, 'police', 'NSIA/2026/7777');
    await choisir(t, 'categorie', 'Assurance particulier');
    await saisir(t, 'effectif', '12');
    await saisir(t, 'contact', 'Mme Test');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final s = m.collection('souscripteurs').actives.first;
    final a = lm(m9(m9(m9(v['souscripteurCreation'])['ecart'])['inserts'])['souscripteurs']).single;
    for (final k in ['nom', 'assureur', 'assureurNom', 'police', 'categorie', 'effectif', 'contact', 'actesExclus', 'produitsExclus', 'accordPrealable', 'source']) {
      expect(s[k], a[k], reason: k);
    }
    expect(kpis(t).first, '10');
  });

  cas('l’impression de la convention porte la grille, ses plafonds et leur unité', (t) async {
    await ouvrir(t, magasin(), 'm9-conventions');
    await saisirBareme(t);
    await toucher(t, find.text('Imprimer la convention'));
    await t.pumpAndSettle();
    expect(find.text('Convention de prise en charge'), findsWidgets);
    final tt = textes(t);
    expect(tt, contains('par personne, tous les deux ans'));
    expect(tt, contains('Accouchement par voie chirurgicale'));
    expect(tt, contains('250 000'));
    expect(tt, contains('Pour le souscripteur'));
  });

  cas('droits : sans le droit d’écrire (direction), ni « Nouveau », ni saisie de grille ; l’impression reste offerte', (t) async {
    await ouvrir(t, magasin(), 'm9-conventions', role: 'direction');
    expect(find.text('Nouveau'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    await toucher(t, find.text('CNSS Atacora').first);
    await t.pumpAndSettle();
    expect(find.text('Saisir la grille depuis le barème de référence'), findsNothing);
    expect(find.text('Modifier la grille'), findsNothing);
    expect(find.text('Imprimer la convention'), findsOneWidget);
  });
}
