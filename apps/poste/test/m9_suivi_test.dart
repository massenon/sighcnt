import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm9_aide.dart';

/// Prises en charge, historique, créances et relances de M9 : les valeurs attendues sont celles de l'écran réel de la maquette (pilote
/// `vecteurs-m9.js`, horloge au 16/08/2026 12:00:28) ; les gestes (correction d'une prise en charge, relance créée / corrigée / archivée) sont
/// accomplis par les boutons, et l'écart du magasin est comparé à ce que la maquette a écrit.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final v = vecteurs();
  final ecrans = m9(v['ecrans']);

  group('m9-prises-en-charge', () {
    cas('KPI = écran réel ; tri par date décroissante, 15 lignes par page', (t) async {
      await ouvrir(t, magasin(), 'm9-prises-en-charge');
      expect(kpis(t), ['145', '2 265 550 FCFA', '1 733 134 FCFA', '532 416 FCFA']);
      expect(find.text('Affichage de 1 à 15 sur 145 enregistrements'), findsOneWidget);
      // La pièce la plus récente de l'écran réel est en tête.
      final premiere = cellulesVecteur(v, 'm9-prises-en-charge').first;
      expect(find.text(premiere[0]), findsWidgets);
    });

    cas('le filtre « Niveau » : Totale = taux 100 ; Partielle = taux < 100, y compris 0', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm9-prises-en-charge');
      final res = m9(m9(ecrans['m9-prises-en-charge'])['filtresResultats']);
      await filtrer(t, 'Niveau de prise en charge', 'Totale (100 %)');
      for (final l in (m9(res['Niveau de prise en charge|totale'])['premieres'] as List)) {
        expect(find.text('${(l as List).first}'), findsWidgets);
      }
      await filtrer(t, 'Niveau de prise en charge', 'Partielle');
      for (final l in (m9(res['Niveau de prise en charge|partielle'])['premieres'] as List)) {
        expect(find.text('${(l as List).first}'), findsWidgets);
      }
    });

    cas('« Modifier » corrige le taux et les parts, et rien d’autre ; pas d’archivage depuis cet écran', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm9-prises-en-charge');
      final cible = cellulesVecteur(v, 'm9-prises-en-charge').first[0];
      expect(find.byTooltip('Archiver'), findsNothing);
      await toucher(t, find.byTooltip('Modifier').first);
      expect(find.text('Modifier l’enregistrement'), findsOneWidget);
      await saisir(t, 'tauxPriseEnCharge', '60');
      await saisir(t, 'partAssurance', '1234');
      await saisir(t, 'partPatient', '4321');
      await saisir(t, 'observations', 'Corrigé au guichet');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final f = m.collection('factures').actives.firstWhere((x) => x['numero'] == cible);
      final patch = lm(m9(m9(m9(m9(ecrans['m9-prises-en-charge'])['modification'])['ecart'])['modifs'])['factures'] ?? const []).single['patch'] as Map;
      for (final k in patch.keys) {
        expect(f[k], patch[k], reason: k);
      }
      expect(f['montantTTC'], isNotNull);
    });

    cas('droits : « Modifier » est ABSENT sans le droit d’écrire (direction)', (t) async {
      await ouvrir(t, magasin(), 'm9-prises-en-charge', role: 'direction');
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(kpis(t).first, '145');
    });
  });

  group('m9-historique', () {
    cas('plage par défaut : 180 jours ; KPI = écran réel', (t) async {
      await ouvrir(t, magasin(), 'm9-historique');
      final base = m9(m9(ecrans['m9-historique'])['base']);
      expect(kpis(t), [for (final k in lm(base['kpis'])) '${k['valeur']}']);
      expect(kpis(t), ['121', '58', '1 814 012 FCFA', '1 566 387 FCFA']);
      expect(textes(t), contains('17/02/2026 → 16/08/2026'));
    });

    cas('une compagnie : les prestations recomptées indépendamment sur le magasin', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm9-historique');
      await choisir(t, 'compagnie', 'NSIA ASSURANCE');
      final debut = DateTime.utc(2026, 2, 17);
      final rows = m.collection('factures').actives.where((f) {
        final d = DateTime.parse('${f['date']}');
        return f['assureur'] == 'NSIA' &&
            !d.isBefore(debut) &&
            !d.isAfter(DateTime.utc(2026, 8, 16));
      }).toList();
      expect(kpis(t).first, nombre(rows.length));
      expect(kpis(t)[3], sp(money(rows.fold<num>(0, (a, f) => a + (f['partAssurance'] as num)))));
    });

    cas('plage sans prestation : message et aucun tableau', (t) async {
      final m = magasin();
      for (final f in m.collection('factures').actives) {
        m.collection('factures').mettreAJour(f['id'], {'assureur': null});
      }
      await ouvrir(t, m, 'm9-historique');
      expect(find.text('Aucune prestation assurée sur la plage choisie.'), findsOneWidget);
      expect(find.text('Détail des prestations'), findsNothing);
      expect(kpis(t).first, '0');
    });

    cas('cliquer une prestation ouvre sa fiche : montants, reste dû et lignes', (t) async {
      await ouvrir(t, magasin(), 'm9-historique');
      final piece = find.byWidgetPredicate(
          (w) => w is Text && w.data != null && RegExp(r'^F[A-Z]-2026-\d{5}$').hasMatch(w.data!));
      await t.ensureVisible(piece.first);
      await t.pump();
      await t.tap(piece.first, warnIfMissed: false);
      await t.pumpAndSettle();
      expect(find.text('Reste dû'), findsOneWidget);
      expect(find.text('Part assureur'), findsWidgets);
      expect(find.text('Lignes de la prestation'), findsOneWidget);
    });
  });

  group('m9-creances', () {
    final cas0 = lm(m9(ecrans['m9-creances'])['cas']);
    cas('KPI et balance âgée = écran réel (13 compagnies, triées par total dû décroissant)', (t) async {
      await ouvrir(t, magasin(), 'm9-creances');
      expect(kpis(t), [for (final k in lm(cas0[0]['kpis'])) '${k['valeur']}']);
      expect(kpis(t), ['1 733 134 FCFA', '316 886 FCFA', '709 172 FCFA', '707 076 FCFA']);
      for (final l in (cas0[0]['lignes'] as List).take(3)) {
        expect(find.text('${(l as List)[1]}'), findsWidgets);
        expect(texteSp('${l[6]}'), findsWidgets);
      }
      expect(find.text('Relance impérative'), findsOneWidget);
    });

    cas('filtres : compagnie, ancienneté retenue, créance minimale (comme l’écran réel)', (t) async {
      await ouvrir(t, magasin(), 'm9-creances');
      await choisir(t, 'compagnie', 'NSIA — NSIA ASSURANCE');
      expect(kpis(t), [for (final k in lm(cas0[6]['kpis'])) '${k['valeur']}']);
      await toucher(t, find.text('Réinitialiser'));
      expect(kpis(t)[0], '1 733 134 FCFA');
      await choisir(t, 'seuil', 'Au moins 200 000 F');
      expect(kpis(t), [for (final k in lm(cas0[7]['kpis'])) '${k['valeur']}']);
      await choisir(t, 'seuil', 'Au moins 1 000 000 F');
      expect(kpis(t), ['0 FCFA', '0 FCFA', '0 FCFA', '0 FCFA']);
      expect(find.textContaining('Aucune créance ne répond à cette sélection'), findsOneWidget);
      await toucher(t, find.text('Réinitialiser'));
      await choisir(t, 'anciennete', 'Moins de 30 jours');
      expect(kpis(t), [for (final k in lm(cas0[3]['kpis'])) '${k['valeur']}']);
    });

    cas('l’état imprimé : total refait depuis les lignes imprimées, filtres en force portés sur la pièce', (t) async {
      await ouvrir(t, magasin(), 'm9-creances');
      await choisir(t, 'compagnie', 'NSIA — NSIA ASSURANCE');
      await toucher(t, find.text('Éditer l’état des créances'));
      await t.pumpAndSettle();
      expect(find.text('État des créances — tiers payeurs'), findsWidgets);
      expect(find.text('Balance âgée au 16/08/2026'), findsOneWidget);
      final tt = textes(t);
      expect(tt, contains('181 404'));
      expect(tt.where((x) => x.contains('NSIA — NSIA ASSURANCE')), isNotEmpty,
          reason: 'le filtre « Compagnie » en force est relevé sur la pièce');
    });

    cas('lecture seule : aucune commande d’écriture sur l’écran', (t) async {
      await ouvrir(t, magasin(), 'm9-creances');
      expect(find.text('Nouveau'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
    });
  });

  group('m9-relances', () {
    final r = m9(ecrans['m9-relances']);
    Future<void> creer(WidgetTester t, String compagnie, String periode,
        {String? niveau, String? canal, String? obs}) async {
      await toucher(t, find.text('Nouvelle relance'));
      await choisir(t, 'assureur', compagnie);
      await saisir(t, 'periode', periode);
      if (niveau != null) await choisir(t, 'niveau', niveau);
      if (canal != null) await choisir(t, 'canal', canal);
      if (obs != null) await saisir(t, 'observations', obs);
    }

    cas('registre vide : état vide dit quoi faire ; quatre indicateurs à zéro', (t) async {
      await ouvrir(t, magasin(), 'm9-relances');
      expect(kpis(t), ['0', '0', '0', '0 FCFA']);
      expect(find.text('Aucune relance enregistrée.'), findsOneWidget);
      expect(find.textContaining('Établir une relance pour une compagnie'), findsOneWidget);
    });

    cas('Nouvelle relance : le montant proposé est la créance de la compagnie choisie ; la fiche écrite = celle de la maquette',
        (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm9-relances');
      final creance = money(assCreance(assFacturesAssurance(m.collection('factures').actives), 'NSIA'));
      await creer(t, 'NSIA ASSURANCE — créance : $creance', 'juin – juillet 2026', canal: 'Courrier électronique');
      expect(t.widget<TextField>(champ('montant')).controller!.text, '181404',
          reason: 'créance de NSIA, lue de l’écran réel : 181 404 F');
      await saisir(t, 'montant', '150000');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et éditer'));
      final fiche = m.collection('relances').actives.single;
      final attendu = lm(m9(m9(lm(r['cas'])[0]['ecart'])['inserts'])['relances']).single;
      for (final k in ['assureur', 'assureurNom', 'date', 'periode', 'montant', 'niveau', 'canal', 'statutRelance', 'reference', 'observations']) {
        expect(fiche[k], attendu[k], reason: k);
      }
      expect(find.text('Relance REL-0001 enregistrée.'), findsOneWidget);
      // La lettre s'ouvre aussitôt, au ton de la relance simple.
      expect(find.text('Lettre de relance'), findsWidgets);
      expect(find.textContaining('Nous vous saurions gré de bien vouloir procéder au règlement'), findsOneWidget);
      expect(find.textContaining('mettons en demeure'), findsNothing);
    });

    cas('la mise en demeure change le ton, cite les observations, et la référence suit le registre (E500)', (t) async {
      final m = magasin();
      m.collection('relances').inserer({'id': 'RELX', 'statut': 'actif', 'reference': 'REL-0007', 'assureur': 'AFR', 'assureurNom': 'AFRICAINE DES ASSURANCES', 'date': '2026-08-01', 'periode': 'x', 'montant': 1, 'niveau': '1re relance', 'canal': 'Courrier recommandé', 'statutRelance': 'en_attente'});
      await ouvrir(t, m, 'm9-relances');
      await creer(t, 'OLEA ASSURANCE — créance : ${money(331365)}', 'avril – mai 2026',
          niveau: 'Mise en demeure', canal: 'Courrier recommandé', obs: 'Dernier rappel avant suspension');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et éditer'));
      expect(find.text('Relance REL-0008 enregistrée.'), findsOneWidget,
          reason: 'le compteur de la maquette repartait à REL-0001 à chaque chargement : doublon possible');
      expect(find.text('Mise en demeure de payer'), findsWidgets);
      expect(find.textContaining('nous vous mettons en demeure'), findsOneWidget);
      expect(find.text('Dernier rappel avant suspension'), findsWidgets);
    });

    cas('période vide : refus, la fenêtre reste ouverte et rien n’est écrit', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm9-relances');
      await toucher(t, find.text('Nouvelle relance'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et éditer'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(find.text('Nouvelle relance'), findsWidgets);
      expect(m.collection('relances').toutes, isEmpty);
    });

    cas('les indicateurs SUIVENT le registre : création, correction de la suite, archivage annulable', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm9-relances');
      await creer(t, 'NSIA ASSURANCE — créance : ${money(181404)}', 'juin – juillet 2026');
      await saisir(t, 'montant', '150000');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et éditer'));
      await t.pumpAndSettle();
      await t.tap(find.text('Fermer').last);
      await t.pumpAndSettle();
      expect(kpis(t), ['1', '1', '0', '150 000 FCFA']);
      await toucher(t, find.byTooltip('Modifier la relance').first);
      await choisir(t, 'statutRelance', 'Régularisée');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(kpis(t), ['1', '0', '1', '150 000 FCFA']);
      expect(m.collection('relances').actives.single['statutRelance'], 'regularisee');
      await toucher(t, find.byTooltip('Archiver').first);
      expect(kpis(t), ['0', '0', '0', '0 FCFA']);
      expect(m.collection('relances').toutes.length, 1, reason: 'archivage LOGIQUE (RG-14)');
      await t.tap(find.text('Annuler').first, warnIfMissed: false); // le message le plus récent est en tête de pile
      await t.pumpAndSettle();
      expect(kpis(t), ['1', '0', '1', '150 000 FCFA'], reason: 'l’annulation est visible');
    });

    cas('droits : « Nouvelle relance » ABSENTE (direction) ; « Archiver » ABSENT sans le droit d’annuler (caissier)', (t) async {
      await ouvrir(t, magasin(), 'm9-relances', role: 'direction');
      expect(find.text('Nouvelle relance'), findsNothing);
      final m = magasin();
      m.collection('relances').inserer({'id': 'RELX', 'statut': 'actif', 'reference': 'REL-0001', 'assureur': 'AFR', 'assureurNom': 'AFRICAINE DES ASSURANCES', 'date': '2026-08-01', 'periode': 'x', 'montant': 1, 'niveau': '1re relance', 'canal': 'Courrier recommandé', 'statutRelance': 'en_attente'});
      await ouvrir(t, m, 'm9-relances', role: 'caissier');
      expect(find.text('Nouvelle relance'), findsOneWidget);
      expect(find.byTooltip('Modifier la relance'), findsOneWidget);
      expect(find.byTooltip('Archiver'), findsNothing);
    });
  });
}
