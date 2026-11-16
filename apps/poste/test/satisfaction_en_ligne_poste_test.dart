import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'aide_qualite.dart';

/// LOT SAT (ADR-0009), les écrans du poste : la carte « Analyse » de `adm-satisfaction` (filtres, « Non calculable » jamais zéro) rejouée sur les vecteurs tirés de l'écran RÉEL de la maquette
/// (`satisfaction_en_ligne.json`), et le partage « En ligne » de `adm-enquetes` (point de collecte, adresse publique, affiche A4 avec bloc QR). Non éprouvé ici : l'impression sur matériel.
final v = m_(jsonDecode(File('../../packages/domaine/test/vecteurs/satisfaction_en_ligne.json').readAsStringSync()));

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  Magasin magasinAnalyse() {
    final a = m_(v['analyse']);
    final e = m_(m_(a['entrees'])['enquete']);
    final reps = [
      for (final (i, r) in liste(m_(a['entrees'])['reponses']).indexed) {'id': 'R$i', 'statut': 'actif', ...r}
    ];
    return magasinDe({'enquetes': [e], 'reponsesEnquetes': reps, 'jetonsEnquete': const []});
  }

  void verifierKpis(WidgetTester t, Map<String, Object?> c) {
    for (final k in liste(c['kpis'])) {
      expect(sp(kpi(t, '${k['label']}')), sp(k['valeur']), reason: '${c['nom']} : ${k['label']}');
    }
  }

  Future<void> filtrer(WidgetTester t, String cle, String libelle) async {
    await toucher(t, find.byKey(Key('qual:an:$cle')));
    await toucher(t, find.text(libelle).last);
    await t.pump(const Duration(milliseconds: 300));
  }

  group('adm-satisfaction : la carte Analyse', () {
    final cas0 = liste(m_(v['analyse'])['cas']);
    cas('sans filtre : les indicateurs de l’écran réel de la maquette ; le taux de réponse est « Non calculable »', (t) async {
      await ouvrir(t, magasinAnalyse(), 'adm-satisfaction');
      expect(find.text('Analyse'), findsWidgets);
      verifierKpis(t, cas0.firstWhere((c) => c['nom'] == 'sans filtre'));
      expect(kpi(t, 'Taux de réponse'), 'Non calculable');
    });
    cas('un point de collecte choisi : les indicateurs de la maquette pour ce point ; un point sans réponse : « Non calculable », jamais zéro', (t) async {
      await ouvrir(t, magasinAnalyse(), 'adm-satisfaction');
      await filtrer(t, 'point', 'Accueil');
      verifierKpis(t, cas0.firstWhere((c) => c['nom'] == 'un point'));
      await filtrer(t, 'point', 'Pharmacie');
      verifierKpis(t, cas0.firstWhere((c) => c['nom'] == 'aucune réponse ne correspond'));
    });
    cas('une version et un canal choisis : les indicateurs de la maquette', (t) async {
      await ouvrir(t, magasinAnalyse(), 'adm-satisfaction');
      await filtrer(t, 'version', 'V2 (depuis le 10/08/2026)');
      verifierKpis(t, cas0.firstWhere((c) => c['nom'] == 'une version'));
      await filtrer(t, 'version', 'Toutes les versions');
      await filtrer(t, 'canal', 'Lien public');
      verifierKpis(t, cas0.firstWhere((c) => c['nom'] == 'un canal'));
    });
    cas('en lecture seule : aucune commande d’écriture', (t) async {
      await ouvrir(t, magasinAnalyse(), 'adm-satisfaction');
      expect([for (final e in find.byType(BoutonSigh).evaluate()) (e.widget as BoutonSigh).libelle].where(ecriture0), isEmpty);
    });
  });

  group('adm-enquetes : le partage « En ligne »', () {
    cas('un lien « En ligne » : point de collecte, version, adresse publique sans identifiant d’enquête, QR ; l’affiche A4 porte le bloc QR', (t) async {
      final m = magasinDe({'enquetes': jeuJson('enquetes'), 'reponsesEnquetes': jeuJson('reponsesEnquetes'), 'jetonsEnquete': const []});
      await ouvrir(t, m, 'adm-enquetes');
      await toucher(t, find.byTooltip('Partager à un tiers'));
      for (final l in liste(m_(m_(v['partageEnLigne'])['form'])['champs']).map((c) => '${c['nom']}')) {
        expect(find.byKey(Key('kit:champ:$l')), findsOneWidget, reason: 'champ $l, comme à l’écran de la maquette');
      }
      await choisir(t, 'usage', 'En ligne : adresse publique ou code QR (le relais ne lit pas la réponse)');
      await choisir(t, 'point', 'Laboratoire');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Ouvrir le lien'));
      final j = m.collection('jetonsEnquete').actives.single;
      expect(j['jeton'], matches(RegExp(r'^[a-km-z2-9]{24}$')));
      expect(j['enLigne'], true);
      expect(j['point'], 'laboratoire');
      expect(j['usage'], 'en_ligne');
      expect(j['version'], 'V1');
      final adresse = t.widget<TextField>(find.byKey(const Key('qual:adresse'))).controller!.text;
      expect(adresse, 'https://sighcnt.nassieratoo.com/s/${j['jeton']}');
      expect(adresse, isNot(contains('${j['enqueteId']}')), reason: 'l’adresse ne porte JAMAIS l’identifiant de l’enquête');
      expect(find.byKey(const Key('qual:qr')), findsOneWidget);
      expect(find.textContaining('La collecte en ligne est désactivée'), findsOneWidget, reason: 'désactivée par défaut : le tiroir le dit');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Imprimer l’affiche (A4)'));
      expect(find.text('Votre avis nous intéresse'), findsWidgets);
      expect(find.textContaining('Point de collecte : Laboratoire'), findsWidgets);
      expect(find.byKey(const Key('impression:qr')), findsOneWidget, reason: 'le bloc QR de l’affiche');
      expect(find.textContaining('ni votre nom ni votre numéro de dossier'), findsWidgets);
    });
    cas('un lien local n’a ni affiche ni adresse publique', (t) async {
      final m = magasinDe({'enquetes': jeuJson('enquetes'), 'reponsesEnquetes': jeuJson('reponsesEnquetes'), 'jetonsEnquete': const []});
      await ouvrir(t, m, 'adm-enquetes');
      await toucher(t, find.byTooltip('Partager à un tiers'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Ouvrir le lien'));
      final j = m.collection('jetonsEnquete').actives.single;
      expect(j.containsKey('enLigne'), isFalse);
      expect(find.widgetWithText(BoutonSigh, 'Imprimer l’affiche (A4)'), findsNothing, reason: 'commande absente : ce lien n’est pas en ligne');
    });
  });
}

bool ecriture0(String l) => RegExp(r'Nouveau|Enregistrer|Valider|Archiver|Modifier|Supprimer|Recueillir|Créer|Rejeter|Révoquer').hasMatch(l);
