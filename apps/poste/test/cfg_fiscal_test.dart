import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// cfg-fiscalite et cfg-comptabilite : les règles (prochaine échéance, report au jour ouvrable, indicateurs, textes des redevances) sont rejouées sur les
/// vecteurs de la maquette à neuf dates (packages/domaine/test/cfb_regles_test.dart) ; ici, l'ÉCRAN — ce qu'il montre à la date du poste, ce qu'il ne
/// permet pas (aucune saisie : c'est une RÉFÉRENCE, le suivi des paiements est à m12-echeances).
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('fiscalité au 30/10/2026 : 19 échéances, 4 mensuelles, 4 dans les 30 jours (ITS, AIB, VPS, CNSS le 10/11/2026), CCIB 300 000 FCFA', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-fiscalite');
    for (final k in ['Échéances suivies', 'Mensuelles', 'Dans les 30 jours', 'CCIB annuelle', '19']) {
      expect(find.text(k), findsWidgets, reason: k);
    }
    expect(find.textContaining('300 000'), findsWidgets);
    expect(find.textContaining('4 échéance(s) dans les trente jours : ITS le 10/11/2026 · AIB le 10/11/2026 · VPS le 10/11/2026 · CNSS le 10/11/2026.'), findsOneWidget);
    expect(find.text('11 j'), findsNWidgets(4));
    expect(find.text('reportée — jour ouvrable'), findsNWidgets(2), reason: 'PATENTE-DECL (31/01/2027, un dimanche) et CCIB-DECL (28/02/2027, un dimanche)');
    expect(find.text('01/02/2027'), findsOneWidget);
    expect(find.text('01/03/2027'), findsOneWidget);
  });

  casM14('le 1er octobre, l’échéance du 10 (un samedi) est REPORTÉE au lundi 12, jamais avancée', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-fiscalite', horloge: DateTime(2026, 10, 1, 10));
    expect(find.text('12/10/2026'), findsNWidgets(4));
    expect(find.text('reportée — jour ouvrable'), findsWidgets);
    expect(find.text('10/10/2026'), findsNothing);
  });

  casM14('le 10 novembre à 10 h, l’échéance du matin est déjà passée : elle bascule au 10 décembre', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-fiscalite', horloge: DateTime(2026, 11, 10, 10));
    expect(find.text('10/12/2026'), findsWidgets);
    expect(find.text('10/11/2026'), findsNothing);
  });

  casM14('identification fiscale UNIQUE (arbitrage du 31/08/2026), numérotation, obligations déclaratives : aucune saisie, aucune commande d’écriture', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-fiscalite');
    for (final k in ['3201642748214', 'RB/NAT/2016-B-268', 'CLINIQUE NASSIERA TOO SARL', 'FN-AAAA-NNNNN', 'CNT/[n°]/[AA]', 'Cotisations CNSS']) {
      expect(find.text(k), findsWidgets, reason: k);
    }
    expect(find.widgetWithText(BoutonSigh, 'Éditer'), findsNWidgets(5));
    expect(find.widgetWithText(BoutonSigh, 'Configuration MECeF'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
  });

  casM14('comptabilité : obligations, acomptes d’IS, tranches, redevances ORTB radio 1 000 + télé 3 000 = 4 000 au-dessus de 60 000 F', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-comptabilite');
    for (final k in ['Obligations suivies', 'Mensuelles', 'Annuelles', 'Réglées en tranches']) {
      expect(find.text(k), findsWidgets, reason: k);
    }
    expect(find.textContaining('CNSS — part patronale 16.4 %, part ouvrière 3.6 %. VPS — 4 % du salaire brut.'), findsOneWidget);
    expect(find.text('le 10 septembre'), findsOneWidget);
    expect(find.textContaining('Un agent au-dessus du seuil acquitte donc'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').replaceAll(RegExp(r'[\s\u202f\u00a0]'), '').contains('soit4000surl’année.')), findsOneWidget);
    expect(find.text('Redevance ORTB / Radio'), findsOneWidget);
    expect(find.text('Redevance ORTB / Télé'), findsOneWidget);
    expect(find.textContaining('par an, en deux tranches égales de'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Suivi nominatif'), findsOneWidget);
    expect(find.text('Six obligations exigent une déclaration avant paiement — elle est signalée à l’échéance.'), findsOneWidget);
  });
}
