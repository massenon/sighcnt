import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm9_aide.dart';

/// Relevé & facture mensuelle, facture mère : les valeurs attendues sont celles que l'écran réel de la maquette a affichées (pilote
/// `vecteurs-m9.js`, horloge au 16/08/2026 12:00:28). Les gestes (émission, règlements) sont accomplis par les boutons ; la fiche écrite est comparée
/// à celle que la maquette a écrite. Un rapprochement qui ne concorde pas est PROVOQUÉ sur le magasin : le refus doit nommer la pièce.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final v = vecteurs();
  final ecrans = m9(v['ecrans']);

  group('m9-factures-assureur', () {
    final casVecteur = lm(m9(ecrans['m9-factures-assureur'])['cas']);

    Future<void> regler(WidgetTester t, String compagnie, int mois) async {
      await choisir(t, 'compagnie', compagnie);
      final libelle = moisAnnee(DateTime(2026, mois + 1));
      await choisir(t, 'mois', libelle);
    }

    cas('DAYO / juillet : KPI, relevé par souscripteur et facture mensuelle = écran réel', (t) async {
      await ouvrir(t, magasin(), 'm9-factures-assureur');
      await regler(t, 'DAYO ASSURANCE', 6);
      final c0 = casVecteur[0];
      expect(kpis(t), [for (final k in lm(m9(c0['vue'])['kpis'])) '${k['valeur']}']);
      expect(find.text('Université de Parakou — police DAYO/2024/0106'), findsOneWidget);
      for (final l in (m9(((c0['vue'] as Map)['tables'] as List).first)['lignes'] as List)) {
        final cel = (l as Map)['cellules'] as List;
        expect(find.text('${cel[0]}'), findsWidgets, reason: 'dossier ${cel[0]}');
        expect(find.text('${cel[1]}'), findsWidgets);
      }
      await toucher(t, find.text('Facture mensuelle').first);
      await t.pumpAndSettle();
      expect(find.textContaining('Relevé et facture se recoupent pour les 1 souscripteur(s) du mois'), findsOneWidget);
      expect(find.text('Facture mensuelle — DAYO ASSURANCE, juillet 2026'), findsOneWidget);
      expect(texteSp('46 378'), findsWidgets);
    });

    cas('un mois sans prestation : message, aucune pièce, et les éditions refusent en le disant', (t) async {
      await ouvrir(t, magasin(), 'm9-factures-assureur');
      await regler(t, 'ASK ASSURANCE BENIN', 7);
      expect(kpis(t), ['0', '0', '0 FCFA', '0 FCFA']);
      expect(find.text('Aucune prestation assurée pour cette compagnie sur le mois choisi.'), findsOneWidget);
      await toucher(t, find.text('Éditer le relevé'));
      expect(find.text('Aucune prestation à relever sur ce mois.'), findsOneWidget);
      await toucher(t, find.text('Éditer la facture mensuelle'));
      expect(find.text('Aucune prestation à facturer sur ce mois.'), findsOneWidget);
    });

    cas('le relevé imprimé refait ses totaux depuis ses lignes et nomme le souscripteur', (t) async {
      await ouvrir(t, magasin(), 'm9-factures-assureur');
      await regler(t, 'NSIA ASSURANCE', 6);
      await toucher(t, find.text('Éditer le relevé'));
      await t.pumpAndSettle();
      expect(find.text('Relevé des prestations de la clinique'), findsWidgets);
      final tt = textes(t);
      expect(tt, contains('NSIA ASSURANCE — juillet 2026'));
      expect(tt.where((x) => x.contains('GIZ Bénin') && x.contains('police')), isNotEmpty);
      // Le pied reprend la somme des lignes imprimées (écran réel : 18 926 facturé, 16 329 réclamé).
      expect(tt, contains('TOTAL'));
      expect(tt, contains('18 926'));
      expect(tt, contains('16 329'));
    });

    cas('la facture mensuelle porte son numéro, son RCCM, et le montant réclamé en lettres', (t) async {
      await ouvrir(t, magasin(), 'm9-factures-assureur');
      await regler(t, 'OLEA ASSURANCE', 3);
      await toucher(t, find.text('Éditer la facture mensuelle'));
      await t.pumpAndSettle();
      expect(find.text('FA 141/04/CNT/2026 — OLEA ASSURANCE'), findsOneWidget);
      expect(find.textContaining('RB/NAT/2016-B-268'), findsWidgets);
      expect(find.textContaining('soixante-dix-sept mille francs CFA'), findsOneWidget);
    });

    cas('relevé et facture qui ne se recoupent pas : écart NOMMÉ, « Ne pas transmettre avant correction »', (t) async {
      final m = magasin();
      final f = m.collection('factures').actives.firstWhere((x) =>
          x['assureur'] == 'DAYO' && '${x['date']}'.startsWith('2026-07'));
      m.collection('factures').mettreAJour(f['id'], {'partPatient': (f['partPatient'] as num) + 500});
      await ouvrir(t, m, 'm9-factures-assureur');
      await regler(t, 'DAYO ASSURANCE', 6);
      await toucher(t, find.text('Facture mensuelle').first);
      await t.pumpAndSettle();
      expect(find.textContaining('1 souscripteur(s) en écart entre le relevé et la facture : Université de Parakou'), findsOneWidget);
      expect(find.textContaining('Ne pas transmettre avant correction.'), findsOneWidget);
    });
  });

  group('m9-facture-mere', () {
    final grille = lm(m9(ecrans['m9-facture-mere'])['grille']);
    M situation(String code, String per) =>
        grille.firstWhere((g) => g['assureur'] == code && g['periode'] == per);

    Future<void> choisirPeriode(WidgetTester t, String libelle) =>
        choisir(t, 'periode', libelle);

    cas('AFR / mensuelle : KPI et rapprochement concordant = écran réel ; l’émission est offerte', (t) async {
      await ouvrir(t, magasin(), 'm9-facture-mere');
      final s = situation('AFR', 'mois');
      expect(kpis(t), [for (final k in lm(s['kpis'])) '${k['valeur']}']);
      expect(kpis(t), ['2', '4', '30 140 FCFA', 'Concordant']);
      expect(find.textContaining('Les trois niveaux concordent'), findsOneWidget);
      expect(find.text('Émettre la facture mère'), findsOneWidget);
      expect(find.text('Aperçu de la facture mère'), findsOneWidget);
    });

    cas('toutes les situations lues sur l’écran réel : trimestre, semestre et année', (t) async {
      await ouvrir(t, magasin(), 'm9-facture-mere');
      for (final (per, lib) in const [
        ('trimestre', 'Trimestrielle'),
        ('semestre', 'Semestrielle'),
        ('annee', 'Annuelle')
      ]) {
        await choisirPeriode(t, lib);
        final s = situation('AFR', per);
        expect(kpis(t), [for (final k in lm(s['kpis'])) '${k['valeur']}'], reason: per);
      }
    });

    cas('une compagnie sans pièce : « Aucune pièce », émission ABSENTE, et le message de la maquette (E502)', (t) async {
      await ouvrir(t, magasin(), 'm9-facture-mere');
      await choisir(t, 'compagnie', 'ASK ASSURANCE BENIN');
      expect(kpis(t), ['0', '0', '0 FCFA', 'Aucune pièce']);
      expect(find.text('Émettre la facture mère'), findsNothing);
      expect(find.textContaining('La facture mère ne peut pas être émise.'), findsOneWidget);
    });

    cas('un détail qui ne se recoupe pas : l’émission est refusée et la pièce en cause est NOMMÉE', (t) async {
      final m = magasin();
      final f = m.collection('factures').actives.firstWhere((x) =>
          x['assureur'] == 'AFR' && (x['partAssurance'] as num) > 0 && x['lignes'] is List);
      m.collection('factures').mettreAJour(f['id'], {'partAssurance': (f['partAssurance'] as num) + 100});
      await ouvrir(t, m, 'm9-facture-mere', le: DateTime(2026, 8, 16, 12));
      await choisirPeriode(t, 'Annuelle');
      expect(find.text('Émettre la facture mère'), findsNothing);
      expect(find.textContaining('La facture mère ne peut pas être émise.'), findsOneWidget);
      expect(find.textContaining('Pièce ${f['numero']} — ${f['patient']}'), findsOneWidget);
      expect(find.textContaining('diffère du détail ligne à ligne'), findsOneWidget);
    });

    cas('émettre : confirmation, fiche écrite = celle de la maquette, pièce imprimée, annulation visible', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm9-facture-mere');
      await toucher(t, find.text('Émettre la facture mère'));
      await t.pumpAndSettle();
      expect(find.text('Émettre la facture mère ?'), findsOneWidget);
      expect(find.textContaining('2 souscripteur(s) et 4 facture(s) fille(s)'), findsOneWidget);
      expect(find.textContaining('une correction passera par un avoir'), findsOneWidget);
      await t.tap(find.text('Émettre et transmettre'));
      await t.pumpAndSettle();
      final fiche = m.collection('facturesMere').actives.first;
      final attendu = lm(m9(m9(m9(m9(ecrans['m9-facture-mere'])['emission'])['ecart'])['inserts'])['facturesMere']).single;
      for (final k in ['numero', 'compagnieCode', 'periode', 'periodeLabel', 'debut', 'fin', 'dateEmission', 'nbSouscripteurs', 'nbFactures', 'montantReclame', 'souscripteurs', 'piecesFilles', 'controle', 'etat']) {
        expect(fiche[k], attendu[k], reason: k);
      }
      expect(fiche['numero'], 'FM-2026-0014');
      expect(find.text('FACTURE MÈRE — AFRICAINE DES ASSURANCES'), findsWidgets);
      expect(find.text('TOTAL GÉNÉRAL'), findsOneWidget);
      expect(textes(t), contains('30 140'));
      expect(find.textContaining('Les trois montants coïncident.'), findsOneWidget);
    });

    cas('l’émission annulée archive la pièce (jamais supprimée, RG-14)', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm9-facture-mere');
      await toucher(t, find.text('Émettre la facture mère'));
      await t.pumpAndSettle();
      await t.tap(find.text('Émettre et transmettre'));
      await t.pumpAndSettle();
      final avant = m.collection('facturesMere').toutes.length;
      await t.tap(find.text('Fermer').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Annuler').first, warnIfMissed: false);
      await t.pumpAndSettle();
      expect(m.collection('facturesMere').toutes.length, avant);
      expect(m.collection('facturesMere').actives.length, avant - 1);
    });

    cas('règlement : le montant saisi REMPLACE le précédent (E501) ; seule une pièce réglée EN ENTIER est soldée', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm9-facture-mere');
      await toucher(t, find.text('Émettre la facture mère'));
      await t.pumpAndSettle();
      await t.tap(find.text('Émettre et transmettre'));
      await t.pumpAndSettle();
      await t.tap(find.text('Fermer').last);
      await t.pumpAndSettle();
      final id = m.collection('facturesMere').actives.first['id'];

      Future<void> regler(String montant, String ref) async {
        await toucher(t, find.text('Factures mères émises').first);
        await t.pumpAndSettle();
        await toucher(t, find.text('Enregistrer le règlement').first);
        await t.pumpAndSettle();
        await saisir(t, 'montantRegle', montant);
        await saisir(t, 'reference', ref);
        await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
        await t.pumpAndSettle();
      }

      await regler('1000', 'VIR-001');
      var f = m.collection('facturesMere').parId(id)!;
      expect(f['reliquat'], 29140);
      expect(f['etat'], 'transmise');
      expect(find.textContaining('Règlement partiel enregistré — ${money(29140)} restent en créance.'), findsOneWidget);
      await regler('29140', 'VIR-002');
      f = m.collection('facturesMere').parId(id)!;
      expect(f['montantRegle'], 29140, reason: 'le second règlement remplace le premier');
      expect(f['reliquat'], 1000);
      expect(f['etat'], 'transmise', reason: 'comme la maquette : 1 000 + 29 140 ne solde pas');
      await regler('30140', 'VIR-003');
      f = m.collection('facturesMere').parId(id)!;
      expect(f['etat'], 'reglee');
      expect(find.text('Facture mère soldée.'), findsOneWidget);
    });

    cas('droits : sans le droit d’écrire (direction), ni émission ni règlement ; l’aperçu reste offert', (t) async {
      await ouvrir(t, magasin(), 'm9-facture-mere', role: 'direction');
      expect(find.text('Émettre la facture mère'), findsNothing);
      expect(find.text('Aperçu de la facture mère'), findsOneWidget);
      await toucher(t, find.text('Factures mères émises').first);
      await t.pumpAndSettle();
      expect(find.text('Enregistrer le règlement'), findsNothing);
      expect(find.byTooltip('Réimprimer la facture mère'), findsWidgets);
    });

    cas('l’aperçu d’une pièce non émise le dit', (t) async {
      await ouvrir(t, magasin(), 'm9-facture-mere');
      await toucher(t, find.text('Aperçu de la facture mère'));
      await t.pumpAndSettle();
      expect(find.text('Aperçu — pièce non émise'), findsWidgets);
      expect(find.textContaining('— aperçu —'), findsWidgets);
    });
  });
}
