import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show smsCleActif;
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/sms_poste.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// LA PASSERELLE SMS AU POSTE (lot SMS-R, ADR-0008) : `cfg-sms` et `m13-sms-journal` contre une source de la mère FAUSSE. L'état est lu au relais par la mère ; les identifiants ne sont jamais
/// montrés ; les commandes (enregistrer, tester, calculer et déposer) sont ABSENTES sans le geste réservé `regler_passerelle_sms` ; le moteur (`SmsPoste`) refuse aussi.
class FausseSource implements SourceSms {
  final List<String> appels = [];
  ErreurSmsPoste? refus;
  Map<String, Object?> passerelle = {'fournisseur': 'twilio', 'identifiantsDefinis': true, 'expediteurDefini': true, 'configuree': true, 'envoyesAujourdhui': 3, 'reglages': {'plafond_jour': 200}};

  @override
  Future<Map<String, Object?>> etat() async => {
        'passerelle': passerelle,
        'planifies': [
          {'type': 'rappel_rdv', 'heure': '2026-10-31T18:00', 'numeroMasque': '••••0001'}
        ],
        'dernier': null,
        'erreur': null,
      };
  @override
  Future<Map<String, Object?>> passe(String role) async {
    appels.add('passe:$role');
    if (refus != null) throw refus!;
    return {'calcules': 2, 'planifies': 2, 'retires': 0, 'ecartes': {}};
  }

  @override
  Future<Map<String, Object?>> tester(String role, String numero) async {
    appels.add('tester:$role:$numero');
    if (refus != null) throw refus!;
    return {'ok': true, 'idFournisseur': 'SM123'};
  }

  @override
  Future<List<Map<String, Object?>>> journal() async => [
        {'id': 'a' * 64, 'type': 'rappel_rdv', 'etat': 'envoye', 'code': null, 'numeroMasque': '••••0001', 'idFournisseur': 'SM1', 'maj': DateTime(2026, 10, 30, 9).millisecondsSinceEpoch},
        {'id': 'b' * 64, 'type': 'anniversaire_patient', 'etat': 'refuse', 'code': 'PLAFOND_ATTEINT', 'numeroMasque': '••••0002', 'idFournisseur': null, 'maj': DateTime(2026, 10, 30, 10).millisecondsSinceEpoch},
        {'id': 'c' * 64, 'type': 'rappel_rdv', 'etat': 'planifie', 'code': null, 'numeroMasque': '••••0003', 'idFournisseur': null, 'maj': DateTime(2026, 10, 29, 10).millisecondsSinceEpoch},
      ];
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  SmsPoste installer(Magasin m, FausseSource s, {bool mere = true, bool fileul = false}) {
    final p = SmsPoste(m, estFileul: () => fileul, estMere: () => mere, source: s, gesteDe: (r) => r == 'admin' || r == 'da');
    p.installer();
    return p;
  }

  final enregistrer = find.widgetWithText(BoutonSigh, 'Enregistrer la passerelle');
  final tester = find.widgetWithText(BoutonSigh, 'Tester l’envoi');

  casM14('cfg-sms : l\'état se lit au relais, les identifiants sont « définis » sans valeur, les envois planifiés ont un numéro masqué', (t) async {
    final m = magasinM14();
    installer(m, FausseSource());
    await ouvrirM14(t, m, 'cfg-sms');
    for (final k in ['Prête', 'Envois aujourd’hui', '3 sur 200', 'Réglages de la passerelle', 'Test d’envoi', 'Envois automatiques planifiés', '••••0001', 'Twilio']) {
      expect(find.textContaining(k), findsWidgets, reason: k);
    }
    expect(find.text('Défini dans le .env du relais'), findsNWidgets(3));
    expect(enregistrer, findsOneWidget);
    expect(tester, findsOneWidget);
  });

  casM14('cfg-sms : sans le geste réservé (Direction : lecture seule), les commandes sont ABSENTES', (t) async {
    final m = magasinM14();
    installer(m, FausseSource());
    await ouvrirM14(t, m, 'cfg-sms', role: 'direction');
    expect(find.text('Passerelle SMS'), findsWidgets);
    expect(enregistrer, findsNothing);
    expect(tester, findsNothing);
    expect(find.byKey(const Key('sms:calculer')), findsNothing);
    expect(find.byKey(const Key('sms:test-absent')), findsOneWidget);
  });

  casM14('cfg-sms : un fileul rattaché lit le réglage sans aucune commande', (t) async {
    final m = magasinM14();
    installer(m, FausseSource(), mere: false, fileul: true);
    await ouvrirM14(t, m, 'cfg-sms');
    expect(enregistrer, findsNothing);
    expect(find.textContaining('se règle sur le poste mère'), findsOneWidget);
  });

  casM14('cfg-sms : activer les envois est un réglage daté et journalisé ; « Calculer et déposer maintenant » appelle la mère avec le rôle ; « Tester l\'envoi » rend le résultat nommé', (t) async {
    final m = magasinM14();
    final src = FausseSource();
    final p = installer(m, src);
    expect(p.actif, isFalse, reason: 'désactivés par défaut');
    await ouvrirM14(t, m, 'cfg-sms');
    await toucherM14(t, find.text('Passerelle active'));
    await toucherM14(t, enregistrer);
    expect(p.actif, isTrue);
    expect(m.collection('audit').toutes.any((f) => '${f['action']}'.contains('Réglage de la passerelle SMS')), isTrue, reason: 'RG-12');
    await t.pump(const Duration(milliseconds: 300));
    await toucherM14(t, find.byKey(const Key('sms:calculer')));
    expect(src.appels, ['passe:admin']);
    await saisir(t, 'numero', '+22997000009');
    await toucherM14(t, tester);
    expect(src.appels.last, 'tester:admin:+22997000009');
    expect(find.textContaining('Accepté par le fournisseur'), findsOneWidget);
    expect(find.text('Réussi'), findsOneWidget);
  });

  casM14('cfg-sms : un refus de la mère est nommé à l\'écran', (t) async {
    final m = magasinM14();
    final src = FausseSource()..refus = const ErreurSmsPoste(RefusSmsPoste('GESTE_RESERVE', 'droit réservé', 'Demander à l\'administrateur.'));
    installer(m, src);
    await ouvrirM14(t, m, 'cfg-sms');
    await saisir(t, 'numero', '+22997000009');
    await toucherM14(t, tester);
    expect(find.textContaining('GESTE_RESERVE'), findsWidgets);
    expect(find.text('Échoué'), findsOneWidget);
  });

  test('le moteur refuse aussi : sans le geste, ni test ni calcul ne partent', () async {
    final m = magasinM14();
    final src = FausseSource();
    final p = installer(m, src);
    expect((await p.tester(role: 'reception', numero: '+22997000009')).$2?.code, 'GESTE_RESERVE');
    expect((await p.calculerMaintenant(role: 'reception')).$2?.code, 'GESTE_RESERVE');
    expect(p.definirActif(role: 'reception', actif: true)?.code, 'GESTE_RESERVE');
    expect(src.appels, isEmpty);
    final hors = SmsPoste(m, estMere: () => false, source: src, gesteDe: (_) => true);
    expect((await hors.tester(role: 'admin', numero: '+22997000009')).$2?.code, 'MERE_REQUISE');
    final fileul = SmsPoste(m, estFileul: () => true, gesteDe: (_) => true);
    expect(fileul.definirActif(role: 'admin', actif: true)?.code, 'FILEUL_LECTURE_SEULE');
    expect(m.collection('parametres').toutes.where((f) => f['cle'] == smsCleActif), isEmpty);
  });

  casM14('m13-sms-journal : lecture seule, numéro masqué, filtres du / au, compteurs', (t) async {
    final m = magasinM14();
    installer(m, FausseSource());
    await ouvrirM14(t, m, 'm13-sms-journal');
    for (final k in ['Envois journalisés', 'Acceptés', 'Refusés', 'Reportés', 'Tous les envois', 'Archivés', 'Exporter', 'Colonnes', 'Du', 'Au', '••••0001', 'PLAFOND_ATTEINT']) {
      expect(find.textContaining(k), findsWidgets, reason: k);
    }
    expect(find.textContaining('0197'), findsNothing, reason: 'jamais un numéro en clair');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Aujourd’hui'));
    expect(find.text('••••0003'), findsNothing, reason: 'la ligne du 29/10 sort du filtre « aujourd\'hui »');
    expect(find.text('••••0001'), findsWidgets);
  });

  casM14('personnel : date de naissance et consentement SMS (décoché par défaut) à la création, tracés', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm10-personnel');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau').first);
    expect(find.text('Date de naissance'), findsWidgets);
    expect(find.text('Accepte de recevoir les vœux d’anniversaire par SMS'), findsOneWidget);
    await saisir(t, 'matricule', '9901');
    await saisir(t, 'nom', 'AGBO');
    await saisir(t, 'prenom', 'Rosine');
    await choisirM14(t, 'fonction', 'Infirmier');
    await choisirM14(t, 'service', 'Soins infirmiers');
    await saisir(t, 'salaireBase', '120000');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final f = m.collection('personnel').toutes.firstWhere((x) => x['matricule'] == '9901');
    expect(f['consentementSms'], false, reason: 'décoché par défaut : rien ne part sans un oui');
    expect('${f['consentementSmsLe']}', startsWith('2026-10-30'));
    expect('${f['consentementSmsPar']}', isNotEmpty);
  });
}
