import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/service_installation.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/identite_poste.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// La configuration fiscale VALIDÉE et DATÉE au poste (Direction, 06/11/2026 ; écarts E2276 à E2278) : identité légale et obligations se vérifient et se
/// valident à la première configuration, puis se modifient par versions datées. Les règles du domaine sont rejouées sur `fiscal-date.json` ; ici, les
/// ÉCRANS (commande Valider absente sans droit, bandeau d'état, modale de portée, historique), l'identité imprimée à la date de la pièce, l'ORTB daté, la
/// détection de l'assistant d'installation par VALIDATION et le fileul en lecture seule.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  Finder valider(String quoi) => find.byKey(Key('cfb:valider:$quoi'));

  casM14('cfg-fiscalite : « Valider » pose valideLe et validePar sur la fiche, UNE ligne de journal, le bandeau passe à « validée »', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-fiscalite');
    expect(find.byKey(const Key('cfb:etat:identite:a_valider')), findsOneWidget);
    expect(m.collection('identiteLegale').actives.first['valideLe'], isNull);
    final avant = m.collection('audit').toutes.length;
    await toucherM14(t, valider('identite'));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider').last);
    final f = m.collection('identiteLegale').actives.first;
    expect(f['valideLe'], isNotNull);
    expect(f['validePar'], isNotEmpty);
    expect(find.byKey(const Key('cfb:etat:identite:valide')), findsOneWidget);
    expect(m.collection('audit').toutes.length, avant + 1, reason: 'une seule ligne de journal pour la validation (RG-12)');
    final j = m.collection('audit').toutes.first;
    expect([j['action'], j['module'], j['entite']], ['Identité légale validée', 'CFG', 'identiteLegale']);
  });

  casM14('après validation, « Enregistrer » ouvre la modale de portée : motif obligatoire, puis une NOUVELLE version, la v1 est conservée, bandeau « à revalider »', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-fiscalite');
    await toucherM14(t, valider('identite'));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider').last);
    await t.pump(const Duration(seconds: 10));
    await saisir(t, 'rccm', 'RB/NAT/2016-B-269');
    await toucherM14(t, find.byKey(const Key('cfb:fiscalite:enregistrer')));
    expect(find.text('Portée de la modification'), findsOneWidget);
    // Sans motif : refusé, rien n'est écrit.
    await toucherM14(t, find.byKey(const Key('cfb:portee:appliquer')));
    expect(find.text('Date d’effet et motif sont obligatoires.'), findsOneWidget);
    expect(m.collection('identiteLegale').actives.length, 1);
    await t.pump(const Duration(seconds: 10));
    await saisir(t, 'motif', 'Nouveau RCCM après transfert');
    await toucherM14(t, find.byKey(const Key('cfb:portee:appliquer')));
    final versions = m.collection('identiteLegale').actives.toList()..sort((a, b) => (a['version'] as int).compareTo(b['version'] as int));
    expect(versions.length, 2);
    expect(versions[0]['rccm'], 'RB/NAT/2016-B-268', reason: 'la version sortante reste telle qu’elle a été validée');
    expect(versions[0]['valideLe'], isNotNull);
    expect(versions[1]['rccm'], 'RB/NAT/2016-B-269');
    expect(versions[1]['valideLe'], isNull);
    expect(versions[1]['motif'], 'Nouveau RCCM après transfert');
    expect(find.byKey(const Key('cfb:etat:identite:modifie_depuis')), findsOneWidget);
  });

  casM14('une pièce imprime l’identité EN FORCE À SA DATE : la v1 avant la date d’effet, la v2 à partir de cette date', (t) async {
    final m = magasinM14();
    final col = m.collection('identiteLegale');
    final v1 = col.actives.first;
    col.mettreAJour('${v1['id']}', {'fin': '2026-08-31'});
    col.inserer({...Map<String, Object?>.of(v1)..remove('id'), 'version': 2, 'debut': '2026-09-01', 'fin': null, 'rccm': 'RB/NAT/2016-B-269'}, prefixe: 'IDL');
    expect(identiteImprimeeDe(m, DateTime(2026, 8, 16)).rccm, 'RB/NAT/2016-B-268');
    expect(identiteImprimeeDe(m, DateTime(2026, 9, 1)).rccm, 'RB/NAT/2016-B-269');
    expect(identiteImprimeeDe(m, DateTime(2020, 1, 1)).rccm, 'RB/NAT/2016-B-268', reason: 'la v1 couvre depuis l’ouverture');
  });

  casM14('Valider est ABSENT (jamais grisé) sans le droit d’écrire sur CFG : l’accueil lit, ne valide pas depuis un écran en lecture seule', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-fiscalite', role: 'reception');
    expect(valider('identite'), findsNothing);
    expect(find.byKey(const Key('cfb:fiscalite:enregistrer')), findsNothing);
    expect(find.text('Valider'), findsNothing);
    expect(cfbControleValidation(role: 'reception')?.code, 'VALIDATION_RESERVEE', reason: 'le domaine refait le contrôle même si l’écran est fermé');
  });

  casM14('cfg-comptabilite : « Valider les obligations » valide les 19 obligations ET les paramètres ORTB ; modifier ITS ensuite ouvre la modale de portée', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-comptabilite');
    final col = m.collection('obligationsFiscales');
    expect(col.actives.length, 20);
    expect(col.actives.where((f) => f['valideLe'] != null), isEmpty);
    await toucherM14(t, valider('obligations'));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider').last);
    expect(col.actives.where((f) => f['valideLe'] != null).length, 20);
    expect(find.byKey(const Key('cfb:etat:obligations:valide')), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    await toucherM14(t, find.byKey(const Key('cfb:modifier:ITS')));
    await saisir(t, 'jour', '15');
    await toucherM14(t, find.byKey(const Key('cfb:obligation:continuer')));
    expect(find.text('Portée de la modification'), findsOneWidget);
    expect(find.byKey(const Key('cfb:portee:impact')), findsOneWidget, reason: 'la modale annonce ce que la régénération fait des échéances');
    await saisir(t, 'motif', 'Décision de la Direction');
    await toucherM14(t, find.byKey(const Key('cfb:portee:appliquer')));
    final its = col.actives.firstWhere((f) => f['code'] == 'ITS');
    expect(its['jour'], 15);
    expect(m.collection('historiqueObligations').actives.where((h) => h['code'] == 'ITS').length, 1, reason: 'la version sortante part à l’historique');
    expect(find.byKey(const Key('cfb:etat:obligations:modifie_depuis')), findsOneWidget);
  });

  group('l’ORTB est daté', () {
    test('PaiParametresOrtb.aLaDate lit la version en vigueur : un seuil relevé en septembre ne touche pas juin', () {
      final m = magasinM14();
      final obl = m.collection('obligationsFiscales');
      final o = obl.actives.firstWhere((f) => f['type'] == 'parametres');
      final r = cfbModifierOrtb(obl.toutes,
          valeurs: {'seuilTele': 80000, 'radio': {'montant': 1000, 'mois': 2}, 'tele': {'montant': 3000, 'mois': 5}},
          dateEffet: '2026-09-01',
          motif: 'Relèvement du seuil',
          acteur: 'test',
          maintenant: DateTime(2026, 8, 16, 10),
          aujourdhui: DateTime(2026, 8, 16, 10));
      expect(r.ok, isTrue, reason: '${r.refus?.code}');
      m.collection('historiqueObligations').inserer(r.historique!, prefixe: 'HOB');
      obl.mettreAJour('${o['id']}', r.fiche!);
      final juin = PaiParametresOrtb.aLaDate(DateTime(2026, 6, 1), obligations: obl.toutes, historique: m.collection('historiqueObligations').toutes);
      final octobre = PaiParametresOrtb.aLaDate(DateTime(2026, 10, 1), obligations: obl.toutes, historique: m.collection('historiqueObligations').toutes);
      expect(juin.seuilTele, 60000);
      expect(octobre.seuilTele, 80000);
      expect(paiCalculOrtb(70000, 5, parametres: juin).tele?.montant, 3000);
      expect(paiCalculOrtb(70000, 5, parametres: octobre).tele, isNull, reason: '70 000 F ne dépasse plus le seuil de 80 000 F');
    });
  });

  group('assistant d’installation : la ligne n’est « faite » que VALIDÉE', () {
    test('une ÉCRITURE ne coche pas, la case « vérifié » non plus ; la validation coche', () async {
      final m = magasinM14();
      final s = ServiceInstallation.de(m);
      await s.attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'u'));
      expect(s.lignesConfiguration()['cfg-fiscalite']!.ecrit, isFalse);
      expect(s.lignesConfiguration()['cfg-comptabilite']!.ecrit, isFalse);
      // Une écriture (correction de la version non validée) ne suffit pas.
      final f = m.collection('identiteLegale').actives.first;
      m.collection('identiteLegale').mettreAJour('${f['id']}', {'slogan': 'Votre santé, notre raison de vivre'});
      expect(s.lignesConfiguration()['cfg-fiscalite']!.ecrit, isFalse, reason: 'MUTATION : une écriture sans validation ne coche pas');
      expect(s.lignesConfiguration()['cfg-fiscalite']!.verifie, isFalse);
      // Validation de l'identité seule : la ligne fiscalité est faite, la comptabilité non.
      final r = cfbValiderIdentite(m.collection('identiteLegale').toutes, role: 'admin', acteur: 'ADJOVI', maintenant: DateTime(2026, 10, 30), aujourdhui: DateTime(2026, 10, 30));
      expect(r.ok, isTrue);
      for (final id in r.ids) {
        m.collection('identiteLegale').mettreAJour(id, r.patch);
      }
      expect(s.lignesConfiguration()['cfg-fiscalite']!.ecrit, isTrue);
      expect(s.lignesConfiguration()['cfg-comptabilite']!.ecrit, isFalse);
      // Une fiche modifiée après validation (nouvelle version non validée) remet la ligne à « à valider ».
      m.collection('identiteLegale').inserer({'version': 2, 'statut': 'actif', 'debut': '2026-12-01', 'nom': 'X'}, prefixe: 'IDL');
      expect(s.lignesConfiguration()['cfg-fiscalite']!.ecrit, isFalse);
    });
  });

  test('aucune lecture en dur de l’IFU ou du RCCM dans lib/ : les littéraux n’y sont pas, et les états imprimés passent par la fabrique de l’identité à la date', () {
    final fichiers = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
    for (final f in fichiers) {
      final t = f.readAsStringSync();
      expect(t.contains('3201642748214'), isFalse, reason: '${f.path} porte l’IFU en dur');
      expect(t.contains('RB/NAT/2016'), isFalse, reason: '${f.path} porte le RCCM en dur');
    }
    // Les états imprimés (facture mère, relevé assureur, cotisations, ticket) lisent la version en force, plus la constante de semence.
    for (final p in ['lib/modules/m9/releve.dart', 'lib/modules/m9/facture_mere.dart', 'lib/modules/m11/pai_cotisations.dart', 'lib/modules/m8/facturation.dart']) {
      final t = File(p).readAsStringSync();
      expect(RegExp(r'IdentiteClinique\.(ifu|rccm)').hasMatch(t), isFalse, reason: '$p lit la constante de semence');
      expect(t.contains('identiteImprimeeDe'), isTrue, reason: p);
    }
  });

  casM14('adm-validations : les deux lignes de configuration fiscale existent, disparaissent une fois validées et reviennent sur une version non validée', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'adm-validations');
    expect(find.byKey(const Key('qual:config:identite')), findsOneWidget);
    expect(find.byKey(const Key('qual:config:obligations')), findsOneWidget);
    expect(find.text('Identité légale à valider (première configuration)'), findsOneWidget);
    expect(find.text('Obligations fiscales à valider'), findsOneWidget);
    final ri = cfbValiderIdentite(m.collection('identiteLegale').toutes, role: 'admin', acteur: 'ADJOVI', maintenant: DateTime(2026, 10, 30), aujourdhui: DateTime(2026, 10, 30));
    for (final id in ri.ids) {
      m.collection('identiteLegale').mettreAJour(id, ri.patch);
    }
    await t.pump();
    expect(find.byKey(const Key('qual:config:identite')), findsNothing);
    expect(find.byKey(const Key('qual:config:obligations')), findsOneWidget);
    final ro = cfbValiderObligations(m.collection('obligationsFiscales').toutes, role: 'admin', acteur: 'ADJOVI', maintenant: DateTime(2026, 10, 30));
    for (final id in ro.ids) {
      m.collection('obligationsFiscales').mettreAJour(id, ro.patch);
    }
    await t.pump();
    expect(find.byKey(const Key('qual:config:obligations')), findsNothing);
    m.collection('identiteLegale').inserer({'version': 2, 'statut': 'actif', 'debut': '2027-01-01', 'nom': 'X', 'creeLe': '2026-11-01T10:00:00.000'}, prefixe: 'IDL');
    await t.pump();
    expect(find.byKey(const Key('qual:config:identite')), findsOneWidget);
    expect(find.textContaining('à revalider'), findsOneWidget);
  });

  casM14('un fileul rattaché voit cfg-fiscalite et cfg-comptabilite en LECTURE SEULE nommée : ni Enregistrer, ni Valider, ni Modifier', (t) async {
    for (final ecran in ['cfg-fiscalite', 'cfg-comptabilite']) {
      final m = magasinM14();
      await t.runAsync(() => ServiceInstallation.de(m).attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'u', rejoint: true)));
      expect(ServiceInstallation.de(m).rattache, isTrue);
      await ouvrirM14(t, m, ecran);
      expect(valider('identite'), findsNothing, reason: ecran);
      expect(valider('obligations'), findsNothing, reason: ecran);
      expect(find.byKey(const Key('cfb:fiscalite:enregistrer')), findsNothing, reason: ecran);
      expect(find.byKey(const Key('cfb:nouvelle-obligation')), findsNothing, reason: ecran);
      expect(find.byKey(const Key('cfb:modifier:ITS')), findsNothing, reason: ecran);
      expect(find.textContaining('tenue par la mère'), findsWidgets, reason: ecran);
      await t.pump(const Duration(seconds: 10));
    }
  });
}
