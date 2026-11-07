import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/controleur_poste.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/mere/activation.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/modules/mere/mrb_source.dart';
import 'package:sigh_poste/modules/mere/mrc_commun.dart' show Mrc;
import 'package:sigh_poste/modules/rls/rls_commun.dart';
import 'package:sigh_poste/modules/rls/rls_ecrans_a.dart';
import 'package:sigh_poste/modules/rls/rls_ecrans_b.dart';

import 'activation_test.dart' show FauxService;
import 'aide_polices.dart';
import 'parite/extracteur.dart';
import 'mere_b_test.dart' show Faux, bouton, kpi, kpiIndice, maintenant, monterSeul, pomper, toutLeTexte, unEtat, lectureSeule;

/// Module RLS (« Relais en ligne ») dans le poste : les écrans lisent le relais PAR LA MÈRE. Ce qui n'a pas de source côté poste est « non disponible »
/// (jamais un zéro), une commande interdite est absente, un geste que la mère n'expose pas se refuse en le nommant.
const etatMere = {
  'epoch': 3,
  'seq_max': 120,
  'rep_seq': 100,
  'rep_n': 7,
  'appareils': [
    {'uuid': 'u-01', 'etiquette': 'Poste Caisse principale', 'role': 'fileul', 'etat': 'actif', 'dernier_contact': 0, 'dernier_seq': 120, 'derive_ms': 0},
    {'uuid': 'u-07', 'etiquette': 'Mobile Sage-femme de garde', 'role': 'mobile', 'etat': 'actif', 'dernier_contact': 0, 'dernier_seq': 90, 'derive_ms': 0},
    {'uuid': 'u-09', 'etiquette': 'Ancien poste Archives', 'role': 'fileul', 'etat': 'revoque', 'dernier_contact': 0, 'dernier_seq': 10, 'derive_ms': 0},
  ],
  'bloques': ['u-07'],
  'derives': [],
  'conflits_ouverts': 0,
  'alertes': [
    {'quand': 0, 'type': 'trou', 'appareil': 'u-07'}
  ],
  'reinit_ouverte': false,
};

List<MrbAppareil> appareilsFaux() => const [
      MrbAppareil(uuid: 'u-01', etiquette: 'Poste Caisse principale', role: 'fileul', etat: 'actif'),
      MrbAppareil(uuid: 'u-07', etiquette: 'Mobile Sage-femme de garde', role: 'mobile', etat: 'actif'),
      MrbAppareil(uuid: 'u-09', etiquette: 'Ancien poste Archives', role: 'fileul', etat: 'revoque'),
    ];

Faux fauxRelais({int? repN = 7}) {
  final f = Faux();
  f.etatV = unEtat(
      seqMax: 120,
      repSeq: 100,
      repN: repN,
      bloques: ['u-07'],
      alertes: [
        {'quand': maintenant.millisecondsSinceEpoch - 120000, 'type': 'trou', 'appareil': 'u-07'}
      ],
      appareils: appareilsFaux());
  return f;
}

/// Le client de la mère pour la lecture DÉTAILLÉE des appareils (dernier contact, curseur) ; `appels` retient les gestes d'écriture reçus.
ClientMere clientMere(List<String> appels, {Map<String, Object?>? etat, String? code}) => ClientMere(
    base: Uri.parse('http://x'),
    secretAdmin: 's',
    client: MockClient((r) async {
      if (r.method == 'POST') appels.add('${r.url.path} ${r.body}');
      if (r.url.path == '/admin/etat' && etat != null) return http.Response(jsonEncode(etat), 200);
      if (r.url.path == '/admin/code' && code != null) return http.Response(jsonEncode({'code': code}), 200);
      return http.Response('{}', 200);
    }));

void main() {
  setUpAll(chargerPolices);
  final ouvreurOrigine = rlsOuvreur;
  tearDown(() {
    mrbClientMere = null;
    Mrc.brancher();
    rlsOuvreur = ouvreurOrigine;
  });

  group('fonctions pures', () {
    test('adresse du panneau web : relais + /panneau + page, vide sans relais', () {
      expect(rlsAdressePanneau('https://relais.example/', 'rls-appareils'), 'https://relais.example/panneau/appareils');
      expect(rlsAdressePanneau('https://relais.example', 'rls-tableau'), 'https://relais.example/panneau');
      expect(rlsAdressePanneau('', 'rls-codes'), '');
      expect(rlsAdressePanneau('  ', 'rls-codes'), '');
    });

    test('chaque écran du module a sa page au panneau', () {
      expect(rlsPagesPanneau.length, 12);
      expect(rlsPagesPanneau.keys.every((k) => k.startsWith('rls-')), isTrue);
    });

    test('il y a N min', () {
      final n = DateTime(2026, 10, 31, 12);
      expect(rlsIlYa(n.subtract(const Duration(seconds: 40)), n), 'il y a 40 s');
      expect(rlsIlYa(n.subtract(const Duration(minutes: 12)), n), 'il y a 12 min');
      expect(rlsIlYa(n.subtract(const Duration(hours: 3)), n), 'il y a 3 h');
      expect(rlsIlYa(n.subtract(const Duration(days: 30)), n), 'il y a 30 j');
    });
  });

  testWidgets('tableau de bord : les valeurs viennent de la mère, rien d’inventé', (t) async {
    mrbClientMere = clientMere([], etat: etatMere);
    await monterSeul(t, const EcranRlsTableau(), fauxRelais());
    expect(kpi(t, 'Mère'), 'Vivante');
    expect(kpi(t, 'Appareils actifs'), '1', reason: 'u-01 actif ; u-07 bloqué et u-09 révoqué ne comptent pas');
    expect(kpi(t, 'Enveloppes stockées'), '7');
    expect(kpi(t, 'Alertes'), '2', reason: 'un trou relevé par la mère + un appareil bloqué');
    final texte = toutLeTexte(t);
    expect(texte, contains('appareil bloqué : mobile sage-femme de garde'));
    expect(texte, contains('trou dans les rangs d’une boîte : mobile sage-femme de garde'));
  });

  testWidgets('tableau de bord : le service de la mère en panne, aucun zéro de substitution', (t) async {
    final f = fauxRelais();
    f.panneEtat = ErreurMere(503, 'indisponible', 'base arrêtée');
    await monterSeul(t, const EcranRlsTableau(), f);
    for (final k in ['Mère', 'Appareils actifs', 'Enveloppes stockées', 'Alertes']) {
      expect(kpi(t, k), 'non disponible', reason: k);
    }
    expect(toutLeTexte(t), contains('base arrêtée'));
  });

  testWidgets('tableau de bord : compteur d’enveloppes absent = non disponible, pas zéro', (t) async {
    await monterSeul(t, const EcranRlsTableau(), fauxRelais(repN: null));
    expect(kpi(t, 'Enveloppes stockées'), 'non disponible');
  });

  testWidgets('appareils : état, dernier contact, en attente ; Révoquer sur les seuls appareils non révoqués', (t) async {
    mrbClientMere = clientMere([], etat: etatMere);
    await monterSeul(t, const EcranRlsAppareils(), fauxRelais());
    final texte = toutLeTexte(t);
    expect(texte, contains('poste caisse principale'));
    expect(texte, contains('révoqué'));
    expect(texte, contains('bloqué'));
    expect(bouton('Révoquer'), findsNWidgets(2), reason: 'u-01 et u-07 ; pas le poste révoqué');
    // « En attente » = rang de la mère moins dernier rang de l'appareil : 120 - 90 = 30 pour le mobile.
    expect(texte, contains('30'));
  });

  testWidgets('appareils : sans le détail de la mère, dernier contact et attente sont non disponibles', (t) async {
    await monterSeul(t, const EcranRlsAppareils(), fauxRelais());
    expect(toutLeTexte(t), contains('non disponible'));
  });

  testWidgets('appareils : révoquer demande confirmation puis appelle la mère', (t) async {
    mrbClientMere = clientMere([], etat: etatMere);
    final f = fauxRelais();
    await monterSeul(t, const EcranRlsAppareils(), f);
    await t.tap(bouton('Révoquer').first);
    await pomper(t);
    expect(f.appels, isEmpty, reason: 'rien ne part avant la confirmation');
    await t.tap(bouton('Révoquer').last);
    await pomper(t);
    expect(f.appels, ['revoquer u-01']);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('appareils : le refus de la mère se nomme', (t) async {
    mrbClientMere = clientMere([], etat: etatMere);
    final f = _FauxRefus();
    f.etatV = fauxRelais().etatV;
    await monterSeul(t, const EcranRlsAppareils(), f);
    await t.tap(bouton('Révoquer').first);
    await pomper(t);
    await t.tap(bouton('Révoquer').last);
    await pomper(t);
    expect(find.textContaining('Refusé'), findsWidgets);
    expect(find.textContaining('appareil_inconnu'), findsWidgets);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('appareils : en lecture seule, la commande Révoquer est ABSENTE', (t) async {
    mrbClientMere = clientMere([], etat: etatMere);
    await monterSeul(t, const EcranRlsAppareils(), fauxRelais(), droit: lectureSeule);
    expect(bouton('Révoquer'), findsNothing);
    expect(toutLeTexte(t), contains('poste caisse principale'));
  });

  testWidgets('boîtes aux lettres : une boîte par mobile, volumes non disponibles', (t) async {
    await monterSeul(t, const EcranRlsBoites(), fauxRelais());
    expect(kpi(t, 'Boîtes'), '1');
    expect(kpi(t, 'Vers les mobiles'), 'non disponible');
    expect(kpi(t, 'Depuis les mobiles'), 'non disponible');
    expect(toutLeTexte(t), contains('mobile sage-femme de garde'));
  });

  testWidgets('codes d’appairage : états tenus par le relais = non disponibles ; émission réelle par la mère', (t) async {
    final appels = <String>[];
    mrbClientMere = clientMere(appels, etat: etatMere, code: 'ABCD2345');
    await monterSeul(t, const EcranRlsCodes(), fauxRelais());
    for (final k in ['Codes valides', 'Utilisés (30 j)', 'Expirés']) {
      expect(kpi(t, k), 'non disponible', reason: k);
    }
    await t.tap(bouton('Émettre un code d’appairage'));
    await pomper(t);
    await t.enterText(find.byType(TextField).last, 'Poste Accueil 2');
    await t.tap(bouton('Émettre le code').last);
    await pomper(t);
    expect(appels, hasLength(1));
    expect(appels.single, startsWith('/admin/code '));
    expect(appels.single, contains('Poste Accueil 2'));
    expect(find.byKey(const Key('rls:code-emis')), findsOneWidget);
    expect(toutLeTexte(t), contains('ABCD2345'));
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('codes d’appairage : sans le droit d’écrire, aucune émission', (t) async {
    await monterSeul(t, const EcranRlsCodes(), fauxRelais(), droit: lectureSeule);
    expect(bouton('Émettre un code d’appairage'), findsNothing);
  });

  testWidgets('indicateurs reçus : aperçu de ce que la mère enverrait, historique non disponible', (t) async {
    await monterSeul(t, const EcranRlsIndicateurs(), fauxRelais());
    final apercu = t.widget<SelectableText>(find.byKey(const Key('rls:apercu-indicateurs'))).data!;
    expect(apercu, contains('"patients_actifs": 12'));
    expect(apercu, contains('"seq_max": 120'));
    expect(apercu, contains('"retard_replication": 20'));
    expect(toutLeTexte(t), contains('historique non disponible'));
  });

  testWidgets('alertes : règles nommées, seuils non disponibles, courriel de test refusé en le nommant', (t) async {
    await monterSeul(t, const EcranRlsAlertes(), fauxRelais());
    final texte = toutLeTexte(t);
    for (final r in rlsReglesAlerte) {
      expect(texte, contains(r.toLowerCase()));
    }
    await t.tap(bouton('Envoyer un courriel de test'));
    await pomper(t);
    expect(find.textContaining('Non disponible depuis ce poste'), findsWidgets);
    expect(find.textContaining('panneau web'), findsWidgets);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('alertes : sans le droit d’écrire, la commande est absente', (t) async {
    await monterSeul(t, const EcranRlsAlertes(), fauxRelais(), droit: lectureSeule);
    expect(bouton('Envoyer un courriel de test'), findsNothing);
  });

  testWidgets('journal : seuls les évènements de la mère qui concernent le relais', (t) async {
    final f = fauxRelais();
    f.journalV = [
      MrbLigneJournal(quand: maintenant.millisecondsSinceEpoch, niveau: 'info', source: 'relais', message: 'Appareil révoqué : u-09'),
      MrbLigneJournal(quand: maintenant.millisecondsSinceEpoch, niveau: 'info', source: 'synchronisation', message: 'Tirage complet du poste Z'),
    ];
    await monterSeul(t, const EcranRlsJournal(), f);
    final texte = toutLeTexte(t);
    expect(texte, contains('appareil révoqué : u-09'));
    expect(texte, isNot(contains('tirage complet du poste z')));
  });

  testWidgets('comptes superadmin : tenus par le panneau, non lisibles ; changement de mot de passe refusé en le nommant', (t) async {
    await monterSeul(t, const EcranRlsSuperadmin(), fauxRelais());
    expect(toutLeTexte(t), contains('comptes non disponibles'));
    await t.tap(bouton('Changer le mot de passe'));
    await pomper(t);
    expect(find.textContaining('Non disponible depuis ce poste'), findsWidgets);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('paramètres : seule l’adresse du relais est connue du poste, le secret n’est affiché nulle part', (t) async {
    final ctl = ControleurPoste(
        activation: ActivationMere(
            stockage: StockageMemoire(const ParametresPoste(uuidPoste: 'p', relais: 'https://relais.example')),
            service: FauxService(),
            relaisPour: (_, __) => throw StateError('x')),
        config: const ConfigPoste(mode: ModePoste.mere));
    Mrc.brancher(controleur: ctl);
    await monterSeul(t, const EcranRlsParametres(), fauxRelais());
    final texte = toutLeTexte(t);
    expect(texte, contains('https://relais.example'));
    expect(texte, contains('jamais affiché'));
    expect(texte, contains('relais_secret_mere'));
  });

  testWidgets('hébergement : les mesures du relais sont non disponibles, la liaison de la mère est lue', (t) async {
    await monterSeul(t, const EcranRlsHebergement(), fauxRelais());
    for (final k in ['PHP', 'Base', 'Cron', 'Disque']) {
      expect(kpi(t, k), 'non disponible', reason: k);
      expect(kpiIndice(t, k), contains('panneau web'));
    }
    expect(toutLeTexte(t), contains('liaison de la mère avec le relais'));
  });

  testWidgets('sauvegarde du relais : non disponible, et Exporter maintenant refuse en le nommant', (t) async {
    await monterSeul(t, const EcranRlsSauvegarde(), fauxRelais());
    expect(kpi(t, 'Dernier export'), 'non disponible');
    expect(kpi(t, 'Taille'), 'non disponible');
    await t.tap(bouton('Exporter maintenant'));
    await pomper(t);
    expect(find.textContaining('Seul le relais peut exporter sa base'), findsWidgets);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('preuve d’opacité : la conception est dite, la mesure est non disponible', (t) async {
    await monterSeul(t, const EcranRlsOpacite(), fauxRelais());
    expect(kpi(t, 'Clé de clinique au relais'), 'Aucune');
    expect(kpiIndice(t, 'Clé de clinique au relais'), contains('Non mesuré depuis ce poste'));
    expect(kpi(t, 'Entropie moyenne'), 'non disponible');
    expect(kpi(t, 'Noms de collection lisibles'), 'non disponible');
    expect(toutLeTexte(t), contains('contenu d’une enveloppe'));
  });

  testWidgets('lien vers le panneau web : adresse affichée, ouverture et copie', (t) async {
    final ouverts = <String>[];
    rlsOuvreur = (u) async {
      ouverts.add(u);
      return true;
    };
    final ctl = ControleurPoste(
        activation: ActivationMere(
            stockage: StockageMemoire(const ParametresPoste(uuidPoste: 'p', relais: 'https://relais.example/')),
            service: FauxService(),
            relaisPour: (_, __) => throw StateError('x')),
        config: const ConfigPoste(mode: ModePoste.mere));
    Mrc.brancher(controleur: ctl);
    await monterSeul(t, const EcranRlsAppareils(), fauxRelais());
    expect(t.widget<SelectableText>(find.byKey(const Key('rls:adresse-panneau'))).data, 'https://relais.example/panneau/appareils');
    await t.tap(bouton('Ouvrir le panneau web'));
    await pomper(t);
    expect(ouverts, ['https://relais.example/panneau/appareils']);
  });

  testWidgets('lien vers le panneau web : sans adresse de relais, le poste le dit', (t) async {
    await monterSeul(t, const EcranRlsAppareils(), fauxRelais());
    expect(find.byKey(const Key('rls:adresse-panneau')), findsNothing);
    expect(toutLeTexte(t), contains('adresse du relais non configurée sur ce poste'));
  });

  testWidgets('sans liaison avec la mère (poste fileul), chaque écran dit pourquoi il est vide', (t) async {
    await monterSeul(t, const EcranRlsTableau(), _SansService());
    expect(kpi(t, 'Mère'), 'non disponible');
  });

  group('dans la coque', () {
    final donnees = DonneesNavigation.depuisDossier();
    Future<void> ouvrir(WidgetTester t, String ecran, String role) async {
      mrbSourceInjectee = fauxRelais();
      mrbIntervalle = const Duration(hours: 1);
      addTearDown(() => mrbSourceInjectee = null);
      t.view.physicalSize = const Size(1500, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      final client = ClientMere(base: Uri.parse('http://x'), secretAdmin: 's', client: MockClient((r) async => http.Response('{}', 200)));
      await t.pumpWidget(SighPoste(
          key: UniqueKey(),
          donnees: donnees,
          config: ConfigPoste(mode: ModePoste.mere, role: role),
          client: client,
          ecranInitial: ecran,
          magasin: Magasin(),
          horloge: () => maintenant));
      await pomper(t);
    }

    testWidgets('l’administrateur ouvre le tableau de bord du relais : son écran Flutter, plus la coque à convertir', (t) async {
      await ouvrir(t, 'rls-tableau', 'admin');
      expect(find.byKey(const Key('ecran-a-porter')), findsNothing);
      expect(textesVisibles(t), contains('la mère est-elle vivante, à jour, sauvegardée ? volumes et alertes \u2014 sans aucun nom de patient.'));
    });

    testWidgets('la page d’accueil du module montre les douze écrans du relais', (t) async {
      await ouvrir(t, 'hub-rls', 'admin');
      for (final id in rlsPagesPanneau.keys) {
        expect(find.byKey(Key('hub-carte:$id')), findsOneWidget, reason: id);
      }
    });

    testWidgets('un rôle sans droit sur le module RLS ne voit ni son domaine ni ses écrans (RG-13)', (t) async {
      await ouvrir(t, 'rls-tableau', 'caissier');
      expect(textesVisibles(t), isNot(contains('relais en ligne')));
      expect(textesVisibles(t), isNot(contains('tableau de bord du relais')));
    });
  });
}

class _FauxRefus extends Faux {
  @override
  Future<void> revoquer(String uuid) async => throw ErreurMere(404, 'appareil_inconnu', 'Cet appareil est inconnu de la mère.');
}

class _SansService extends Faux {
  @override
  Future<MrbSante> supervision() async => throw ErreurMere(503, 'liaison', 'aucune liaison avec le service de la mère');
}
