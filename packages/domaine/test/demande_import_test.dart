import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';
import 'import_test.dart' show MagasinMemoire, matriceReelle, profilDe;

/// LA DEMANDE D'IMPORT D'UN FILEUL À LA MÈRE (lot IMP-C, réponse Q5) : un référentiel de configuration (famille R) importé à un fileul passe par une demande vérifiée ; la mère
/// REJOUE l'analyse sous le rôle de l'auteur, applique par le chemin de l'import local ou refuse en nommant. Les fichiers sont ceux que la maquette a écrits et mesurés.
void main() {
  final V = lireVecteurs('import');
  final magasinInitial = (V['magasin'] as Map).cast<String, Object?>();
  List<List<Object?>> lignesDuCas(String id) {
    final c = liste(V['cas']).firstWhere((x) => x['id'] == id);
    return [
      for (final l in (c['lignes'] as List)) [for (final x in (l as List)) x]
    ];
  }

  /// Ce que le FILEUL fait : vérifier le fichier sur SON magasin, puis composer la demande (un fichier refusé ne part jamais).
  Map<String, Object?> deposer(String cas, String role, {String par = 'GESTIONNAIRE TEST', Map<String, Object?>? magasin}) {
    final jeu = jeuImportParId('${liste(V['cas']).firstWhere((x) => x['id'] == cas)['jeu']}')!;
    final port = MagasinMemoire(magasin ?? magasinInitial, profil: profilDe(role))..utilisateurFixe = par;
    final a = analyserLignes(jeu, lignesDuCas(cas), '$cas.xlsx', port)..empreinte = 'abc';
    expect(a.accepte, isTrue, reason: 'le fileul n\'envoie que ce qu\'il a vérifié');
    return composerDemandeImport(
        id: 'DIM1', jeu: jeu, analyse: a, role: role, par: par, jour: '2026-11-01', restreint: matriceReelle.declaration(jeu.id)!.restreint);
  }

  VerdictDemandeImport lamere(Map<String, Object?> demande, MagasinMemoire mere) {
    mere
      ..profil = profilDe('${demande['demandeRole']}')
      ..utilisateurFixe = '${demande['demandePar']}';
    return traiterDemandeImport(demande, mere, jeuImportParId);
  }

  test('QUAND : un jeu passe par une demande quand une de ses collections cibles est de configuration (famille R), jamais pour l\'activité', () {
    final config = {...cfbEssentielles, 'utilisateurs'};
    for (final jeu in ['assureurs', 'plan-comptable', 'fournisseurs', 'souscripteurs', 'analyses-modele']) {
      expect(jeuExigeLaMere(matriceReelle.declaration(jeu)!, config), isTrue, reason: jeu);
    }
    for (final jeu in ['patients', 'soldes-ouverture']) {
      expect(jeuExigeLaMere(matriceReelle.declaration(jeu)!, config), isFalse, reason: '$jeu s\'écrit au fileul, par ses propres règles de fusion');
    }
    // UN JEU RESTREINT n'y passe jamais : ses lignes (identité, salaire) ne voyagent pas dans une fiche partagée ; il s'importe à la mère.
    final personnel = matriceReelle.declaration('personnel')!;
    expect(personnel.restreint && personnel.collections.any(config.contains), isTrue, reason: 'le personnel est de configuration ET restreint');
    expect(jeuExigeLaMere(personnel, config), isFalse);
    expect(jeuReserveALaMere(personnel, config), isTrue);
    expect(jeuReserveALaMere(matriceReelle.declaration('assureurs')!, config), isFalse);
  });

  test('LE FILEUL DÉPOSE une fiche vérifiée : jeu, fichier, lignes, comptes, rôle et nom de l\'auteur, état « en attente » ; elle porte les lignes que la mère rejouera', () {
    final d = deposer('as-valide', 'comptable');
    expect(d['etat'], demandeImportEnAttente);
    expect([d['jeu'], d['demandeRole'], d['demandePar'], d['aEcrire'], d['nbLignes']], ['assureurs', 'comptable', 'GESTIONNAIRE TEST', 2, 2]);
    expect((d['lignes'] as List).length, 3, reason: 'l\'en-tête et les deux lignes du fichier');
    expect(d['restreint'], isFalse);
    expect(jsonEncode(d), contains('SUNU'));
  });

  test('LA MÈRE REJOUE puis APPLIQUE par le chemin de l\'import local : le lot est signé de l\'auteur, annulable, et les lignes de la demande sont effacées', () {
    final mere = MagasinMemoire(magasinInitial);
    final d = deposer('as-valide', 'comptable');
    final v = lamere(d, mere);
    expect(v.appliquee, isTrue, reason: '${v.motif}');
    expect([v.lot, v.ecrits], ['IMP-2026-001', 2]);
    final assureurs = mere.actives('assureurs').where((a) => a['lotImport'] == 'IMP-2026-001').toList();
    expect(assureurs.map((a) => a['code']).toSet(), {'SUNU', 'OLEA'});
    expect(assureurs.every((a) => a['validePar'] == 'GESTIONNAIRE TEST'), isTrue, reason: 'RG-12 : le lot est au nom de l\'auteur de la demande, pas de la mère');
    final lot = mere.parId(collectionLots, mere.toutes(collectionLots).first['id'])!;
    expect([lot['etat'], lot['par']], ['applique', 'GESTIONNAIRE TEST']);
    final champs = v.versChamps(traitePar: 'Mère', traiteLe: '2026-11-01');
    expect(champs['etat'], demandeImportAppliquee);
    expect(champs['lignes'], isEmpty, reason: 'aucune valeur de cellule ne reste à la demande une fois le verdict rendu');
    expect(champs['resultatLot'], 'IMP-2026-001');
  });

  test('LA MÈRE REJOUE VRAIMENT : une fiche créée par un autre poste entre-temps refuse la demande en nommant le code, le motif et le geste (rien n\'est écrit)', () {
    final d = deposer('as-valide', 'comptable');
    final mere = MagasinMemoire(magasinInitial);
    mere.inserer('assureurs', {'code': 'SUNU', 'nom': 'SUNU ASSURANCES (créé ailleurs)', 'statut': 'actif'});
    final avant = mere.toutes('assureurs').length;
    final v = lamere(d, mere);
    expect(v.appliquee, isFalse);
    expect(v.code, 'DOUBLON_MAGASIN');
    expect(v.motif, allOf(contains('rejoué à la mère'), contains('ligne 2')));
    expect(v.geste, isNotEmpty);
    expect(mere.toutes('assureurs').length, avant, reason: 'rien n\'a été écrit');
    expect(mere.toutes(collectionLots).single['etat'], 'refuse', reason: 'le fichier refusé est consigné à l\'historique de la mère');
    final champs = v.versChamps(traitePar: 'Mère', traiteLe: '2026-11-01');
    expect([champs['etat'], champs['resultatCode']], [demandeImportRefusee, 'DOUBLON_MAGASIN']);
    expect(champs['lignes'], isEmpty);
  });

  test('LA MÈRE RELIT LE DROIT : un rôle qui ne détient pas le jeu voit sa demande refusée en nommant, même déposée par un fileul qui a contourné son bouton', () {
    // Le caissier n'a aucun droit sur les compagnies : une demande forgée (`demandeRole: caissier`) est refusée par la mère, rien n'est écrit.
    final d = {...deposer('as-valide', 'comptable'), 'demandeRole': 'caissier'};
    final mere = MagasinMemoire(magasinInitial);
    final avant = mere.toutes('assureurs').length;
    final v = lamere(d, mere);
    expect([v.appliquee, v.code], [false, 'DROIT_IMPORT_REFUSE']);
    expect(v.motif, contains('ne détient pas le droit de importer le jeu'));
    expect(mere.toutes('assureurs').length, avant);
    expect(mere.toutes(collectionLots), isEmpty, reason: 'un refus de droit ne se consigne pas');
  });

  test('UN JEU RESTREINT ne recopie aucune valeur de cellule dans le verdict de la mère (motif fixe), et un jeu inconnu est refusé en nommant', () {
    // Les patients s'écrivent au fileul (ils ne passent pas par une demande), mais le verdict d'un jeu restreint reste masqué si une demande en porte un.
    final d = deposer('pa-valide', 'reception', par: 'ACCUEIL TEST');
    final mere = MagasinMemoire(magasinInitial);
    mere.inserer('patients', {'code': 'CNT/12/24', 'nom': 'DEJA', 'prenom': 'Tenu', 'statut': 'actif'});
    final v = lamere(d, mere);
    expect(v.appliquee, isFalse);
    expect(v.code, 'DOUBLON_MAGASIN');
    expect(jsonEncode([v.motif, v.geste]), isNot(contains('CNT/12/24')));
    expect(jsonEncode([v.motif, v.geste]), isNot(contains('DEJA')));
    expect(v.motif, contains('une fiche équivalente est déjà tenue'));
    final inconnu = lamere({...d, 'jeu': 'inconnu'}, MagasinMemoire(magasinInitial));
    expect([inconnu.appliquee, inconnu.code], [false, 'JEU_INCONNU']);
  });
}
