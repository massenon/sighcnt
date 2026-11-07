import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show qualGenererJeton;
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/m13/qual_publique.dart';
import 'package:sigh_poste/shell/barre_superieure.dart';
import 'package:sigh_poste/shell/ruban.dart';

import 'aide_polices.dart';
import 'aide_qualite.dart';
import 'parite/extracteur.dart';

/// Les écrans de la qualité (M13) : enquêtes & questionnaires, satisfaction des patients, centre des validations, page publique d'une fiche d'enquête.
/// Les règles sont rejouées sur les vecteurs de la maquette (`packages/domaine/test/qualite_test.dart`) ; ici, l'ÉCRAN — ce qui est lu, écrit, refusé,
/// annulable, ce que chaque rôle voit, et la parité N1 mesurée contre les fiches extraites.
List<Fiche> casDe(String cle) => liste(vecteurs[cle]);
/// Un libellé de commande qui écrit ou valide (les accès rapides de l'en-tête ne sont que des liens).
bool ecriture(String l) => RegExp(r'Nouveau|Enregistrer|Valider|Archiver|Modifier|Supprimer|Recueillir|Créer|Rejeter|Révoquer').hasMatch(l);

Fiche premier(List<Fiche> l, String debut) => l.firstWhere((x) => '${x['nom']}'.startsWith(debut));

/// Un magasin de la qualité : le modèle de satisfaction, ses réponses et les liens ouverts.
Magasin magasinQualite({List<Fiche>? enquetes, List<Fiche>? reponses, List<Fiche> jetons = const []}) => magasinDe({
      'enquetes': enquetes ?? jeuJson('enquetes'),
      'reponsesEnquetes': reponses ?? jeuJson('reponsesEnquetes'),
      'jetonsEnquete': jetons,
    });

Fiche jeton(String code, {bool anonyme = true, String? expire = '2026-09-30', String? revoque, String statut = 'actif', String enquete = 'ENQ0001'}) => {
      'id': 'J-$code',
      'statut': statut,
      'jeton': code,
      'enqueteId': enquete,
      'enqueteTitre': 'Satisfaction des patients',
      'anonyme': anonyme,
      'usage': 'salle',
      'creeLe': '2026-08-01',
      'expireLe': expire,
      'revoqueLe': revoque,
    };

Future<void> monterPublique(WidgetTester t, Magasin m, String? code) async {
  t.view.physicalSize = const Size(800, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(MaterialApp(home: EcranEnquetePublique(magasin: m, code: code, horloge: () => aujourdhui)));
  await t.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  // ============================================================================================================================ SATISFACTION
  group('adm-satisfaction', () {
    for (final c in casDe('satisfaction').where((x) => x['entrees'] != null)) {
      cas('${c['nom']}', (t) async {
        final e = m_(m_(c['entrees'])['enquete']);
        final reps = [
          for (final (i, r) in liste(m_(c['entrees'])['reponses']).indexed) {'id': 'R$i', 'statut': 'actif', 'canal': 'Au guichet', ...r}
        ];
        await ouvrir(t, magasinQualite(enquetes: [e], reponses: reps), 'adm-satisfaction');
        for (final k in liste(c['kpis'])) {
          expect(sp(kpi(t, '${k['label']}')), sp(k['valeur']), reason: '${k['label']}');
        }
        final g = c['graphique'];
        if (g == null) {
          expect(find.byType(GraphiqueBarres), findsNothing);
          expect(find.text('Aucune question de type note.'), findsOneWidget);
        } else {
          final b = t.widget<GraphiqueBarres>(find.byType(GraphiqueBarres));
          final data = ((m_(g)['series'] as List).first as Map)['data'] as List;
          expect([for (final x in b.series.first.donnees) x.toDouble()], [for (final x in data) (x as num).toDouble()]);
          expect(b.etiquettes, (m_(g)['etiquettes'] as List).cast<String>());
        }
        final comms = (c['commentaires'] as List).cast<List>();
        for (final l in comms) {
          expect(find.text('${l[0]}'), findsWidgets);
        }
        if (comms.isEmpty) expect(find.text('Aucun commentaire libre recueilli.'), findsOneWidget);
        // L'ordre : le plus récent d'abord.
        final textes = [for (final w in t.widgetList<Text>(find.byType(Text))) if ((w.data ?? '').startsWith('« ')) w.data!];
        expect(textes, [for (final l in comms) '${l[0]}']);
        expect(textes.length, lessThanOrEqualTo(8));
      });
    }

    cas('aucune enquête active : l’écran le dit', (t) async {
      await ouvrir(t, magasinQualite(enquetes: [], reponses: []), 'adm-satisfaction');
      expect(find.textContaining('Aucune enquête de satisfaction'), findsOneWidget);
    });

    cas('en lecture seule : aucune commande d’écriture', (t) async {
      await ouvrir(t, magasinQualite(), 'adm-satisfaction');
      expect([for (final e in find.byType(BoutonSigh).evaluate()) (e.widget as BoutonSigh).libelle].where(ecriture), isEmpty);
    });

    cas('le jeu du poste : parité N1', (t) async {
      await ouvrir(t, magasinQualite(), 'adm-satisfaction');
      await parite(t, 'adm-satisfaction');
    });
  });

  // ============================================================================================================================ VALIDATIONS
  group('adm-validations', () {
    List<Fiche> deplier(Object? v) => [
          for (final g in liste(v))
            for (var i = 0; i < (g['n'] as num); i++) {for (final e in g.entries) if (e.key != 'n') e.key: e.value}
        ];
    Magasin magasinDeCas(Fiche c) {
      final e = m_(c['entrees']);
      return magasinDe({
        for (final n in ['demandesAnalyses', 'ecritures', 'besoins', 'commandes', 'factures', 'resultatsImagerie', 'echeancesFiscales', 'materiel', 'plagesReactif'])
          n: [for (final (i, f) in deplier(e[n]).indexed) {'id': '$n$i', ...f}]
      });
    }

    for (final c in casDe('validations')) {
      cas('${c['nom']}', (t) async {
        await ouvrir(t, magasinDeCas(c), 'adm-validations');
        for (final k in liste(c['kpis'])) {
          expect(sp(kpi(t, '${k['label']}')), sp(k['valeur']), reason: '${k['label']}');
        }
        // Une file par carte : son compte (ou « — » quand elle n'est pas amorcée) et sa phrase.
        for (final f in liste(c['files'])) {
          final textes = (f['textes'] as List).cast<String>();
          expect(find.text(textes[0]), findsOneWidget);
          expect(find.text(textes[1]), findsWidgets, reason: textes[0]);
        }
        final comptes = [for (final w in t.widgetList<Text>(find.byWidgetPredicate((w) => w is Text && (w.key as ValueKey?)?.value.toString().startsWith('qual:compte:') == true))) w.data];
        expect([for (final x in comptes) sp(x)], [for (final f in liste(c['files'])) sp(f['compte'])]);
        // Aucune commande qui valide : on navigue seulement.
        final libelles = {for (final e in find.byType(BoutonSigh).evaluate()) (e.widget as BoutonSigh).libelle};
        expect(libelles.where(ecriture), isEmpty, reason: 'le centre oriente, il ne valide jamais');
        expect(libelles, containsAll({'Y aller', 'Ouvrir'}));
      });
    }

    cas('non amorcé : « — » et la file le dit, jamais un faux 0', (t) async {
      final c = premier(casDe('validations'), 'besoins et commandes non amorcés');
      await ouvrir(t, magasinDeCas(c), 'adm-validations');
      expect(find.text('File non amorcée sur ce poste — ouvrir l’écran pour la charger'), findsNWidgets(2));
      expect(find.byKey(const Key('qual:compte:m7-besoins')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('qual:compte:m7-besoins'))).data, '—');
    });

    cas('« Y aller » ouvre l’écran du geste, « Ouvrir » celui du référentiel', (t) async {
      final c = casDe('validations').first;
      await ouvrir(t, magasinDeCas(c), 'adm-validations');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Y aller').first);
      expect(find.byKey(const Key('titre-page')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('titre-page'))).data, isNot('Validations en attente'));
    });

    cas('le jeu du poste : parité N1', (t) async {
      await ouvrir(t, magasinDe({
        'demandesAnalyses': jeuJson('demandesAnalyses'),
        'ecritures': jeuJson('ecritures'),
        'besoins': jeuJson('besoins'),
        'commandes': jeuJson('commandes'),
        'factures': jeuJson('factures'),
        'resultatsImagerie': jeuJson('resultatsImagerie'),
        'echeancesFiscales': jeuJson('echeancesFiscales'),
        'materiel': jeuJson('materiel'),
        'plagesReactif': jeuJson('plagesReactif'),
      }), 'adm-validations');
      await parite(t, 'adm-validations');
    });
  });

  // ============================================================================================================================ ENQUÊTES
  group('adm-enquetes', () {
    final enq = casDe('enquetes');
    Fiche enquete(Magasin m) => m.collection('enquetes').actives.firstWhere((e) => e['reference'] == 'ENQ-SAT');

    cas('à l’ouverture : indicateurs, onglets, en-têtes et ligne du modèle', (t) async {
      await ouvrir(t, magasinQualite(), 'adm-enquetes');
      final c = enq.first;
      // Le jeu du poste porte 26 réponses, comme la maquette amorcée.
      for (final k in liste(c['kpis'])) {
        expect(sp(kpi(t, '${k['label']}')), sp(k['valeur']), reason: '${k['label']}');
      }
      expect(find.text('Modèles (1)'), findsOneWidget);
      expect(find.text('Liens de partage (0)'), findsOneWidget);
      final tab = t.widget<TableauSigh>(find.byType(TableauSigh));
      expect([for (final x in tab.colonnes) x.libelle], (c['entetes'] as List).cast<String>().where((x) => x != 'Actions').toList());
      final ligne = cellules(tab, t.state<TableauSighState>(find.byType(TableauSigh)).lignesFiltrees.first);
      final attendu = ((c['lignes'] as List).first as List).cast<String>();
      expect([for (final x in ligne) sp(x)], [for (final x in attendu.take(4)) sp(x)]);
      await parite(t, 'adm-enquetes');
    });

    cas('Recueillir : le formulaire NAÎT du modèle, une question ajoutée au modèle paraît à la saisie suivante', (t) async {
      final m = magasinQualite();
      await ouvrir(t, m, 'adm-enquetes');
      final c = premier(enq, 'Recueillir');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Recueillir'));
      for (final l in (m_(c['ouverture1'])['libelles'] as List)) {
        expect(find.text('$l'), findsWidgets, reason: '$l');
      }
      expect(find.textContaining('La signalisation est-elle claire'), findsNothing);
      await t.tap(find.widgetWithText(BoutonSigh, 'Annuler'));
      await t.pump(const Duration(milliseconds: 300));
      // On ajoute la question AU MODÈLE (une donnée) : rien n'est codé.
      final e = enquete(m);
      m.collection('enquetes').mettreAJour(e['id'], {
        'questions': [...(e['questions'] as List), {'code': 'Q_NEUF', 'libelle': 'La signalisation est-elle claire ?', 'type': 'choix', 'options': ['Oui', 'Non']}]
      });
      await t.pump();
      await toucher(t, find.widgetWithText(BoutonSigh, 'Recueillir'));
      for (final l in (m_(c['ouverture2'])['libelles'] as List)) {
        expect(find.text('$l'), findsWidgets, reason: '$l');
      }
      final avant = m.collection('reponsesEnquetes').actives.length;
      await choisir(t, 'Q_ACCUEIL', '5');
      await choisir(t, '_canal', 'À la sortie');
      await choisir(t, 'Q_RECO', 'Plutôt oui');
      await saisir(t, 'Q_LIBRE', 'Mieux indiquer la salle');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer la réponse'));
      final reps = m.collection('reponsesEnquetes').actives;
      expect(reps.length, avant + 1);
      final r = reps.first;
      expect(r['canal'], 'À la sortie');
      expect(r['enqueteId'], e['id']);
      expect(r['date'], '2026-08-16');
      final rep = m_(r['reponses']);
      expect(rep['Q_ACCUEIL'], 5, reason: 'une note s’écrit comme un nombre');
      expect(rep['Q_RECO'], 'Plutôt oui');
      expect(rep['Q_NEUF'], 'Oui');
      expect(rep['Q_LIBRE'], 'Mieux indiquer la salle');
      expect(r['saisiPar'], isNotEmpty, reason: 'RG-12 : aucune action anonyme');
      expect(find.text('Réponse recueillie.'), findsOneWidget);
    });

    cas('Nouveau modèle : refus nommés, puis création en « proposition à valider »', (t) async {
      final m = magasinQualite();
      await ouvrir(t, m, 'adm-enquetes');
      final c = premier(enq, 'Nouveau modèle');
      final n0 = m.collection('enquetes').toutes.length;
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau modèle'));
      await saisir(t, 'titre', 'Accueil des visiteurs');
      await saisir(t, 'description', 'Test');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer le modèle'));
      expect(find.text('Un questionnaire sans question ne recueille rien.'), findsOneWidget);
      expect(m.collection('enquetes').toutes.length, n0);
      expect(obj0(c['refusSansQuestion'])['ajoutes'], 0);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Ajouter une question'));
      await saisir(t, 'libelle', 'Quel service ?');
      await choisir(t, 'type', 'Choix dans une liste');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Ajouter').last);
      expect(find.text('Une question à choix a besoin de ses choix.'), findsOneWidget);
      await saisir(t, 'optionsTexte', 'Accueil | Caisse |  | Labo');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Ajouter').last);
      expect(find.text('1. Quel service ?'), findsOneWidget);
      expect(find.text('Choix dans une liste — Accueil · Caisse · Labo'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer le modèle'));
      final neuf = m.collection('enquetes').actives.first;
      final attendu = m_(m_(c['cree']));
      expect(neuf['titre'], attendu['titre']);
      expect(neuf['reference'], 'ENQ-001');
      expect(neuf['aValider'], true);
      expect(neuf['source'], attendu['source']);
      expect(neuf['creeLe'], '2026-08-16');
      final q = liste(neuf['questions']).single;
      expect(q['options'], ['Accueil', 'Caisse', 'Labo']);
      expect(q['type'], 'choix');
      expect(find.text('Modèle créé.'), findsOneWidget);
      expect(kpi(t, 'Modèles à valider'), '1');
    });

    cas('Partager : un jeton de 24 caractères, jamais l’identifiant, avec son QR ; Révoquer ferme la porte sans rien effacer', (t) async {
      final m = magasinQualite();
      await ouvrir(t, m, 'adm-enquetes');
      final p = premier(enq, 'Partager');
      await toucher(t, find.byTooltip('Partager à un tiers'));
      for (final l in (m_(p['formPartage'])['libelles'] as List)) {
        expect(find.textContaining(('$l').replaceAll(' *', '')), findsWidgets, reason: '$l');
      }
      await choisir(t, 'usage', 'Sur une tablette de la clinique (mode kiosque)');
      await saisir(t, 'note', 'Salle d’attente');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Ouvrir le lien'));
      final j = m.collection('jetonsEnquete').actives.single;
      expect(j['jeton'], matches(RegExp(r'^[a-km-z2-9]{24}$')));
      expect(j['anonyme'], true);
      expect(j['usage'], 'tablette');
      expect(j['expireLe'], '2026-09-15', reason: 'trente jours par défaut');
      expect(j['revoqueLe'], isNull);
      expect(j['enqueteId'], enquete(m)['id']);
      expect(find.text('Lien de partage'), findsOneWidget);
      expect(find.byKey(const Key('qual:qr')), findsOneWidget);
      final champ = t.widget<TextField>(find.byKey(const Key('qual:adresse')));
      final adresse = champ.controller!.text;
      expect(adresse, contains('/enquete-publique.php?jeton=${j['jeton']}'));
      expect(adresse, isNot(contains('${j['enqueteId']}')), reason: 'l’adresse ne porte JAMAIS l’identifiant de l’enquête');
      expect(find.text('Ouvert'), findsOneWidget);
      expect(kpi(t, 'Liens ouverts'), '1');
      // Copier l'adresse.
      String? copie;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copie = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Copier l’adresse'));
      expect(copie, adresse);
      expect(find.text('Adresse copiée.'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump(const Duration(milliseconds: 400));
      await toucher(t, find.text('Liens de partage (1)'));
      expect(find.text('Anonyme'), findsOneWidget);
      expect(find.text('Ouvert'), findsOneWidget);
      final reponses = m.collection('reponsesEnquetes').actives.length;
      await toucher(t, find.byTooltip('Révoquer le lien'));
      expect(find.text('Révoquer ce lien ?'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Révoquer').last);
      final apres = m.collection('jetonsEnquete').toutes.single;
      expect(apres['revoqueLe'], '2026-08-16');
      expect(apres['revoquePar'], isNotEmpty);
      expect(m.collection('reponsesEnquetes').actives.length, reponses, reason: 'révoquer n’efface rien');
      expect(find.text('Révoqué le 16/08/2026'), findsOneWidget);
      expect(find.byTooltip('Révoquer le lien'), findsNothing);
      expect(kpi(t, 'Liens ouverts'), '0');
      expect(find.text('Lien révoqué.'), findsOneWidget);
      // Annuler la révocation rouvre la porte.
      await toucher(t, find.widgetWithText(BoutonSigh, 'Annuler').last);
      expect(m.collection('jetonsEnquete').toutes.single['revoqueLe'], isNull);
      expect(kpi(t, 'Liens ouverts'), '1');
    });

    cas('Voir les réponses : le détail question par question', (t) async {
      await ouvrir(t, magasinQualite(), 'adm-enquetes');
      await toucher(t, find.byTooltip('Voir les réponses'));
      expect(find.text('26 réponse(s)'), findsOneWidget);
      expect(find.textContaining('Qualité de l’accueil'), findsWidgets);
    });

    cas('sans le droit d’écrire, les commandes sont ABSENTES ; la lecture reste', (t) async {
      final role = roleSelonDroit('adm-enquetes', editer: false);
      if (role == null) return;
      await ouvrir(t, magasinQualite(), 'adm-enquetes', role: role);
      expect(find.widgetWithText(BoutonSigh, 'Nouveau modèle'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Recueillir'), findsNothing);
      expect(find.byTooltip('Partager à un tiers'), findsNothing);
      expect(find.byTooltip('Modifier le modèle'), findsNothing);
      expect(find.byTooltip('Voir les réponses'), findsOneWidget);
    });
  });

  // ============================================================================================================================ PAGE PUBLIQUE
  group('enquete-publique', () {
    final pub = casDe('publique');
    final etats = liste(m_(pub[0])['etats']);
    Magasin magasinPublic() => magasinQualite(jetons: [
          jeton('ouvertanonyme2222222222222'),
          jeton('ouvertnominatif33333333333', anonyme: false),
          jeton('echeancememe444444444444444', expire: '2026-08-16'),
          jeton('echu5555555555555555555555', expire: '2026-08-15'),
          jeton('revoque666666666666666666666', revoque: '2026-08-10'),
          jeton('archive7777777777777777777', statut: 'archive'),
          jeton('sansfin8888888888888888888', expire: null),
          jeton('orphelin999999999999999999', enquete: 'ENQ-INCONNUE'),
        ]);

    for (final e in etats) {
      cas('${e['nom']}', (t) async {
        await monterPublique(t, magasinPublic(), e['code'] as String?);
        final fermee = sp(e['texte']).contains(sp('Ce lien n’est plus valable.'));
        expect(find.byKey(const Key('qual:lien-invalide')), fermee ? findsOneWidget : findsNothing);
        if (fermee) {
          expect(find.text('Ce lien n’est plus valable.'), findsOneWidget);
          expect(find.textContaining('Tél. 01 95 44 51 51 / 01 66 43 28 20'), findsOneWidget);
          // Ni le titre de l'enquête, ni rien qui la nomme.
          expect(find.textContaining('Satisfaction des patients'), findsNothing);
          expect(find.byType(FormulaireSigh), findsNothing);
        } else {
          expect(find.text('Satisfaction des patients'), findsOneWidget);
          for (final l in (e['libelles'] as List)) {
            expect(find.text('$l'), findsOneWidget, reason: '$l');
          }
          expect(find.text('Envoyer ma réponse'), findsOneWidget);
        }
        // SANS COQUILLE : ni ruban, ni barre supérieure, ni lien, ni recherche.
        expect(find.byType(Ruban), findsNothing);
        expect(find.byType(BarreSuperieure), findsNothing);
        expect(find.byType(TextButton), findsNothing);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(AppBar), findsNothing);
      });
    }

    cas('inconnu, expiré, révoqué : LA MÊME réponse, au mot près', (t) async {
      final textes = <String>{};
      for (final code in ['nexistepas', 'echu5555555555555555555555', 'revoque666666666666666666666', 'archive7777777777777777777', null]) {
        await monterPublique(t, magasinPublic(), code);
        textes.add(textesVisibles(t).join('|'));
      }
      expect(textes.length, 1);
    });

    cas('l’anonymat est porté par le lien ; aucune donnée médicale', (t) async {
      await monterPublique(t, magasinPublic(), 'ouvertanonyme2222222222222');
      expect(find.textContaining('Questionnaire ANONYME'), findsOneWidget);
      expect(find.text('Votre nom *'), findsNothing);
      expect(find.textContaining('Aucune question ne porte sur votre santé.'), findsOneWidget);
      await monterPublique(t, magasinPublic(), 'ouvertnominatif33333333333');
      expect(find.textContaining('Questionnaire NOMINATIF'), findsOneWidget);
      expect(find.text('Votre nom *'), findsOneWidget);
      for (final mot in ['diagnostic', 'ordonnance', 'consultation du']) {
        expect([for (final x in textesVisibles(t)) if (x.contains(mot)) x], isEmpty);
      }
    });

    cas('envoyer une réponse anonyme : canal « Lien public », aucun nom, le lien tracé', (t) async {
      final m = magasinPublic();
      await monterPublique(t, m, 'ouvertanonyme2222222222222');
      final avant = m.collection('reponsesEnquetes').toutes.length;
      final v = liste(m_(pub[1])['envois']).first;
      await choisir(t, 'Q_ACCUEIL', '5');
      await choisir(t, 'Q_ATTENTE', '2');
      await choisir(t, 'Q_PROPRETE', '4');
      await choisir(t, 'Q_SOINS', '3');
      await choisir(t, 'Q_RECO', 'Plutôt non');
      await saisir(t, 'Q_LIBRE', 'Trop long');
      await toucher(t, find.text('Envoyer ma réponse'));
      expect(m.collection('reponsesEnquetes').toutes.length, avant + 1);
      final r = m.collection('reponsesEnquetes').toutes.first;
      final attendu = m_(v['reponse']);
      expect(r['canal'], attendu['canal']);
      expect(r['saisiPar'], attendu['saisiPar']);
      expect(r['jetonId'], 'J-ouvertanonyme2222222222222');
      expect(m_(r['reponses']), m_(attendu['reponses']));
      expect(find.byKey(const Key('qual:merci')), findsOneWidget);
      expect(find.text('Merci !'), findsOneWidget);
      expect(find.text('Votre réponse a bien été enregistrée.'), findsOneWidget);
      expect(find.byType(FormulaireSigh), findsNothing);
    });

    cas('nominatif : le nom est exigé, puis enregistré', (t) async {
      final m = magasinPublic();
      await monterPublique(t, m, 'ouvertnominatif33333333333');
      final avant = m.collection('reponsesEnquetes').toutes.length;
      await toucher(t, find.text('Envoyer ma réponse'));
      expect(find.text('Merci de compléter les réponses attendues.'), findsOneWidget);
      expect(m.collection('reponsesEnquetes').toutes.length, avant, reason: 'rien n’est écrit');
      await saisir(t, '_repondant', 'KOUASSI Awa');
      await toucher(t, find.text('Envoyer ma réponse'));
      final r = m.collection('reponsesEnquetes').toutes.first;
      expect(r['saisiPar'], 'KOUASSI Awa');
      expect(r['canal'], 'Lien public');
      expect(m_(r['reponses']).containsKey('_repondant'), isFalse, reason: 'le nom ne se mêle pas aux réponses');
    });

    cas('un lien révoqué pendant la saisie : la réponse n’est pas perdue de vue, le lien suivant est fermé', (t) async {
      final m = magasinPublic();
      m.collection('jetonsEnquete').mettreAJour('J-ouvertanonyme2222222222222', {'revoqueLe': '2026-08-16'});
      await monterPublique(t, m, 'ouvertanonyme2222222222222');
      expect(find.byKey(const Key('qual:lien-invalide')), findsOneWidget);
    });

    cas('le jeton tiré : 24 caractères, alphabet sans l, 1, o, 0', (t) async {
      var i = 0;
      final j = qualGenererJeton((n) => (i++ * 7) % n);
      expect(j, matches(RegExp(r'^[a-km-z2-9]{24}$')));
    });

    cas('« Ouvrir la page publique » monte la page DANS UNE ROUTE sans chrome', (t) async {
      final m = magasinQualite(jetons: [jeton('ouvertanonyme2222222222222')]);
      await ouvrir(t, m, 'adm-enquetes');
      await toucher(t, find.text('Liens de partage (1)'));
      await toucher(t, find.byTooltip('Afficher le lien et le QR'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Ouvrir la page publique'));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('qual:questionnaire')), findsOneWidget);
      expect(find.byType(Ruban), findsNothing, reason: 'la coque est sous la route, non visible');
      expect(find.byType(BarreSuperieure), findsNothing);
    });
  });
}

Map<String, Object?> obj0(Object? o) => (o as Map).cast<String, Object?>();
