import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// RAP — les quatre écrans de rapports, d'impression et d'états officiels, contre les vecteurs tirés des écrans RÉELS de la maquette
/// (`prototype_html/build/vecteurs-rapports.js`) : catalogue et écrans producteurs, point de la Direction (période × axe), générateur et ses modèles,
/// historique des éditions. Les règles chiffrées sont rejouées dans `packages/domaine/test/rap_regles_test.dart`.
final _v = (jsonDecode(File('../../packages/domaine/test/vecteurs/rap.json')
        .readAsStringSync()) as Map)
    .cast<String, Object?>();
Map<String, Object?> _o(Object? x) => (x as Map).cast<String, Object?>();
List<Map<String, Object?>> _l(Object? x) =>
    [for (final e in (x as List)) _o(e)];
String _s(Object? v) => '$v'.replaceAll(RegExp(r'[\s  ]'), '');

/// Le 16/08/2026 à 10 h : la date d'arrêt par défaut des états tombe sur la fin du jeu de démonstration (les factures s'arrêtent au 26/08).
final _aout = DateTime(2026, 8, 16, 10);

/// Le jeu COMPLET du poste : les vecteurs ont été tirés de l'écran réel monté sur ce jeu (le jeu sobre est un sous-ensemble).
Magasin _m() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

/// Un texte affiché, espaces insécables et fines neutralisées.
Finder _txt(Object? attendu) => find.byWidgetPredicate(
    (w) => w is Text && w.data != null && _s(w.data) == _s(attendu),
    description: 'texte « $attendu »');

Future<void> _ouvrir(WidgetTester t, Magasin m, String ecran,
        {String role = 'admin', DateTime? horloge}) =>
    ouvrirM14(t, m, ecran, role: role, horloge: horloge ?? _aout);

void main() {
  setUpAll(chargerPolices);
  setUp(
      () => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  group('rapports-bibliotheque', () {
    casM14(
        'indicateurs, mentions de l\'en-tête UNIQUE, pied normalisé et treize domaines — comme la maquette',
        (t) async {
      await _ouvrir(t, _m(), 'rapports-bibliotheque');
      final k = _l(_o(_v['bibliotheque'])['kpis']);
      for (final x in k) {
        expect(find.text('${x['libelle']}'), findsOneWidget,
            reason: '${x['libelle']}');
      }
      expect(find.text('76'), findsWidgets);
      expect(find.text('Unique'), findsOneWidget);
      expect(find.text('Brand Configuration Center'), findsOneWidget);
      for (final x in [
        'Mentions portées sur tous les états',
        'Pied de page normalisé',
        'Dénomination',
        'Adresse postale',
        'Téléphones',
        'Autorisation d’ouverture',
        'Devise'
      ]) {
        expect(find.text(x), findsOneWidget, reason: x);
      }
      // L'identité imprimée est UNIQUE (arbitrage du 31/08/2026) : un IFU, un RCCM.
      expect(find.text('3201642748214'), findsOneWidget);
      expect(find.text('RB/NAT/2016-B-268'), findsOneWidget);
      for (final x in rapMentionsPied) {
        expect(find.text(x), findsOneWidget, reason: x);
      }
      final titres = _l(_o(_v['bibliotheque'])['cartes'])
          .map((c) => c['titre'])
          .whereType<String>()
          .where((s) => s.endsWith('état(s)'));
      expect(titres.length, 13);
      for (final x in titres) {
        expect(find.text(x), findsOneWidget, reason: x);
      }
      // Chaque état au catalogue a son « Éditer » (76), aucun n'est « À venir ».
      expect(find.widgetWithText(BoutonSigh, 'Éditer'), findsNWidgets(76));
      expect(find.text('À venir'), findsNothing);
    });

    casM14('« Éditer » ouvre l\'écran producteur du catalogue', (t) async {
      await _ouvrir(t, _m(), 'rapports-bibliotheque');
      final e = rapCatalogue().firstWhere((x) => x.etat == 'Journal d’audit');
      expect(e.ecran, 'm14-audit');
      final ligne = find
          .ancestor(
              of: find.text('Journal d’audit'), matching: find.byType(Row))
          .first;
      await toucherM14(
          t,
          find.descendant(
              of: ligne, matching: find.widgetWithText(BoutonSigh, 'Éditer')));
      await t.pump(const Duration(milliseconds: 500));
      expect(
          find.text(
              'Traçabilité intégrale : création, modification, validation, archivage et connexions.'),
          findsWidgets);
    });

    casM14(
        'un écran fermé au profil : le refus se NOMME (jamais un bouton qui ne fait rien)',
        (t) async {
      // Le caissier ouvre la bibliothèque (catalogue sans écriture) mais la paie lui est fermée.
      await _ouvrir(t, _m(), 'rapports-bibliotheque', role: 'caissier');
      expect(donneesNav.matrice.peutVoir('caissier', 'm11-bulletins'), isFalse);
      final ligne = find
          .ancestor(
              of: find.text('Bulletin de paie'), matching: find.byType(Row))
          .first;
      await toucherM14(
          t,
          find.descendant(
              of: ligne, matching: find.widgetWithText(BoutonSigh, 'Éditer')));
      expect(find.text('Écran fermé à votre profil.'), findsOneWidget);
      expect(find.textContaining('la matrice des rôles ne l’ouvre pas'),
          findsOneWidget);
      // Le bouton d'identité ouvre cfg-branding, fermé lui aussi au caissier.
      await toucherM14(
          t, find.widgetWithText(BoutonSigh, 'Modifier l’identité'));
      expect(find.text('Écran fermé à votre profil.'), findsWidgets);
    });

    casM14(
        'la bibliothèque s\'ouvre à tous les profils qui impriment ; les trois écrans producteurs, non',
        (t) async {
      for (final r in [
        'medecin',
        'infirmier',
        'laborantin',
        'stock',
        'caissier',
        'reception'
      ]) {
        expect(donneesNav.matrice.peutVoir(r, 'rapports-bibliotheque'), isTrue,
            reason: r);
        for (final e in [
          'rapports-direction',
          'rapports-generateur',
          'rapports-historique'
        ]) {
          expect(donneesNav.matrice.peutVoir(r, e), isFalse, reason: '$r $e');
        }
      }
      expect(donneesNav.matrice.peutVoir('comptable', 'rapports-direction'),
          isFalse);
      expect(donneesNav.matrice.peutVoir('comptable', 'rapports-generateur'),
          isTrue);
      expect(donneesNav.matrice.peutVoir('direction', 'rapports-direction'),
          isTrue);
      await _ouvrir(t, _m(), 'rapports-direction', role: 'caissier');
      expect(find.text('Éditer l’état'), findsNothing);
    });
  });

  group('rapports-direction', () {
    final regl = _l(_o(_v['direction'])['sorties']);
    Map<String, Object?> vec(
            String periode, String axe, String fin, bool det) =>
        regl.firstWhere((r) =>
            _o(r['reglage']).values.join('|') == '$periode|$axe|$fin|$det');

    casM14(
        'réglage initial : mensuel, par client, arrêté au jour — KPI et cumul identiques à la maquette',
        (t) async {
      await _ouvrir(t, _m(), 'rapports-direction');
      final r = vec('mois', 'client', '2026-08-16', false);
      final k = _l(r['kpis']);
      for (final x in k) {
        expect(find.text('${x['libelle']}'), findsOneWidget,
            reason: '${x['libelle']}');
      }
      expect(_txt(k[0]['valeur']), findsOneWidget);
      expect(_txt(k[1]['valeur']), findsOneWidget);
      expect(_txt(k[2]['valeur']), findsOneWidget);
      expect(find.text('${k[0]['indice']}'), findsOneWidget);
      expect(find.text('${k[3]['valeur']}'), findsWidgets);
      expect(find.text('Un patient, une ligne'), findsOneWidget);
      expect(_txt((r['notes'] as List).last), findsOneWidget);
      // Les quatre commandes de la barre : trois listes/dates, une case, un bouton.
      for (final x in [
        'Périodicité',
        'Arrêté au',
        'Axe d’analyse',
        'Cumul détaillé',
        'Éditer l’état'
      ]) {
        expect(find.text(x), findsWidgets, reason: x);
      }
    });

    casM14(
        'changer la période et l\'axe recalcule tout, comme la maquette (trimestre × article, semestre × famille)',
        (t) async {
      await _ouvrir(t, _m(), 'rapports-direction');
      await choisirM14(t, 'periode', 'Trimestriel');
      await choisirM14(t, 'axe', 'Par article');
      final r = vec('trimestre', 'article', '2026-08-16', false);
      expect(find.text('Point trimestriel'), findsOneWidget);
      expect(find.text('${_l(r['kpis'])[0]['indice']}'), findsOneWidget);
      expect(find.text('Postes — article'), findsOneWidget);
      expect(find.text('Chaque produit ou prestation vendu'), findsOneWidget);
      expect(find.text('Point trimestriel — par article'), findsOneWidget);
      expect(_txt((r['notes'] as List).last), findsOneWidget);
      // La première ligne du tableau est le premier poste du vecteur (tri par montant décroissant).
      expect(find.text('${_l(r['lignes']).first['libelle']}'), findsWidgets);
      await choisirM14(t, 'periode', 'Semestriel');
      await choisirM14(t, 'axe', 'Par famille d’articles');
      final f = vec('semestre', 'famille', '2026-08-16', false);
      expect(find.text('Sept familles de l’inventaire SAGE'), findsOneWidget);
      expect(_txt((f['notes'] as List).last), findsOneWidget);
    });

    casM14(
        '« Cumul détaillé » ajoute les parts assureur et patient pour les seuls axes au niveau de la pièce',
        (t) async {
      await _ouvrir(t, _m(), 'rapports-direction');
      expect(find.text('PART ASSUREUR'), findsNothing);
      await cocher(t, 'detaille');
      expect(find.text('PART ASSUREUR'), findsOneWidget);
      expect(find.text('PART PATIENT'), findsOneWidget);
      await choisirM14(t, 'axe', 'Par article');
      expect(find.text('PART ASSUREUR'), findsNothing,
          reason: 'les lignes d’article n’ont pas de part de pièce');
    });

    casM14(
        'l\'axe « groupe » avoue que le regroupement est une proposition à valider',
        (t) async {
      await _ouvrir(t, _m(), 'rapports-direction');
      expect(find.textContaining('est une proposition'), findsNothing);
      await choisirM14(t, 'axe', 'Par groupe d’articles');
      expect(
          find.textContaining(
              'Le regroupement en quatre groupes est une proposition'),
          findsOneWidget);
      expect(find.textContaining('À valider avant usage officiel.'),
          findsOneWidget);
    });

    casM14(
        'sans vente sur la période, l\'écran le dit (le jeu s\'arrête en août : à la date du jour il est vide)',
        (t) async {
      await _ouvrir(t, _m(), 'rapports-direction',
          horloge: DateTime(2026, 10, 30, 10));
      expect(find.text('Aucune vente sur la période.'), findsOneWidget);
      expect(
          _txt(
              'Cumul global : 0 FCFA sur 0 unité(s) vendue(s), 0 poste(s) d’analyse.'),
          findsOneWidget);
    });

    casM14(
        '« Éditer l\'état » : cartouche, filtres en force, tableau et CUMUL GLOBAL calculé, deux signatures — puis « Archiver » au journal (RG-12)',
        (t) async {
      final m = _m();
      await _ouvrir(t, m, 'rapports-direction');
      final r = vec('mois', 'client', '2026-08-16', false);
      final et = _o((r['etat'] as List).single);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Éditer l’état'));
      expect(find.text('${et['titre']}'), findsWidgets);
      expect(find.text('${et['sousTitre']}'), findsOneWidget);
      expect(find.text('CUMUL GLOBAL'), findsOneWidget);
      expect(find.text('La Directrice Administrative'), findsOneWidget);
      expect(find.text('Le Comptable'), findsOneWidget);
      expect(find.text('KASSA Augustin'), findsOneWidget);
      expect(find.byKey(const Key('impression:filtres')), findsOneWidget);
      expect(find.textContaining('Périodicité : Mensuel', findRichText: true),
          findsWidgets);
      expect(
          find.textContaining('Axe d’analyse : Par client', findRichText: true),
          findsWidgets);
      expect(find.textContaining('Arrêté au : 16/08/2026', findRichText: true),
          findsWidgets);
      // « Archiver » : l'édition entre au journal, module RAP (c'est ce que lit l'historique), avec sa référence.
      final avant = m.collection('audit').toutes.length;
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver'));
      final a = m.collection('audit').toutes.first;
      expect([a['action'], a['module'], a['entite']],
          ['Impression', 'RAP', 'Document']);
      expect('${a['reference']}', startsWith('CNT-20260816-'));
      expect(m.collection('audit').toutes.length, avant < 400 ? avant + 1 : 400,
          reason: 'le journal est plafonné à 400 entrées');
      expect(a['utilisateur'], isNotEmpty, reason: 'aucune action anonyme');
      expect(find.text('Réf. ${a['reference']}'), findsOneWidget);
    });

    casM14(
        'un profil en simple lecture imprime (imprimer n\'est pas écrire) : la commande reste offerte',
        (t) async {
      await _ouvrir(t, _m(), 'rapports-direction', role: 'echographiste');
      expect(find.text('Éditer l’état'), findsOneWidget);
    });
  });

  group('rapports-generateur', () {
    final g = _o(_v['generateur']);

    casM14(
        'état initial : titre, sous-titre du mois, deux sections cochées, quatre modèles — comme la maquette',
        (t) async {
      await _ouvrir(t, _m(), 'rapports-generateur');
      for (final x in [
        'Paramètres du rapport',
        'Sections à inclure',
        'Génération',
        'Modèles enregistrés',
        'Prévisualiser et imprimer'
      ]) {
        expect(find.text(x), findsOneWidget, reason: x);
      }
      for (final s in rapSections) {
        expect(find.text(s.libelle), findsOneWidget, reason: s.id);
      }
      expect(tester(t), [true, true, false, false, false, false, false]);
      for (final m in rapModeles) {
        expect(find.text(m.nom), findsOneWidget, reason: m.nom);
        expect(find.text(m.destinataire), findsWidgets, reason: m.nom);
      }
      expect(
          find.text(
              'Le rapport reprend automatiquement l’entête et le pied de page officiels de la clinique.'),
          findsOneWidget);
      expect(find.text('Période : août 2026'), findsOneWidget);
      expect(find.text('Rapport d’activité'), findsWidgets);
    });

    casM14(
        '« Prévisualiser et imprimer » : l\'état porte les indicateurs CALCULÉS de chaque section cochée',
        (t) async {
      await _ouvrir(t, _m(), 'rapports-generateur');
      await toucherM14(
          t, find.widgetWithText(BoutonSigh, 'Prévisualiser et imprimer'));
      final et = _o((_o(g['defaut'])['etat'] as List).single);
      for (final tab in _l(et['tableaux'])) {
        for (final l in (tab['lignes'] as List)) {
          expect(find.text('${(l as List)[0]}'), findsWidgets,
              reason: '${l[0]}');
        }
      }
      // Les intertitres s'impriment en capitales ; les signatures sont celles de la maquette.
      expect(find.text('ACTIVITÉ'), findsOneWidget);
      expect(find.text('FINANCIER'), findsOneWidget);
      expect(find.text('Le Rédacteur'), findsOneWidget);
      expect(find.text('La Directrice Administrative'), findsOneWidget);
      expect(find.text('Le Directeur Médical'), findsOneWidget);
      expect(
          find.textContaining('Destinataire : Usage interne',
              findRichText: true),
          findsOneWidget,
          reason: 'destinataire absent = usage interne');
    });

    casM14(
        'un modèle enregistré charge titre et sections, annonce le chargement — son destinataire hors liste vide la liste (E1040)',
        (t) async {
      await _ouvrir(t, _m(), 'rapports-generateur');
      await toucherM14(t, find.byKey(const Key('rap:modele:1')));
      expect(
          find.text('Modèle « Situation des stocks » chargé.'), findsOneWidget);
      expect(tester(t), [false, false, true, false, false, false, false]);
      await toucherM14(t, find.byKey(const Key('rap:modele:2')));
      expect(tester(t), [false, true, false, false, false, true, false]);
      await toucherM14(
          t, find.widgetWithText(BoutonSigh, 'Prévisualiser et imprimer'));
      final att =
          _o(_o(_o(g['modeles'])['Rapport financier trimestriel'])['gen']);
      final et = _o((att['etat'] as List).single);
      expect(find.text('${et['titre']}'), findsWidgets);
      expect(find.text('FINANCIER'), findsOneWidget);
      expect(find.text('COMPTABILITÉ'), findsOneWidget);
      expect(find.text('ACTIVITÉ'), findsNothing);
    });

    casM14('refus nommés : aucune section cochée ; titre vide', (t) async {
      await _ouvrir(t, _m(), 'rapports-generateur');
      await toucherM14(t, find.byKey(const Key('rap:section:activite')));
      await toucherM14(t, find.byKey(const Key('rap:section:financier')));
      expect(tester(t), everyElement(isFalse));
      await toucherM14(
          t, find.widgetWithText(BoutonSigh, 'Prévisualiser et imprimer'));
      expect(find.text('Sélectionner au moins une section.'), findsOneWidget);
      expect(find.byKey(const Key('impression:filtres')), findsNothing,
          reason: 'rien ne s\'imprime');
      await t.pump(const Duration(seconds: 6));
      // titre vide
      await toucherM14(t, find.byKey(const Key('rap:section:rh')));
      await saisir(t, 'titre', '');
      await toucherM14(
          t, find.widgetWithText(BoutonSigh, 'Prévisualiser et imprimer'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
    });

    casM14(
        'une écriture déséquilibrée fait NOMMER l\'écart dans la section comptable',
        (t) async {
      final m = _m();
      final inj = _o(_o(_v['generateurEcart'])['injection']);
      m.collection('ecritures').inserer({...inj});
      await _ouvrir(t, m, 'rapports-generateur');
      await toucherM14(t, find.byKey(const Key('rap:section:activite')));
      await toucherM14(t, find.byKey(const Key('rap:section:financier')));
      await toucherM14(t, find.byKey(const Key('rap:section:comptable')));
      await toucherM14(
          t, find.widgetWithText(BoutonSigh, 'Prévisualiser et imprimer'));
      expect(find.textContaining('Écart de '), findsOneWidget);
    });
  });

  group('rapports-historique', () {
    casM14(
        '60 éditions de démonstration (graine 3221) : indicateurs, colonnes, graphiques — comme la maquette',
        (t) async {
      final m = _m();
      await _ouvrir(t, m, 'rapports-historique',
          horloge: DateTime(2026, 10, 30, 10));
      final att = _o(_v['historiqueJeu']);
      for (final x in _l(att['kpis'])) {
        expect(find.text('${x['libelle']}'), findsOneWidget);
        expect(_txt(x['valeur']), findsWidgets, reason: '${x['libelle']}');
      }
      for (final x in [
        'RÉF. DOCUMENT',
        'HORODATAGE',
        'ÉTAT ÉDITÉ',
        'MODULE',
        'FORMAT',
        'GÉNÉRÉ PAR',
        'POSTE'
      ]) {
        expect(find.text(x), findsOneWidget, reason: x);
      }
      expect(find.text('Éditions par module'), findsOneWidget);
      expect(find.text('États les plus édités'), findsOneWidget);
      expect(
          find.textContaining(
              'conformément à l’exigence de traçabilité (RG-12)'),
          findsOneWidget);
      // La première ligne est la plus récente du vecteur.
      expect(
          find.text('${_l(att['lignes']).first['reference']}'), findsOneWidget);
    });

    casM14(
        'les éditions archivées entrent en tête de liste de lecture et dans les indicateurs ; aucune commande d\'écriture',
        (t) async {
      final m = _m();
      m.utilisateur = 'TAKI Alimatou';
      m.journaliser('Impression', 'RAP', 'Document', 'CNT-20261030-0042', null,
          {'titre': 'Point mensuel'});
      await _ouvrir(t, m, 'rapports-historique',
          horloge: DateTime(2026, 10, 30, 10));
      final rows = rapEditions(
          m.collection('audit').toutes,
          [
            for (final p in m.collection('personnel').actives)
              '${p['nomComplet']}'
          ],
          DateTime(2026, 10, 30, 10));
      expect(rows.length, 60);
      expect(rows.where((r) => r['reference'] == 'CNT-20261030-0042'),
          hasLength(1));
      final st = rapStatsHistorique(rows, DateTime(2026, 10, 30, 10));
      expect(find.text('${st.ceMois}'), findsWidgets);
      // Écran en lecture seule : ni création, ni modification, ni archivage.
      for (final x in [
        'Nouvelle',
        'Ajouter',
        'Modifier',
        'Archiver',
        'Supprimer'
      ]) {
        expect(find.textContaining(x), findsNothing, reason: x);
      }
    });

    casM14(
        'de bout en bout : imprimer un état, l\'archiver, le retrouver à l\'historique (RG-12)',
        (t) async {
      final m = _m();
      await _ouvrir(t, m, 'rapports-generateur');
      await toucherM14(
          t, find.widgetWithText(BoutonSigh, 'Prévisualiser et imprimer'));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver'));
      final a = m.collection('audit').toutes.first;
      expect(a['action'], 'Impression');
      final ref = '${a['reference']}';
      await t.pump(const Duration(seconds: 10));
      await _ouvrir(t, m, 'rapports-historique');
      final rows = rapEditions(
          m.collection('audit').toutes,
          [
            for (final p in m.collection('personnel').actives)
              '${p['nomComplet']}'
          ],
          _aout);
      expect(
          rows.any((r) =>
              r['reference'] == ref &&
              r['module'] == 'RAP' &&
              r['format'] == 'PDF'),
          isTrue);
      expect(find.text('Éditions enregistrées'), findsOneWidget);
    });

    casM14(
        'fermé aux profils qui n\'écrivent pas : le médecin n\'y accède pas ; le comptable, oui',
        (t) async {
      expect(donneesNav.matrice.peutVoir('medecin', 'rapports-historique'),
          isFalse);
      expect(donneesNav.matrice.peutVoir('comptable', 'rapports-historique'),
          isTrue);
      await _ouvrir(t, _m(), 'rapports-historique', role: 'medecin');
      expect(find.text('Journal des éditions'), findsNothing);
    });
  });
}

/// L'état des sept cases « Sections à inclure », dans l'ordre.
List<bool> tester(WidgetTester t) => [
      for (final s in rapSections)
        (find
                .descendant(
                    of: find.byKey(Key('rap:section:${s.id}')),
                    matching: find.byType(Checkbox))
                .evaluate()
                .single
                .widget as Checkbox)
            .value!
    ];
