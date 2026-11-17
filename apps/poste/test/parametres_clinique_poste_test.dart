import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/parametres_clinique_poste.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// LOT PARAM-CLINIQUE (décisions 10 et 14 de la Direction du 15/11/2026) au poste : le préavis de péremption (RG-05) et les deux bornes de la balance âgée
/// sont des PARAMÈTRES DE CLINIQUE (registre `parametres`, famille `clinique`, défauts semés 90, 30 et 90, versionnés par date, jamais vers un téléphone). Les
/// écrans du stock, les alertes et la balance âgée les LISENT à la date ; le réglage est borné, motivé, journalisé, réservé au geste de la fiche RBAC.
final donnees = DonneesNavigation.depuisDossier();
final auj = DateTime(2026, 11, 16);
String iso(DateTime d) => parametreDateIso(d);

Magasin magasin({List<Fiche> lots = const []}) {
  final m = Magasin({
    'produits': [
      {'id': 'P1', 'code': 'AMOX', 'designation': 'Amoxicilline 500', 'stock': 10, 'stockGros': 10, 'stockDetail': 0, 'seuilAlerte': 2, 'cump': 100, 'prixAchat': 100, 'statut': 'actif', 'categorie': 'medicament'}
    ],
    'lots': lots,
    'audit': const [],
  });
  serviceParametres(m, auteur: () => 'semis', horloge: () => auj).semerDefauts();
  return m;
}

Fiche lot(String id, int dans) => {'id': id, 'produitId': 'P1', 'produit': 'Amoxicilline 500', 'numeroLot': id, 'datePeremption': iso(auj.add(Duration(days: dans))), 'quantiteRestante': 3, 'statut': 'actif'};

RefusParametreClinique? regler(Magasin m, String cle, Object? v, {String? date, String? motif = 'réglage de test', bool geste = true}) =>
    reglerParametreClinique(m, cle: cle, valeur: v, dateEffet: date ?? iso(auj), gesteAccorde: geste, libelleRole: 'Gestionnaire de stock', motif: motif, horloge: () => auj);

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(key: UniqueKey(), donnees: donnees, config: ConfigPoste(mode: ModePoste.mere, role: role), ecranInitial: ecran, magasin: m, horloge: () => auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Map<String, String> kpis(WidgetTester t) {
  final l = [for (final w in t.widgetList<Text>(find.byKey(const Key('kit:kpi-libelle')))) w.data!];
  final v = [for (final w in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur')))) w.data!];
  return {for (var i = 0; i < l.length; i++) l[i]: v[i]};
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('lecture à la date et réglage', () {
    test('défauts SEMÉS en base (90, 30, 90) ; une version datée s\'applique à sa date, l\'ancienne reste lisible ; le statut d\'un lot suit le préavis lu', () {
      final m = magasin(lots: [lot('L100', 100)]);
      expect(m.collection(parCollectionParametres).toutes.where((v) => v['famille'] == pcFamille).length, 7, reason: 'sept versions 0 semées (lot PTA : la tolérance de l’alerte du plan annuel ; lot MAJ : trois réglages de mise à jour)');
      expect(preavisPeremptionPoste(m, auj), 90);
      expect(tranchesCreancesPoste(m, auj).courte, 30);
      expect(tranchesCreancesPoste(m, auj).longue, 90);
      expect(statutLotPoste(m, m.collection('lots').parId('L100')!, auj), 'actif');
      expect(regler(m, pcCleDelaiPeremption, 120), isNull);
      expect(preavisPeremptionPoste(m, auj), 120);
      expect(statutLotPoste(m, m.collection('lots').parId('L100')!, auj), 'alerte', reason: 'le lot à 100 jours entre dans le préavis de 120 jours');
      expect(preavisPeremptionPoste(m, auj.subtract(const Duration(days: 1))), 90, reason: 'la veille de la date d\'effet, la version semée');
      expect(regler(m, pcCleDelaiPeremption, 60, date: iso(auj.add(const Duration(days: 10)))), isNull);
      expect(preavisPeremptionPoste(m, auj), 120, reason: 'une version à venir ne change pas la valeur du jour');
      expect(preavisPeremptionPoste(m, auj.add(const Duration(days: 10))), 60);
      expect(m.collection('audit').toutes.where((a) => a['action'] == 'Paramètre de clinique : nouvelle version').length, 2, reason: 'RG-12 : chaque version journalisée');
      final journal = m.collection('audit').toutes.firstWhere((a) => a['action'] == 'Paramètre de clinique : nouvelle version');
      expect('${journal['apres']}', contains('réglage de test'));
    });

    test('refus NOMMÉS : sans le geste, hors bornes, non entier, tranches incohérentes, sans motif, date antérieure à la dernière version ; rien n\'est écrit', () {
      final m = magasin();
      final n0 = m.collection(parCollectionParametres).toutes.length;
      expect(regler(m, pcCleDelaiPeremption, 120, geste: false)?.code, 'PARAMETRE_CLINIQUE_RESERVE');
      expect(regler(m, pcCleDelaiPeremption, 0)?.code, 'PARAMETRE_HORS_BORNES');
      expect(regler(m, pcCleDelaiPeremption, 731)?.code, 'PARAMETRE_HORS_BORNES');
      expect(regler(m, pcCleDelaiPeremption, 12.5)?.code, 'PARAMETRE_HORS_BORNES');
      expect(regler(m, pcCleDelaiPeremption, '')?.code, 'PARAMETRE_HORS_BORNES');
      expect(regler(m, pcCleTrancheCourte, 90)?.code, 'TRANCHES_INCOHERENTES', reason: 'la première tranche doit être plus courte que la deuxième (90)');
      expect(regler(m, pcCleTrancheLongue, 30)?.code, 'TRANCHES_INCOHERENTES');
      expect(regler(m, pcCleDelaiPeremption, 100, motif: '')?.code, 'PARAMETRE_MOTIF_OBLIGATOIRE');
      expect(m.collection(parCollectionParametres).toutes.length, n0, reason: 'aucune version écrite par un refus');
      expect(regler(m, pcCleDelaiPeremption, 100, date: '2026-12-01'), isNull);
      expect(regler(m, pcCleDelaiPeremption, 110, date: '2026-11-20')?.code, 'DATE_EFFET_ANTERIEURE');
      final r = regler(m, pcCleDelaiPeremption, 0)!;
      expect(r.motif, contains('1 à 730'), reason: 'la borne est DITE');
      expect(r.geste, isNotEmpty);
    });

    test('RG-13 : la famille « clinique » est fermée aux téléphones (liste blanche refusée, la mère refuse une version déclarée « mobile ») ; réglage dédié hors du panneau générique', () {
      expect(parFamillesJamaisMobile, contains(pcFamille));
      expect(parFamillesReglageDedie, contains(pcFamille));
      for (final d in pcDefinitions) {
        expect(d.mobile, isFalse, reason: d.cle);
        final champs = {...Parametres.semer(d).toJson(), 'mobile': true};
        expect(Parametres.autoriseMobile(champs), isFalse, reason: '${d.cle} : jamais vers un téléphone, même déclaré « mobile »');
        final v = Parametres.proposer(definition: d, versions: const [], usages: const [], valeur: d.defaut, dateEffet: '2026-11-16', auteur: 'admin');
        expect(Parametres.validerChamps({...v.valeur!.toJson(), 'mobile': true}, const [], const [])?.code, 'mobile_interdit');
      }
    });
  });

  group('les écrans lisent la valeur en vigueur', () {
    testWidgets('m6-alertes : « Péremption sous 90 j » au défaut, puis 120 réglé : le libellé et le compte suivent, le lot à 100 jours entre dans les alertes', (t) async {
      final m = magasin(lots: [lot('L100', 100), lot('L10', 10)]);
      await ouvrir(t, m, 'm6-alertes');
      expect(kpis(t)['Péremption sous 90 j'], '1');
      expect(regler(m, pcCleDelaiPeremption, 120), isNull);
      await ouvrir(t, m, 'm6-alertes');
      expect(kpis(t)['Péremption sous 120 j'], '2', reason: kpis(t).toString());
      expect(kpis(t).keys.where((k) => k.contains('90 j')), isEmpty, reason: 'plus aucun « 90 » écrit dans l\'écran');
      expect(find.textContaining('120 jours'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('m9-creances : les tranches au défaut (30 jours ou moins, De 31 à 90 jours), puis la première tranche réglée à 45 jours', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm9-creances');
      expect(kpis(t).keys, containsAll(['30 jours ou moins', 'De 31 à 90 jours', 'Au-delà de 90 jours']));
      expect(regler(m, pcCleTrancheCourte, 45), isNull);
      await ouvrir(t, m, 'm9-creances');
      expect(kpis(t).keys, containsAll(['45 jours ou moins', 'De 46 à 90 jours', 'Au-delà de 90 jours']), reason: kpis(t).keys.toString());
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('cfg-regles : la carte des paramètres de clinique ; « Régler » présent pour l\'administrateur, ABSENT pour un profil sans le geste réservé', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'cfg-regles');
      expect(find.text('Paramètres de clinique (datés)'), findsOneWidget);
      expect(find.byKey(const Key('regler-parametre:$pcCleDelaiPeremption')), findsOneWidget);
      await ouvrir(t, m, 'cfg-regles', role: 'direction');
      expect(find.text('Paramètres de clinique (datés)'), findsOneWidget);
      expect(find.byKey(const Key('regler-parametre:$pcCleDelaiPeremption')), findsNothing, reason: 'commande ABSENTE sans le geste (la Direction lit l\'écran sans régler)');
      await t.pump(const Duration(seconds: 10));
    });
  });
}
