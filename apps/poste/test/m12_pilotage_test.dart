import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';
import 'parite/extracteur.dart';

/// M12 — pilotage : m12-bfr, m12-cout-activite. Les règles (BFR, alerte de recouvrement, marge sur consommables, prévision saisonnière) sont rejouées sur
/// les vecteurs de la maquette (`packages/domaine/test/cpc_bfr_test.dart`) ; ici, l'ÉCRAN : la parité N1, puis ce qui est lu, annoncé, refusé — et ce qui
/// n'est JAMAIS inventé (le coût de personnel, un composant non amorcé, une prévision sur deux mois).
Map<String, Object?> fiche(String id) =>
    (jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()) as Map).cast<String, Object?>();

Magasin magasinComplet() => Magasin.depuisDossier(Magasin.collectionsDuJeu);
String nt(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();

/// Pose [valeur] dans le champ [champ] (un champ de date : la saisie est une chaîne ISO, comme celle que rend le sélecteur de dates).
Future<void> poserChamp(WidgetTester t, String champ, String valeur) async {
  final f = t.widgetList<FormulaireSigh>(find.byType(FormulaireSigh)).firstWhere((x) => x.controleur.champs.any((c) => c.nom == champ));
  f.controleur.poser(champ, valeur);
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('parité N1', () {
    for (final id in ['m12-bfr', 'm12-cout-activite']) {
      casM14('$id : N1 = 100 %', (t) async {
        final m = magasinComplet();
        await ouvrirM14(t, m, id);
        final p = comparerContenu(id, fiche(id), textesVisibles(t));
        expect(p.manquants, isEmpty, reason: '$id : ${p.presents}/${p.attendus}');
        expect(p.taux, 1.0);
      });
    }
  });

  group('m12-bfr', () {
    casM14('les trois composantes sont CALCULÉES et se lisent au chiffre de la maquette : 5 011 584 FCFA, 305 jours de chiffre d\'affaires', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-bfr');
      for (final k in ['En-cours clients', 'Valorisation des stocks', 'Dettes fournisseurs']) {
        expect(find.text(k), findsOneWidget, reason: k);
      }
      expect(find.text('Besoin en fonds de roulement'), findsWidgets);
      expect(find.text(money(2854586)), findsOneWidget);
      expect(find.text(money(5373632)), findsOneWidget);
      expect(find.text(money(3216634)), findsOneWidget);
      expect(find.text(money(5011584)), findsOneWidget);
      expect(find.text('305 jours de chiffre d’affaires'), findsOneWidget);
      expect(find.text('méthode en vigueur : prix de vente'), findsOneWidget);
      expect(find.text('5 facture(s) non réglée(s)'), findsOneWidget);
      expect(find.textContaining('que la clinique finance sur sa propre trésorerie', findRichText: true), findsOneWidget);
      expect(find.textContaining('Calcul incomplet'), findsNothing);
    });

    casM14('l\'encours se lit À UNE DATE, le flux SUR UNE PÉRIODE : la note le dit, la fenêtre porte ses bornes', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-bfr');
      expect(find.textContaining('Les trois encours sont arrêtés au 30/10/2026'), findsOneWidget);
      expect(find.textContaining('sur la période du 01/08/2026 au 30/10/2026'), findsOneWidget);
      expect(find.text('Encours arrêtés au'), findsOneWidget);
      expect(find.text('Chiffre d’affaires observé sur'), findsOneWidget);
    });

    casM14('changer la date d\'arrêt déplace la fenêtre ; un chiffre d\'affaires nul se DIT (« CA nul sur la période »), il n\'est pas zéro', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-bfr');
      await poserChamp(t, 'fin', '2027-03-01');
      expect(find.textContaining('Les trois encours sont arrêtés au 01/03/2027'), findsOneWidget);
      expect(find.textContaining('sur la période du 01/12/2026 au 01/03/2027'), findsOneWidget);
      expect(find.text('CA nul sur la période'), findsOneWidget);
      expect(find.text(money(5011584)), findsOneWidget, reason: 'l\'encours ne dépend pas de la fenêtre');
    });

    casM14('un composant NON AMORCÉ SE DIT : sans factures fournisseurs, le BFR est surestimé et la note danger le nomme', (t) async {
      final m = magasinComplet();
      for (final f in m.collection('facturesFournisseurs').actives) {
        m.collection('facturesFournisseurs').archiver(f['id']);
      }
      await ouvrirM14(t, m, 'm12-bfr');
      expect(find.textContaining('Calcul incomplet — les factures fournisseurs ne sont pas amorcés sur ce poste', findRichText: true), findsOneWidget);
      expect(find.textContaining('est donc surestimé de la dette qui manque', findRichText: true), findsOneWidget);
      expect(find.text(money(8228218)), findsWidgets, reason: 'le BFR amputé de ses dettes : 8 228 218 FCFA, et le dit');
      expect(find.text('0 facture(s) non réglée(s)'), findsOneWidget);
    });

    casM14('les créances au-delà du seuil (60 jours) : treize compagnies, la plus lourde en tête, avec leur NOM', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-bfr');
      expect(find.text('Créances au-delà de 60 jours — le levier le plus court'), findsOneWidget);
      expect(find.text('OLEA ASSURANCE'), findsOneWidget);
      expect(find.text('295 jours'), findsOneWidget);
      expect(find.text(money(331365, avecDevise: false)), findsWidgets);
      expect(find.widgetWithText(BoutonSigh, 'Ouvrir les relances'), findsOneWidget);
    });

    casM14('le seuil vit dans les objectifs de la Direction : le passer à 400 jours vide la liste, le moteur n\'a rien à changer', (t) async {
      final m = magasinComplet();
      m.collection('objectifsPilotage').mettreAJour('creance_agee', {'cible': 400});
      await ouvrirM14(t, m, 'm12-bfr');
      expect(find.text('Aucune créance au-delà du seuil retenu.'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Ouvrir les relances'), findsNothing);
    });

    casM14('les trois sources sont OUVRABLES : un agrégat qu\'on ne peut pas redescendre est un agrégat qu\'on ne vérifie jamais', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-bfr');
      for (final b in ['Ouvrir la balance âgée des créances', 'Ouvrir le point de stock', 'Ouvrir les factures fournisseurs']) {
        expect(find.widgetWithText(BoutonSigh, b), findsOneWidget, reason: b);
      }
      expect(find.text('Redescendre à la source'), findsOneWidget);
      expect(find.text('Composition du besoin'), findsOneWidget);
      expect(find.text('Dettes fournisseurs (à déduire)'), findsOneWidget);
    });

    casM14('l\'impression porte la composition et un TOTAL calculé qui est le BFR', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-bfr');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer l’état du BFR'));
      expect(find.text('Besoin en fonds de roulement'), findsWidgets);
      expect(find.text('Encours arrêtés au 30/10/2026'), findsOneWidget);
      expect(find.text('TOTAL'), findsOneWidget);
      expect(find.text(money(5011584, avecDevise: false)), findsWidgets);
      expect(find.textContaining('305 jours'), findsWidgets);
    });
  });

  group('m12-cout-activite', () {
    casM14('une MARGE SUR CONSOMMABLES, jamais un coût de revient : l\'écran dit que le personnel n\'est pas imputé', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-cout-activite');
      expect(find.textContaining('Marge sur consommables, et non coût de revient.'), findsOneWidget);
      expect(find.textContaining('Le coût de personnel n’est pas réparti par séjour'), findsOneWidget);
      expect(find.text('hors personnel et charges de structure'), findsOneWidget);
      expect(find.text('Coût de revient'), findsNothing);
    });

    casM14('les six groupes de la période par défaut (90 jours), au chiffre de la maquette', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-cout-activite');
      expect(find.text(money(1479323)), findsOneWidget);
      expect(find.text(money(752261)), findsOneWidget);
      expect(find.text(money(727062)), findsOneWidget);
      expect(find.text('49.1 %'), findsOneWidget);
      for (final g in ['Imagerie médicale', 'Laboratoire', 'Hospitalisation et soins', 'Pharmacie', 'Consultation', 'Maternité']) {
        expect(find.text(g), findsWidgets, reason: g);
      }
      // une marge NÉGATIVE se lit comme telle
      expect(find.text('-363 326'), findsOneWidget);
      expect(find.text('-320.7 %'), findsOneWidget);
    });

    casM14('changer la période recalcule : juillet donne une marge négative, une période vide donne « — » et non 0 %', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-cout-activite');
      await poserChamp(t, 'du', '2026-07-01');
      await poserChamp(t, 'au', '2026-07-31');
      expect(find.text(money(1087676)), findsOneWidget);
      expect(find.text(money(-1076996)), findsOneWidget);
      expect(find.text('-99.0 %'), findsOneWidget);
      await poserChamp(t, 'du', '2027-01-01');
      await poserChamp(t, 'au', '2027-12-31');
      expect(find.text('—'), findsWidgets);
      expect(find.text('Aucun enregistrement.'), findsOneWidget);
    });

    casM14('les sorties sans groupe facturé sont comptées À PART, jamais réparties au prorata', (t) async {
      final m = magasinComplet();
      // un consommable de fond de rayon, sorti sur la période : aucun groupe « consommable » ne se facture
      final p = m.collection('produits').actives.firstWhere((x) => x['categorie'] != 'medicament' && x['categorie'] != 'reactif' && x['categorie'] != 'conso_labo');
      m.collection('mouvements').inserer({
        'type': 'sortie', 'date': '2026-09-15', 'produitId': p['id'], 'quantite': 1000, 'statut': 'actif'
      });
      // pas de groupe « hospitalisation » facturé sur septembre : la sortie ne se rattache à rien
      for (final f in m.collection('factures').actives) {
        if ('${f['date']}'.startsWith('2026-09')) m.collection('factures').archiver(f['id']);
      }
      await ouvrirM14(t, m, 'm12-cout-activite');
      await poserChamp(t, 'du', '2026-09-01');
      await poserChamp(t, 'au', '2026-09-30');
      expect(find.textContaining('de sorties ne se rattachent à aucun groupe facturé sur la période'), findsOneWidget);
      expect(find.textContaining('comptées à part plutôt que réparties'), findsOneWidget);
    });

    casM14('la prévision saisonnière est une PROJECTION et le dit ; six mois d\'admissions, indices au centième', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-cout-activite');
      expect(find.text('Prévision saisonnière du besoin de financement'), findsOneWidget);
      expect(find.textContaining('Une projection, pas une prévision budgétaire.'), findsOneWidget);
      expect(find.text('0.46'), findsOneWidget);
      expect(find.text('1.78'), findsOneWidget);
      expect(find.text('2 313 039'), findsOneWidget);
      expect(find.text('8 921 721'), findsOneWidget);
    });

    casM14('moins de trois mois d\'admissions : AUCUNE prévision, et l\'écran explique pourquoi', (t) async {
      final m = magasinComplet();
      for (final a in m.collection('admissions').actives.skip(2)) {
        m.collection('admissions').archiver(a['id']);
      }
      await ouvrirM14(t, m, 'm12-cout-activite');
      expect(find.text('Prévision saisonnière'), findsOneWidget);
      expect(find.textContaining('Moins de trois mois d’admissions renseignés'), findsOneWidget);
      expect(find.textContaining('ce serait une coïncidence'), findsOneWidget);
      expect(find.text('Prévision saisonnière du besoin de financement'), findsNothing);
    });

    casM14('l\'impression porte les totaux CALCULÉS et nomme le personnel « non imputé »', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-cout-activite');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer l’analyse'));
      expect(find.text('Coût à l’activité — marge sur consommables'), findsWidgets);
      expect(find.textContaining('non imputé — aucune clé de répartition documentée'), findsOneWidget);
      expect(find.text('TOTAL'), findsOneWidget);
      expect(find.text('Du 01/08/2026 au 30/10/2026'), findsOneWidget);
    });
  });
}
