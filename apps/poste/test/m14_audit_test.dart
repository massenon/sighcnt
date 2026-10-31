import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// m14-audit : le journal RG-12, tel qu'il est tenu (plafonné à 400), lu sous ses deux formes de valeurs (texte du jeu, objets du poste).
void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  casM14('indicateurs recalculés depuis le journal, note des tentatives infructueuses, tableau et graphiques', (t) async {
    final m = magasinM14();
    final rows = m.collection('audit').toutes;
    final s = secStatsAudit(rows);
    await ouvrirM14(t, m, 'm14-audit');
    expect(rows.length, lessThanOrEqualTo(400), reason: 'plafonné à 400 entrées');
    for (final k in ['Actions journalisées', 'Utilisateurs tracés', 'Modules concernés', 'Tentatives infructueuses']) {
      expect(find.text(k), findsOneWidget, reason: k);
    }
    expect(find.text('${s.actions}'), findsWidgets);
    for (final e in ['HORODATAGE', 'UTILISATEUR', 'ACTION', 'MODULE', 'ENTITÉ CONCERNÉE', 'RÉFÉRENCE', 'POSTE', 'RÉSULTAT']) {
      expect(find.text(e), findsOneWidget, reason: e);
    }
    expect(find.text('Actions par module'), findsOneWidget);
    expect(find.text('Répartition par type d’action'), findsOneWidget);
    expect(find.textContaining('cinq ans minimum'), findsOneWidget);
    expect(find.text('Imprimer le journal'), findsOneWidget);
    // Le bandeau d'alerte paraît si et seulement si le journal compte des échecs.
    expect(find.textContaining('tentative(s) d’accès infructueuse(s) enregistrée(s).'), s.echecs > 0 ? findsOneWidget : findsNothing);
  });

  casM14('une entrée en échec fait paraître le bandeau, le badge rouge et l\'indicateur', (t) async {
    final m = magasinM14();
    final echecsAvant = secStatsAudit(m.collection('audit').toutes).echecs;
    m.collection('audit').inserer({
      'id': 'LOGX1',
      'dateHeure': '2026-10-30T09:59:30.000Z',
      'utilisateur': 'OROU YO Edmond',
      'action': 'Connexion',
      'module': 'M14',
      'entite': 'session',
      'reference': 'v.test',
      'poste': 'POSTE-ACCUEIL',
      'succes': false,
    });
    await ouvrirM14(t, m, 'm14-audit');
    expect(find.textContaining('${echecsAvant + 1} tentative(s) d’accès infructueuse(s) enregistrée(s).'), findsOneWidget);
    expect(find.text('Échec'), findsWidgets);
    expect(find.text('à l’instant'), findsOneWidget);
    // L'entrée la plus récente est en tête (tri par horodatage décroissant).
    await toucherM14(t, find.text('Connexion').first);
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Connexion — session'), findsOneWidget);
    expect(find.text('Aucune valeur détaillée conservée pour cette action.'), findsOneWidget);
  });

  casM14('le tiroir lit les deux formes de valeurs : texte du jeu, objets du poste — indentées, jamais réécrites', (t) async {
    final m = magasinM14();
    m.collection('audit').inserer({
      'id': 'LOGX2',
      'dateHeure': '2026-10-30T09:58:00.000Z',
      'utilisateur': 'TAKI Alimatou',
      'action': 'Modification',
      'module': 'M12',
      'entite': 'écriture',
      'reference': 'OD-2026-00004',
      'poste': 'POSTE-DAF',
      'succes': true,
      'avant': {'statut': 'brouillon'},
      'apres': {'statut': 'validee'},
    });
    await ouvrirM14(t, m, 'm14-audit');
    await toucherM14(t, find.text('OD-2026-00004'));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Ancienne valeur'), findsOneWidget);
    expect(find.text('Nouvelle valeur'), findsOneWidget);
    expect(find.text('{\n  "statut": "brouillon"\n}'), findsOneWidget);
    expect(find.text('{\n  "statut": "validee"\n}'), findsOneWidget);
    // Un texte qui n'est pas du JSON (valeur du jeu tronquée à cent caractères) est rendu tel quel.
    expect(secJsonLisible('{"id":"CST1","statut":"actif","reference":"CST-00091","patientCode":"CNT/95/25","patien'),
        '{"id":"CST1","statut":"actif","reference":"CST-00091","patientCode":"CNT/95/25","patien');
  });

  casM14('RG-12 : toute écriture du poste entre au journal (en tête) ; il est plafonné à 400 entrées, les plus anciennes sortent du tampon', (t) async {
    final m = magasinM14();
    m.utilisateur = 'Administrateur système';
    final avant = m.collection('audit').toutes.length;
    expect(avant, lessThan(400));
    m.collection('utilisateurs').inserer({'identifiant': 'v.audit', 'role': 'reception'}, prefixe: 'UTI');
    final tete = m.collection('audit').toutes.first;
    expect(tete['action'], 'Création');
    expect(tete['module'], 'M14');
    expect(tete['utilisateur'], 'Administrateur système', reason: 'aucune action anonyme');
    expect(m.collection('audit').toutes.length, avant + 1);
    for (var i = 0; i < 250; i++) {
      m.journaliser('Impression', 'M8', 'facture', 'F$i', null, null);
    }
    expect(m.collection('audit').toutes.length, 400);
    await ouvrirM14(t, m, 'm14-audit');
    expect(find.text('400'), findsWidgets);
  });

  casM14('« Imprimer le journal » : l\'état porte le cartouche, les cent premières lignes et les deux signatures', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-audit');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer le journal'));
    expect(find.text('Traçabilité des actions — situation au 30/10/2026'), findsOneWidget);
    expect(find.text('Actions journalisées'), findsWidgets);
    expect(find.text('L’Administrateur système'), findsOneWidget);
    expect(find.text('La Direction'), findsOneWidget);
    expect(find.text('BASSONGUI Chabi Séko'), findsWidgets);
  });

  casM14('le journal est en lecture seule par nature : aucune commande d\'écriture, même pour l\'administrateur', (t) async {
    await ouvrirM14(t, magasinM14(), 'm14-audit');
    for (final c in ['Nouveau', 'Modifier', 'Archiver', 'Supprimer']) {
      expect(find.widgetWithText(BoutonSigh, c), findsNothing, reason: c);
      expect(find.byTooltip(c), findsNothing, reason: c);
    }
  });
}
