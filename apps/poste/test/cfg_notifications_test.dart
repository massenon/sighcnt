import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/cfg/cfb_notifications.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// cfg-notifications : les règles (canaux, profils, notes) sont rejouées sur les vecteurs de la maquette (packages/domaine/test/cfb_regles_test.dart) ;
/// ici, l'ÉCRAN — ce que chaque geste écrit aux réglages, ce qui est journalisé, et ce que le son ne coupe PAS.
void main() {
  setUpAll(chargerPolices);
  tearDown(() {
    ToastsSigh.viderPourTests();
    CfbAudio.disponible = () => false;
  });

  Fiche? reglage(Magasin m, String id) => m.collection('reglages').actives.where((f) => f['id'] == id).firstOrNull;

  casM14('ouverture : douze événements, 12 / 3 / 5 canaux, et le poste dit que la sonorisation est INDISPONIBLE sans rien couper d’autre', (t) async {
    CfbAudio.disponible = () => false;
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-notifications');
    for (final k in ['Événements paramétrés', 'Notifications dans l’application', 'Notifications par SMS', 'Notifications par courriel']) {
      expect(find.text(k), findsOneWidget, reason: k);
    }
    expect(find.text('12'), findsNWidgets(2));
    expect(find.text('Sonorisation indisponible'), findsOneWidget);
    expect(find.textContaining('L’application continue normalement'), findsOneWidget);
    expect(find.text('Nouvelle admission'), findsOneWidget);
    expect(find.text('Échec de sauvegarde'), findsOneWidget);
    expect(find.textContaining('0 alerte(s) en attente pour votre poste'), findsOneWidget);
  });

  casM14('sonorisation disponible : le badge le dit, et « Tester » émet sans créer la moindre notification métier', (t) async {
    CfbAudio.disponible = () => true;
    var joue = 0;
    CfbAudio.tester = () async {
      joue++;
      return (joue: true, motif: null);
    };
    final m = magasinM14();
    final avant = m.collection('notifications').toutes.length;
    await ouvrirM14(t, m, 'cfg-notifications');
    expect(find.text('Sonorisation disponible'), findsOneWidget);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Tester la sonorisation'));
    expect(joue, 1);
    expect(find.text('Son de test émis.'), findsOneWidget);
    expect(find.text('Aucune alerte n’a été créée : ce test ne touche ni les données ni les workflows.'), findsOneWidget);
    expect(m.collection('notifications').toutes.length, avant, reason: 'un test qui laisserait une trace serait pire qu’aucun test');
  });

  casM14('un son qui ne joue pas est DIT avec son motif, jamais passé sous silence', (t) async {
    CfbAudio.disponible = () => true;
    CfbAudio.tester = () async => (joue: false, motif: 'Aucun périphérique audio détecté.');
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-notifications');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Tester la sonorisation'));
    expect(find.text('Son de test non émis.'), findsOneWidget);
    expect(find.text('Aucun périphérique audio détecté.'), findsOneWidget);
  });

  casM14('couper le son : le réglage est écrit, le profil et la temporisation deviennent INERTES — l’alerte, elle, n’est pas touchée', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-notifications');
    expect(t.widget<IgnorePointer>(find.byKey(const Key('cfb:notif:reglages-son'))).ignoring, isFalse);
    await toucherM14(t, find.byKey(const Key('cfb:notif:son')));
    final p = reglage(m, 'notificationsSon')!['valeur'] as Map;
    expect([p['son'], p['visuel'], p['profil'], p['temporisation']], [false, true, 'standard', 30]);
    expect(t.widget<IgnorePointer>(find.byKey(const Key('cfb:notif:reglages-son'))).ignoring, isTrue);
    // rien d’autre n’a bougé : aucune notification, aucun canal
    expect(reglage(m, 'notificationsCanaux'), isNull);
  });

  casM14('profil « Critique seulement » et temporisation de 4 heures : écrits, et la note du profil change', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-notifications');
    expect(find.text('Son court pour l’information, son renforcé pour l’urgent.'), findsOneWidget);
    await choisirM14(t, 'profil', 'Critique seulement');
    expect(find.text('Seules les alertes graves sonnent, et elles se répètent une fois.'), findsOneWidget);
    await choisirM14(t, 'temporisation', '4 heures');
    final p = reglage(m, 'notificationsSon')!['valeur'] as Map;
    expect([p['profil'], p['temporisation'], p['son'], p['visuel']], ['critique', 240, true, true]);
  });

  casM14('enregistrer la matrice : les canaux cochés sont écrits, le journal porte leur NOMBRE, les indicateurs se recomptent', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-notifications');
    await toucherM14(t, find.byKey(const Key('cfb:canal:admission:sms')));
    await toucherM14(t, find.byKey(const Key('cfb:canal:rupture:mail')));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer le paramétrage'));
    expect(find.text('Paramétrage enregistré.'), findsOneWidget);
    expect(find.text('22 canal(aux) actif(s).'), findsOneWidget);
    final canaux = reglage(m, 'notificationsCanaux')!['valeur'] as Map;
    expect((canaux['admission'] as Map)['sms'], true);
    expect((canaux['rupture'] as Map)['mail'], true);
    final j = m.collection('audit').toutes.firstWhere((a) => a['entite'] == 'ParametrageNotifications');
    expect([j['action'], j['module'], j['reference']], ['Modification', 'CFG', 'NOTIF']);
    expect(j['apres'], {'canauxActifs': 22});
    expect(find.text('4'), findsWidgets, reason: 'quatre notifications par SMS');
    expect(find.text('6'), findsWidgets, reason: 'six par courriel');
  });

  casM14('droits : en lecture seule, « Enregistrer le paramétrage » est ABSENT (jamais grisé)', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-notifications', role: 'admin', donnees: donneesLectureSeule('admin', 'cfg-notifications'));
    expect(find.widgetWithText(BoutonSigh, 'Enregistrer le paramétrage'), findsNothing);
    expect(find.text('Matrice des notifications'), findsOneWidget);
  });
}
