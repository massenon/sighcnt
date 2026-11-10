import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/aib_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';

/// Lot L2 : l'AIB au poste. Les règles sont au domaine (rejouées sur les vecteurs de la maquette, `packages/domaine/test/aib_test.dart`) ; ici le BRANCHEMENT au
/// magasin du poste : le registre des paramètres tient les quatre réglages, le contrôle refuse en nommant, le branchement désactivé n'écrit RIEN, activé il n'écrit
/// que ce que l'aperçu liste, une seule fois, en brouillon et équilibré.
typedef M = Map<String, Object?>;

Magasin _magasin() {
  final m = Magasin({
    'utilisateurs': <M>[],
    'audit': <M>[],
    'comptes': <M>[
      {'id': 'C1', 'statut': 'actif', 'num': '447000', 'libelle': 'Etat impôts retenu à la source'},
      {'id': 'C2', 'statut': 'actif', 'num': '401110', 'libelle': 'Fournisseurs'},
    ],
    'fournisseurs': <M>[
      {'id': 'F1', 'statut': 'actif', 'code': 'F-IFU', 'nom': 'Fournisseur avec IFU', 'ifu': '3201642748214'},
      {'id': 'F2', 'statut': 'actif', 'code': 'F-SANS', 'nom': 'Fournisseur sans IFU'},
    ],
    'facturesFournisseurs': <M>[
      {'id': 'FF1', 'statut': 'actif', 'reference': 'FF-A', 'fournisseur': 'F-IFU', 'fournisseurNom': 'Fournisseur avec IFU', 'date': '2026-06-10', 'montantFacture': 100000},
      {'id': 'FF2', 'statut': 'actif', 'reference': 'FF-B', 'fournisseur': 'F-SANS', 'fournisseurNom': 'Fournisseur sans IFU', 'date': '2026-06-10', 'montantFacture': 100000},
      {'id': 'FF3', 'statut': 'actif', 'reference': 'FF-C', 'fournisseur': 'F-SANS', 'fournisseurNom': 'Fournisseur sans IFU', 'date': '2026-10-10', 'montantFacture': 100000},
    ],
    'ecritures': <M>[],
  });
  serviceParametres(m, auteur: () => 'Poste mère').semerDefauts();
  return m;
}

AibPoste _aib(Magasin m, {String role = 'comptable', bool fileul = false, String jour = '2026-11-09'}) {
  final d = DateTime.parse(jour);
  return AibPoste(m, auteur: () => 'Comptable de test', role: role, libelleRole: role, fileul: fileul, horloge: () => d);
}

void main() {
  const pref = 'bareme_aib.';

  test('le barème est semé en mémoire, une seule fois : trois situations, quatre versions, toutes « à valider »', () {
    final m = _magasin();
    AibPoste.amorcer(m);
    AibPoste.amorcer(m);
    expect(m.collection('situationsAib').toutes.length, 3);
    expect(m.collection('baremeAib').toutes.length, 4);
    expect(m.collection('baremeAib').toutes.every((f) => f['aValider'] == true), isTrue);
  });

  test('départ : charge « clinique » non arrêtée, branchement désactivé, aucun compte ; l’aperçu liste sans rien écrire et écrire est refusé', () {
    final m = _magasin();
    final a = _aib(m);
    final d = a.donnees();
    expect(aibChargeALaDate(d, '2026-11-09')['arrete'], isFalse);
    expect(aibBranchementALaDate(d, '2026-11-09')['actif'], isFalse);
    final ap = a.apercu(du: '2026-01-01', au: '2026-12-31');
    expect(ap['ecrire'], isFalse);
    final taux = {for (final l in (ap['lignes'] as List).cast<M>()) l['reference']: l['taux']};
    expect(taux, {'FF-A': 1, 'FF-B': 1, 'FF-C': 5}, reason: 'le taux suit la situation du fournisseur et la date de la facture');
    final r = a.ecrire(du: '2026-01-01', au: '2026-12-31');
    expect(r['code'], 'AIB_BRANCHEMENT_DESACTIVE');
    expect(m.collection('ecritures').toutes, isEmpty);
  });

  test('le contrôle refuse en nommant : hors famille, fileul, compte hors plan, motif absent, activation incomplète', () {
    final m = _magasin();
    expect(_aib(m, role: 'direction').controlerReglage('${pref}chargePrelevement', 'acheteur', '2026-11-09', 'Essai')!['code'], 'AIB_ECRITURE_RESERVEE');
    expect(_aib(m, fileul: true).controlerReglage('${pref}chargePrelevement', 'acheteur', '2026-11-09', 'Essai')!['code'], 'AIB_POSTE_FILEUL');
    expect(_aib(m).controlerReglage('${pref}compteAcompte', '999999', '2026-11-09', 'Essai')!['code'], 'AIB_COMPTE_INCONNU');
    expect(_aib(m).controlerReglage('${pref}chargePrelevement', 'acheteur', '2026-11-09', '  ')!['code'], 'AIB_MOTIF_ABSENT');
    final inc = _aib(m).controlerReglage('${pref}branchementAchats', 'actif', '2026-11-09', 'Essai')!;
    expect(inc['code'], 'AIB_BRANCHEMENT_INCOMPLET');
    expect((inc['manque'] as List).length, 3);
    // Une clé qui n'est pas de la famille AIB n'est pas contrôlée ici.
    expect(_aib(m).controlerReglage('planning.circuitPresences', 'daf', '2026-11-09', null), isNull);
  });

  test('activé : écrit EXACTEMENT ce qui est listé, une pièce équilibrée en brouillon par facture, rien de plus, une seule fois', () {
    final m = _magasin();
    final a = _aib(m);
    final s = a.service;
    for (final x in [('chargePrelevement', 'acheteur'), ('compteAcompte', '447000'), ('compteContrepartie', '401110')]) {
      expect(a.controlerReglage('$pref${x.$1}', x.$2, '2026-11-01', 'Choix du comptable'), isNull);
      expect(s.regler('$pref${x.$1}', x.$2, '2026-11-01', motif: 'Choix du comptable').ok, isTrue);
    }
    expect(a.controlerReglage('${pref}branchementAchats', 'actif', '2026-11-01', 'Branchement'), isNull);
    expect(s.regler('${pref}branchementAchats', 'actif', '2026-11-01', motif: 'Branchement').ok, isTrue);
    final ap = a.apercu(du: '2026-01-01', au: '2026-12-31');
    expect(ap['ecrire'], isTrue);
    final r = a.ecrire(du: '2026-01-01', au: '2026-12-31');
    expect(r['ok'], isTrue);
    expect((r['pieces'] as List).map((p) => (p as Map)['numero']).toList(), ['AIB-FF-A', 'AIB-FF-B', 'AIB-FF-C']);
    final ecr = m.collection('ecritures').toutes;
    expect(ecr.length, 6);
    expect(ecr.every((e) => e['statut'] == 'brouillon'), isTrue);
    final debit = ecr.fold<num>(0, (t, e) => t + (e['debit'] as num));
    final credit = ecr.fold<num>(0, (t, e) => t + (e['credit'] as num));
    expect(debit, credit, reason: 'RG-10 : débit égal crédit');
    expect(debit, 1000 + 1000 + 5000);
    expect(ecr.firstWhere((e) => e['numero'] == 'AIB-FF-C' && (e['debit'] as num) > 0)['compte'], '447000');
    // Rejoué : aucune pièce de plus.
    expect((a.ecrire(du: '2026-01-01', au: '2026-12-31')['pieces'] as List), isEmpty);
    expect(m.collection('ecritures').toutes.length, 6);
    // Le geste est au journal (RG-12).
    expect(m.collection('audit').toutes.any((e) => e['action'] == 'AIB sur achats écrit'), isTrue);
    // Un profil hors famille n'écrit pas, même branchement actif.
    expect(_aib(m, role: 'caissier').ecrire(du: '2026-01-01', au: '2026-12-31')['code'], 'AIB_ECRITURE_RESERVEE');
  });
}
