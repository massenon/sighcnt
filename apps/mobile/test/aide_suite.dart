// Aides des tests de la suite du mobile (CPN, CPoN, surveillance, orientation, réglages, lot, code PIN) : un faux moteur qui offre aussi les
// extensions (source, agent, appareil, rafraîchissement, réinitialisation), et des lots de démonstration pour la sage-femme et la réception.
import 'package:sigh_mobile/moteur/moteur_mobile.dart';

import 'aide_mobile.dart';

class FauxMoteurSuite extends FauxMoteur implements ExtensionsMobile {
  FauxMoteurSuite({super.fonction, super.source, super.agent, this.agentReception = 'OROU YO Edmond'});
  final String agentReception;
  int rafraichissements = 0;
  bool reinitialise = false;
  String? uuid = 'u-test-01';

  @override
  String get agent => profil == ProfilMobile.soignant ? super.agent : agentReception;

  @override
  Future<String?> appareil() async => uuid;

  @override
  Future<void> actualiser() async => rafraichissements++;

  @override
  Future<void> reinitialiserAppairage() async {
    reinitialise = true;
    profil = null;
  }
}

/// Le lot de la sage-femme au 31/10/2026 : SOUROU (31 ans, CPN 3), KPOGNON (29 ans, post-partum J5), DOSSOU (67 ans : l'âge à risque se signale).
SourceMemoire lotSageFemme() => SourceMemoire({
      'patients': [
        const LigneLot('p4', {'code': 'CNT/913/25', 'nom': 'SOUROU', 'prenom': 'Mariam', 'quartier': 'Winké', 'ageDeclare': 31}),
        const LigneLot('p2', {'code': 'CNT/174/26', 'nom': 'KPOGNON', 'prenom': 'Rose', 'quartier': 'Péporiyakou', 'ageDeclare': 29}),
        const LigneLot('p1', {'code': 'CNT/12/26', 'nom': 'DOSSOU', 'prenom': 'Aline', 'quartier': 'Kouba', 'ageDeclare': 67}),
      ],
      'rendezvous': [
        const LigneLot('r1', {'patientId': 'p4', 'date': '2026-10-31T09:30', 'statut': 'planifiee', 'type': 'Domicile', 'motif': 'CPN 3, 28 SA'}),
      ],
    })
      ..fin = DateTime(2026, 10, 31, 20).millisecondsSinceEpoch;

/// La réception de secours : deux dossiers ouverts à l'accueil (l'un porte un numéro provisoire), plus un patient du poste qui n'est pas un dossier de secours.
SourceMemoire accueilDeSecours() => SourceMemoire({
      'patients': [
        const LigneLot('d1', {'code': 'CNT/1241/26', 'nom': 'AKPO', 'prenom': 'Marc', 'ageDeclare': 34, 'origine': 'reception_secours'}),
        const LigneLot('d2', {'code': 'PROV-1', 'nom': 'HOUNKPATIN', 'prenom': 'Ida', 'ageDeclare': 22, 'origine': 'reception_secours'}),
        const LigneLot('x1', {'code': 'CNT/12/26', 'nom': 'DOSSOU', 'prenom': 'Aline', 'ageDeclare': 67}),
      ],
    });
