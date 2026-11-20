// Rejoue `test/vecteurs/aib.json` (prototype_html/build/vecteurs-aib.js : le moteur RÉEL de la maquette, SIGH.baremeAib et SIGH.reglagesAib, horloge figée au
// 16/08/2026 10 h) sur les fonctions pures de `src/comptabilite/aib.dart`, dans l'ORDRE des gestes du script : le barème (taux à la date, situation d'après l'IFU,
// taux proposés), la lecture des réglages à l'état semé, seize gestes enchaînés (refus nommés, charge « acheteur », deux comptes, activation), la liste « ce qu'il
// faudrait écrire », la désactivation datée, l'écriture refusée tant que le branchement n'est pas actif, puis écrite (exactement ce qui est listé), rejouée sans
// doublon.
//
// Quatre MUTATIONS doivent faire tomber ces tests : lire le taux d'une situation sans la date (sans IFU avant/après le 07/09/2026), laisser écrire quand le branchement
// est désactivé (`refusDesactive`), autoriser l'activation sans la charge arrêtée (geste d'activation incomplète), écrire deux fois la même facture (`rejeu`).
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();

const _ignorer = {'creeLe', 'creePar', '_creePar', '_creeLe', 'modifieLe', 'modifiePar', '_modifiePar', '_modifieLe', 'valideLe'};

/// Les comptes posés par le script : un compte de tiers, un compte de fournisseur, un compte ARCHIVÉ (refusé comme absent).
final List<M> _comptes = [
  {'id': 'CPT1', 'statut': 'actif', 'num': '447000', 'libelle': 'Etat impôts retenu à la source'},
  {'id': 'CPT2', 'statut': 'actif', 'num': '401110', 'libelle': 'Fournisseurs'},
  {'id': 'CPT3', 'statut': 'archive', 'num': '411999', 'libelle': 'Compte archivé'},
];

final List<M> _fournisseurs = [
  {'id': 'FO1', 'statut': 'actif', 'code': 'F-IFU', 'nom': 'Fournisseur avec IFU', 'ifu': '3201642748214'},
  {'id': 'FO2', 'statut': 'actif', 'code': 'F-SANS', 'nom': 'Fournisseur sans IFU'},
  {'id': 'FO3', 'statut': 'actif', 'code': 'F-FAUX', 'nom': 'Fournisseur IFU illisible', 'ifu': '123'},
];

M _ff(String id, String ref, String four, String nom, String date, num montant, [String statut = 'actif']) =>
    {'id': id, 'statut': statut, 'reference': ref, 'fournisseur': four, 'fournisseurNom': nom, 'date': date, 'montantFacture': montant};

final List<M> _factures = [
  _ff('FF1', 'FF-A', 'F-IFU', 'Fournisseur avec IFU', '2026-06-10', 100000),
  _ff('FF2', 'FF-B', 'F-SANS', 'Fournisseur sans IFU', '2026-06-10', 100000),
  _ff('FF3', 'FF-C', 'F-SANS', 'Fournisseur sans IFU', '2026-10-10', 100000),
  _ff('FF4', 'FF-D', 'F-IFU', 'Fournisseur avec IFU', '2026-10-10', 250050),
  _ff('FF5', 'FF-E', 'F-SANS', 'Fournisseur sans IFU', '2025-03-10', 100000),
  _ff('FF6', 'FF-F', 'F-FAUX', 'Fournisseur IFU illisible', '2026-06-10', 100000),
  _ff('FF7', 'FF-G', 'F-IFU', 'Fournisseur avec IFU', '2026-07-01', 0),
  _ff('FF8', 'FF-H', 'F-IFU', 'Fournisseur avec IFU', '2026-07-02', 100000, 'archive'),
  _ff('FF9', 'FF-I', 'INCONNU', 'Fournisseur absent du répertoire', '2026-07-03', 100000),
  _ff('FF10', 'FF-J', 'F-IFU', 'Fournisseur avec IFU', '2027-01-05', 100000),
];

void main() {
  final v = lireVecteurs('aib');
  final libelles = obj(lireVecteurs('validation')['libelles']).cast<String, String>();
  const aujourdhui = '2026-08-16';
  String libelleRole(String r) => libelles[r] ?? r;

  final sem = obj(v['semences']);
  final situations = liste(sem['situations']);
  final bareme = liste(sem['bareme']);
  // L'état des réglages : les deux versions semées, puis chaque version créée par un geste (ajout et fermeture de la précédente).
  final reglages = liste(sem['reglages']).map((f) => {...f}).toList();
  List<M> ecritures = [];
  AibDonnees donnees() => AibDonnees(
        situations: situations,
        bareme: bareme,
        reglages: reglages,
        comptes: _comptes,
        fournisseurs: _fournisseurs,
        facturesFournisseurs: _factures,
        ecritures: ecritures,
      );

  test('le vecteur est celui de l’horloge du 16/08/2026', () {
    expect(v['aujourdhui'], aujourdhui);
  });

  test('les définitions et les deux versions semées sont celles de la maquette (aucun compte semé, aucun défaut codé ailleurs)', () {
    memes(aibDefinitionsReglages, v['definitions'], 'definitions');
    final s = liste(sem['reglages']);
    expect(s.length, 2);
    for (var i = 0; i < 2; i++) {
      memes(aibSemencesReglages[i], s[i], 'semence[$i]', ignorer: {'id', 'statut', 'dateFin', 'aValider', 'creeLe', 'creePar'}, sousEnsemble: true);
      expect(s[i]['aValider'], isTrue, reason: 'tous les défauts naissent « à valider »');
    }
    expect(s.any((x) => x['cle'] == 'compteAcompte' || x['cle'] == 'compteContrepartie'), isFalse);
  });

  group('le barème : le taux suit la situation ET la date', () {
    test('taux à la date de chaque situation (refus nommé AIB_SANS_BAREME hors versions, jamais zéro)', () {
      for (final c in liste(v['tauxALaDate'])) {
        memes(aibTauxALaDate(donnees(), '${c['situation']}', '${c['date']}'), c['sortie'], 'taux ${c['situation']} ${c['date']}');
      }
    });
    test('la situation se tire de l’IFU (13 chiffres présumé actif, vide = sans IFU, autre = IFU_INVALIDE) et le taux de la date', () {
      for (final c in liste(v['pourAcheteur'])) {
        memes(aibTauxPourAcheteur(donnees(), ifu: c['ifu'], date: '${c['date']}'), c['sortie'], 'acheteur ${c['ifu']} ${c['date']}');
      }
    });
    test('les taux proposés à la caisse', () {
      for (final c in liste(v['proposes'])) {
        memes(aibTauxProposes(donnees(), ifu: c['ifu'], date: '${c['date']}'), c['sortie'], 'proposes ${c['ifu']} ${c['date']}');
      }
    });
  });

  void lectureAttendue(M c) {
    final d = '${c['date']}';
    memes(aibChargeALaDate(donnees(), d), c['charge'], 'charge $d');
    memes(aibBranchementALaDate(donnees(), d), c['branchement'], 'branchement $d');
    memes(aibReglageALaDate(donnees(), 'compteAcompte', d), c['acompte'], 'acompte $d');
    memes(aibReglageALaDate(donnees(), 'compteContrepartie', d), c['contrepartie'], 'contrepartie $d');
    memes(aibReglageALaDate(donnees(), 'inexistant', d), c['inconnu'], 'inconnu $d');
  }

  int crees = 0;
  /// Un geste : la sortie (refus nommé ou succès), puis l'état des versions APRÈS (la fiche créée et la précédente fermée).
  void geste(M g) {
    final nom = '${g['nom']}';
    final attendu = obj(g['sortie']);
    final apresAttendu = liste(g['versions']);
    final id = 'RAI-${crees + 1}';
    // Le marquage du profil de la famille est celui que la maquette a posé sur la fiche créée (arrêtée par le comptable, la DAF ou l'administrateur).
    final cree = apresAttendu.where((x) => x['id'] == id).toList();
    final marquage = cree.isEmpty
        ? null
        : {for (final k in ['aValider', 'valideLe', 'validePar', 'valideRole']) if (cree.first.containsKey(k)) k: cree.first[k]};
    final r = aibDefinirReglage(donnees(), obj(g['entree']),
        role: '${g['role']}', libelleRole: libelleRole('${g['role']}'), fileul: g['fileul'] == true, id: id, creeLe: aujourdhui, auteur: 'Comptable Vecteur', marquage: marquage);
    memes(r, attendu, nom, ignorer: {'fiche', 'fermeture'});
    if (r['ok'] == true) {
      if (r['fermeture'] != null) {
        final f = obj(r['fermeture']);
        final i = reglages.indexWhere((x) => x['id'] == f['id']);
        reglages[i] = {...reglages[i], 'dateFin': f['dateFin']};
      }
      // Le magasin de la maquette insère EN TÊTE : la dernière version créée est la première de la collection.
      reglages.insert(0, obj(r['fiche']));
      crees++;
    }
    final obtenu = reglages.where((x) => x['statut'] != 'archive').toList();
    memes(obtenu, apresAttendu, '$nom : versions après', ignorer: _ignorer);
  }

  final gestes = liste(v['gestes']);
  final lectures = liste(v['lectures']);
  final achats = obj(v['achats']);

  group('les réglages : la lecture, puis les gestes enchaînés', () {
    test('à l’état semé : charge « clinique » NON ARRÊTÉE (le message le dit), branchement désactivé, comptes sans version (AIB_REGLAGE_SANS_VERSION)', () {
      lectureAttendue(lectures[0]);
      final c = aibChargeALaDate(donnees(), aujourdhui);
      expect(c['valeur'], 'clinique');
      expect(c['arrete'], isFalse);
      expect(c['message'], isNotNull);
      expect(aibBranchementALaDate(donnees(), aujourdhui)['actif'], isFalse);
      expect(aibReglageALaDate(donnees(), 'compteAcompte', aujourdhui)['code'], 'AIB_REGLAGE_SANS_VERSION');
    });

    test('seize gestes : onze refus nommés puis charge, deux comptes, refus de date antérieure, activation (les refus n’écrivent rien)', () {
      for (var i = 0; i < 16; i++) {
        geste(gestes[i]);
      }
      // Les refus ne laissent aucune version : deux semées, quatre créées par les gestes réussis.
      expect(reglages.length, 6);
    });

    test('lectures après les seize gestes : avant l’effet, le jour même, en fin d’année', () {
      for (var i = 1; i <= 3; i++) {
        lectureAttendue(lectures[i]);
      }
      expect(aibBranchementALaDate(donnees(), aujourdhui)['actif'], isTrue);
      expect(aibBranchementALaDate(donnees(), '2026-08-15')['actif'], isFalse, reason: 'la veille de l’effet, le branchement est encore désactivé');
    });
  });

  group('les achats : le taux de chaque ligne suit la situation du fournisseur et la date de la facture', () {
    test('aperçu actif : avec IFU 1 %, sans IFU 1 % avant le 07/09/2026 et 5 % après, IFU illisible refusé, montant arrondi à l’entier, charge portée par ligne', () {
      final c = obj(achats['apercuActif']);
      final e = obj(c['entree']);
      final r = aibAchatsAEcrire(donnees(), du: '${e['du']}', au: '${e['au']}', aujourdhui: aujourdhui);
      memes(r, c['sortie'], 'apercuActif');
      final l = (r['lignes'] as List).cast<M>();
      expect(l.firstWhere((x) => x['reference'] == 'FF-D')['aib'], 2501, reason: '250 050 × 1 % = 2 500,5 arrondi à 2 501');
      expect(l.firstWhere((x) => x['reference'] == 'FF-C')['taux'], 5);
      expect(l.firstWhere((x) => x['reference'] == 'FF-B')['taux'], 1);
    });

    test('une facture antérieure à tout barème est refusée en le nommant (AIB_SANS_BAREME), sans taux ni montant : jamais zéro', () {
      final c = obj(achats['apercuAvant2026']);
      final e = obj(c['entree']);
      final r = aibAchatsAEcrire(donnees(), du: '${e['du']}', au: '${e['au']}', aujourdhui: aujourdhui);
      memes(r, c['sortie'], 'apercuAvant2026');
      final l = (r['lignes'] as List).cast<M>().single;
      expect(l['refus'], 'AIB_SANS_BAREME');
      expect(l.containsKey('aib'), isFalse);
    });
  });

  group('le branchement : désactivé il n’écrit rien, activé il n’écrit que ce qui est listé', () {
    test('geste 17 : la désactivation datée du 01/12/2026 ferme la version précédente à la veille', () {
      geste(gestes[16]);
    });

    test('désactivé : la liste est un APERÇU, écrire est REFUSÉ (AIB_BRANCHEMENT_DESACTIVE) et le journal des écritures ne bouge pas', () {
      final a = obj(achats['apercuDesactive']);
      memes(aibAchatsAEcrire(donnees(), du: '2026-01-01', au: '2026-12-31', aujourdhui: aujourdhui), a['sortie'], 'apercuDesactive');
      final c = obj(achats['refusDesactive']);
      final r = aibEcrireAchats(donnees(), du: '2026-01-01', au: '2026-12-31', aujourdhui: aujourdhui, role: 'comptable', libelleRole: libelleRole('comptable'));
      memes(r, c['sortie'], 'refusDesactive', ignorer: {'lignesEcritures'});
      expect(r['code'], 'AIB_BRANCHEMENT_DESACTIVE');
      expect(r.containsKey('lignesEcritures'), isFalse);
      expect(liste(c['ecritures']), isEmpty);
    });

    test('un profil hors famille ne l’écrit pas (AIB_ECRITURE_RESERVEE), même si le branchement est actif', () {
      final c = obj(achats['refusRole']);
      final r = aibEcrireAchats(donnees(), du: '2026-01-01', au: '2026-11-30', aujourdhui: aujourdhui, role: 'caissier', libelleRole: libelleRole('caissier'));
      memes(r, c['sortie'], 'refusRole');
      expect(liste(c['ecritures']), isEmpty);
    });

    test('actif : écrit EXACTEMENT les pièces listées, deux lignes équilibrées (RG-10) en brouillon par facture ; rejoué, n’en pose aucune de plus', () {
      final c = obj(achats['ecriture']);
      final e = obj(c['entree']);
      final avant = aibAchatsAEcrire(donnees(), du: '${e['du']}', au: '${e['au']}', aujourdhui: aujourdhui);
      expect(avant['ecrire'], isTrue);
      final r = aibEcrireAchats(donnees(), du: '${e['du']}', au: '${e['au']}', aujourdhui: aujourdhui, role: 'comptable', libelleRole: libelleRole('comptable'));
      memes(r, c['sortie'], 'ecriture', ignorer: {'lignesEcritures'});
      final posees = (r['lignesEcritures'] as List).cast<M>();
      // Même ordre d'insertion en tête : la dernière écriture posée est la première de la collection de la maquette.
      memes(posees.reversed.toList(), liste(c['ecritures']), 'ecritures', ignorer: _ignorer);
      // Ce qui est écrit est ce qui était listé : mêmes références, dans le même ordre, pas une de plus.
      final listees = (avant['lignes'] as List).cast<M>().where((l) => l['refus'] == null && l['ecriteSous'] == null && (l['aib'] as num) > 0).map((l) => l['reference']).toList();
      expect((r['pieces'] as List).map((p) => obj(p)['numero'].toString().substring(4)).toList(), listees);
      // RG-10 : par pièce, débit = crédit, et jamais un débit ET un crédit sur la même ligne.
      final parPiece = <String, List<M>>{};
      for (final l in posees) {
        (parPiece['${l['numero']}'] ??= []).add(l);
        expect((l['debit'] as num) == 0 || (l['credit'] as num) == 0, isTrue);
        expect(l['statut'], 'brouillon');
      }
      for (final l in parPiece.values) {
        expect(l.length, 2);
        expect(l.fold<num>(0, (s, x) => s + (x['debit'] as num)), l.fold<num>(0, (s, x) => s + (x['credit'] as num)));
      }
      ecritures = [...ecritures, ...posees];
      final j = obj(achats['rejeu']);
      final r2 = aibEcrireAchats(donnees(), du: '${e['du']}', au: '${e['au']}', aujourdhui: aujourdhui, role: 'comptable', libelleRole: libelleRole('comptable'));
      expect((r2['pieces'] as List).length, obj(j['sortie'])['pieces']);
      expect(ecritures.length, j['nbEcritures']);
    });

    test('une fois écrit, l’aperçu n’a plus rien à écrire (chaque facture porte sa pièce)', () {
      final c = obj(achats['apercuApresEcriture']);
      final e = obj(c['entree']);
      final r = aibAchatsAEcrire(donnees(), du: '${e['du']}', au: '${e['au']}', aujourdhui: aujourdhui);
      memes(r, c['sortie'], 'apercuApresEcriture');
      expect(r['aEcrire'], 0);
    });
  });

  test('une version de réglage ne se réécrit pas : valeur, réglage et date d’effet sont figés', () {
    final avant = reglages.first;
    expect(aibVersionFigee(avant, {...avant, 'valeur': 'acheteur'}), startsWith('AIB_VERSION_FIGEE'));
    expect(aibVersionFigee(avant, {...avant, 'dateEffet': '2026-02-01'}), startsWith('AIB_VERSION_FIGEE'));
    expect(aibVersionFigee(avant, {...avant, 'dateFin': '2026-08-15', 'modifiePar': 'x'}), isNull, reason: 'la fermeture à la veille reste possible');
    expect(obj(v['versionFigee'])['valeurApres'], isTrue);
  });

  test('l’arrondi à l’entier est celui de la caisse (moitié vers le haut)', () {
    expect(aibDivArrondi(250050, 100), 2501);
    expect(aibDivArrondi(100000 * 5, 100), 5000);
    expect(aibVeille('2026-01-01'), '2025-12-31');
    expect(aibVeille('2026-03-01'), '2026-02-28');
  });
}
