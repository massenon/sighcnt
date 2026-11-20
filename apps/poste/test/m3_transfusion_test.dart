import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/m3/surv_commun.dart' show dateTexte;

import 'aide_polices.dart';
import 'm3_surv_aide.dart';
import 'parite/extracteur.dart';

/// `m3-transfusion` : l'écran rejoue les vecteurs de la maquette (`hospitalisation.json`, groupe `transfusion`, tiré de l'écran réel piloté dans
/// Chrome). Écart E366 : la commande « Modifier » de la maquette plante, elle est ABSENTE ici.
final v = dico(lireVecteurs('hospitalisation.json')['transfusion']);
final soignants = liste(jsonDecode(File('assets/donnees/jeu/soignants.json').readAsStringSync()));

Magasin magasin() => Magasin({
      'surveillancesTransfusion': [for (final x in liste(v['jeu'])) {...x}],
      'patients': liste(v['patients']),
      'soignants': soignants,
      'audit': const [],
    }, 'POSTE');

const temps = ['t0', 't15', 't30', 't60', 't90', 'fin', 'h1', 'h2'];

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  cas('transfusion : KPI, lignes et badges identiques à la maquette', (t) async {
    await ouvrir(t, magasin(), 'm3-transfusion');
    final ecran = dico(v['ecran']);
    for (final k in liste(ecran['kpis'])) {
      final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == k['libelle']));
      expect(sans(w.valeur), sans(k['valeur']), reason: '${k['libelle']}');
      expect(w.indice, k['indice'], reason: 'indice ${k['libelle']}');
    }
    final lignes = (dico((ecran['tableaux'] as List).single)['lignes'] as List).cast<List>();
    final tab = t.widget<TableauSigh>(find.byType(TableauSigh));
    expect(tab.lignes.length, lignes.length);
    for (var i = 0; i < lignes.length; i++) {
      final r = tab.lignes[i];
      expect(r['reference'], lignes[i][0]);
      expect(dateTexte(r['date']), lignes[i][1]);
      expect(r['patient'], lignes[i][2]);
      expect(r['service'], lignes[i][3]);
      expect(r['pochePSL'], lignes[i][4]);
      expect(r['debut'], lignes[i][5]);
      expect('${r['releves']} / ${r['attendus']}', lignes[i][6]);
      expect(r['incident'] == true ? 'OUI' : 'Non', lignes[i][7]);
    }
    expect(find.text('OUI'), findsOneWidget);
    expect(find.text('5 / 8'), findsOneWidget);
  });

  cas('transfusion : « Modifier » est ABSENT (E366 : la commande de la maquette plante), Consulter et Archiver restent', (t) async {
    await ouvrir(t, magasin(), 'm3-transfusion');
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.byTooltip('Consulter'), findsWidgets);
    expect(find.byTooltip('Archiver'), findsWidgets);
  });

  cas('transfusion : la fiche affiche les huit temps, l\'incident nommé et la conclusion', (t) async {
    await ouvrir(t, magasin(), 'm3-transfusion');
    await toucher(t, find.byTooltip('Consulter').at(1)); // TRF-0002, la 2e ligne (date décroissante)
    expect(find.text('OUI — Frissons'), findsOneWidget);
    expect(find.text('Relevés du protocole'), findsOneWidget);
    for (final e in ['Température', 'Tension artérielle', 'Fréquence respiratoire', 'Fréquence cardiaque', 'SpO₂', 'Aspect des urines', 'Conscience', 'Autre élément surveillé']) {
      expect(find.text(e), findsWidgets, reason: e);
    }
    for (final tt in ['Avant la pose', '15 min', '30 min', '60 min', '90 min', 'Fin', '1 heure après', '2 heures après']) {
      expect(find.text(tt.toUpperCase()), findsWidgets, reason: tt);
    }
    expect(find.text('Conclusion 2'), findsOneWidget);
  });

  cas('transfusion : un protocole INCOMPLET est signalé, jamais refusé ; un formulaire vide est refusé', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm3-transfusion');
    await toucher(t, find.text('Nouvelle surveillance'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
    expect(m.collection('surveillancesTransfusion').actives.length, 2);
    await choisir(t, 'patientCode', 'CNT/2/26 — BAKO Boukari');
    await ecrire(t, 'service', 'Médecine');
    await ecrire(t, 'pochePSL', 'PSL-900');
    await ecrire(t, 'debut', '08h30');
    await ecrire(t, 't0_temperature', '37.0');
    await ecrire(t, 't0_ta', '12/8');
    await ecrire(t, 't15_temperature', '37.2');
    await ecrire(t, 'fin_conscience', 'normale');
    await ecrire(t, 'h2_autre', 'x');
    await ecrire(t, 'conclusion', 'RAS');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final att = dico(dico(dico(v['creation'])['partielle'])['fiche']);
    final f = m.collection('surveillancesTransfusion').actives.first;
    expect(f['reference'], 'TRF-0004', reason: 'série lue sur le registre (E360) : après TRF-0001 et TRF-0002 archivée ou non, jamais TRF-0001');
    expect(f['releves'], 4);
    expect(f['attendus'], 8);
    expect(f['valeurs'], att['valeurs']);
    expect(f['incident'], false);
    expect(f['responsable'], att['responsable']);
    expect(f['patient'], att['patient']);
    expect(find.text('Surveillance enregistrée — 4 temps non relevé(s).'), findsOneWidget);
  });

  cas('transfusion : protocole complet avec incident → deux messages, dont l\'alerte rouge nommant la poche', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm3-transfusion');
    await toucher(t, find.text('Nouvelle surveillance'));
    await choisir(t, 'patientCode', 'CNT/3/26 — N’TCHA Yacoubou');
    await ecrire(t, 'service', 'Urgences');
    await ecrire(t, 'pochePSL', 'PSL-901');
    await ecrire(t, 'debut', '09h00');
    for (final tt in temps) {
      await ecrire(t, '${tt}_temperature', '37');
    }
    await toucher(t, find.text('Un incident transfusionnel est survenu'));
    await ecrire(t, 'natureIncident', 'Frissons');
    await ecrire(t, 'conclusion', 'Frissons à 30 min');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final f = m.collection('surveillancesTransfusion').actives.first;
    expect(f['releves'], 8);
    expect(f['incident'], true);
    expect(f['natureIncident'], 'Frissons');
    expect(find.text('Surveillance complète enregistrée.'), findsOneWidget);
    expect(find.text('Incident transfusionnel signalé — poche PSL-901'), findsOneWidget);
  });

  cas('transfusion : parité N1 = 100 % contre la fiche de la maquette (jeu complet)', (t) async {
    await ouvrir(t, Magasin.depuisDossier(Magasin.collectionsDuJeu), 'm3-transfusion');
    final fiche = dico(jsonDecode(File('../../docs/architecture/ecrans/m3-transfusion.json').readAsStringSync()));
    final p = comparerContenu('m3-transfusion', fiche, textesVisibles(t));
    expect(p.manquants, isEmpty, reason: 'taux ${p.taux}');
  });
}
