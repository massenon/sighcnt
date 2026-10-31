import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'hos_aide.dart';
import 'parite/extracteur.dart';

/// `m3-feuille-temperature` : les admissions et relevés d'essai de la maquette (`vecteurs.temperature`) sont montés ; tableau, courbes, saisie (refus et
/// plage physiologique), archivage annulable, feuille imprimée et droits doivent être ce que la maquette a affiché ou écrit.
Map<String, Object?> tmp() => carte(vecteurs['temperature']);

Magasin magasinEssai({bool admissions = true}) => Magasin({
      'admissions': admissions ? [for (final x in liste(tmp()['admissions'])) {...x}] : const [],
      'releves': [for (final x in liste(tmp()['releves'])) {...x}],
      'audit': const [],
    }, 'POSTE');

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  cas('premier patient hospitalisé : cartes, six relevés actifs dans l\'ordre de la maquette (le plus récent en tête), relevé archivé exclu', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-feuille-temperature');
    final e = carte(tmp()['ecran']);
    for (final c in (e['cartes'] as List).cast<String>()) {
      expect(affiche(t, c), isTrue, reason: c);
    }
    final lignes = ((e['tableaux'] as List).single as Map)['lignes'] as List;
    final tab = t.widget<TableauSigh>(find.byType(TableauSigh));
    expect(tab.lignes.length, lignes.length);
    expect(tab.lignes.any((r) => r['id'] == 'REL7'), isFalse, reason: 'le relevé archivé n\'est pas à la feuille');
    for (var i = 0; i < lignes.length; i++) {
      final l = lignes[i] as List;
      final r = tab.lignes[i];
      expect(sansEspaces('${r['date']} ${r['heure']}'), isNot(''));
      expect(r['tension'], l[3], reason: 'rang $i');
      expect(r['heure'], l[1], reason: 'rang $i');
      expect(r['saisiPar'], l[10]);
    }
    // les cellules affichées, ligne par ligne, telles que la maquette les a rendues
    final vues = <String, int>{};
    for (final l in lignes) {
      final date = (l as List)[0] as String;
      final rang = vues[date] = (vues[date] ?? -1) + 1;
      final cellules = sansEspaces(ligneDe(t, date, rang: rang).join('|'));
      for (final idx in [2, 4, 5, 6, 7, 8, 9]) {
        expect(cellules.contains(sansEspaces(l[idx])), isTrue, reason: '${l[0]} ${l[1]} : « ${l[idx]} » absent');
      }
    }
    expect(affiche(t, 'TCHANE Bertine'), isTrue);
    expect(affiche(t, '4 jour(s)'), isTrue, reason: 'séjour depuis le 12/08/2026');
  });

  cas('courbes : température sur l\'axe borné 35–41 (série rouge), FC et SpO₂ sans aire, étiquettes « jj/mm hh:mm » — valeurs de la maquette', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-feuille-temperature');
    final g = liste(carte(tmp()['ecran'])['graphiques']);
    final lignes = t.widgetList<GraphiqueLigne>(find.byType(GraphiqueLigne)).toList();
    expect(lignes.length, 2);
    final a0 = g[0]['args'] as List;
    expect(lignes[0].etiquettes, (a0[0] as List).cast<String>());
    expect(lignes[0].series.single.donnees, (liste(a0[1]).single['data'] as List).cast<num>());
    expect(lignes[0].min, 35);
    expect(lignes[0].max, 41);
    final a1 = g[1]['args'] as List;
    expect(lignes[1].etiquettes, (a1[0] as List).cast<String>());
    expect([for (final s in lignes[1].series) s.libelle], [for (final s in liste(a1[1])) s['label']]);
    expect([for (final s in lignes[1].series) s.donnees], [for (final s in liste(a1[1])) (s['data'] as List).cast<num>()]);
    expect(lignes[1].series.every((s) => !s.aire), isTrue);
    expect(lignes[1].min, isNull, reason: 'FC et SpO₂ partent de zéro');
  });

  cas('le sélecteur change de patient ; sans relevé : message dit, et le bouton « Saisir le premier relevé » pour qui peut écrire', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-feuille-temperature');
    await choisir(t, 'admissionId', 'BAKO Boukari');
    final s = '${carte(tmp()['sansReleve'])['texte']}';
    expect(s, contains('Aucun relevé enregistré pour ce patient.'));
    expect(affiche(t, 'Aucun relevé enregistré pour ce patient.'), isTrue);
    expect(affiche(t, 'C1 LIT1'), isTrue);
    expect(find.widgetWithText(BoutonSigh, 'Saisir le premier relevé'), findsOneWidget);
    expect(find.byType(GraphiqueLigne), findsNothing);
    expect(find.byType(TableauSigh), findsNothing);
  });

  cas('aucun patient hospitalisé : la feuille le dit et renvoie à l\'admission', (t) async {
    await ouvrir(t, magasinEssai(admissions: false), 'm3-feuille-temperature');
    final v = '${carte(tmp()['vide'])['texte']}';
    expect(v, contains('Aucun patient hospitalisé actuellement.'));
    expect(affiche(t, 'Aucun patient hospitalisé actuellement.'), isTrue);
    expect(affiche(t, 'La feuille de température se saisit pour les patients en cours d’hospitalisation.'), isTrue);
    expect(find.widgetWithText(BoutonSigh, 'Créer une admission'), findsOneWidget);
  });

  cas('saisie : champs de la maquette, valeurs par défaut ; formulaire vide refusé ; température hors plage refusée avec son message ; rien n\'est écrit', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-feuille-temperature');
    final col = m.collection('releves');
    final avant = col.toutes.length;
    await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau relevé'));
    final s = carte(tmp()['saisie']);
    for (final lib in (s['champs'] as List).cast<String>()) {
      expect(affiche(t, lib.replaceAll(' *', '')), isTrue, reason: lib);
    }
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(find.text(((carte(s['refusVide'])['toasts'] as List).single as List).single as String), findsOneWidget);
    expect(col.toutes.length, avant);
    await t.pump(const Duration(seconds: 10));
    await saisir(t, 'temperature', '99');
    await saisir(t, 'tension', '12/8');
    await saisir(t, 'fc', '80');
    await saisir(t, 'spo2', '97');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(find.text((carte(s['refusPlage'])['erreurs'] as List).single as String), findsOneWidget);
    expect(col.toutes.length, avant, reason: 'une température de 99 °C n\'est pas une constante');
    await saisir(t, 'heure', '25:99');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(find.text('Heure attendue au format HH:mm.'), findsOneWidget);
    expect(col.toutes.length, avant);
  });

  cas('saisie complète : la fiche écrite est celle de la maquette (champs vides → rien), le nouveau relevé passe en tête et sur la courbe, le geste est annulable', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-feuille-temperature');
    final col = m.collection('releves');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau relevé'));
    await saisir(t, 'temperature', '37.8');
    await saisir(t, 'tension', '12/8');
    await saisir(t, 'fc', '80');
    await saisir(t, 'spo2', '97');
    await saisir(t, 'fr', '20');
    await saisir(t, 'diurese', '1200');
    await saisir(t, 'traitement', 'Paracétamol');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final f = col.actives.first;
    final att = carte(carte(carte(tmp()['saisie'])['cree'])['fiche']);
    for (final k in ['statut', 'date', 'heure', 'temperature', 'tension', 'fc', 'spo2', 'fr', 'diurese', 'poids', 'taille', 'traitement', 'admissionId']) {
      expect(f[k], att[k], reason: k);
    }
    expect('${f['saisiPar']}', isNotEmpty, reason: 'RG-12 : le relevé porte l\'agent connecté');
    expect(find.text('Relevé enregistré.'), findsOneWidget);
    final apres = carte(tmp()['apresCreation']);
    final ligne1 = (((apres['tableaux'] as List).single as Map)['lignes'] as List).first as List;
    expect(sansEspaces(ligneDe(t, ligne1[0] as String).join('|')), contains(sansEspaces(ligne1[9])));
    final courbe = t.widgetList<GraphiqueLigne>(find.byType(GraphiqueLigne)).first;
    final args = ((apres['graphiques'] as List).first as Map)['args'] as List;
    expect(courbe.series.single.donnees, (liste(args[1]).single['data'] as List).cast<num>());
    await toucher(t, find.text('Annuler'));
    expect(col.parId(f['id'])!['statut'], 'archive', reason: 'RG-14 : l\'annulation archive');
  });

  cas('archivage d\'un relevé : annulable, le relevé quitte la feuille (RG-14), la ligne revient à l\'annulation', (t) async {
    final m = magasinEssai();
    await ouvrir(t, m, 'm3-feuille-temperature');
    final col = m.collection('releves');
    expect(find.byTooltip('Archiver ce relevé'), findsNWidgets(6));
    await toucher(t, find.byTooltip('Archiver ce relevé').first);
    expect(col.parId('REL6')!['statut'], 'archive', reason: 'la première ligne est le relevé du 15/08 à 14:00');
    expect(find.text('Relevé archivé.'), findsOneWidget);
    expect(t.widget<TableauSigh>(find.byType(TableauSigh)).lignes.length, 5);
    await toucher(t, find.text('Annuler'));
    expect(col.parId('REL6')!['statut'], isNot('archive'));
  });

  cas('droits : la réception LIT la feuille mais n\'a ni « Nouveau relevé », ni « Saisir le premier relevé », ni archivage (RG-13, E371)', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-feuille-temperature', role: 'reception');
    expect(affiche(t, 'Courbe de température (°C)'), isTrue, reason: 'l\'écran s\'ouvre à ce profil');
    expect(find.widgetWithText(BoutonSigh, 'Nouveau relevé'), findsNothing);
    expect(find.byTooltip('Archiver ce relevé'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Imprimer la feuille'), findsOneWidget);
    await choisir(t, 'admissionId', 'BAKO Boukari');
    expect(affiche(t, 'Aucun relevé enregistré pour ce patient.'), isTrue);
    expect(find.widgetWithText(BoutonSigh, 'Saisir le premier relevé'), findsNothing);
  });

  cas('feuille imprimée : cartouche, en-têtes et relevés dans l\'ordre chronologique, deux signatures — comme la maquette', (t) async {
    await ouvrir(t, magasinEssai(), 'm3-feuille-temperature');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Imprimer la feuille'));
    final e = carte(tmp()['etat']);
    expect(affiche(t, '${e['titre']}'), isTrue);
    expect(affiche(t, '${e['sousTitre']}'), isTrue);
    for (final c in (e['cartouche'] as List)) {
      expect(affiche(t, '${(c as List)[1]}'), isTrue, reason: '${c[0]}');
    }
    final haut = {for (final h in ['13/08/2026', '15/08/2026']) h: t.getTopLeft(find.text(h).last).dy};
    expect(haut['13/08/2026']! < haut['15/08/2026']!, isTrue, reason: 'ordre chronologique à l\'impression');
    expect(affiche(t, 'L’Infirmier traitant'), isTrue);
    expect(affiche(t, 'Le Médecin'), isTrue);
  });

  cas('parité N1 = 100 % contre la fiche de la maquette (jeu complet, au jour où la fiche a été tirée)', (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    await ouvrir(t, m, 'm3-feuille-temperature', le: DateTime(2026, 10, 30, 10));
    final fiche = (jsonDecode(File('../../docs/architecture/ecrans/m3-feuille-temperature.json').readAsStringSync()) as Map).cast<String, Object?>();
    final p = comparerContenu('m3-feuille-temperature', fiche, textesVisibles(t));
    expect(p.manquants, isEmpty, reason: 'taux ${p.taux}');
  });
}
