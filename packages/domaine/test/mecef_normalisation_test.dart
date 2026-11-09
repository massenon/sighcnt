// Contrôles qui précèdent la normalisation d'une vente (E2299). Port de la DÉCISION de la maquette, sans appareil : éprouvé ici, pas par vecteurs.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> vente([Map<String, Object?> sup = const {}]) => {
      'id': 'F1',
      'numero': 'FC-2026-00001',
      'montantTTC': 10000,
      'montantPaye': 10000,
      'lignes': [
        {'id': 'L1', 'designation': 'Consultation', 'quantite': 1, 'prixUnitaire': 10000, 'partAssureur': 0, 'partPatient': 10000, 'statutPaiement': 'paye'}
      ],
      ...sup,
    };

void main() {
  group('preparerNormalisation', () {
    test('une vente encaissée est préparée : acheteur par défaut, montants entiers', () {
      final p = preparerNormalisation(vente());
      expect(p.ok, isTrue);
      expect(p.acheteur!.aibTaux, 1);
      expect(p.montants!.base, 10000);
      expect(p.montants!.aib, 100);
      expect(p.montants!.net, 10100);
    });
    test('l\'acheteur de la pièce, sinon celui de la fenêtre', () {
      final p = preparerNormalisation(vente({'ifuClient': '3201642748214', 'acheteurNom': 'Clinique X', 'aibTaux': 5}));
      expect(p.acheteur!.ifu, '3201642748214');
      expect(p.acheteur!.aibTaux, 5);
      final q = preparerNormalisation(vente({'ifuClient': '3201642748214', 'acheteurNom': 'Clinique X'}),
          acheteurSaisi: {'ifu': '', 'nom': 'Particulier', 'aibTaux': 0});
      expect(q.acheteur!.ifu, isNull);
      expect(q.acheteur!.aibTaux, 0);
    });
    test('refus nommés, dans l\'ordre', () {
      expect(preparerNormalisation(vente({'proforma': true})).refus!.code, 'PROFORMA');
      expect(preparerNormalisation(vente({'montantPaye': 0})).refus!.code, 'VENTE_NON_ENCAISSEE');
      expect(preparerNormalisation(vente({'statutMecef': 'valide', 'numeroMecef': 'MECEF2000001'})).refus!.code, 'DEJA_NORMALISEE');
      expect(preparerNormalisation(vente(), acheteurSaisi: {'ifu': '12', 'nom': 'X'}).refus!.code, 'IFU_INVALIDE');
      expect(preparerNormalisation(vente({'montantTTC': 10001})).refus!.code, 'TOTAL_INCOHERENT');
      expect(preparerNormalisation(vente({'lignes': [{'id': 'L1', 'designation': 'x', 'quantite': 1, 'prixUnitaire': 1500.5}], 'montantTTC': 1500})).refus!.code, 'PRIX_DECIMAL');
    });
    test('mode désactivé : rien à normaliser, sans refus', () {
      final p = preparerNormalisation(vente(), modeDesactive: true);
      expect(p.ignore, isTrue);
      expect(p.ok, isFalse);
      expect(p.refus, isNull);
    });
    test('un numéro sans état normalisé ne bloque pas : seule une pièce normalisée ne se renormalise pas', () {
      expect(preparerNormalisation(vente({'statutMecef': 'en_attente', 'numeroMecef': 'MECEF2000001'})).ok, isTrue);
    });
  });

  test('un numéro simulé n\'est jamais déjà porté', () {
    expect(numeroMecefLibre(2000001, {'MECEF2000001', 'MECEF2000002'}), 'MECEF2000003');
    expect(numeroMecefLibre(2000001, {}), 'MECEF2000001');
  });

  group('refusRetransmission', () {
    test('jamais une vente normalisée', () {
      expect(refusRetransmission({'statutMecef': 'valide', 'numeroMecef': 'M'}, 'da')!.code, 'DEJA_NORMALISEE');
    });
    test('une vente à vérifier se reprend, elle ne se retransmet pas', () {
      expect(refusRetransmission({'statutMecef': 'a_verifier'}, 'da')!.code, 'PAS_RETRANSMISSIBLE');
    });
    test('le caissier une fois, puis la DA', () {
      expect(refusRetransmission({'statutMecef': 'rejete'}, 'caissier'), isNull);
      expect(refusRetransmission({'statutMecef': 'rejete', 'retransmissions': 1}, 'caissier')!.code, 'RETRANSMISSION_RESERVEE');
      expect(refusRetransmission({'statutMecef': 'rejete', 'retransmissions': 1}, 'da'), isNull);
    });
    test('les autres rôles sont refusés', () {
      expect(refusRetransmission({'statutMecef': 'expiree'}, 'medecin')!.code, 'RETRANSMISSION_INTERDITE');
    });
  });
}
