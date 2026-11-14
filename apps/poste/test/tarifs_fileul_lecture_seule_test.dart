import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/core/service_installation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// CONSTAT DE L'ESSAI LE PLUS PROCHE DE L'APPLICATION RÉELLE (lot TFIN, étape 5). Le parcours « proposer, appliquer, décider, voir la grille » est tenu par TROIS tests liés, jamais par un seul
/// scénario d'écran de bout en bout :
///  1. le dépôt d'une demande de prix par un fileul, son application par la VRAIE mère Dart (service branché dans `main.dart`), le verdict et le Oui qui reviennent : `service_propositions_tarif_test.dart` ;
///  2. le geste d'écran « Proposer, puis Oui » sur l'écran de la mère : `tarifs_ecran_test.dart` ;
///  3. la grille imprimée portant ce prix : `impression_grille_test.dart`.
/// Ce test-ci dit ce que l'ESSAI A FAIT APPARAÎTRE : sur un poste FILEUL RATTACHÉ, la coque met « Tarifs et prix » en LECTURE SEULE (`coque.dart`, `_surLaMere` : tout écran du module CFG), donc ni
/// « Proposer un changement » ni Oui ou Non n'y sont offerts. Le dépôt d'une demande par un fileul (décision T11 : la Direction est fileul) n'est atteignable que par l'API, pas par un geste
/// d'écran : écart dit, à trancher par la Direction (DECISIONS-A-VALIDER, section AE).
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('sur un fileul rattaché, « Tarifs et prix » se lit et se consulte, mais « Proposer un changement » est ABSENT (la coque le met en lecture seule)', (t) async {
    final m = magasinM14();
    await t.runAsync(() => ServiceInstallation.de(m).attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'u', rejoint: true)));
    expect(ServiceInstallation.de(m).rattache, isTrue);
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'direction');
    await t.enterText(find.byKey(const Key('kit:tableau-recherche')).first, 'MG01');
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('Consulter'), findsWidgets, reason: 'la lecture reste offerte');
    expect(find.byTooltip('Proposer un changement'), findsNothing, reason: 'la commande est absente, jamais grisée : la coque met l\'écran en lecture seule sur un fileul rattaché');
    expect(find.textContaining('Réglé sur la mère'), findsWidgets, reason: 'l\'écran le dit en tête de sa règle');
  });

  casM14('hors fileul rattaché (la mère, un poste autonome), la même Direction a « Proposer un changement » : la différence est bien celle du rattachement', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'direction');
    await t.enterText(find.byKey(const Key('kit:tableau-recherche')).first, 'MG01');
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('Proposer un changement'), findsWidgets);
  });
}
