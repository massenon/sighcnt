import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm9_aide.dart';

/// Tableau de bord, compagnies et assurés de M9. Les VALEURS attendues sont celles que l'écran réel de la maquette a affichées (pilote
/// `vecteurs-m9.js`, horloge au 16/08/2026) ; les comptes sont aussi recomptés INDÉPENDAMMENT sur le magasin, jamais lus de l'écran testé.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final v = vecteurs();
  final ecrans = m9(v['ecrans']);

  group('m9-dashboard', () {
    cas('les huit indicateurs sont ceux de l’écran réel de la maquette', (t) async {
      await ouvrir(t, magasin(), 'm9-dashboard');
      expect(kpis(t), [
        for (final k in lm(m9(ecrans['m9-dashboard'])['kpis'])) '${k['valeur']}'
      ]);
      expect(kpis(t), [
        '13', '70', '27', '43', '145', '1 733 134 FCFA', '1 733 134 FCFA', '84.1 %'
      ]);
    });

    cas('l’alerte RG-09 compte les cartes expirées, et disparaît quand toutes sont valides',
        (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm9-dashboard');
      expect(find.textContaining('43 carte(s) d’assurance expirée(s)'), findsOneWidget);
      expect(find.textContaining('doit être intégrale'), findsOneWidget);
      // Toutes les cartes renouvelées : l'alerte n'a plus lieu d'être.
      final m2 = magasin();
      for (final p in m2.collection('patients').actives) {
        if (p['assureur'] != null) {
          m2.collection('patients').mettreAJour(p['id'], {'carteExpiration': '2030-01-01'});
        }
      }
      await ouvrir(t, m2, 'm9-dashboard');
      expect(find.textContaining('carte(s) d’assurance expirée(s)'), findsNothing);
      expect(kpis(t).sublist(2, 4), ['70', '0']);
    });

    cas('les créances par compagnie sont classées de la plus forte à la plus faible', (t) async {
      await ouvrir(t, magasin(), 'm9-dashboard');
      final lus = textes(t);
      final i = lus.indexOf('OLEA');
      expect(i, greaterThan(-1));
      expect(lus.indexOf('SOS'), greaterThan(i));
      expect(lus.indexOf('ASCOMA'), greaterThan(lus.indexOf('SOS')));
      expect(lus, contains('331 365'));
    });
  });

  group('m9-compagnies', () {
    cas('KPI, 13 compagnies, assurés et créances par ligne (valeurs de l’écran réel)', (t) async {
      await ouvrir(t, magasin(), 'm9-compagnies');
      expect(kpis(t), ['13', '13', '70', '1 733 134 FCFA']);
      expect(find.text('Tous les compagnies'), findsWidgets);
      for (final c in cellulesVecteur(v, 'm9-compagnies')) {
        expect(find.text(c[2]), findsWidgets, reason: c[2]);
        if (c[8] != '—') expect(texteSp(c[8]), findsWidgets, reason: 'créance ${c[2]}');
      }
    });

    cas('« Nouveau » écrit la compagnie telle que la maquette l’écrit, et Annuler l’archive (RG-14)',
        (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm9-compagnies');
      await toucher(t, find.text('Nouveau'));
      expect(find.text('Nouveau compagnie'), findsOneWidget);
      await saisir(t, 'code', 'TST');
      await saisir(t, 'nom', 'COMPAGNIE DE TEST');
      await saisir(t, 'email', 'test@exemple.bj');
      await choisir(t, 'convention', 'Suspendue');
      await saisir(t, 'contact', 'M. Test');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final cree = m.collection('assureurs').actives.first;
      final attendu = lm(m9(m9(m9(ecrans['m9-compagnies'])['creation'])['inserts'])['assureurs']).single;
      for (final k in ['code', 'nom', 'email', 'convention', 'contact', 'statut']) {
        expect(cree[k], attendu[k], reason: k);
      }
      expect(kpis(t).first, '14');
      await toucher(t, find.text('Annuler').last);
      expect(m.collection('assureurs').actives.any((x) => x['code'] == 'TST'), isFalse);
      expect(m.collection('assureurs').toutes.any((x) => x['code'] == 'TST'), isTrue);
    });

    cas('sans code ni raison sociale : refus, rien n’est écrit', (t) async {
      final m = magasin();
      final avant = m.collection('assureurs').toutes.length;
      await ouvrir(t, m, 'm9-compagnies');
      await toucher(t, find.text('Nouveau'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(m.collection('assureurs').toutes.length, avant);
    });

    cas('le filtre « Cartes des assurés » ne garde que les compagnies qui ont une carte expirée', (t) async {
      final m = magasin();
      // Une compagnie sans aucun assuré n'a « aucune carte expirée » : elle sort des deux listes.
      m.collection('assureurs').inserer({'id': 'ASSVIDE', 'n': 14, 'code': 'VID', 'nom': 'COMPAGNIE VIDE', 'statut': 'actif', 'convention': 'Signée', 'tel': <Object?>[], 'email': ''});
      await ouvrir(t, m, 'm9-compagnies');
      expect(find.text('COMPAGNIE VIDE'), findsOneWidget);
      await filtrer(t, 'Cartes des assurés', 'Toutes les cartes valides');
      expect(find.text('COMPAGNIE VIDE'), findsNothing);
      expect(find.text('AFRICAINE DES ASSURANCES'), findsNothing,
          reason: 'les treize compagnies du jeu portent au moins une carte expirée (écran réel)');
    });

    cas('droits : sans le droit d’écrire, « Nouveau » est ABSENT (direction) ; sans annuler, « Archiver » aussi (caissier)',
        (t) async {
      await ouvrir(t, magasin(), 'm9-compagnies', role: 'direction');
      expect(find.text('Nouveau'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      await ouvrir(t, magasin(), 'm9-compagnies', role: 'caissier');
      expect(find.text('Nouveau'), findsOneWidget);
      expect(find.byTooltip('Archiver'), findsNothing);
    });
  });

  group('m9-assures', () {
    cas('KPI et verdict RG-09 de chaque ligne = écran réel', (t) async {
      await ouvrir(t, magasin(), 'm9-assures');
      expect(kpis(t), ['70', '27', '43', '84.1 %']);
      expect(find.textContaining('43 carte(s) expirée(s)'), findsOneWidget);
      for (final c in cellulesVecteur(v, 'm9-assures').take(15)) {
        expect(find.text(c[0]), findsWidgets, reason: c[0]);
        expect(find.text(c[8]), findsWidgets, reason: '${c[0]} ${c[8]}');
      }
      // La première ligne : une carte expirée (21/07/2026), badge « Expirée ».
      expect(find.text('Expirée'), findsWidgets);
    });

    cas('Vérifier une carte VALIDE : verdict, taux, historique vide et prises en charge accordées', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm9-assures');
      await filtrer(t, 'Validité de la carte', 'Cartes valides');
      await toucher(t, find.text('Vérifier la carte').first);
      await t.pumpAndSettle();
      expect(find.text('Carte valide — prise en charge applicable'), findsOneWidget);
      expect(find.textContaining('Taux applicable'), findsOneWidget);
      expect(find.text('Historique des couvertures'), findsOneWidget);
      expect(find.textContaining('Aucun changement enregistré'), findsOneWidget);
    });

    cas('Vérifier une carte EXPIRÉE : refus de prise en charge, facturation intégrale', (t) async {
      await ouvrir(t, magasin(), 'm9-assures');
      await toucher(t, find.text('Vérifier la carte').first);
      await t.pumpAndSettle();
      expect(find.text('Carte expirée — prise en charge refusée'), findsOneWidget);
      expect(find.textContaining('Facturation intégrale au patient (RG-09)'), findsOneWidget);
    });

    Future<void> changer(WidgetTester t, {int jour = 20, String police = 'NSIA/2026/9999'}) async {
      await toucher(t, find.byTooltip('Mettre à jour la couverture').first);
      expect(find.text('Mettre à jour la couverture'), findsWidgets);
      await dater(t, 'dateEffet', jour);
      await choisir(t, 'motif', 'Changement d’employeur');
      await choisir(t, 'assureur', 'NSIA — NSIA ASSURANCE');
      await saisir(t, 'numeroPolice', police);
      await saisir(t, 'tauxPriseEnCharge', '70');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer le changement'));
    }

    cas('Mettre à jour la couverture : l’ancienne est CLOSE (jamais écrasée), la nouvelle ouverte, le tout daté', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm9-assures');
      final p = m.collection('patients').actives.firstWhere((x) => x['code'] == 'CNT/2/26');
      await changer(t);
      final hist = m.collection('couverturesAssurance').actives
          .where((x) => x['patientId'] == p['id'])
          .toList();
      expect(hist.length, 2, reason: 'la couverture reprise du dossier + la nouvelle');
      final neuve = hist.firstWhere((x) => x['debut'] == '2026-08-20');
      final close = hist.firstWhere((x) => x['debut'] == null);
      expect(close['fin'], '2026-08-19', reason: 'close la VEILLE de la date d’effet');
      expect(close['assureur'], 'SUNU', reason: 'la couverture précédente reste lisible');
      expect(neuve['assureur'], 'NSIA');
      expect(neuve['numeroPolice'], 'NSIA/2026/9999');
      expect(neuve['motif'], 'Changement d’employeur');
      // La bascule est datée du 20 : la fiche du dossier garde ce qui est en force AUJOURD'HUI (le 16).
      expect(m.collection('patients').parId(p['id'])!['assureur'], 'SUNU');
      expect(find.text('Couverture mise à jour — l’historique conserve la précédente.'), findsOneWidget);
    });

    cas('une date d’effet passée change la fiche du dossier tout de suite', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm9-assures');
      final p = m.collection('patients').actives.firstWhere((x) => x['code'] == 'CNT/2/26');
      await changer(t, jour: 10);
      expect(m.collection('patients').parId(p['id'])!['assureur'], 'NSIA');
      expect(m.collection('patients').parId(p['id'])!['numeroPolice'], 'NSIA/2026/9999');
    });

    cas('une date d’effet non postérieure à la couverture en cours : refus NOMMÉ, rien n’est écrit', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm9-assures');
      await changer(t);
      final avant = m.collection('couverturesAssurance').toutes.length;
      await changer(t, police: 'NSIA/2026/0002');
      expect(m.collection('couverturesAssurance').toutes.length, avant);
      expect(find.textContaining('doit être postérieure au début de la couverture en cours (20/08/2026)'), findsOneWidget);
    });

    cas('le motif obligatoire est présélectionné (première entrée de la liste), comme la liste native de la maquette', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm9-assures');
      await toucher(t, find.byTooltip('Mettre à jour la couverture').first);
      await dater(t, 'dateEffet', 20);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer le changement'));
      final neuve = m.collection('couverturesAssurance').actives.firstWhere((x) => x['debut'] == '2026-08-20');
      expect(neuve['motif'], 'Changement d’employeur');
    });

    cas('droits : la mise à jour de la couverture est ABSENTE sans droit d’écrire (direction)', (t) async {
      await ouvrir(t, magasin(), 'm9-assures', role: 'direction');
      expect(find.byTooltip('Mettre à jour la couverture'), findsNothing);
      expect(find.byTooltip('Attestation de prise en charge'), findsWidgets);
      await toucher(t, find.text('Vérifier la carte').first);
      await t.pumpAndSettle();
      expect(find.text('Mettre à jour la couverture'), findsNothing);
      expect(find.text('Attestation'), findsOneWidget);
    });

    cas('l’attestation dit CARTE EXPIRÉE et la règle RG-09 pour une carte expirée', (t) async {
      await ouvrir(t, magasin(), 'm9-assures');
      await toucher(t, find.byTooltip('Attestation de prise en charge').first);
      await t.pumpAndSettle();
      expect(find.text('Attestation de prise en charge'), findsWidgets);
      expect(find.text('CARTE EXPIRÉE'), findsOneWidget);
      expect(find.textContaining('règle RG-09'), findsOneWidget);
      expect(textes(t).where((x) => x.startsWith('Validité au 16/08/2026')), isNotEmpty);
    });
  });
}
