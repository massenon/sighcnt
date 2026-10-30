import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/sync/etat_sync.dart';

void main() {
  testWidgets('la pastille dit toujours où en est la synchronisation, jamais un voyant muet', (t) async {
    final maintenant = DateTime(2026, 10, 30, 12, 0, 0);
    final source = ValueNotifier(const EtatSync(niveau: NiveauSync.synchronise));
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PastilleSync(source: source, maintenant: () => maintenant))));
    expect(find.text('Synchronisé'), findsOneWidget);

    source.value = EtatSync(niveau: NiveauSync.horsLigne, enAttente: 3, depuis: maintenant.subtract(const Duration(minutes: 12)));
    await t.pump();
    expect(find.text('Hors ligne · depuis 12 min · 3 en attente'), findsOneWidget);

    source.value = EtatSync(niveau: NiveauSync.enRetard, enAttente: 1, aTraiter: 2, depuis: maintenant.subtract(const Duration(seconds: 40)));
    await t.pump();
    expect(find.text('En retard · depuis 40 s · 1 en attente · 2 à traiter'), findsOneWidget);

    source.value = const EtatSync(niveau: NiveauSync.suspendu);
    await t.pump();
    expect(find.text('Poste suspendu'), findsOneWidget);
  });

  testWidgets('la pastille porte un libellé d\'accessibilité complet', (t) async {
    final h = t.ensureSemantics();
    final source = ValueNotifier(const EtatSync(niveau: NiveauSync.horsLigne, enAttente: 2));
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PastilleSync(source: source))));
    expect(find.bySemanticsLabel(RegExp('État de la synchronisation : Hors ligne')), findsOneWidget);
    h.dispose();
  });
}
