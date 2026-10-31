import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_mobile/main.dart';
import 'package:sigh_mobile/moteur/moteur_mobile.dart';

class FauxMoteur implements MoteurMobile {
  FauxMoteur({this.refus});
  final String? refus;
  @override
  ProfilMobile? profil;
  @override
  final ValueNotifier<EtatMobile> etat = ValueNotifier(const EtatMobile(horsLigne: true));
  final List<FichePatient> lot = [const FichePatient(id: 'p1', champs: {'nom': 'DOSSOU', 'prenom': 'Aline', 'code': 'CNT/12/26', 'quartier': 'Kouba'})];
  final List<FichePatient> crees = [];
  final List<(String, Map<String, Object?>)> constantes = [];
  String? codeAppairage;

  @override
  Future<void> appairer({required String code, required String cleClinique, required ProfilMobile profil}) async {
    if (refus != null) throw StateError(refus!);
    codeAppairage = code;
    this.profil = profil;
  }

  @override
  Future<List<FichePatient>> tournee() async => lot;
  @override
  Future<List<FichePatient>> dossiersCrees() async => crees;
  @override
  Future<String> creerPatient(Map<String, Object?> champs) async {
    crees.add(FichePatient(id: 'n${crees.length}', champs: champs));
    etat.value = EtatMobile(horsLigne: true, enAttente: crees.length);
    return 'n${crees.length - 1}';
  }

  @override
  Future<void> enregistrerConstantes(String patientId, Map<String, Object?> c) async => constantes.add((patientId, c));
}

void main() {
  testWidgets('appairage : champs obligatoires, refus affiché tel quel, puis l\'accueil du profil choisi', (t) async {
    final m = FauxMoteur();
    await t.pumpWidget(SighMobile(moteur: m));
    await t.tap(find.byKey(const Key('appairer')));
    await t.pump();
    expect(find.text('Le code d’appairage et la clé de clinique sont obligatoires.'), findsOneWidget);

    await t.enterText(find.byKey(const Key('code')), 'abcd2345');
    await t.enterText(find.byKey(const Key('cle')), 'Y2xl');
    await t.tap(find.text('Réception de secours'));
    await t.pump();
    await t.tap(find.byKey(const Key('appairer')));
    await t.pumpAndSettle();
    expect(m.codeAppairage, 'ABCD2345');
    expect(m.profil, ProfilMobile.receptionSecours);
    expect(find.text('Réception de secours'), findsWidgets);
  });

  testWidgets('appairage refusé par la mère : la cause s\'affiche, on reste sur l\'écran', (t) async {
    await t.pumpWidget(SighMobile(moteur: FauxMoteur(refus: 'code_invalide')));
    await t.enterText(find.byKey(const Key('code')), 'X');
    await t.enterText(find.byKey(const Key('cle')), 'Y');
    await t.tap(find.byKey(const Key('appairer')));
    await t.pumpAndSettle();
    expect(find.textContaining('code_invalide'), findsOneWidget);
    expect(find.byKey(const Key('appairer')), findsOneWidget);
  });

  testWidgets('soignant : tournée du lot, constantes saisies, refus nommé d\'un nombre faux', (t) async {
    final m = FauxMoteur()..profil = ProfilMobile.soignant;
    await t.pumpWidget(SighMobile(moteur: m));
    await t.pumpAndSettle();
    expect(find.text('Ma tournée'), findsOneWidget);
    expect(find.textContaining('Hors ligne'), findsOneWidget);
    expect(find.text('DOSSOU Aline'), findsOneWidget);
    expect(find.text('Réception de secours'), findsNothing);

    await t.tap(find.byKey(const Key('patient-p1')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('champ-temperature')), 'chaud');
    await t.tap(find.byKey(const Key('enregistrer')));
    await t.pump();
    expect(find.text('« temperature » doit être un nombre.'), findsOneWidget);
    expect(m.constantes, isEmpty);

    await t.enterText(find.byKey(const Key('champ-temperature')), '38,5');
    await t.enterText(find.byKey(const Key('champ-tension')), '12/8');
    await t.tap(find.byKey(const Key('enregistrer')));
    await t.pumpAndSettle();
    expect(m.constantes.single.$1, 'p1');
    expect(m.constantes.single.$2, {'temperature': 38.5, 'tension': '12/8'});
  });

  testWidgets('réception de secours : dossier visible AUSSITÔT, compteur « en attente », contrôles du formulaire', (t) async {
    final m = FauxMoteur()..profil = ProfilMobile.receptionSecours;
    await t.pumpWidget(SighMobile(moteur: m));
    await t.pumpAndSettle();
    expect(find.text('Ma tournée'), findsNothing);

    await t.tap(find.byKey(const Key('creer')));
    await t.pump();
    expect(find.text('Le nom et le prénom sont obligatoires.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('nom')), 'AKPO');
    await t.enterText(find.byKey(const Key('prenom')), 'Marc');
    await t.enterText(find.byKey(const Key('age')), '200');
    await t.tap(find.byKey(const Key('creer')));
    await t.pump();
    expect(find.text('L’âge déclaré est obligatoire (0 à 120 ans).'), findsOneWidget);
    expect(m.crees, isEmpty);

    await t.enterText(find.byKey(const Key('age')), '34');
    await t.tap(find.byKey(const Key('creer')));
    await t.pumpAndSettle();
    expect(m.crees.single.champs['origine'], 'reception_secours');
    expect(find.text('AKPO Marc'), findsOneWidget);
    expect(find.text('en attente de numéro'), findsOneWidget);
    expect(find.textContaining('1 en attente d’envoi'), findsOneWidget);
  });

  test('le moteur réel (sigh_sync) s\'instancie dans l\'application : non appairé, rien en attente, aucun profil', () async {
    final m = MoteurMobileSync.creer(dbChemin: ':memory:', relais: 'http://127.0.0.1:1');
    expect(m.profil, isNull);
    await m.actualiser();
    expect(m.etat.value.appaire, isFalse);
    expect(m.etat.value.enAttente, 0);
    expect(m.etat.value.suspendu, isFalse);
    m.arreter();
  });
}
