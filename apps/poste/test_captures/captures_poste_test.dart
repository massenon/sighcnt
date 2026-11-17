import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/identite_migration_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/sms_poste.dart';
import 'package:sigh_poste/kit/kit.dart';

import '../test/aide_polices.dart';
import '../test/cfg_sms_test.dart' show FausseSource;
import '../test/m14_aide.dart';

/// CAPTURES DU POSTE pour le manuel d'utilisation (17/11/2026) : écrans réels du poste Flutter, vraies polices, jeu sobre de test.
/// `flutter test test_captures/captures_poste_test.dart` écrit `../../docs/manuels/source-utilisation/captures/poste-*.png`.
/// Ce n'est pas une suite de vérification : aucune assertion sur le comportement. NON VÉRIFIÉ : Windows, rendu natif.
Future<void> photographier(WidgetTester t, String nom, [List<String> cibles = const []]) async {
  final dossier = Directory('../../docs/manuels/source-utilisation/captures');
  await t.pump(const Duration(milliseconds: 500));
  final limite = t.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  // Cadres rouges : positions (pixels logiques) des libellés cités ; le script annoter-poste.py les dessine sur la capture.
  final rects = <Map<String, Object?>>[];
  for (final c in cibles) {
    var f = find.widgetWithText(BoutonSigh, c);
    if (f.evaluate().isEmpty) f = find.text(c);
    if (f.evaluate().isEmpty) continue;
    final r = t.getRect(f.first);
    rects.add({'texte': c, 'x': r.left, 'y': r.top, 'w': r.width, 'h': r.height});
  }
  File('${dossier.path}/$nom.rects.json').writeAsStringSync(jsonEncode(rects));
  await t.runAsync(() async {
    final ui.Image img = await limite.toImage(pixelRatio: 1.5);
    final octets = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    File('${dossier.path}/$nom.png').writeAsBytesSync(octets.buffer.asUint8List());
  });
}

final horlogeManuel = DateTime(2026, 11, 17, 10, 30);

/// Le jeu sobre du poste, à la date du manuel, avec la version 2 de l'identité (RCCM NAT/2021/M02-020) posée comme au démarrage d'un poste installé.
Magasin magasinManuel() {
  final m = magasinM14();
  m.horloge = () => horlogeManuel;
  migrerIdentiteVersion2(m);
  return m;
}

final cibles = <String, List<String>>{
  'poste-cfg-sms': ['Enregistrer la passerelle', 'Tester l’envoi'],
  'poste-identite-rccm': ['Enregistrer', 'Valider l’identité légale'],
  'poste-plan-annuel': ['Nouvelle action', 'Imprimer le plan'],
  'poste-factures-tiers': ['Nouvelle facture à un tiers payeur', 'Créances'],
  'poste-mecef-config': ['Régler le mode', 'Régler l’imprimante'],
  'poste-aib': ['Imputations'],
  'poste-commandes': ['Nouvelle commande'],
  'poste-enquetes': ['Nouveau modèle'],
  'poste-obligations': ['Confirmer'],
};

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('poste : passerelle SMS', (t) async {
    final m = magasinManuel();
    SmsPoste(m, estFileul: () => false, estMere: () => true, source: FausseSource(), gesteDe: (r) => r == 'admin' || r == 'da').installer();
    await ouvrirM14(t, m, 'cfg-sms', horloge: horlogeManuel);
    await photographier(t, 'poste-cfg-sms', ['Enregistrer la passerelle', 'Tester l’envoi']);
  });

  casM14('poste : journal des envois SMS', (t) async {
    final m = magasinManuel();
    SmsPoste(m, estFileul: () => false, estMere: () => true, source: FausseSource(), gesteDe: (r) => r == 'admin' || r == 'da').installer();
    await ouvrirM14(t, m, 'm13-sms-journal', horloge: horlogeManuel);
    await photographier(t, 'poste-sms-journal');
  });

  casM14('poste : configuration fiscale (modes MECeF)', (t) async {
    final m = magasinManuel();
    await ouvrirM14(t, m, 'mecef-config', horloge: horlogeManuel);
    await photographier(t, 'poste-mecef-config', ['Régler le mode', 'Régler l’imprimante']);
  });

  for (final e in ['cfg-fiscalite:identite-rccm', 'm13-plan-annuel:plan-annuel', 'cfg-bareme-aib:aib', 'm7-commandes:commandes', 'm8-factures-tiers:factures-tiers', 'adm-satisfaction:satisfaction', 'adm-enquetes:enquetes', 'cfg-comptabilite:obligations']) {
    final c = e.split(':');
    casM14('poste : ${c[0]}', (t) async {
      final m = magasinManuel();
      await ouvrirM14(t, m, c[0], horloge: horlogeManuel);
      await photographier(t, 'poste-${c[1]}', cibles['poste-${c[1]}'] ?? const []);
    });
  }
}
