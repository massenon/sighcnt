import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';
import 'parite/extracteur.dart';

/// M1 — Patients & Dossier médical (14 écrans). Les règles sont rejouées sur les vecteurs de la maquette
/// (packages/domaine/test/pat_regles_test.dart) ; ici, l'ÉCRAN : parité de contenu N1, ce qui est écrit, refusé, annulable, et ce que chaque rôle voit.
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 10, 30, 12);

const ecransM1 = [
  'm1-patients',
  'm1-patient-profil',
  'm1-externe',
  'm1-antecedents',
  'm1-pieces',
  'm1-constantes',
  'm1-reference',
  'm1-contre-reference',
  'm1-documents',
  'm1-numerisation',
  'm1-dossier-medical',
  'm1-dossier-etendu',
  'm1-patient-nouveau',
  'm1-certificats-externes',
];

Map<String, Object?> vecteurs(String nom) =>
    (jsonDecode(File('../../packages/domaine/test/vecteurs/$nom.json').readAsStringSync()) as Map).cast<String, Object?>();

Magasin jeuComplet() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => aujourdhui));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> saisir(WidgetTester t, String champ, String valeur) async {
  await t.enterText(find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(TextField)), valeur);
  await t.pump();
}

Future<void> choisir(WidgetTester t, String champ, String cible) async {
  final portee = find.descendant(of: find.byKey(const Key('kit:modale-panneau')), matching: find.byKey(Key('kit:champ:$champ')));
  final zone = portee.evaluate().isNotEmpty ? portee : find.byKey(Key('kit:champ:$champ'));
  final avant = find.text(cible).evaluate().length;
  await toucher(t, find.descendant(of: zone, matching: find.byType(InkWell)).first);
  // Le panneau d'une longue liste ne construit que les lignes visibles : si l'option n'est pas apparue, on la cherche.
  if (find.text(cible).evaluate().length == avant) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
  await t.pump(const Duration(milliseconds: 400));
}

String kpi(WidgetTester t, String libelle) =>
    t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == libelle)).valeur;
String? indice(WidgetTester t, String libelle) =>
    t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == libelle)).indice;

String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

Fiche p(String id, String code, [Fiche extra = const {}]) => {
      'id': id,
      'statut': 'actif',
      'code': code,
      'nom': 'NOM$id',
      'prenom': 'Pre$id',
      'sexe': 'F',
      'dateNaissance': '1990-01-01',
      'telephone': '9',
      'quartier': 'Perma',
      'dateCreation': '2026-05-01',
      ...extra,
    };

Magasin petit(Map<String, List<Fiche>> jeux) => Magasin(jeux, 'POSTE', {
      ...(jsonDecode(File('assets/donnees/jeu/referentiels.json').readAsStringSync()) as Map).cast<String, Object?>()
    });

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  // =========================================================================================================================================
  group('parité de contenu N1 (14 écrans, jeu complet, rôle admin)', () {
    final m = jeuComplet();
    for (final id in ecransM1) {
      testWidgets(id, (t) async {
        final f = (jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()) as Map).cast<String, Object?>();
        // Le jeu du poste ne porte aucun document numérisé (la maquette l'amorce à l'ouverture de l'écran) : les en-têtes du tableau ne se dessinent
        // qu'avec des lignes — on mesure donc cet écran sur le jeu posé du vecteur.
        final mm = id == 'm1-documents'
            ? petit({'patients': [p('K1', 'CNT/1/26')], 'documentsPatient': [for (final x in (vecteurs('pat_documents')['jeu'] as List)) (x as Map).cast<String, Object?>()]})
            : m;
        await ouvrir(t, mm, id);
        final r = comparerContenu(id, f, textesVisibles(t));
        expect(r.manquants, isEmpty, reason: '$id : ${r.presents}/${r.attendus} — manque ${r.manquants}');
        await t.pump(const Duration(seconds: 10));
      });
    }
  });

  // =========================================================================================================================================
  group('m1-patients', () {
    final doc = vecteurs('pat_patients');
    cas('les quatre indicateurs, les onglets et les lignes sont ceux de la maquette sur le jeu posé', (t) async {
      final r = (doc['repertoire'] as Map).cast<String, Object?>();
      final jeu = [for (final x in (r['jeu'] as List)) (x as Map).cast<String, Object?>()];
      await ouvrir(t, petit({'patients': jeu, 'couverturesAssurance': []}), 'm1-patients');
      final k = r['kpis'] as List;
      expect(kpi(t, 'Dossiers actifs'), (k[0] as List)[1]);
      expect(kpi(t, 'Créés en 2026'), (k[1] as List)[1]);
      expect(kpi(t, 'Patients assurés'), (k[2] as List)[1]);
      expect(norm(indice(t, 'Patients assurés')!), (k[2] as List)[2]);
      expect(kpi(t, 'Cartes expirées'), (k[3] as List)[1]);
      expect(find.textContaining('Tous les patients'), findsWidgets);
      // La ligne d'un assuré dont la carte est expirée dit CARTE NON VALIDE ; l'âge DÉCLARÉ s'affiche (E301).
      expect(find.text('CARTE NON VALIDE'), findsWidgets);
      expect(find.textContaining('36 ans'), findsWidgets);
    });

    cas('« Nouveau » conduit à la page d\'ouverture, qui réserve le code et l\'écrit au format CNT/n/AA', (t) async {
      final m = petit({
        'patients': [p('1', 'CNT/1109/26'), p('2', 'CNT530/26')],
        'audit': []
      });
      await ouvrir(t, m, 'm1-patient-nouveau');
      expect(find.byKey(const Key('m1:code')), findsOneWidget);
      expect((t.widget<Text>(find.byKey(const Key('m1:code')))).data, 'CNT/1110/26');
      await saisir(t, 'nom', 'Bio');
      await saisir(t, 'prenom', 'Zakari');
      await choisir(t, 'naissanceConnue', 'Inconnue — indiquer l’âge déclaré');
      await saisir(t, 'age', '41');
      await saisir(t, 'telephone', '97000001');
      await toucher(t, find.text('Ouvrir le dossier').last);
      final cree = m.collection('patients').toutes.first;
      expect(cree['code'], 'CNT/1110/26');
      expect(cree['nom'], 'Bio');
      expect(cree['age'], 41);
      expect(cree['ageReferenceLe'], '2026-10-30');
      expect(cree['statut'], 'actif');
      expect(cree['dateCreation'], '2026-10-30');
      expect(m.collection('audit').toutes, isNotEmpty, reason: 'RG-12 : la création est journalisée');
    });

    cas('un champ obligatoire vide : rien n\'est écrit', (t) async {
      final m = petit({'patients': [p('1', 'CNT/1/26')]});
      await ouvrir(t, m, 'm1-patient-nouveau');
      await toucher(t, find.text('Ouvrir le dossier').last);
      expect(m.collection('patients').toutes.length, 1);
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
    });

    cas('la fiche : menu des rubriques et leurs comptes sur le jeu posé', (t) async {
      final d = vecteurs('pat_profil');
      final m = petit({
        'patients': [p('P1', 'CNT/1/26', {'nom': 'TCHANE', 'prenom': 'Bertine', 'allergies': ['Sulfamides'], 'assureur': 'NSIA', 'assureurNom': 'NSIA ASSURANCE', 'carteExpiration': '2027-12-31'})],
        'consultations': [
          {'id': 'C1', 'statut': 'actif', 'patientId': 'P1', 'type': 'Consultation', 'date': '2026-08-10', 'motif': 'Toux', 'diagnostic': 'Asthme', 'medecin': 'Dr A'}
        ],
        'dossiersConsultation': [
          {
            'id': 'DS1', 'statut': 'actif', 'patientId': 'P1', 'reference': 'DOS-1', 'dateArrivee': '2026-08-10', 'heureArrivee': '09h00', 'ouvertLe': '2026-08-10T09:05:00',
            'examensPhysiques': {
              'cardio_vasculaire': {'inspection': 'RAS', 'palpation': 'RAS', 'percussion': 'RAS', 'auscultation': 'RAS'},
              'pleuro_pulmonaire': {'inspection': 'RAS', 'auscultation': 'Sibilants bilatéraux'}
            }
          }
        ],
      });
      await ouvrir(t, m, 'm1-patient-profil');
      final menu = (d['menu'] as List).cast<String>();
      for (final r in menu) {
        final libelle = r.replaceAll(RegExp(r'\d+$'), '');
        expect(find.text(libelle), findsWidgets, reason: libelle);
      }
      expect(find.textContaining('Allergie(s) déclarée(s) : Sulfamides'), findsOneWidget);
      // L'examen IPPOA par appareil s'affiche (écart E316 : la synthèse recevait le dossier et restait vide).
      expect(find.text('Appareil cardio-vasculaire'), findsOneWidget);
      expect(find.text('RAS — normal'), findsOneWidget);
      expect(find.textContaining('Sibilants bilatéraux'), findsOneWidget);
      await toucher(t, find.byKey(const Key('m1:rubrique:medical')));
      expect(find.text('Asthme'), findsWidgets);
    });

    cas('un profil sans le droit d\'écrire ne voit ni « Modifier le dossier » ni « Nouveau »', (t) async {
      final m = petit({'patients': [p('1', 'CNT/1/26')]});
      await ouvrir(t, m, 'm1-patient-profil', role: 'laborantin');
      expect(find.text('Modifier le dossier'), findsNothing);
    });
  });

  // =========================================================================================================================================
  group('m1-antecedents', () {
    final d = vecteurs('pat_antecedents');
    cas('indicateurs et risque sur le jeu posé', (t) async {
      final jeu = [for (final x in (d['jeu'] as List)) (x as Map).cast<String, Object?>()];
      await ouvrir(t, petit({'patients': jeu}), 'm1-antecedents');
      final k = d['kpis'] as List;
      expect(kpi(t, 'Dossiers renseignés'), (k[0] as List)[1]);
      expect(kpi(t, 'Allergies déclarées'), (k[1] as List)[1]);
      expect(kpi(t, 'Antécédents à risque'), (k[2] as List)[1]);
      expect(kpi(t, 'Sans antécédent notable'), (k[3] as List)[1]);
    });

    cas('modifier un patient à deux antécédents n\'en efface aucun (E304)', (t) async {
      final jeu = [for (final x in (d['jeu'] as List)) (x as Map).cast<String, Object?>()];
      final m = petit({'patients': jeu, 'audit': []});
      await ouvrir(t, m, 'm1-antecedents');
      await t.enterText(find.byType(TextField).first, 'CNT/3/26');
      await t.pump(const Duration(milliseconds: 500));
      await toucher(t, find.byTooltip('Modifier les antécédents'));
      await saisir(t, 'antecedentsAutres', 'Appendicectomie');
      await toucher(t, find.text('Enregistrer').last);
      final f = m.collection('patients').toutes.firstWhere((x) => x['code'] == 'CNT/3/26');
      expect(f['antecedents'], ['Drépanocytose', 'Asthme']);
      expect(f['antecedentsAutres'], 'Appendicectomie');
      expect(find.text('Éléments médicaux enregistrés.'), findsOneWidget);
    });
  });

  // =========================================================================================================================================
  group('m1-constantes', () {
    final d = vecteurs('pat_constantes');
    cas('indicateurs et contrôle des bornes sur le jeu posé', (t) async {
      final pats = [for (final n in [1, 2, 3]) p('K$n', 'CNT/$n/26')];
      final jeu = [for (final x in (d['jeu'] as List)) (x as Map).cast<String, Object?>()];
      await ouvrir(t, petit({'patients': pats, 'constantes': jeu}), 'm1-constantes');
      final k = d['kpis'] as List;
      expect(kpi(t, 'Relevés enregistrés'), (k[0] as List)[1]);
      expect(kpi(t, 'Aujourd’hui'), (k[1] as List)[1]);
      expect(kpi(t, 'Patients suivis'), (k[2] as List)[1]);
      expect(kpi(t, 'Constantes hors bornes'), (k[3] as List)[1]);
      expect(find.textContaining('hors bornes : fréquence respiratoire'), findsWidgets);
    });

    cas('un relevé complet : tension et IMC sont CALCULÉS, la référence suit le registre', (t) async {
      final m = petit({
        'patients': [p('K2', 'CNT/2/26')],
        'constantes': [
          {'id': 'C1', 'statut': 'actif', 'reference': 'CST-00013', 'patientCode': 'CNT/2/26', 'dateHeure': '2026-10-30T08:00'}
        ],
        'audit': []
      });
      await ouvrir(t, m, 'm1-constantes');
      await toucher(t, find.text('Nouveau relevé').last);
      await choisir(t, 'patientCode', 'CNT/2/26 — NOMK2 PreK2');
      await choisir(t, 'moment', 'Midi');
      await saisir(t, 'tensionSys', '12');
      await saisir(t, 'tensionDia', '8');
      await saisir(t, 'poids', '62.5');
      await saisir(t, 'taille', '168');
      await saisir(t, 'releveePar', 'SANNI Bibata');
      await toucher(t, find.text('Créer').last);
      final r = m.collection('constantes').toutes.first;
      expect(r['reference'], 'CST-00014');
      expect(r['tension'], '12/8');
      expect(r['imc'], 22.1);
      expect(r['origine'], 'accueil');
      expect(r['patient'], 'NOMK2 PreK2');
      expect(find.text('Relevé créé.'), findsOneWidget);
    });
  });

  // =========================================================================================================================================
  group('m1-reference et m1-contre-reference', () {
    final d = vecteurs('pat_reference');
    cas('fiches : indicateurs, onglets et contre-référence attendue', (t) async {
      final pats = [for (final n in [1, 2, 3]) p('K$n', 'CNT/$n/26')];
      await ouvrir(
          t,
          petit({
            'patients': pats,
            'fichesReference': [for (final x in (d['jeuRefs'] as List)) (x as Map).cast<String, Object?>()],
            'contreReferences': [for (final x in (d['jeuContre'] as List)) (x as Map).cast<String, Object?>()],
          }),
          'm1-reference');
      final k = (d['reference'] as Map)['kpis'] as List;
      expect(kpi(t, 'Fiches de référence'), (k[0] as List)[1]);
      expect(kpi(t, 'Sans contre-référence'), (k[3] as List)[1]);
      expect(find.textContaining('Reçue le 11/08/2026'), findsWidgets);
      expect(find.text('Attendue'), findsWidgets);
    });

    cas('contre-références : les pourcentages sont des POURCENTAGES (E306)', (t) async {
      await ouvrir(
          t,
          petit({
            'patients': [p('K1', 'CNT/1/26')],
            'fichesReference': [for (final x in (d['jeuRefs'] as List)) (x as Map).cast<String, Object?>()],
            'contreReferences': [for (final x in (d['jeuContre'] as List)) (x as Map).cast<String, Object?>()],
          }),
          'm1-contre-reference');
      expect(norm(indice(t, 'Diagnostics concordants')!), '50.0 % des retours');
      expect(kpi(t, 'Décès au centre d’accueil'), '1');
    });
  });

  // =========================================================================================================================================
  group('m1-pieces', () {
    final d = vecteurs('pat_pieces');
    Magasin jeuPieces() {
      final posees = [for (final x in (d['jeu'] as List)) (x as Map).cast<String, Object?>()];
      final cat = (jsonDecode(File('assets/donnees/jeu/catalogueTarifs.json').readAsStringSync()) as List)
          .map((e) => (e as Map).cast<String, Object?>())
          .toList();
      return petit({
        'patients': [
          p('K1', 'CNT/1/26'),
          p('K2', 'CNT/2/26', {'assureur': 'SOS', 'tauxPriseEnCharge': 80, 'carteExpiration': '2027-12-31'}),
          p('K4', 'CNT/4/26', {'externe': true}),
        ],
        'pieces': posees,
        'factures': [
          {'id': 'F1', 'statut': 'actif', 'numero': 'FC-2026-00001', 'lignes': [{'statutPaiement': 'paye'}], 'reliquat': 0},
          {'id': 'F2', 'statut': 'actif', 'numero': 'FC-2026-00002', 'lignes': [{'statutPaiement': 'du'}], 'reliquat': 7000, 'partPatient': 7000},
        ],
        'catalogueTarifs': cat,
        'personnel': [
          {'id': 'MED', 'statut': 'actif', 'nomComplet': 'BASSONGUI Chabi Séko', 'fonction': 'medecin', 'poste': 'Directeur médical'}
        ],
        'taches': [],
        'audit': []
      });
    }

    cas('indicateurs, onglets et règlement lu sur la pièce de caisse', (t) async {
      await ouvrir(t, jeuPieces(), 'm1-pieces');
      final k = (d['registre'] as Map)['kpis'] as List;
      expect(kpi(t, 'Pièces délivrées'), (k[0] as List)[1]);
      expect(norm(kpi(t, 'Encaissé')), (k[2] as List)[1]);
      expect(norm(kpi(t, 'À encaisser')), (k[3] as List)[1]);
      expect(find.text('Réglé'), findsWidgets);
      expect(find.text('À encaisser'), findsWidgets);
      expect(find.text('Non tarifée'), findsWidgets);
    });

    cas('délivrer un CMVC à un assuré SOS : n° suivant de la série, pièce de caisse couverte au taux du dossier', (t) async {
      final m = jeuPieces();
      await ouvrir(t, m, 'm1-pieces');
      await toucher(t, find.text('Délivrer une pièce').last);
      await choisir(t, 'typeId', 'Certificat médical de visite et de contre-visite');
      await choisir(t, 'patientCode', 'CNT/2/26 — NOMK2 PreK2');
      await choisir(t, 'medecin', 'BASSONGUI Chabi Séko — Directeur médical');
      await toucher(t, find.text('Créer').last);
      final piece = m.collection('pieces').toutes.first;
      expect(piece['numero'], 7);
      expect(piece['reference'], 'CMVC 007/007/CNT/DG/DE/2026');
      expect(piece['montant'], 8000);
      final f = m.collection('factures').toutes.first;
      expect(f['partAssurance'], 6400);
      expect(f['partPatient'], 1600);
      expect(piece['factureNumero'], f['numero']);
      expect(m.collection('taches').toutes.first['statut'], 'en_attente');
    });

    cas('ni dossier ni identité : refus nommé, rien n\'est écrit', (t) async {
      final m = jeuPieces();
      final avant = m.collection('pieces').toutes.length;
      await ouvrir(t, m, 'm1-pieces');
      await toucher(t, find.text('Délivrer une pièce').last);
      await choisir(t, 'typeId', 'Certificat médical de non-infirmité');
      await choisir(t, 'medecin', 'BASSONGUI Chabi Séko — Directeur médical');
      await toucher(t, find.text('Créer').last);
      expect(m.collection('pieces').toutes.length, avant);
      expect(find.textContaining('Choisir un dossier du répertoire'), findsOneWidget);
    });
  });

  // =========================================================================================================================================
  group('m1-externe', () {
    final d = vecteurs('pat_externe');
    cas('le registre dit la cause du verrou : caisse, ou échantillon non parvenu (E309)', (t) async {
      final dem = (Fiche o) => {
            'statut': 'actif', 'patientId': 'E1', 'patientCode': 'CNT/901/26', 'patient': 'EXT1 Un', 'analyse': 'NFS',
            'dateHeure': '2026-08-01T10:00:00.000Z', 'prescripteur': 'Dr Ext', 'origineDemande': 'externe', 'factureId': 'F1', ...o
          };
      await ouvrir(
          t,
          petit({
            'patients': [p('E1', 'CNT/901/26', {'externe': true})],
            'demandesAnalyses': [
              dem({'id': 'D1', 'reference': 'LAB-00001', 'bloqueParPaiement': true, 'etatAnalyse': 'en_attente'}),
              dem({'id': 'D2', 'reference': 'LAB-00002', 'etatAnalyse': 'attente_prelevement', 'dateHeure': '2026-08-02T10:00:00.000Z'}),
              dem({'id': 'D5', 'reference': 'LAB-00005', 'etatAnalyse': 'valide', 'recuLaboLe': 'x', 'dateHeure': '2026-08-05T10:00:00.000Z'}),
            ],
            'demandesImagerie': [],
          }),
          'm1-externe');
      expect(find.text('En attente de caisse'), findsWidgets);
      expect(find.text('Échantillon non parvenu'), findsOneWidget);
      expect(find.text('Résultat rendu'), findsOneWidget);
      expect(kpi(t, 'Demandes externes'), '3');
      expect(kpi(t, 'En attente de caisse'), '1');
      expect(kpi(t, 'Résultats rendus'), '1');
      // La commande de saisie est visible et VERROUILLÉE : elle nomme où la balle se trouve.
      expect(find.byTooltip('Analyse non réglée. Le patient doit passer à la CAISSE ; le biologiste ne saisit qu’un examen payé.'), findsOneWidget);
    });

    cas('transcrire deux analyses : dossier externe, facture à lignes payables, caisse saisie, prélèvement bloqué', (t) async {
      final cat = (d['analysesCatalogue'] as List).cast<Map>().map((e) => e.cast<String, Object?>()).toList();
      final m = Magasin({
        'patients': [for (var i = 0; i < 3; i++) p('x$i', 'CNT/${i + 1}/26')],
        'demandesAnalyses': [],
        'factures': [],
        'taches': [],
        'audit': [],
        'analyses': cat,
      }, 'POSTE', {'analyses': cat});
      await ouvrir(t, m, 'm1-externe');
      await toucher(t, find.text('Nouvelle demande externe').last);
      await saisir(t, 'nom', 'Gado');
      await saisir(t, 'prenom', 'Issa');
      await choisir(t, 'naissanceConnue', 'Inconnue — indiquer l’âge déclaré');
      await saisir(t, 'age', '41');
      await saisir(t, 'telephone', '97000000');
      await saisir(t, 'residence', 'Boriyoure');
      await saisir(t, 'prescripteur', 'Dr HOUNSOU Rémi');
      await choisir(t, 'analyses', 'AKOP');
      // Le panneau d'une liste à cases reste ouvert d'un choix à l'autre : un clic hors du panneau le referme.
      await t.tapAt(const Offset(5, 5));
      await t.pump(const Duration(milliseconds: 300));
      await toucher(t, find.text('Enregistrer et envoyer à la caisse').last);
      final f = m.collection('factures').toutes.first;
      expect(f['numero'], 'FE-2026-00001');
      expect(f['montantTTC'], 2000);
      expect(f['statutPaiement'], 'impayee');
      final pat = m.collection('patients').toutes.first;
      expect(pat['code'], 'CNT/903/26');
      expect(pat['externe'], true);
      expect(pat['age'], 41);
      expect(pat['ageReferenceLe'], '2026-10-30');
      final dm = m.collection('demandesAnalyses').toutes.first;
      expect(dm['bloqueParPaiement'], true);
      expect(dm['reference'], 'LAB-00001');
      expect(m.collection('taches').toutes.map((x) => x['statut']).toSet(), {'en_attente', 'bloque'});
      expect(find.text('Demande enregistrée'), findsOneWidget);
    });
  });

  // =========================================================================================================================================
  group('m1-documents, m1-numerisation et pages-renvoi', () {
    final d = vecteurs('pat_documents');
    cas('indicateurs, fichier déposé ou référencé, poids lisible', (t) async {
      final jeu = [for (final x in (d['jeu'] as List)) (x as Map).cast<String, Object?>()];
      await ouvrir(t, petit({'patients': [p('K1', 'CNT/1/26'), p('K2', 'CNT/2/26')], 'documentsPatient': jeu}), 'm1-documents');
      final k = d['kpis'] as List;
      expect(kpi(t, 'Documents numérisés'), (k[0] as List)[1]);
      expect(kpi(t, 'Validés'), (k[1] as List)[1]);
      expect(kpi(t, 'En attente de validation'), (k[2] as List)[1]);
      expect(kpi(t, 'Dossiers couverts'), (k[3] as List)[1]);
      expect(find.textContaining('JPEG · 3.0 Mo'), findsOneWidget);
      expect(find.textContaining('PNG · 0 Ko'), findsOneWidget);
    });

    cas('retirer un document : motif obligatoire, archivé (RG-14), annulable', (t) async {
      final jeu = [for (final x in (d['jeu'] as List)) (x as Map).cast<String, Object?>()];
      final m = petit({'patients': [p('K1', 'CNT/1/26')], 'documentsPatient': jeu, 'audit': []});
      await ouvrir(t, m, 'm1-documents');
      await toucher(t, find.byTooltip('Retirer du dossier').first);
      expect(find.textContaining('du dossier ?'), findsOneWidget);
      await toucher(t, find.text('Retirer du dossier').last);
      // Sans motif : refusé.
      expect(m.collection('documentsPatient').archivees.where((x) => x['id'] != 'DOC4'), isEmpty);
    });

    cas('la numérisation édite son état d\'avancement', (t) async {
      await ouvrir(t, petit({}), 'm1-numerisation');
      expect(find.text('Lot 3 — Maternité et suivis prénataux'), findsOneWidget);
      expect(find.textContaining('860 / 980 (88 %)'), findsOneWidget);
    });

    cas('une page-renvoi renvoie vers son écran', (t) async {
      await ouvrir(t, petit({}), 'm1-dossier-etendu');
      expect(find.text('Ouvrir les dossiers de consultation'), findsOneWidget);
      await ouvrir(t, petit({}), 'm1-certificats-externes');
      expect(find.text('Ouvrir le registre des certificats'), findsOneWidget);
    });
  });
}
